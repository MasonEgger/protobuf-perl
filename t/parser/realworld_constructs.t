# ABOUTME: real-world .proto constructs the Temporal graph uses that the first
# parser pass missed — enum value options (N-001), empty statements (N-002/N-004),
# map field options (N-003), and nested no-colon aggregate option values.
use v5.38;
use warnings;
use Test::More;
use lib 'lib';

use Protobuf::Parser;

sub parse_ok ($label, $src) {
    my $file = eval { Protobuf::Parser->new->parse_string( 't.proto', $src ) };
    ok( $file, $label ) or diag $@;
    return $file;
}

# N-001: enum value options [deprecated = true].
{
    my $f = parse_ok( 'enum value options parse',
        qq{syntax = "proto3";\nenum E { A = 0; B = 1 [deprecated = true]; }\n} );
    my ($b) = grep { $_->{name} eq 'B' } @{ $f->enums->[0]->values };
    is( $b->{options}{deprecated}, 1, '  enum value option captured' );
}

# N-002: empty statement after a oneof block (and bare ; in message/enum/file).
parse_ok( 'empty statement after oneof',
    qq{syntax = "proto3";\nmessage M {\n  oneof s { int64 a = 3; int64 b = 4; };\n  int32 c = 5;\n}\n} );
parse_ok( 'empty statement at file scope', qq{syntax = "proto3";\n;\nmessage M { int32 x = 1; }\n} );
parse_ok( 'empty statement in enum body',
    qq{syntax = "proto3";\nenum E { A = 0; ; B = 1; }\n} );

# N-003: map field options [deprecated = true].
{
    my $f = parse_ok( 'map field options parse',
        qq{syntax = "proto3";\nmessage M { map<string, int32> m = 3 [deprecated = true]; }\n} );
    my ($m) = grep { $_->name eq 'm' } @{ $f->messages->[0]->fields };
    is( $m->options->{deprecated}, 1, '  map field option captured' );
}

# N-004: empty statement in service body.
parse_ok( 'empty statement in service body',
    qq{syntax = "proto3";\nmessage M {}\nservice S { rpc Do (M) returns (M); ; }\n} );

# N-004 note: nested aggregate option value with no colon before the sub-message
# (google.api.http additional_bindings style).
{
    my $src = qq{syntax = "proto3";
message M {}
service S {
  rpc Do (M) returns (M) {
    option (google.api.http) = { post: "/v1/x" additional_bindings { post: "/v2/x" } };
  }
}
};
    parse_ok( 'nested no-colon aggregate option value', $src );
}


# Enum-body reserved ranges and names (real-world: temporal enums).
{
    my $f = parse_ok( q{enum reserved parses},
        qq{syntax = "proto3";\nenum E { A = 0; reserved 4; reserved "OLD"; }\n} );
    is_deeply( $f->enums->[0]->reserved_names, ["OLD"], q{  enum reserved name captured} );
    is( $f->enums->[0]->reserved_numbers->[0][0], 4, q{  enum reserved number captured} );
}

# List option value (swagger tags: [ {...}, {...} ] style).
{
    my $f = parse_ok( q{list option value parses},
        qq{syntax = "proto3";\noption (x) = { tags: [ { name: "a" }, { name: "b" } ] };\n} );
    my $tags = $f->options->{q{(x)}}{tags};
    is( ref $tags, q{ARRAY}, q{  list value is an arrayref} );
    is( $tags->[1]{name}, q{b}, q{  nested aggregate in list captured} );
}

done_testing;
