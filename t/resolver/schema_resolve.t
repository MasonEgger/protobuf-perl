# ABOUTME: Tests for Protobuf::Schema->resolve — wiring the Step 8 resolver into
# the schema facade so every message/enum-typed Field gets its $type_ref.
# Covers before/after type_ref, enum fields, idempotency, dangling type_name,
# and owning-message scope (spec §4.2 + §4.3; T-schema-3, T-schema-4).
use v5.38;
use strict;
use warnings;
use utf8;
use Test::More;

use Protobuf::Schema;
use Protobuf::Schema::File;
use Protobuf::Schema::Message;
use Protobuf::Schema::Enum;
use Protobuf::Schema::Field;

# ---------------------------------------------------------------------------
# T-schema-3: a message-typed field's type_ref is undef before resolve and the
# exact Schema::Message instance after resolve.
{
    my $bar = Protobuf::Schema::Message->new(
        name => 'Bar', full_name => 'foo.Bar', fields => [],
    );

    my $ref_field = Protobuf::Schema::Field->new(
        name      => 'bar',
        number    => 1,
        type      => 'message',
        type_name => 'foo.Bar',
    );
    my $holder = Protobuf::Schema::Message->new(
        name => 'Holder', full_name => 'foo.Holder', fields => [$ref_field],
    );

    my $file = Protobuf::Schema::File->new(
        name => 'foo.proto', package => 'foo', messages => [ $bar, $holder ],
    );
    my $schema = Protobuf::Schema->new;
    $schema->add_file($file);

    is( $ref_field->type_ref, undef,
        'message-typed field type_ref is undef before resolve (T-schema-3)' );

    my $ret = $schema->resolve;
    is( $ret, $schema, 'resolve returns the schema for chaining' );

    is( $ref_field->type_ref, $bar,
        'after resolve, type_ref is the exact Schema::Message instance (T-schema-3)' );
}

# ---------------------------------------------------------------------------
# Enum-typed field: type_ref is set to the exact Schema::Enum instance.
{
    my $color = Protobuf::Schema::Enum->new(
        name => 'Color', full_name => 'foo.Color', values => [],
    );

    my $enum_field = Protobuf::Schema::Field->new(
        name      => 'color',
        number    => 1,
        type      => 'enum',
        type_name => 'foo.Color',
    );
    my $holder = Protobuf::Schema::Message->new(
        name => 'Painted', full_name => 'foo.Painted', fields => [$enum_field],
    );

    my $file = Protobuf::Schema::File->new(
        name     => 'enum.proto',
        package  => 'foo',
        messages => [$holder],
        enums    => [$color],
    );
    my $schema = Protobuf::Schema->new;
    $schema->add_file($file);

    is( $enum_field->type_ref, undef, 'enum field type_ref undef before resolve' );
    $schema->resolve;
    is( $enum_field->type_ref, $color,
        'after resolve, enum field type_ref is the exact Schema::Enum instance' );
}

# ---------------------------------------------------------------------------
# Scalar fields are left alone: resolve only touches message/enum-typed fields.
{
    my $scalar_field = Protobuf::Schema::Field->new(
        name => 'n', number => 1, type => 'int32',
    );
    my $holder = Protobuf::Schema::Message->new(
        name => 'Nums', full_name => 'foo.Nums', fields => [$scalar_field],
    );
    my $file = Protobuf::Schema::File->new(
        name => 'nums.proto', package => 'foo', messages => [$holder],
    );
    my $schema = Protobuf::Schema->new;
    $schema->add_file($file);

    $schema->resolve;
    is( $scalar_field->type_ref, undef,
        'scalar field type_ref stays undef after resolve' );
}

# ---------------------------------------------------------------------------
# Idempotency (spec §4.2): a second resolve is a no-op and preserves the exact
# type_ref object identity.
{
    my $bar = Protobuf::Schema::Message->new(
        name => 'Bar', full_name => 'foo.Bar', fields => [],
    );
    my $ref_field = Protobuf::Schema::Field->new(
        name => 'bar', number => 1, type => 'message', type_name => 'foo.Bar',
    );
    my $holder = Protobuf::Schema::Message->new(
        name => 'Holder', full_name => 'foo.Holder', fields => [$ref_field],
    );
    my $file = Protobuf::Schema::File->new(
        name => 'idem.proto', package => 'foo', messages => [ $bar, $holder ],
    );
    my $schema = Protobuf::Schema->new;
    $schema->add_file($file);

    $schema->resolve;
    my $first = $ref_field->type_ref;
    is( $first, $bar, 'first resolve sets type_ref' );

    $schema->resolve;
    is( $ref_field->type_ref, $first,
        'second resolve preserves the exact same type_ref object (idempotent)' );
}

# ---------------------------------------------------------------------------
# Resolution respects the owning message's scope: a relative reference resolves
# innermost-first using current_package (the file package) and current_message
# (the owning message full_name). Here `Bar` from inside foo.Outer resolves to
# the nested foo.Outer.Bar rather than a root Bar, re-using Step 8 scoping.
{
    my $inner_bar = Protobuf::Schema::Message->new(
        name => 'Bar', full_name => 'foo.Outer.Bar', fields => [],
    );
    my $root_bar = Protobuf::Schema::Message->new(
        name => 'Bar', full_name => 'foo.Bar', fields => [],
    );

    my $ref_field = Protobuf::Schema::Field->new(
        name      => 'bar',
        number    => 1,
        type      => 'message',
        type_name => 'Bar',          # relative — scope decides which Bar
    );
    my $outer = Protobuf::Schema::Message->new(
        name            => 'Outer',
        full_name       => 'foo.Outer',
        fields          => [$ref_field],
        nested_messages => [$inner_bar],
    );

    my $file = Protobuf::Schema::File->new(
        name     => 'scope.proto',
        package  => 'foo',
        messages => [ $outer, $root_bar ],
    );
    my $schema = Protobuf::Schema->new;
    $schema->add_file($file);

    $schema->resolve;
    is( $ref_field->type_ref, $inner_bar,
        'relative ref resolves innermost-first using owning-message scope' );
    is( $ref_field->type_ref->full_name, 'foo.Outer.Bar',
        'owning-message scope picks the nested foo.Outer.Bar, not root foo.Bar' );
}

# ---------------------------------------------------------------------------
# T-schema-4: a dangling type_name makes resolve raise UnresolvedType carrying
# the dangling name.
{
    my $ref_field = Protobuf::Schema::Field->new(
        name      => 'missing',
        number    => 1,
        type      => 'message',
        type_name => 'foo.DoesNotExist',
    );
    my $holder = Protobuf::Schema::Message->new(
        name => 'Holder', full_name => 'foo.Holder', fields => [$ref_field],
    );
    my $file = Protobuf::Schema::File->new(
        name => 'dangle.proto', package => 'foo', messages => [$holder],
    );
    my $schema = Protobuf::Schema->new;
    $schema->add_file($file);

    my $err = do {
        local $@;
        eval { $schema->resolve; 1 } ? undef : $@;
    };

    ok( $err, 'dangling type_name makes resolve die (T-schema-4)' );
    isa_ok( $err, 'Protobuf::Exception::Schema::UnresolvedType',
        'dangling type_name raises UnresolvedType (T-schema-4)' );
    like( "$err", qr/foo\.DoesNotExist/,
        'exception message names the dangling type (T-schema-4)' );
}

done_testing;
