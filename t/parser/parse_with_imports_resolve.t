# ABOUTME: parse_with_imports resolves cross-file type references by default,
# with a resolve => 0 opt-out (B-014).
use v5.38;
use warnings;
use Test::More;
use lib 'lib';
use File::Temp ();
use File::Spec ();

use Protobuf::Parser;

my $dir = File::Temp->newdir;
my $root = $dir->dirname;

open my $b, '>', File::Spec->catfile( $root, 'b.proto' ) or die $!;
print {$b} qq{syntax = "proto3";\npackage p;\nmessage B { int32 x = 1; }\n};
close $b;

open my $a, '>', File::Spec->catfile( $root, 'a.proto' ) or die $!;
print {$a} qq{syntax = "proto3";\npackage p;\nimport "b.proto";\nmessage A { B b = 1; }\n};
close $a;

# Default: the returned schema is resolved (cross-file type_ref linked).
{
    my $parser = Protobuf::Parser->new( include_paths => [$root] );
    my $schema = $parser->parse_with_imports('a.proto');
    my ($field) = grep { $_->name eq 'b' } @{ $schema->message('p.A')->fields };
    ok( $field->type_ref, 'parse_with_imports resolves cross-file refs by default' );
    is( $field->type_ref->full_name, 'p.B', '  type_ref points at p.B' );
}

# Opt-out: resolve => 0 leaves type_ref undef.
{
    my $parser = Protobuf::Parser->new( include_paths => [$root] );
    my $schema = $parser->parse_with_imports( 'a.proto', resolve => 0 );
    my ($field) = grep { $_->name eq 'b' } @{ $schema->message('p.A')->fields };
    ok( !$field->type_ref, 'resolve => 0 leaves the schema unresolved' );
}

done_testing;
