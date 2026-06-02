# ABOUTME: Unit tests for Proto3::Class::Generator — runtime build of Perl
# classes from a Schema::Message with typed accessors and construction (§4.6).
use v5.38;
use warnings;
use Test::More;
use lib 'lib';

use Proto3::Exception;
use Proto3::Schema;
use Proto3::Schema::File;
use Proto3::Schema::Message;
use Proto3::Schema::Field;
use Proto3::Class::Generator;
use Proto3::Class::Accessor;

# --- helpers ------------------------------------------------------------

# Build a single-message schema from the given field specs and return
# ($schema, $message). Each spec is a hashref passed to Schema::Field->new.
my sub schema_with_fields (@field_specs) {
    my @fields = map { Proto3::Schema::Field->new(%$_) } @field_specs;

    my $message = Proto3::Schema::Message->new(
        name      => 'M',
        full_name => 'pkg.M',
        fields    => \@fields,
    );

    my $file = Proto3::Schema::File->new(
        name     => 'm.proto',
        package  => 'pkg',
        messages => [$message],
    );

    my $schema = Proto3::Schema->new;
    $schema->add_file($file);

    return ( $schema, $message );
}

# Unique target package per build so each test gets a fresh class install.
my $pkg_counter = 0;
my sub next_pkg { return 'T::Gen::M' . ( ++$pkg_counter ) }

# --- Proto3::Class::Accessor: name computation --------------------------

is( Proto3::Class::Accessor::accessor_name('encoding'),
    'encoding', 'plain field name unchanged' );
is( Proto3::Class::Accessor::accessor_name('package'),
    'package_', 'keyword-clash field gets trailing underscore' );
is( Proto3::Class::Accessor::accessor_name('print'),
    'print_', 'keyword print -> print_' );
is( Proto3::Class::Accessor::accessor_name('workflow_id'),
    'workflow_id', 'snake_case non-keyword unchanged' );

# --- T-class-1: build + new + getters + to_hashref ----------------------

{
    my ( $schema, $message ) = schema_with_fields(
        { name => 'encoding', number => 1, type => 'string' },
        { name => 'count',    number => 2, type => 'int32' },
    );
    my $target = next_pkg();

    my $built = Proto3::Class::Generator->build(
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
    Proto3::Class::Generator->build(
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
    Proto3::Class::Generator->build(
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
    Proto3::Class::Generator->build(
        schema         => $schema,
        message        => $message,
        target_package => $target,
    );

    my $err;
    eval { $target->new( { encoding => 'x', bogus => 1 } ); 1 }
        or $err = $@;
    ok( $err, 'unknown ctor key dies' );
    isa_ok( $err, 'Proto3::Exception::Argument',
        'unknown ctor key -> Argument' );
    like( "$err", qr/bogus/, 'Argument names the offending key' );
}

# --- wrong-type setter -> TypeMismatch ----------------------------------

{
    my ( $schema, $message ) = schema_with_fields(
        { name => 'count', number => 1, type => 'int32' },
    );
    my $target = next_pkg();
    Proto3::Class::Generator->build(
        schema         => $schema,
        message        => $message,
        target_package => $target,
    );

    my $obj = $target->new;
    my $err;
    eval { $obj->set_count('not-a-number'); 1 } or $err = $@;
    ok( $err, 'wrong-type setter dies' );
    isa_ok( $err, 'Proto3::Exception::Codec::TypeMismatch',
        'wrong-type setter -> TypeMismatch' );
}

# --- T-class-8: keyword-clash accessor package_ -------------------------

{
    my ( $schema, $message ) = schema_with_fields(
        { name => 'package', number => 1, type => 'string' },
    );
    my $target = next_pkg();
    Proto3::Class::Generator->build(
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
    Proto3::Class::Generator->build(
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

done_testing;
