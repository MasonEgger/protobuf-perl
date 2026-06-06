# ABOUTME: Integration tests for generated-class encode/decode — instances
# self-serialize via Protobuf::Codec, nested fields decode into nested classes (§4.6).
use v5.38;
use warnings;
use Test::More;
use lib 'lib';

use Protobuf::Exception;
use Protobuf::Schema;
use Protobuf::Schema::File;
use Protobuf::Schema::Message;
use Protobuf::Schema::Field;
use Protobuf::Codec;
use Protobuf::Class::Generator;

# --- helpers ------------------------------------------------------------

# Build a one-file schema over the given Schema::Message list and return
# ($schema, $codec).
my sub schema_and_codec (@messages) {
    my $file = Protobuf::Schema::File->new(
        name     => 'm.proto',
        package  => 'pkg',
        messages => [@messages],
    );
    my $schema = Protobuf::Schema->new;
    $schema->add_file($file);
    return ( $schema, Protobuf::Codec->new( schema => $schema ) );
}

# Unique target package per build so each install is fresh.
my $pkg_counter = 0;
my sub next_pkg { return 'T::Codegen::M' . ( ++$pkg_counter ) }

# --- 25.1: instance encode == codec encode of to_hashref ----------------

{
    my $msg = Protobuf::Schema::Message->new(
        name      => 'Flat',
        full_name => 'pkg.Flat',
        fields    => [
            Protobuf::Schema::Field->new( name => 'encoding', number => 1, type => 'string' ),
            Protobuf::Schema::Field->new( name => 'count',    number => 2, type => 'int32' ),
        ],
    );
    my ( $schema, $codec ) = schema_and_codec($msg);
    my $target = next_pkg();
    Protobuf::Class::Generator->build(
        schema         => $schema,
        message        => $msg,
        target_package => $target,
    );

    my $obj = $target->new( { encoding => 'json/plain', count => 7 } );
    is(
        $obj->encode,
        $codec->encode( 'pkg.Flat', $obj->to_hashref ),
        '25.1: instance encode equals codec encode of to_hashref',
    );
}

# --- 25.2: Class->decode equals codec hashref decode --------------------

{
    my $msg = Protobuf::Schema::Message->new(
        name      => 'Flat',
        full_name => 'pkg.Flat',
        fields    => [
            Protobuf::Schema::Field->new( name => 'encoding', number => 1, type => 'string' ),
            Protobuf::Schema::Field->new( name => 'count',    number => 2, type => 'int32' ),
        ],
    );
    my ( $schema, $codec ) = schema_and_codec($msg);
    my $target = next_pkg();
    Protobuf::Class::Generator->build(
        schema         => $schema,
        message        => $msg,
        target_package => $target,
    );

    my $bytes = "\x0a\x0ajson/plain\x10\x07";    # encoding="json/plain", count=7
    my $obj   = $target->decode($bytes);
    isa_ok( $obj, $target, '25.2: decode returns an instance of the target class' );
    is_deeply(
        $obj->to_hashref,
        $codec->decode( 'pkg.Flat', $bytes ),
        '25.2: instance to_hashref equals codec hashref decode',
    );
}

# --- 25.3 / T-class-7: new -> encode -> decode -> to_hashref round-trip --

{
    my $msg = Protobuf::Schema::Message->new(
        name      => 'Flat',
        full_name => 'pkg.Flat',
        fields    => [
            Protobuf::Schema::Field->new( name => 'encoding', number => 1, type => 'string' ),
            Protobuf::Schema::Field->new( name => 'count',    number => 2, type => 'int32' ),
        ],
    );
    my ( $schema, $codec ) = schema_and_codec($msg);
    my $target = next_pkg();
    Protobuf::Class::Generator->build(
        schema         => $schema,
        message        => $msg,
        target_package => $target,
    );

    my $original = { encoding => 'proto/binary', count => 42 };
    my $obj      = $target->new($original);
    my $decoded  = $target->decode( $obj->encode );
    is_deeply(
        $decoded->to_hashref,
        $original,
        'T-class-7: new -> encode -> decode -> to_hashref equals original',
    );
}

# --- 25.4: nested message fields decode into nested class instances ------

{
    # pkg.Inner { int32 a = 1; string b = 2 }
    my $inner = Protobuf::Schema::Message->new(
        name      => 'Inner',
        full_name => 'pkg.Inner',
        fields    => [
            Protobuf::Schema::Field->new( name => 'a', number => 1, type => 'int32' ),
            Protobuf::Schema::Field->new( name => 'b', number => 2, type => 'string' ),
        ],
    );
    # pkg.Outer { Inner inner = 1; repeated Inner items = 2; int32 tail = 3 }
    my $outer = Protobuf::Schema::Message->new(
        name      => 'Outer',
        full_name => 'pkg.Outer',
        fields    => [
            Protobuf::Schema::Field->new(
                name => 'inner', number => 1, type => 'message',
                type_name => 'pkg.Inner',
            ),
            Protobuf::Schema::Field->new(
                name => 'items', number => 2, type => 'message',
                label => 'repeated', type_name => 'pkg.Inner',
            ),
            Protobuf::Schema::Field->new( name => 'tail', number => 3, type => 'int32' ),
        ],
    );
    my ( $schema, $codec ) = schema_and_codec( $outer, $inner );

    my $inner_pkg = next_pkg();
    Protobuf::Class::Generator->build(
        schema         => $schema,
        message        => $inner,
        target_package => $inner_pkg,
    );
    my $outer_pkg = next_pkg();
    Protobuf::Class::Generator->build(
        schema         => $schema,
        message        => $outer,
        target_package => $outer_pkg,
    );

    my $value = {
        inner => { a => 7, b => 'hi' },
        items => [ { a => 1, b => 'x' }, { a => 2, b => 'y' } ],
        tail  => 9,
    };
    my $bytes = $codec->encode( 'pkg.Outer', $value );
    my $obj   = $outer_pkg->decode($bytes);

    isa_ok( $obj, $outer_pkg, '25.4: outer decode returns outer class' );
    isa_ok( $obj->inner, $inner_pkg,
        '25.4: singular nested field decodes into the nested class' );
    is( $obj->inner->a, 7, '25.4: nested instance reads scalar a' );
    is( $obj->inner->b, 'hi', '25.4: nested instance reads scalar b' );

    my $items = $obj->items;
    is( scalar @$items, 2, '25.4: repeated nested field has both elements' );
    isa_ok( $items->[0], $inner_pkg,
        '25.4: repeated nested element 0 is a nested class instance' );
    isa_ok( $items->[1], $inner_pkg,
        '25.4: repeated nested element 1 is a nested class instance' );
    is( $items->[1]->a, 2, '25.4: repeated nested element reads its scalar' );

    # The nested instances must round-trip back to the original plain hashref.
    is_deeply( $obj->to_hashref->{inner}->to_hashref, { a => 7, b => 'hi' },
        '25.4: nested instance to_hashref matches original' );
}

done_testing;
