# ABOUTME: Unit tests for Proto3::Codec nested messages, enums, and oneofs (Step 14).
# Embedded singular messages (LEN, unset-omitted), enum-as-varint (unknown number
# preserved), oneof encode-one-member / decode-last-wins, and 3-level nesting.
use v5.38;
use warnings;
use Test::More;
use lib 'lib';

use Proto3::Exception;
use Proto3::Schema;
use Proto3::Schema::File;
use Proto3::Schema::Message;
use Proto3::Schema::Field;
use Proto3::Schema::Oneof;
use Proto3::Codec;

# --- helpers ------------------------------------------------------------

# Build a codec over a one-file schema holding the given Schema::Message list.
my sub codec_for (@messages) {
    my $file = Proto3::Schema::File->new(
        name     => 'm.proto',
        package  => 'pkg',
        messages => [@messages],
    );
    my $schema = Proto3::Schema->new;
    $schema->add_file($file);
    return Proto3::Codec->new( schema => $schema );
}

# --- 14.1 / T-codec-7: embedded message round-trip ----------------------

{
    # pkg.Inner { int32 a = 1; string b = 2 }
    my $inner = Proto3::Schema::Message->new(
        name      => 'Inner',
        full_name => 'pkg.Inner',
        fields    => [
            Proto3::Schema::Field->new( name => 'a', number => 1, type => 'int32' ),
            Proto3::Schema::Field->new( name => 'b', number => 2, type => 'string' ),
        ],
    );
    # pkg.Outer { Inner inner = 1; int32 tail = 2 }
    my $outer = Proto3::Schema::Message->new(
        name      => 'Outer',
        full_name => 'pkg.Outer',
        fields    => [
            Proto3::Schema::Field->new(
                name => 'inner', number => 1, type => 'message',
                type_name => 'pkg.Inner',
            ),
            Proto3::Schema::Field->new( name => 'tail', number => 2, type => 'int32' ),
        ],
    );
    my $codec = codec_for( $outer, $inner );

    my $value = { inner => { a => 7, b => 'hi' }, tail => 9 };
    my $bytes = $codec->encode( 'pkg.Outer', $value );

    # Embedded message is LEN-delimited under tag(1,LEN).
    my $inner_body = "\x08\x07\x12\x02hi";    # a=7, b="hi"
    my $expected =
          "\x0a" . chr( length $inner_body ) . $inner_body    # inner
        . "\x10\x09";                                          # tail=9
    is( $bytes, $expected, 'T-codec-7: embedded message is LEN-delimited' );

    is_deeply(
        $codec->decode( 'pkg.Outer', $bytes ),
        $value,
        'T-codec-7: embedded message round-trips all inner values'
    );
}

# --- 14.1: unset embedded message field omitted entirely ----------------

{
    my $inner = Proto3::Schema::Message->new(
        name      => 'Inner',
        full_name => 'pkg.Inner',
        fields    => [
            Proto3::Schema::Field->new( name => 'a', number => 1, type => 'int32' ),
        ],
    );
    my $outer = Proto3::Schema::Message->new(
        name      => 'Outer',
        full_name => 'pkg.Outer',
        fields    => [
            Proto3::Schema::Field->new(
                name => 'inner', number => 1, type => 'message',
                type_name => 'pkg.Inner',
            ),
            Proto3::Schema::Field->new( name => 'tail', number => 2, type => 'int32' ),
        ],
    );
    my $codec = codec_for( $outer, $inner );

    # No 'inner' key at all -> the message field is omitted from the wire.
    is(
        $codec->encode( 'pkg.Outer', { tail => 5 } ),
        "\x10\x05",
        '14.1: unset embedded message field is omitted'
    );

    # And an unset message field stays absent after decode.
    my $decoded = $codec->decode( 'pkg.Outer', "\x10\x05" );
    ok( !exists $decoded->{inner}, '14.1: omitted message stays absent on decode' );
    is( $decoded->{tail}, 5, '14.1: sibling scalar still decodes' );
}

# --- 14.2: enum encodes/decodes as varint -------------------------------

{
    # pkg.M { Color color = 1 }  (enum carried as the integer value)
    my $m = Proto3::Schema::Message->new(
        name      => 'M',
        full_name => 'pkg.M',
        fields    => [
            Proto3::Schema::Field->new(
                name => 'color', number => 1, type => 'enum',
                type_name => 'pkg.Color',
            ),
        ],
    );
    my $codec = codec_for($m);

    # color = 2 -> tag(1,VARINT) + varint(2).
    is(
        $codec->encode( 'pkg.M', { color => 2 } ),
        "\x08\x02",
        '14.2: enum encodes as a varint integer'
    );
    is_deeply(
        $codec->decode( 'pkg.M', "\x08\x02" ),
        { color => 2 },
        '14.2: enum decodes back to its integer value'
    );
    # An enum at its default (0) is omitted (implicit presence).
    is(
        $codec->encode( 'pkg.M', { color => 0 } ),
        '',
        '14.2: enum at default 0 is omitted'
    );
}

# --- 14.3: unknown enum number preserved as int -------------------------

{
    my $m = Proto3::Schema::Message->new(
        name      => 'M',
        full_name => 'pkg.M',
        fields    => [
            Proto3::Schema::Field->new(
                name => 'color', number => 1, type => 'enum',
                type_name => 'pkg.Color',
            ),
        ],
    );
    my $codec = codec_for($m);

    # 4242 is not a defined enumerator; it must survive as the raw integer.
    my $bytes = $codec->encode( 'pkg.M', { color => 4242 } );
    is_deeply(
        $codec->decode( 'pkg.M', $bytes ),
        { color => 4242 },
        '14.3: unknown enum number is preserved as an integer'
    );
}

# --- 14.4: oneof encode emits only the set member -----------------------

# pkg.M with oneof choice { int32 i = 1; string s = 2 } plus a plain field.
my sub oneof_message () {
    my $i = Proto3::Schema::Field->new(
        name => 'i', number => 1, type => 'int32', oneof_index => 0,
    );
    my $s = Proto3::Schema::Field->new(
        name => 's', number => 2, type => 'string', oneof_index => 0,
    );
    my $plain = Proto3::Schema::Field->new(
        name => 'plain', number => 3, type => 'int32',
    );
    return Proto3::Schema::Message->new(
        name      => 'M',
        full_name => 'pkg.M',
        fields    => [ $i, $s, $plain ],
        oneofs    => [
            Proto3::Schema::Oneof->new(
                name => 'choice', oneof_index => 0, fields => [ $i, $s ],
            ),
        ],
    );
}

{
    my $codec = codec_for( oneof_message() );

    # Only 's' is set: emit only field 2; 'i' must NOT appear.
    is(
        $codec->encode( 'pkg.M', { s => 'x' } ),
        "\x12\x01x",
        '14.4: oneof encode emits only the set member'
    );

    # A oneof member set to its scalar default is STILL emitted (presence is by
    # being set in the oneof, not by value).
    is(
        $codec->encode( 'pkg.M', { i => 0 } ),
        "\x08\x00",
        '14.4: oneof member at default value is still emitted'
    );
}

# --- 14.4: oneof decode last-wins clears the earlier sibling ------------

{
    my $codec = codec_for( oneof_message() );

    # Wire carries i=5 (field 1) then s="y" (field 2): same oneof, last wins.
    my $bytes = "\x08\x05" . "\x12\x01y";
    my $decoded = $codec->decode( 'pkg.M', $bytes );
    is( $decoded->{s}, 'y', '14.4: oneof decode keeps the last-seen member' );
    ok( !exists $decoded->{i}, '14.4: oneof decode clears the earlier member' );

    # Reverse order: s="y" then i=5 -> i wins, s cleared.
    my $bytes2 = "\x12\x01y" . "\x08\x05";
    my $decoded2 = $codec->decode( 'pkg.M', $bytes2 );
    is( $decoded2->{i}, 5, '14.4: oneof decode last-wins (reverse order)' );
    ok( !exists $decoded2->{s}, '14.4: oneof decode clears the earlier member (reverse)' );
}

# --- 14.5: deeply nested (3-level) message round-trip -------------------

{
    # pkg.L3 { int32 v = 1 }
    my $l3 = Proto3::Schema::Message->new(
        name => 'L3', full_name => 'pkg.L3',
        fields => [
            Proto3::Schema::Field->new( name => 'v', number => 1, type => 'int32' ),
        ],
    );
    # pkg.L2 { L3 l3 = 1 }
    my $l2 = Proto3::Schema::Message->new(
        name => 'L2', full_name => 'pkg.L2',
        fields => [
            Proto3::Schema::Field->new(
                name => 'l3', number => 1, type => 'message', type_name => 'pkg.L3',
            ),
        ],
    );
    # pkg.L1 { L2 l2 = 1 }
    my $l1 = Proto3::Schema::Message->new(
        name => 'L1', full_name => 'pkg.L1',
        fields => [
            Proto3::Schema::Field->new(
                name => 'l2', number => 1, type => 'message', type_name => 'pkg.L2',
            ),
        ],
    );
    my $codec = codec_for( $l1, $l2, $l3 );

    my $value = { l2 => { l3 => { v => 42 } } };
    my $bytes = $codec->encode( 'pkg.L1', $value );
    is_deeply(
        $codec->decode( 'pkg.L1', $bytes ),
        $value,
        '14.5: 3-level nested message round-trips'
    );
}

done_testing;
