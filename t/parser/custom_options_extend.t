# ABOUTME: custom options [(opt) = ...], top-level/nested `extend`, aggregate
# option values { a: 1 b: 2 }, and adjacent string concatenation (B-002/B-009/B-011).
use v5.38;
use warnings;
use Test::More;
use lib 'lib';

use Protobuf::Parser;

# B-002: top-level extend + custom field option.
{
    my $src = q{syntax = "proto3";
import "google/protobuf/descriptor.proto";
extend google.protobuf.FieldOptions { string my_option = 50000; }
message M { string name = 1 [(my_option) = "tag1"]; }
};
    my $f = eval { Protobuf::Parser->new->parse_string( 't.proto', $src ) };
    ok( $f, 'extend + custom field option parses' ) or diag $@;
    if ($f) {
        is( scalar @{ $f->extensions }, 1, '  one file-level extension recorded' );
        is( $f->extensions->[0]->name, 'my_option', '  extension field name' );
        is( $f->extensions->[0]->extendee,
            'google.protobuf.FieldOptions', '  extendee recorded' );
        my $opts = $f->messages->[0]->fields->[0]->options;
        is( $opts->{'(my_option)'}, 'tag1', '  custom option value recorded' );
    }
}

# B-011: aggregate option value (gRPC google.api.http style).
{
    my $src = q{syntax = "proto3";
service S {
  rpc Get (M) returns (M) { option (google.api.http) = { get: "/v1/x" body: "*" }; }
}
message M { string x = 1; }
};
    my $f = eval { Protobuf::Parser->new->parse_string( 't.proto', $src ) };
    ok( $f, 'aggregate option value parses' ) or diag $@;
}

# B-011 at file scope, asserting the aggregate is captured as a hashref.
{
    my $src = q{syntax = "proto3"; option foo = { a: 1 b: 2 };};
    my $f = eval { Protobuf::Parser->new->parse_string( 't.proto', $src ) };
    ok( $f, 'file-scope aggregate option parses' ) or diag $@;
    is( ref $f->options->{foo}, 'HASH', '  aggregate stored as hashref' ) if $f;
    is( $f->options->{foo}{a}, 1, '  aggregate field a' ) if $f;
}

# B-009: adjacent string literal concatenation.
{
    my $src = q{syntax = "proto3"; option foo = "hello" " " "world";};
    my $f = eval { Protobuf::Parser->new->parse_string( 't.proto', $src ) };
    ok( $f, 'adjacent string literals parse' ) or diag $@;
    is( $f->options->{foo}, 'hello world', '  concatenated value' ) if $f;
}

done_testing;
