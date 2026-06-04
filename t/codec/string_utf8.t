# ABOUTME: proto3 `string` fields encode as UTF-8 octets on the wire (not raw
# Perl wide chars); `bytes` fields stay raw octets. Guards the conformance bug.
use v5.38;
use warnings;
use utf8;
use Test::More;
use lib 'lib';
use Encode ();

use Proto3::Schema;
use Proto3::Schema::File;
use Proto3::Schema::Message;
use Proto3::Schema::Field;
use Proto3::Codec;

# Build a one-field message of the given proto type, return a ready codec + name.
sub codec_for ($type) {
    my $f = Proto3::Schema::Field->new(
        name => 'f', json_name => 'f', number => 1,
        label => 'singular', type => $type,
    );
    my $m = Proto3::Schema::Message->new(
        name => 'M', full_name => 'M', fields => [$f],
    );
    my $schema = Proto3::Schema->new;
    $schema->add_file(
        Proto3::Schema::File->new(
            name => 'x.proto', package => '',
            messages => [$m], enums => [], services => [], imports => [],
        )
    );
    $schema->resolve;
    return Proto3::Codec->new( schema => $schema );
}

# "café" — the é is U+00E9, which is two bytes (c3 a9) in UTF-8.
my $CAFE = "caf\x{e9}";

# --- string: must emit UTF-8 octets, length-prefixed by BYTE count -----------
{
    my $codec = codec_for('string');
    my $bytes = $codec->encode( 'M', { f => $CAFE } );

    # tag 0x0a (field 1, LEN), len 0x05, then 63 61 66 c3 a9.
    is(
        join( ' ', map { sprintf '%02x', ord } split //, $bytes ),
        '0a 05 63 61 66 c3 a9',
        'string encodes as UTF-8 octets with a byte-count length prefix',
    );

    # No byte may exceed 0xFF — a wide char on the wire is the bug.
    ok( !grep( { ord > 0xff } split //, $bytes ),
        'encoded string carries no wide characters' );

    my $back = $codec->decode( 'M', $bytes );
    is( $back->{f}, $CAFE, 'string round-trips back to the original text' );
}

# --- bytes: raw octets, unchanged, no UTF-8 transform ------------------------
{
    my $codec = codec_for('bytes');
    my $raw   = "\x00\xff\xc3\xa9";    # arbitrary octets incl. high bytes
    my $bytes = $codec->encode( 'M', { f => $raw } );

    is(
        join( ' ', map { sprintf '%02x', ord } split //, $bytes ),
        '0a 04 00 ff c3 a9',
        'bytes encodes the raw octets verbatim',
    );
    my $back = $codec->decode( 'M', $bytes );
    is( $back->{f}, $raw, 'bytes round-trips the raw octets' );
}

# --- a pure-ASCII string already in byte form is unaffected -------------------
{
    my $codec = codec_for('string');
    my $bytes = $codec->encode( 'M', { f => 'hello' } );
    is(
        join( ' ', map { sprintf '%02x', ord } split //, $bytes ),
        '0a 05 68 65 6c 6c 6f',
        'ASCII string encodes unchanged',
    );
}

done_testing;
