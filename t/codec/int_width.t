# ABOUTME: proto3 32-bit integer fields (int32/uint32/sint32) wrap their decoded
# value to 32 bits — an over-width varint truncates, matching protoc.
use v5.38;
use warnings;
use Test::More;
use lib 'lib';

use Proto3::Schema;
use Proto3::Schema::File;
use Proto3::Schema::Message;
use Proto3::Schema::Field;
use Proto3::Codec;

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

# int32 field 1, varint 0x200000000 (8589934592) overflows 32 bits -> 0.
{
    my $codec = codec_for('int32');
    my $d = $codec->decode( 'M', "\x08\x80\x80\x80\x80\x20" );
    is( $d->{f}, 0, 'int32 wraps an over-width varint to 32 bits (-> 0)' );
}

# int32: 0xFFFFFFFF (4294967295) wraps to -1 as a signed 32-bit value.
{
    my $codec = codec_for('int32');
    my $d = $codec->decode( 'M', "\x08\xff\xff\xff\xff\x0f" );
    is( $d->{f}, -1, 'int32 0xFFFFFFFF -> -1 (signed 32-bit)' );
}

# uint32: 0x100000000 (4294967296) wraps to 0.
{
    my $codec = codec_for('uint32');
    my $d = $codec->decode( 'M', "\x08\x80\x80\x80\x80\x10" );
    is( $d->{f}, 0, 'uint32 wraps an over-width varint to 32 bits (-> 0)' );
}

# A normal in-range int32 is unaffected.
{
    my $codec = codec_for('int32');
    my $d = $codec->decode( 'M', "\x08\x2a" );
    is( $d->{f}, 42, 'in-range int32 unchanged' );
}

# sint32: an over-width zigzag varint truncates to 32 bits BEFORE the zigzag
# transform. Wire 28 82 80 80 80 10 (field 5) is protoc's SINT32[4] case -> 1.
{
    my $codec = codec_for('sint32');
    # field 1 version of the same over-width raw varint 0x80000002 -> zigzag(of
    # low-32 0x80000002 = 2147483650 & 0xffffffff = 2) ... protoc result is 1.
    my $d = $codec->decode( 'M', "\x08\x82\x80\x80\x80\x10" );
    is( $d->{f}, 1, 'sint32 truncates an over-width varint before zigzag (-> 1)' );
}

# sint32 zigzag basics still hold.
{
    my $codec = codec_for('sint32');
    is( $codec->decode( 'M', "\x08\x02" )->{f},  1,  'sint32 zigzag(2) -> 1' );
    is( $codec->decode( 'M', "\x08\x01" )->{f}, -1,  'sint32 zigzag(1) -> -1' );
}

# int64 is NOT narrowed: a large 64-bit value stays intact.
{
    my $codec = codec_for('int64');
    my $d = $codec->decode( 'M', "\x08\x80\x80\x80\x80\x20" );
    is( "$d->{f}", '8589934592', 'int64 keeps full 64-bit value' );
}

done_testing;
