# ABOUTME: parse_with_imports treats standard proto2 well-known imports
# (google/protobuf/descriptor.proto) as opaque built-ins, so real proto3 graphs
# that import them for custom options parse cleanly; a user's own proto2 import
# still fails loud (N-005).
use v5.38;
use warnings;
use Test::More;
use lib 'lib';
use File::Temp ();
use File::Spec ();

use Protobuf::Parser;
use Protobuf::Exception;

my $dir  = File::Temp->newdir;
my $root = $dir->dirname;

sub write_proto ($rel, $body) {
    my $abs = File::Spec->catfile( $root, $rel );
    my ( $vol, $d ) = File::Spec->splitpath($abs);
    File::Path::make_path($d) if $d && !-d $d;
    open my $fh, '>', $abs or die "$abs: $!";
    print {$fh} $body;
    close $fh;
}
use File::Path ();

# a.proto imports the canonical proto2 descriptor.proto and uses a custom option.
# descriptor.proto is deliberately NOT written to the include tree.
write_proto( 'a.proto', <<'P' );
syntax = "proto3";
import "google/protobuf/descriptor.proto";
message M { string x = 1 [(my.opt) = "bar"]; }
P

# Built-in opaque handling: succeeds without descriptor.proto on disk, resolved.
{
    my $parser = Protobuf::Parser->new( include_paths => [$root] );
    my $schema = eval { $parser->parse_with_imports('a.proto') };
    ok( $schema, 'graph importing descriptor.proto parses (opaque built-in)' )
        or diag $@;
    my ($x) = grep { $_->name eq 'x' } @{ $schema->message('M')->fields };
    is( $x->options->{'(my.opt)'}, 'bar', '  custom option still captured' );
}

# A user's OWN proto2 file still fails loud (proto3-only is a real constraint).
{
    write_proto( 'legacy.proto', qq{syntax = "proto2";\nmessage L { optional int32 n = 1; }\n} );
    write_proto( 'uses_legacy.proto',
        qq{syntax = "proto3";\nimport "legacy.proto";\nmessage U { string y = 1; }\n} );
    my $parser = Protobuf::Parser->new( include_paths => [$root] );
    my $err = do { local $@; eval { $parser->parse_with_imports('uses_legacy.proto'); 1 }; $@ };
    isa_ok( $err, 'Protobuf::Exception::Parser::UnsupportedSyntax',
        'a user-defined proto2 import still errors loudly' );
}

# opaque_imports extends the set for a caller's own opaque dependency.
{
    write_proto( 'needs_opaque.proto',
        qq{syntax = "proto3";\nimport "vendor/opaque.proto";\nmessage N { string z = 1; }\n} );
    my $parser = Protobuf::Parser->new(
        include_paths  => [$root],
        opaque_imports => ['vendor/opaque.proto'],
    );
    my $schema = eval { $parser->parse_with_imports('needs_opaque.proto') };
    ok( $schema, 'opaque_imports lets a caller mark its own opaque import' )
        or diag $@;
}

done_testing;
