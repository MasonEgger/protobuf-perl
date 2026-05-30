# ABOUTME: Unit tests for the Proto3 exception hierarchy (base + typed subclasses).
# Asserts message/throw/cause behavior, stringification overload, and isa chains.

use strict;
use warnings;
use Test::More;

use Proto3::Exception;

# ---------------------------------------------------------------------------
# T-exc-1: construction, message accessor, throw dies with an object.
# ---------------------------------------------------------------------------
{
    my $exc = Proto3::Exception->new( message => 'boom' );
    isa_ok( $exc, 'Proto3::Exception', 'new returns a Proto3::Exception' );
    is( $exc->message, 'boom', 'message accessor returns the supplied text' );

    eval { $exc->throw };
    my $err = $@;
    ok( ref $err, 'throw dies with a reference (object), not a string' );
    isa_ok( $err, 'Proto3::Exception', 'thrown value is a Proto3::Exception' );
    is( $err, $exc, 'throw dies with the same object it was called on' );
}

# throw can also be used as a class/constructor shortcut.
{
    eval { Proto3::Exception->throw( message => 'kaboom' ) };
    my $err = $@;
    isa_ok( $err, 'Proto3::Exception', 'class-method throw dies with an object' );
    is( $err->message, 'kaboom', 'class-method throw carries the message' );
}

# ---------------------------------------------------------------------------
# T-exc-2: stringification overload yields the message text.
# ---------------------------------------------------------------------------
{
    my $exc = Proto3::Exception->new(
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
    my $exc = Proto3::Exception::Wire::Truncated->new( message => 'short read' );
    isa_ok( $exc, 'Proto3::Exception::Wire::Truncated' );
    isa_ok( $exc, 'Proto3::Exception::Wire' );
    isa_ok( $exc, 'Proto3::Exception' );
    is( "$exc", 'short read', 'subclass inherits stringification overload' );

    eval { $exc->throw };
    isa_ok( $@, 'Proto3::Exception::Wire::Truncated',
        'subclass throw dies with the subclass object' );
}

# ---------------------------------------------------------------------------
# cause defaults to undef and round-trips when supplied.
# ---------------------------------------------------------------------------
{
    my $bare = Proto3::Exception->new( message => 'no cause' );
    is( $bare->cause, undef, 'cause defaults to undef' );

    my $root = Proto3::Exception->new( message => 'root' );
    my $wrap = Proto3::Exception->new( message => 'wrapper', cause => $root );
    is( $wrap->cause, $root, 'cause round-trips the supplied value' );
}

# throw with no message still dies with a usable object.
{
    eval { Proto3::Exception->new->throw };
    my $err = $@;
    isa_ok( $err, 'Proto3::Exception', 'throw with no message still dies usably' );
    ok( defined "$err", 'stringifying a message-less exception is defined' );
}

# ---------------------------------------------------------------------------
# Every declared subclass exists and chains to its domain base + Proto3::Exception.
# ---------------------------------------------------------------------------
my %hierarchy = (
    'Proto3::Exception::Argument' => 'Proto3::Exception',

    'Proto3::Exception::Wire'                  => 'Proto3::Exception',
    'Proto3::Exception::Wire::Truncated'       => 'Proto3::Exception::Wire',
    'Proto3::Exception::Wire::VarintTooLong'   => 'Proto3::Exception::Wire',
    'Proto3::Exception::Wire::DeprecatedGroup' => 'Proto3::Exception::Wire',

    'Proto3::Exception::Schema'                 => 'Proto3::Exception',
    'Proto3::Exception::Schema::DuplicateField' => 'Proto3::Exception::Schema',
    'Proto3::Exception::Schema::DuplicateMessage' =>
        'Proto3::Exception::Schema',
    'Proto3::Exception::Schema::UnresolvedType' => 'Proto3::Exception::Schema',

    'Proto3::Exception::Parser'                  => 'Proto3::Exception',
    'Proto3::Exception::Parser::ImportNotFound'  => 'Proto3::Exception::Parser',
    'Proto3::Exception::Parser::ImportCycle'     => 'Proto3::Exception::Parser',
    'Proto3::Exception::Parser::UnsupportedSyntax' =>
        'Proto3::Exception::Parser',

    'Proto3::Exception::Codec'               => 'Proto3::Exception',
    'Proto3::Exception::Codec::TypeMismatch' => 'Proto3::Exception::Codec',
    'Proto3::Exception::Codec::UnknownType'  => 'Proto3::Exception::Codec',

    'Proto3::Exception::JSON'       => 'Proto3::Exception',
    'Proto3::Exception::JSON::Parse' => 'Proto3::Exception::JSON',
    'Proto3::Exception::JSON::WKT'   => 'Proto3::Exception::JSON',
);

for my $class ( sort keys %hierarchy ) {
    my $parent = $hierarchy{$class};
    my $exc    = $class->new( message => "msg for $class" );
    isa_ok( $exc, $class,                'constructed' );
    isa_ok( $exc, $parent,               "isa $parent" );
    isa_ok( $exc, 'Proto3::Exception',   'isa Proto3::Exception' );
    is( "$exc", "msg for $class", "$class stringifies to its message" );
}

done_testing;
