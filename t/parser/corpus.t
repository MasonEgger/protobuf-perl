# ABOUTME: real-world .proto corpus canary (S-001/S-002/S-003) — every file under
# t/corpus/ must parse; standalone files must also parse_with_imports and resolve.
# Ungated: this runs in the default `prove -lr t` so a parser regression is caught
# the moment it lands, against real protos rather than only bespoke fixtures.
use v5.38;
use warnings;
use Test::More;
use lib 'lib';
use File::Find ();
use File::Spec ();

use Protobuf::Parser;

my $CORPUS = 't/corpus';

sub protos_under ($dir) {
    my @found;
    File::Find::find(
        sub { push @found, $File::Find::name if /\.proto\z/ }, $dir
    );
    my @sorted = sort @found;
    return @sorted;
}

# Every corpus file must lex + parse without error (grammar-level canary).
my @all = protos_under($CORPUS);
ok( @all >= 10, 'corpus has a meaningful number of files (' . @all . ')' );
for my $path (@all) {
    open my $fh, '<:raw', $path or die "cannot read $path: $!";
    my $src = do { local $/; <$fh> };
    close $fh;
    my $ok = eval { Protobuf::Parser->new->parse_string( $path, $src ); 1 };
    ok( $ok, "parses: $path" ) or diag $@;
}

# Standalone files (self-contained proto3) must also parse_with_imports and come
# back fully resolved — every message field's type reference linked.
my $standalone_root = "$CORPUS/standalone";
for my $path ( protos_under($standalone_root) ) {
    my $rel = File::Spec->abs2rel( $path, $standalone_root );
    my $parser = Protobuf::Parser->new( include_paths => [$standalone_root] );
    my $schema = eval { $parser->parse_with_imports($rel) };
    ok( $schema, "parse_with_imports + resolve: $rel" ) or do { diag $@; next };

    my $unresolved = 0;
    for my $msg ( @{ $schema->all_messages } ) {
        for my $field ( @{ $msg->fields } ) {
            next unless $field->is_message || $field->is_enum;
            $unresolved++ unless $field->type_ref;
        }
    }
    is( $unresolved, 0, "  all type_refs resolved in $rel" );
}

done_testing;
