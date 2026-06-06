# ABOUTME: Unit tests for Protobuf::Codec encode/decode of map fields (Step 13).
# Maps are repeated synthetic MapEntry{key=1,value=2}: deterministic key-sorted
# encode, last-wins decode, empty-omit, and key-type validation at construction.
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

# --- helpers ------------------------------------------------------------

# Build a codec over a one-file schema holding the given Schema::Message list.
my sub codec_for (@messages) {
    my $file = Protobuf::Schema::File->new(
        name     => 'm.proto',
        package  => 'pkg',
        messages => [@messages],
    );
    my $schema = Protobuf::Schema->new;
    $schema->add_file($file);
    return Protobuf::Codec->new( schema => $schema );
}

# A synthetic MapEntry message: key (field 1) of $key_type, value (field 2) of
# $value_type. A message-typed value carries $value_type_name for resolution.
my sub map_entry_message ($full_name, $key_type, $value_type, %opts) {
    my @value_extra;
    @value_extra = ( type_name => $opts{value_type_name} )
        if $value_type eq 'message';
    return Protobuf::Schema::Message->new(
        name         => ( split /\./, $full_name )[-1],
        full_name    => $full_name,
        is_map_entry => 1,
        fields       => [
            Protobuf::Schema::Field->new(
                name => 'key', number => 1, type => $key_type,
            ),
            Protobuf::Schema::Field->new(
                name => 'value', number => 2, type => $value_type,
                @value_extra,
            ),
        ],
    );
}

# A map field 'm' (number 1) whose element type is the MapEntry $entry_full_name.
my sub map_field ($entry_full_name) {
    return Protobuf::Schema::Field->new(
        name      => 'm',
        number    => 1,
        type      => 'message',
        label     => 'repeated',
        type_name => $entry_full_name,
        map_entry => $entry_full_name,
    );
}

# A message named pkg.M with a single map field 'm' over the given MapEntry.
my sub map_holder ($entry_full_name) {
    return Protobuf::Schema::Message->new(
        name      => 'M',
        full_name => 'pkg.M',
        fields    => [ map_field($entry_full_name) ],
    );
}

# --- 13.1 / T-codec-6: map<string,int32> sorted-by-key exact bytes ------

{
    my $entry = map_entry_message( 'pkg.M.MEntry', 'string', 'int32' );
    my $codec = codec_for( map_holder('pkg.M.MEntry'), $entry );

    # Each MapEntry: tag(1,LEN) for key(string), then tag(2,VARINT) for value.
    # { a => 1 } entry body: \x0a\x01a (key="a") . \x10\x01 (value=1)  => 5 bytes
    # { b => 2 } entry body: \x0a\x01b (key="b") . \x10\x02 (value=2)  => 5 bytes
    # Each wrapped as map field 1 LEN entry: \x0a (tag 1,LEN) \x05 (len) body.
    my $a_entry = "\x0a\x01a\x10\x01";
    my $b_entry = "\x0a\x01b\x10\x02";
    my $expected =
          "\x0a" . chr( length $a_entry ) . $a_entry
        . "\x0a" . chr( length $b_entry ) . $b_entry;

    is(
        $codec->encode( 'pkg.M', { m => { b => 2, a => 1 } } ),
        $expected,
        'T-codec-6: map<string,int32> emits MapEntries sorted by key'
    );
}

# --- 13.2: round-trip map<string,int32> ---------------------------------

{
    my $entry = map_entry_message( 'pkg.M.MEntry', 'string', 'int32' );
    my $codec = codec_for( map_holder('pkg.M.MEntry'), $entry );

    my $value = { m => { alpha => 7, beta => 8, gamma => 9 } };
    my $bytes = $codec->encode( 'pkg.M', $value );
    is_deeply(
        $codec->decode( 'pkg.M', $bytes ),
        $value,
        '13.2: map<string,int32> round-trips to a hashref'
    );
}

# --- 13.2: round-trip map<int32,Message> --------------------------------

{
    # Value message: pkg.Val { int32 v = 1 }.
    my $val = Protobuf::Schema::Message->new(
        name      => 'Val',
        full_name => 'pkg.Val',
        fields    => [
            Protobuf::Schema::Field->new(
                name => 'v', number => 1, type => 'int32',
            ),
        ],
    );
    my $entry = map_entry_message(
        'pkg.M.MEntry', 'int32', 'message',
        value_type_name => 'pkg.Val',
    );
    my $codec = codec_for( map_holder('pkg.M.MEntry'), $entry, $val );

    my $value = { m => { 1 => { v => 100 }, 2 => { v => 200 } } };
    my $bytes = $codec->encode( 'pkg.M', $value );
    is_deeply(
        $codec->decode( 'pkg.M', $bytes ),
        $value,
        '13.2: map<int32,Message> round-trips to a nested hashref'
    );
}

# --- 13.3: duplicate key on the wire -> last wins -----------------------

{
    my $entry = map_entry_message( 'pkg.M.MEntry', 'string', 'int32' );
    my $codec = codec_for( map_holder('pkg.M.MEntry'), $entry );

    # Two MapEntries for key "a": value 1 then value 2; last wins.
    my $first  = "\x0a\x01a\x10\x01";
    my $second = "\x0a\x01a\x10\x02";
    my $bytes =
          "\x0a" . chr( length $first ) . $first
        . "\x0a" . chr( length $second ) . $second;
    is_deeply(
        $codec->decode( 'pkg.M', $bytes ),
        { m => { a => 2 } },
        '13.3: duplicate map key on the wire keeps the last value'
    );
}

# --- 13.4: disallowed key type -> Schema at construction ----------------

for my $bad_key (qw(float double bytes)) {
    my $entry = map_entry_message( 'pkg.M.MEntry', $bad_key, 'int32' );
    my $err;
    eval {
        codec_for( map_holder('pkg.M.MEntry'), $entry );
        1;
    } or $err = $@;
    ok(
        $err && $err->isa('Protobuf::Exception::Schema'),
        "13.4: map key type '$bad_key' raises Schema at codec construction"
    );
}

# An integral key type and a string key type both construct cleanly.
for my $ok_key (qw(int32 int64 uint32 uint64 sint32 bool fixed32 string)) {
    my $entry = map_entry_message( 'pkg.M.MEntry', $ok_key, 'int32' );
    my $ok = eval {
        codec_for( map_holder('pkg.M.MEntry'), $entry );
        1;
    };
    ok( $ok, "13.4: map key type '$ok_key' is accepted at construction" );
}

# --- 13.5: empty map omitted entirely -----------------------------------

{
    my $entry = map_entry_message( 'pkg.M.MEntry', 'string', 'int32' );
    my $codec = codec_for( map_holder('pkg.M.MEntry'), $entry );
    is(
        $codec->encode( 'pkg.M', { m => {} } ),
        '',
        '13.5: empty map encodes to no bytes'
    );
    is_deeply(
        $codec->decode( 'pkg.M', '' ),
        { m => {} },
        '13.5: absent map decodes to an empty hashref'
    );
}

done_testing;
