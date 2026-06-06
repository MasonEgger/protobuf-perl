# ABOUTME: Unit tests for Protobuf::Class::Generator — runtime build of Perl
# classes from a Schema::Message with typed accessors and construction (§4.6).
use v5.38;
use warnings;
use Test::More;
use lib 'lib';

use Protobuf::Exception;
use Protobuf::Schema;
use Protobuf::Schema::File;
use Protobuf::Schema::Message;
use Protobuf::Schema::Field;
use Protobuf::Schema::Oneof;
use Protobuf::Class::Generator;
use Protobuf::Class::Accessor;

# --- helpers ------------------------------------------------------------

# Build a single-message schema from the given field specs and return
# ($schema, $message). Each spec is a hashref passed to Schema::Field->new.
my sub schema_with_fields (@field_specs) {
    my @fields = map { Protobuf::Schema::Field->new(%$_) } @field_specs;

    my $message = Protobuf::Schema::Message->new(
        name      => 'M',
        full_name => 'pkg.M',
        fields    => \@fields,
    );

    my $file = Protobuf::Schema::File->new(
        name     => 'm.proto',
        package  => 'pkg',
        messages => [$message],
    );

    my $schema = Protobuf::Schema->new;
    $schema->add_file($file);

    return ( $schema, $message );
}

# Unique target package per build so each test gets a fresh class install.
my $pkg_counter = 0;
my sub next_pkg { return 'T::Gen::M' . ( ++$pkg_counter ) }

# --- Protobuf::Class::Accessor: name computation --------------------------

is( Protobuf::Class::Accessor::accessor_name('encoding'),
    'encoding', 'plain field name unchanged' );
is( Protobuf::Class::Accessor::accessor_name('package'),
    'package_', 'keyword-clash field gets trailing underscore' );
is( Protobuf::Class::Accessor::accessor_name('print'),
    'print_', 'keyword print -> print_' );
is( Protobuf::Class::Accessor::accessor_name('workflow_id'),
    'workflow_id', 'snake_case non-keyword unchanged' );

# --- T-class-1: build + new + getters + to_hashref ----------------------

{
    my ( $schema, $message ) = schema_with_fields(
        { name => 'encoding', number => 1, type => 'string' },
        { name => 'count',    number => 2, type => 'int32' },
    );
    my $target = next_pkg();

    my $built = Protobuf::Class::Generator->build(
        schema         => $schema,
        message        => $message,
        target_package => $target,
    );
    is( $built, $target, 'build returns the target package name' );

    my $obj = $target->new( { encoding => 'json/plain', count => 7 } );
    isa_ok( $obj, $target, 'new returns an instance of the target package' );
    is( $obj->encoding, 'json/plain', 'string getter' );
    is( $obj->count,    7,            'int32 getter' );

    is_deeply(
        $obj->to_hashref,
        { encoding => 'json/plain', count => 7 },
        'T-class-1: to_hashref round-trips the constructor input',
    );
}

# --- T-class-2: chainable setters return $self --------------------------

{
    my ( $schema, $message ) = schema_with_fields(
        { name => 'encoding', number => 1, type => 'string' },
        { name => 'count',    number => 2, type => 'int32' },
    );
    my $target = next_pkg();
    Protobuf::Class::Generator->build(
        schema         => $schema,
        message        => $message,
        target_package => $target,
    );

    my $obj = $target->new;
    my $ret = $obj->set_encoding('json/plain');
    is( $ret, $obj, 'T-class-2: setter returns $self (chainable)' );

    $obj->set_encoding('proto/binary')->set_count(99);
    is( $obj->encoding, 'proto/binary', 'chained set_encoding applied' );
    is( $obj->count,    99,             'chained set_count applied' );
}

# --- clear_<name> resets to undef ---------------------------------------

{
    my ( $schema, $message ) = schema_with_fields(
        { name => 'encoding', number => 1, type => 'string' },
    );
    my $target = next_pkg();
    Protobuf::Class::Generator->build(
        schema         => $schema,
        message        => $message,
        target_package => $target,
    );

    my $obj = $target->new( { encoding => 'json/plain' } );
    is( $obj->encoding, 'json/plain', 'value set before clear' );
    my $ret = $obj->clear_encoding;
    is( $ret,           $obj,  'clear_<name> returns $self' );
    is( $obj->encoding, undef, 'clear_<name> resets the field' );
}

# --- unknown constructor key -> Argument --------------------------------

{
    my ( $schema, $message ) = schema_with_fields(
        { name => 'encoding', number => 1, type => 'string' },
    );
    my $target = next_pkg();
    Protobuf::Class::Generator->build(
        schema         => $schema,
        message        => $message,
        target_package => $target,
    );

    my $err;
    eval { $target->new( { encoding => 'x', bogus => 1 } ); 1 }
        or $err = $@;
    ok( $err, 'unknown ctor key dies' );
    isa_ok( $err, 'Protobuf::Exception::Argument',
        'unknown ctor key -> Argument' );
    like( "$err", qr/bogus/, 'Argument names the offending key' );
}

# --- wrong-type setter -> TypeMismatch ----------------------------------

{
    my ( $schema, $message ) = schema_with_fields(
        { name => 'count', number => 1, type => 'int32' },
    );
    my $target = next_pkg();
    Protobuf::Class::Generator->build(
        schema         => $schema,
        message        => $message,
        target_package => $target,
    );

    my $obj = $target->new;
    my $err;
    eval { $obj->set_count('not-a-number'); 1 } or $err = $@;
    ok( $err, 'wrong-type setter dies' );
    isa_ok( $err, 'Protobuf::Exception::Codec::TypeMismatch',
        'wrong-type setter -> TypeMismatch' );
}

# --- T-class-8: keyword-clash accessor package_ -------------------------

{
    my ( $schema, $message ) = schema_with_fields(
        { name => 'package', number => 1, type => 'string' },
    );
    my $target = next_pkg();
    Protobuf::Class::Generator->build(
        schema         => $schema,
        message        => $message,
        target_package => $target,
    );

    my $obj = $target->new( { package => 'temporal.api' } );
    can_ok( $obj, 'package_' );
    is( $obj->package_, 'temporal.api',
        'T-class-8: keyword field reads via package_' );

    $obj->set_package_('other.pkg');
    is( $obj->package_, 'other.pkg', 'set_package_ updates the field' );

    my $obj2 = $target->new( { package => 'temporal.api' } );
    is_deeply(
        $obj2->to_hashref,
        { package => 'temporal.api' },
        'to_hashref keys by the proto field name (package), not package_',
    );
}

# --- descriptor returns the Schema::Message -----------------------------

{
    my ( $schema, $message ) = schema_with_fields(
        { name => 'encoding', number => 1, type => 'string' },
    );
    my $target = next_pkg();
    Protobuf::Class::Generator->build(
        schema         => $schema,
        message        => $message,
        target_package => $target,
    );

    is( $target->descriptor, $message,
        'descriptor (class method) returns the Schema::Message' );
    my $obj = $target->new;
    is( $obj->descriptor, $message,
        'descriptor (instance method) returns the Schema::Message' );
}

# --- T-class-4: repeated field — getter arrayref; add_ appends; set_ replaces -

{
    my ( $schema, $message ) = schema_with_fields(
        {
            name   => 'scores',
            number => 1,
            type   => 'int32',
            label  => 'repeated',
        },
    );
    my $target = next_pkg();
    Protobuf::Class::Generator->build(
        schema         => $schema,
        message        => $message,
        target_package => $target,
    );

    my $obj = $target->new;
    is_deeply( $obj->scores, [],
        'T-class-4: repeated getter returns empty arrayref when unset' );

    can_ok( $obj, 'add_scores' );
    my $ret = $obj->add_scores(1);
    is( $ret, $obj, 'add_<name> returns $self (chainable)' );
    $obj->add_scores(2)->add_scores(3);
    is_deeply( $obj->scores, [ 1, 2, 3 ],
        'T-class-4: add_<name> appends in order' );

    my $set_ret = $obj->set_scores( [ 7, 8 ] );
    is( $set_ret, $obj, 'set_<name> returns $self (chainable)' );
    is_deeply( $obj->scores, [ 7, 8 ],
        'T-class-4: set_<name> replaces the whole list' );

    is_deeply(
        $obj->to_hashref,
        { scores => [ 7, 8 ] },
        'repeated value round-trips through to_hashref',
    );
}

# --- T-class-5: map field — getter hashref; set_<n>_entry updates one key -----

{
    # A map field points at a synthetic MapEntry message (key=1, value=2) and is
    # flagged via map_entry + label 'repeated'.
    my $entry = Protobuf::Schema::Message->new(
        name         => 'AttrsEntry',
        full_name    => 'pkg.M.AttrsEntry',
        is_map_entry => 1,
        fields       => [
            Protobuf::Schema::Field->new(
                name => 'key', number => 1, type => 'string' ),
            Protobuf::Schema::Field->new(
                name => 'value', number => 2, type => 'int32' ),
        ],
    );

    my $map_field = Protobuf::Schema::Field->new(
        name      => 'attrs',
        number    => 1,
        type      => 'message',
        label     => 'repeated',
        map_entry => $entry,
    );

    my $message = Protobuf::Schema::Message->new(
        name      => 'M',
        full_name => 'pkg.M',
        fields    => [$map_field],
    );
    my $file = Protobuf::Schema::File->new(
        name     => 'm.proto',
        package  => 'pkg',
        messages => [$message],
    );
    my $schema = Protobuf::Schema->new;
    $schema->add_file($file);

    my $target = next_pkg();
    Protobuf::Class::Generator->build(
        schema         => $schema,
        message        => $message,
        target_package => $target,
    );

    my $obj = $target->new;
    is_deeply( $obj->attrs, {},
        'T-class-5: map getter returns empty hashref when unset' );

    can_ok( $obj, 'set_attrs_entry' );
    my $ret = $obj->set_attrs_entry( 'a', 1 );
    is( $ret, $obj, 'set_<n>_entry returns $self (chainable)' );
    $obj->set_attrs_entry( 'b', 2 );
    is_deeply( $obj->attrs, { a => 1, b => 2 },
        'T-class-5: set_<n>_entry adds keys' );

    $obj->set_attrs_entry( 'a', 99 );
    is_deeply( $obj->attrs, { a => 99, b => 2 },
        'T-class-5: set_<n>_entry overwrites one key' );

    $obj->set_attrs( { x => 5 } );
    is_deeply( $obj->attrs, { x => 5 },
        'map set_<name> replaces the whole map' );
}

# --- T-class-3: oneof — setting one member clears siblings; which_<oneof> -----

{
    my $oneof = Protobuf::Schema::Oneof->new(
        name        => 'kind',
        oneof_index => 0,
    );

    my @fields = (
        Protobuf::Schema::Field->new(
            name => 'text', number => 1, type => 'string', oneof_index => 0 ),
        Protobuf::Schema::Field->new(
            name => 'number', number => 2, type => 'int32', oneof_index => 0 ),
        Protobuf::Schema::Field->new(
            name => 'tag', number => 3, type => 'string' ),
    );

    my $message = Protobuf::Schema::Message->new(
        name      => 'M',
        full_name => 'pkg.M',
        fields    => \@fields,
        oneofs    => [$oneof],
    );
    my $file = Protobuf::Schema::File->new(
        name     => 'm.proto',
        package  => 'pkg',
        messages => [$message],
    );
    my $schema = Protobuf::Schema->new;
    $schema->add_file($file);

    my $target = next_pkg();
    Protobuf::Class::Generator->build(
        schema         => $schema,
        message        => $message,
        target_package => $target,
    );

    my $obj = $target->new;
    can_ok( $obj, 'which_kind' );
    is( $obj->which_kind, undef,
        'T-class-3: which_<oneof> is undef when no member set' );

    $obj->set_text('hello');
    is( $obj->which_kind, 'text', 'which_kind reports the set member' );
    is( $obj->text,       'hello', 'oneof member value stored' );

    $obj->set_number(42);
    is( $obj->which_kind, 'number',
        'T-class-3: setting another member switches which_kind' );
    is( $obj->number, 42,    'new oneof member value stored' );
    is( $obj->text,   undef, 'T-class-3: setting one member clears its sibling' );

    # Non-oneof field is unaffected by oneof switching.
    $obj->set_tag('t')->set_text('again');
    is( $obj->tag, 't',
        'non-oneof field survives oneof member changes' );
    is( $obj->number, undef, 'switching back clears the other member' );
}

# --- T-class-6: has_<n> only for explicit-presence; clear resets -------------

{
    my ( $schema, $message ) = schema_with_fields(
        {
            name   => 'maybe',
            number => 1,
            type   => 'int32',
            label  => 'optional',     # explicit presence
        },
        {
            name   => 'always',
            number => 2,
            type   => 'int32',          # implicit presence (singular)
        },
    );
    my $target = next_pkg();
    Protobuf::Class::Generator->build(
        schema         => $schema,
        message        => $message,
        target_package => $target,
    );

    my $obj = $target->new;
    can_ok( $obj, 'has_maybe' );
    ok( !$target->can('has_always'),
        'T-class-6: has_<n> NOT generated for implicit-presence field' );

    ok( !$obj->has_maybe, 'has_<n> false before set' );
    $obj->set_maybe(0);
    ok( $obj->has_maybe,
        'T-class-6: has_<n> true after set, even for zero value' );

    $obj->clear_maybe;
    ok( !$obj->has_maybe, 'T-class-6: clear_<n> resets presence' );
    is( $obj->maybe, undef, 'cleared field reads undef' );
}

done_testing;
