# ABOUTME: proto3 keywords are contextual — they are legal field/message/enum-value/
# rpc/oneof names everywhere except their structural position (B-001).
use v5.38;
use warnings;
use Test::More;
use lib 'lib';

use Protobuf::Parser;

my @KEYWORDS = qw(
    syntax import weak public package option
    enum message service rpc returns stream
    repeated optional reserved to max oneof map
    double float int32 int64 uint32 uint64
    sint32 sint64 fixed32 fixed64 sfixed32 sfixed64
    bool string bytes extend
);

# Every keyword must be usable as a field name.
for my $kw (@KEYWORDS) {
    my $src = qq{syntax = "proto3";\nmessage M { string $kw = 1; }\n};
    my $file = eval { Protobuf::Parser->new->parse_string( 't.proto', $src ) };
    ok( $file, "keyword '$kw' accepted as a field name" ) or diag $@;
    if ($file) {
        is( $file->messages->[0]->fields->[0]->name,
            $kw, "  field name round-trips as '$kw'" );
    }
}

# Keyword as a message name.
{
    my $f = eval {
        Protobuf::Parser->new->parse_string( 't.proto',
            qq{syntax = "proto3";\nmessage service { string x = 1; }\n} );
    };
    ok( $f, 'keyword accepted as a message name' ) or diag $@;
    is( $f->messages->[0]->name, 'service', '  message name is "service"' ) if $f;
}

# Keyword as an enum value name, including the option/value ambiguity.
{
    my $f = eval {
        Protobuf::Parser->new->parse_string( 't.proto',
            qq{syntax = "proto3";\nenum E { option = 0; map = 1; reserved_ok = 2; }\n} );
    };
    ok( $f, 'keyword (incl. "option") accepted as an enum value name' ) or diag $@;
    is( $f->enums->[0]->values->[0]{name}, 'option', '  enum value 0 is "option"' )
        if $f;
}

# Keyword as an rpc method name and a oneof name.
{
    my $src = qq{syntax = "proto3";
message Req { string x = 1; }
message Resp { string y = 1; }
service S { rpc stream (Req) returns (Resp); }
message M { oneof map { string a = 1; string b = 2; } }
};
    my $f = eval { Protobuf::Parser->new->parse_string( 't.proto', $src ) };
    ok( $f, 'keyword accepted as rpc method name and oneof name' ) or diag $@;
    is( $f->services->[0]->methods->[0]{name}, 'stream', '  rpc method is "stream"' )
        if $f;
}

done_testing;
