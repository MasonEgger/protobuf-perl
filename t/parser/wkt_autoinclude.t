# ABOUTME: the parser auto-includes the distribution's vendored proto3 WKTs
# (share/proto) so a .proto importing google/protobuf/* resolves with no
# explicit include_paths; opt-out via include_wkt => 0; user paths win (E-001).
use v5.38;
use warnings;
use Test::More;
use lib 'lib';
use File::Temp ();
use File::Spec ();
use File::Path ();

use Protobuf::Parser;

my $dir = File::Temp->newdir;
my $tmp = $dir->dirname;

sub write_file ($rel, $body) {
    my $abs = File::Spec->catfile( $tmp, $rel );
    my ( undef, $d ) = File::Spec->splitpath($abs);
    File::Path::make_path($d) if $d && !-d $d;
    open my $fh, '>', $abs or die "$abs: $!";
    print {$fh} $body;
    close $fh;
}

# Each vendored proto3 WKT must resolve with NO explicit include path for it.
my @WKT = qw(
    google/protobuf/any.proto
    google/protobuf/duration.proto
    google/protobuf/empty.proto
    google/protobuf/field_mask.proto
    google/protobuf/struct.proto
    google/protobuf/timestamp.proto
    google/protobuf/wrappers.proto
);
for my $wkt (@WKT) {
    ( my $stem = $wkt ) =~ s{.*/|\.proto$}{}g;
    my $entry = "uses_$stem.proto";
    write_file( $entry, qq{syntax = "proto3";\nimport "$wkt";\nmessage M { string x = 1; }\n} );
    my $schema = eval {
        Protobuf::Parser->new( include_paths => [$tmp] )->parse_with_imports($entry);
    };
    ok( $schema, "auto-includes $wkt (no explicit include path)" ) or diag $@;
}

# descriptor.proto (proto2) is still satisfied — as an opaque built-in.
{
    write_file( 'uses_desc.proto',
        qq{syntax = "proto3";\nimport "google/protobuf/descriptor.proto";\nmessage M { string x = 1; }\n} );
    ok(
        eval {
            Protobuf::Parser->new( include_paths => [$tmp] )->parse_with_imports('uses_desc.proto');
        },
        'descriptor.proto still satisfied (opaque) alongside auto-include'
    ) or diag $@;
}

# include_wkt => 0 disables the auto-include (strict/hermetic mode).
{
    write_file( 'uses_ts.proto',
        qq{syntax = "proto3";\nimport "google/protobuf/timestamp.proto";\nmessage M { string x = 1; }\n} );
    my $err = do {
        local $@;
        eval {
            Protobuf::Parser->new( include_paths => [$tmp], include_wkt => 0 )
                ->parse_with_imports('uses_ts.proto');
            1;
        };
        $@;
    };
    isa_ok( $err, 'Protobuf::Exception::Parser::ImportNotFound',
        'include_wkt => 0 disables auto-include (import not found)' );
}

# A user-supplied copy wins over the bundled WKT (append-don't-prepend).
{
    write_file( 'google/protobuf/timestamp.proto',
        qq{syntax = "proto3";\npackage google.protobuf;\nmessage Timestamp { int64 seconds = 1; string MARKER_user_copy = 2; }\n} );
    write_file( 'uses_ts2.proto',
        qq{syntax = "proto3";\nimport "google/protobuf/timestamp.proto";\nmessage M { string x = 1; }\n} );
    my $schema =
        Protobuf::Parser->new( include_paths => [$tmp] )->parse_with_imports('uses_ts2.proto');
    my $ts = $schema->message('google.protobuf.Timestamp');
    ok( ( grep { $_->name eq 'MARKER_user_copy' } @{ $ts->fields } ),
        'user-supplied WKT copy takes precedence over the bundled one' );
}

done_testing;
