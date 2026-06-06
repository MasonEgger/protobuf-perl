# ABOUTME: Unit tests for Protobuf::Schema element classes (Step 6, T-schema-1/2).
# Covers Field predicates, Enum allow_alias, and Message duplicate detection.
use v5.38;
use warnings;
use Test::More;

use Protobuf::Schema::Field;
use Protobuf::Schema::Oneof;
use Protobuf::Schema::Enum;
use Protobuf::Schema::Message;
use Protobuf::Schema::Service;
use Protobuf::Schema::File;
use Protobuf::Exception;

# --- T-schema-1: trivial Message with 2 fields; readers return them ---------
{
    my $f1 = Protobuf::Schema::Field->new( name => 'id',   number => 1, type => 'int32' );
    my $f2 = Protobuf::Schema::Field->new( name => 'name', number => 2, type => 'string' );

    is( $f1->name,   'id',     'field 1 name reader' );
    is( $f1->number, 1,        'field 1 number reader' );
    is( $f1->type,   'int32',  'field 1 type reader' );
    is( $f1->label,  'singular', 'field label defaults to singular' );

    my $msg = Protobuf::Schema::Message->new(
        name      => 'Thing',
        full_name => 'pkg.Thing',
        fields    => [ $f1, $f2 ],
    );
    is( $msg->name,      'Thing',     'message name reader' );
    is( $msg->full_name, 'pkg.Thing', 'message full_name reader' );
    is( scalar @{ $msg->fields }, 2,  'message fields reader returns both' );
    is( $msg->fields->[1]->name, 'name', 'second field accessible via reader' );
}

# --- T-schema-2: duplicate field NUMBER -> DuplicateField --------------------
{
    my $f1 = Protobuf::Schema::Field->new( name => 'a', number => 1, type => 'int32' );
    my $f2 = Protobuf::Schema::Field->new( name => 'b', number => 1, type => 'int32' );

    my $err;
    eval {
        Protobuf::Schema::Message->new(
            name => 'Dup', full_name => 'pkg.Dup', fields => [ $f1, $f2 ],
        );
        1;
    } or $err = $@;

    ok( $err, 'duplicate field number raises' );
    ok( ref $err && $err->isa('Protobuf::Exception::Schema::DuplicateField'),
        'duplicate field number -> Schema::DuplicateField' );
}

# --- 6.3: duplicate field NAME -> DuplicateField ----------------------------
{
    my $f1 = Protobuf::Schema::Field->new( name => 'a', number => 1, type => 'int32' );
    my $f2 = Protobuf::Schema::Field->new( name => 'a', number => 2, type => 'int32' );

    my $err;
    eval {
        Protobuf::Schema::Message->new(
            name => 'DupN', full_name => 'pkg.DupN', fields => [ $f1, $f2 ],
        );
        1;
    } or $err = $@;

    ok( $err, 'duplicate field name raises' );
    ok( ref $err && $err->isa('Protobuf::Exception::Schema::DuplicateField'),
        'duplicate field name -> Schema::DuplicateField' );
}

# --- 6.4: Field predicates is_message/is_enum/is_repeated/is_map ------------
{
    my $scalar = Protobuf::Schema::Field->new( name => 'n', number => 1, type => 'int32' );
    ok( !$scalar->is_message,  'scalar is not message' );
    ok( !$scalar->is_enum,     'scalar is not enum' );
    ok( !$scalar->is_repeated, 'singular is not repeated' );
    ok( !$scalar->is_map,      'plain field is not map' );

    my $msg_field = Protobuf::Schema::Field->new(
        name => 'inner', number => 2, type => 'message', type_name => '.pkg.Inner',
    );
    ok( $msg_field->is_message, 'type message -> is_message' );
    ok( !$msg_field->is_enum,   'message field is not enum' );

    my $enum_field = Protobuf::Schema::Field->new(
        name => 'e', number => 3, type => 'enum', type_name => '.pkg.E',
    );
    ok( $enum_field->is_enum,     'type enum -> is_enum' );
    ok( !$enum_field->is_message, 'enum field is not message' );

    my $rep = Protobuf::Schema::Field->new(
        name => 'list', number => 4, type => 'int32', label => 'repeated',
    );
    ok( $rep->is_repeated, 'label repeated -> is_repeated' );

    my $map = Protobuf::Schema::Field->new(
        name => 'm', number => 5, type => 'message', label => 'repeated',
        map_entry => { key => 'string', value => 'int32' },
    );
    ok( $map->is_map, 'map_entry set -> is_map' );
}

# --- 6.5: is_packed only true for packable repeated scalar ------------------
{
    # packed flag set, repeated, packable scalar (int32) -> true
    my $packed_int = Protobuf::Schema::Field->new(
        name => 'xs', number => 1, type => 'int32', label => 'repeated', packed => 1,
    );
    ok( $packed_int->is_packed, 'packed repeated int32 -> is_packed' );

    # packable repeated enum -> true
    my $packed_enum = Protobuf::Schema::Field->new(
        name => 'es', number => 2, type => 'enum', type_name => '.pkg.E',
        label => 'repeated', packed => 1,
    );
    ok( $packed_enum->is_packed, 'packed repeated enum -> is_packed' );

    # packed but NOT repeated -> false
    my $packed_singular = Protobuf::Schema::Field->new(
        name => 'one', number => 3, type => 'int32', label => 'singular', packed => 1,
    );
    ok( !$packed_singular->is_packed, 'packed but singular -> not is_packed' );

    # repeated string (not packable) even with packed flag -> false
    my $packed_string = Protobuf::Schema::Field->new(
        name => 'ss', number => 4, type => 'string', label => 'repeated', packed => 1,
    );
    ok( !$packed_string->is_packed, 'repeated string is never packed' );

    # repeated message (not packable) -> false
    my $packed_msg = Protobuf::Schema::Field->new(
        name => 'ms', number => 5, type => 'message', type_name => '.pkg.M',
        label => 'repeated', packed => 1,
    );
    ok( !$packed_msg->is_packed, 'repeated message is never packed' );

    # repeated packable scalar but packed flag false/undef -> false
    my $unpacked = Protobuf::Schema::Field->new(
        name => 'us', number => 6, type => 'int32', label => 'repeated',
    );
    ok( !$unpacked->is_packed, 'repeated int32 without packed flag -> not is_packed' );
}

# --- 6.6: Enum allow_alias validation --------------------------------------
{
    # allow_alias=0 (default) with distinct numbers constructs fine
    my $ok_enum = Protobuf::Schema::Enum->new(
        name => 'Color', full_name => 'pkg.Color',
        values => [ { name => 'RED', number => 0 }, { name => 'GREEN', number => 1 } ],
    );
    is( $ok_enum->name, 'Color', 'enum with distinct values constructs' );
    is( $ok_enum->allow_alias, 0, 'allow_alias defaults to 0' );

    # allow_alias=0 with duplicate value numbers -> raises
    my $err;
    eval {
        Protobuf::Schema::Enum->new(
            name => 'Bad', full_name => 'pkg.Bad',
            values => [ { name => 'A', number => 0 }, { name => 'B', number => 0 } ],
        );
        1;
    } or $err = $@;
    ok( $err, 'duplicate enum value numbers without allow_alias raises' );
    ok( ref $err && $err->isa('Protobuf::Exception::Schema'),
        'duplicate enum number -> Schema exception' );

    # allow_alias=1 with duplicate value numbers constructs fine
    my $alias = Protobuf::Schema::Enum->new(
        name => 'Aliased', full_name => 'pkg.Aliased', allow_alias => 1,
        values => [ { name => 'A', number => 0 }, { name => 'B', number => 0 } ],
    );
    is( $alias->name, 'Aliased', 'allow_alias=1 permits duplicate numbers' );
    is( $alias->allow_alias, 1, 'allow_alias reader returns 1' );
}

# --- Oneof, Service, File construct and expose readers ----------------------
{
    my $of = Protobuf::Schema::Oneof->new( name => 'choice', oneof_index => 0 );
    is( $of->name,        'choice', 'oneof name reader' );
    is( $of->oneof_index, 0,        'oneof index reader' );

    my $svc = Protobuf::Schema::Service->new(
        name => 'Greeter', full_name => 'pkg.Greeter',
        methods => [ { name => 'Hello', input_type => '.pkg.Req', output_type => '.pkg.Res' } ],
    );
    is( $svc->name, 'Greeter', 'service name reader' );
    is( scalar @{ $svc->methods }, 1, 'service methods reader' );

    my $file = Protobuf::Schema::File->new(
        name => 'pkg/thing.proto', package => 'pkg',
    );
    is( $file->name,    'pkg/thing.proto', 'file name reader' );
    is( $file->package, 'pkg',             'file package reader' );
    is( $file->syntax,  'proto3',          'file syntax defaults to proto3' );
}

done_testing;
