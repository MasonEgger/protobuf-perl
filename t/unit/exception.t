# ABOUTME: Unit tests for the Proto3 exception hierarchy (base + typed subclasses).
# Asserts message/throw/cause behavior, stringification overload, and isa chains.

use strict;
use warnings;
use Test::More;

use Protobuf::Exception;

# ---------------------------------------------------------------------------
# T-exc-1: construction, message accessor, throw dies with an object.
# ---------------------------------------------------------------------------
{
    my $exc = Protobuf::Exception->new( message => 'boom' );
    isa_ok( $exc, 'Protobuf::Exception', 'new returns a Protobuf::Exception' );
    is( $exc->message, 'boom', 'message accessor returns the supplied text' );

    eval { $exc->throw };
    my $err = $@;
    ok( ref $err, 'throw dies with a reference (object), not a string' );
    isa_ok( $err, 'Protobuf::Exception', 'thrown value is a Protobuf::Exception' );
    is( $err, $exc, 'throw dies with the same object it was called on' );
}

# throw can also be used as a class/constructor shortcut.
{
    eval { Protobuf::Exception->throw( message => 'kaboom' ) };
    my $err = $@;
    isa_ok( $err, 'Protobuf::Exception', 'class-method throw dies with an object' );
    is( $err->message, 'kaboom', 'class-method throw carries the message' );
}

# ---------------------------------------------------------------------------
# T-exc-2: stringification overload yields the message text.
# ---------------------------------------------------------------------------
{
    my $exc = Protobuf::Exception->new(
        message => "field 'name' (#3) is invalid" );
    is( "$exc", "field 'name' (#3) is invalid",
        'stringification yields the interpolated message' );

    my $interpolated = "error: $exc";
    is( $interpolated, "error: field 'name' (#3) is invalid",
        'overload works inside string interpolation' );
}

# ---------------------------------------------------------------------------
# T-exc-3: isa hierarchy holds three levels deep.
# ---------------------------------------------------------------------------
{
    my $exc = Protobuf::Exception::Wire::Truncated->new( message => 'short read' );
    isa_ok( $exc, 'Protobuf::Exception::Wire::Truncated' );
    isa_ok( $exc, 'Protobuf::Exception::Wire' );
    isa_ok( $exc, 'Protobuf::Exception' );
    is( "$exc", 'short read', 'subclass inherits stringification overload' );

    eval { $exc->throw };
    isa_ok( $@, 'Protobuf::Exception::Wire::Truncated',
        'subclass throw dies with the subclass object' );
}

# ---------------------------------------------------------------------------
# cause defaults to undef and round-trips when supplied.
# ---------------------------------------------------------------------------
{
    my $bare = Protobuf::Exception->new( message => 'no cause' );
    is( $bare->cause, undef, 'cause defaults to undef' );

    my $root = Protobuf::Exception->new( message => 'root' );
    my $wrap = Protobuf::Exception->new( message => 'wrapper', cause => $root );
    is( $wrap->cause, $root, 'cause round-trips the supplied value' );
}

# throw with no message still dies with a usable object.
{
    eval { Protobuf::Exception->new->throw };
    my $err = $@;
    isa_ok( $err, 'Protobuf::Exception', 'throw with no message still dies usably' );
    ok( defined "$err", 'stringifying a message-less exception is defined' );
}

# ---------------------------------------------------------------------------
# Every declared subclass exists and chains to its domain base + Protobuf::Exception.
# ---------------------------------------------------------------------------
my %hierarchy = (
    'Protobuf::Exception::Argument' => 'Protobuf::Exception',

    'Protobuf::Exception::Wire'                  => 'Protobuf::Exception',
    'Protobuf::Exception::Wire::Truncated'       => 'Protobuf::Exception::Wire',
    'Protobuf::Exception::Wire::VarintTooLong'   => 'Protobuf::Exception::Wire',
    'Protobuf::Exception::Wire::DeprecatedGroup' => 'Protobuf::Exception::Wire',

    'Protobuf::Exception::Schema'                 => 'Protobuf::Exception',
    'Protobuf::Exception::Schema::DuplicateField' => 'Protobuf::Exception::Schema',
    'Protobuf::Exception::Schema::DuplicateMessage' =>
        'Protobuf::Exception::Schema',
    'Protobuf::Exception::Schema::UnresolvedType' => 'Protobuf::Exception::Schema',

    'Protobuf::Exception::Parser'                  => 'Protobuf::Exception',
    'Protobuf::Exception::Parser::ImportNotFound'  => 'Protobuf::Exception::Parser',
    'Protobuf::Exception::Parser::ImportCycle'     => 'Protobuf::Exception::Parser',
    'Protobuf::Exception::Parser::UnsupportedSyntax' =>
        'Protobuf::Exception::Parser',

    'Protobuf::Exception::Codec'               => 'Protobuf::Exception',
    'Protobuf::Exception::Codec::TypeMismatch' => 'Protobuf::Exception::Codec',
    'Protobuf::Exception::Codec::UnknownType'  => 'Protobuf::Exception::Codec',

    'Protobuf::Exception::JSON'       => 'Protobuf::Exception',
    'Protobuf::Exception::JSON::Parse' => 'Protobuf::Exception::JSON',
    'Protobuf::Exception::JSON::WKT'   => 'Protobuf::Exception::JSON',
);

for my $class ( sort keys %hierarchy ) {
    my $parent = $hierarchy{$class};
    my $exc    = $class->new( message => "msg for $class" );
    isa_ok( $exc, $class,                'constructed' );
    isa_ok( $exc, $parent,               "isa $parent" );
    isa_ok( $exc, 'Protobuf::Exception',   'isa Protobuf::Exception' );
    is( "$exc", "msg for $class", "$class stringifies to its message" );
}

done_testing;
