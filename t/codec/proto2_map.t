# ABOUTME: Unit tests for proto2/editions map-entry default-fill in Proto3::Codec.
# A MapEntry whose key/value tracks explicit presence (proto2) must STILL
# default-fill its key and value to type-zero when omitted on the wire, never
# leak a HASH ref or undef — a map entry conceptually always has both fields.
use v5.38;
use warnings;
use Test::More;
use lib 'lib';

use Proto3::Schema;
use Proto3::Schema::File;
use Proto3::Schema::Message;
use Proto3::Schema::Field;
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

# A synthetic MapEntry whose key (field 1) and value (field 2) BOTH declare
# explicit presence (label 'optional') — exactly the proto2/editions entry
# shape where an omitted key/value must default rather than stay absent.
my sub explicit_map_entry ($full_name, $key_type, $value_type) {
    return Proto3::Schema::Message->new(
        name         => ( split /\./, $full_name )[-1],
        full_name    => $full_name,
        is_map_entry => 1,
        fields       => [
            Proto3::Schema::Field->new(
                name  => 'key', number => 1,
                type  => $key_type, label => 'optional',
            ),
            Proto3::Schema::Field->new(
                name  => 'value', number => 2,
                type  => $value_type, label => 'optional',
            ),
        ],
    );
}

# A map field 'm' (number 1) over the given MapEntry.
my sub map_field ($entry_full_name) {
    return Proto3::Schema::Field->new(
        name      => 'm',
        number    => 1,
        type      => 'message',
        label     => 'repeated',
        type_name => $entry_full_name,
        map_entry => $entry_full_name,
    );
}

# A message pkg.M with one map field 'm'.
my sub map_holder ($entry_full_name) {
    return Proto3::Schema::Message->new(
        name      => 'M',
        full_name => 'pkg.M',
        fields    => [ map_field($entry_full_name) ],
    );
}

# Wire for an empty map entry under the map field (number 1, LEN): tag 0x0a,
# length 0. This is the "MissingDefault" case: both key and value omitted.
my $EMPTY_ENTRY = "\x0a\x00";

# --- proto2 map<int32,int32>: value omitted -> {0 => 0} -----------------

{
    my $entry = explicit_map_entry( 'pkg.M.MEntry', 'int32', 'int32' );
    my $codec = codec_for( map_holder('pkg.M.MEntry'), $entry );

    is_deeply(
        $codec->decode( 'pkg.M', $EMPTY_ENTRY ),
        { m => { 0 => 0 } },
        'proto2 map<int32,int32> with key+value omitted decodes to {0 => 0}'
    );
}

# --- proto2 map<int32,int32>: only key present, value omitted -> 0 ------

{
    my $entry = explicit_map_entry( 'pkg.M.MEntry', 'int32', 'int32' );
    my $codec = codec_for( map_holder('pkg.M.MEntry'), $entry );

    # Entry body: tag(1,VARINT)=0x08, key=5; value field 2 omitted entirely.
    my $body  = "\x08\x05";
    my $bytes = "\x0a" . chr( length $body ) . $body;
    is_deeply(
        $codec->decode( 'pkg.M', $bytes ),
        { m => { 5 => 0 } },
        'proto2 map<int32,int32> with value omitted defaults the value to 0'
    );
}

# --- proto2 map<string,string>: value omitted -> "" (NOT a ref) ---------

{
    my $entry = explicit_map_entry( 'pkg.M.MEntry', 'string', 'string' );
    my $codec = codec_for( map_holder('pkg.M.MEntry'), $entry );

    my $decoded = $codec->decode( 'pkg.M', $EMPTY_ENTRY );
    is_deeply(
        $decoded,
        { m => { '' => '' } },
        'proto2 map<string,string> with both omitted decodes to {"" => ""}'
    );
    ok(
        !ref $decoded->{m}{''},
        'proto2 map<string,string> omitted value is a plain string, not a ref'
    );
}

# --- proto2 map<bool,bool>: both omitted -> {0 => 0} --------------------

{
    my $entry = explicit_map_entry( 'pkg.M.MEntry', 'bool', 'bool' );
    my $codec = codec_for( map_holder('pkg.M.MEntry'), $entry );

    is_deeply(
        $codec->decode( 'pkg.M', $EMPTY_ENTRY ),
        { m => { 0 => 0 } },
        'proto2 map<bool,bool> with both omitted decodes to {false => false}'
    );
}

# --- round-trip a proto2 map with a zero value --------------------------

{
    my $entry = explicit_map_entry( 'pkg.M.MEntry', 'int32', 'int32' );
    my $codec = codec_for( map_holder('pkg.M.MEntry'), $entry );

    my $value = { m => { 7 => 0 } };
    my $bytes = $codec->encode( 'pkg.M', $value );
    is_deeply(
        $codec->decode( 'pkg.M', $bytes ),
        $value,
        'proto2 map<int32,int32> with a zero value round-trips'
    );
}

done_testing;
