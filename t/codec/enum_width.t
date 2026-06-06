# ABOUTME: proto3 enum fields decode as a SIGNED 32-bit int — an over-width
# varint wraps to 32 bits, exactly like int32 (protoc semantics).
use v5.38;
use warnings;
use Test::More;
use lib 'lib';

use Protobuf::Schema;
use Protobuf::Schema::File;
use Protobuf::Schema::Message;
use Protobuf::Schema::Field;
use Protobuf::Codec;

sub codec_for ($type) {
    # An enum field carries a type_name (the codec never consults the enum's
    # symbol table — an enum is just a varint integer on the wire), so we skip
    # the resolve pass and hand the field its type_name directly.
    my $f = Protobuf::Schema::Field->new(
        name => 'f', json_name => 'f', number => 1,
        label => 'singular', type => $type, type_name => 'pkg.Color',
    );
    my $m = Protobuf::Schema::Message->new(
        name => 'M', full_name => 'M', fields => [$f],
    );
    my $schema = Protobuf::Schema->new;
    $schema->add_file(
        Protobuf::Schema::File->new(
            name => 'x.proto', package => '',
            messages => [$m], enums => [], services => [], imports => [],
        )
    );
    return Protobuf::Codec->new( schema => $schema );
}

# enum: an over-width all-ones varint (0xFFFFFFFFFFFFFFFF) wraps to a signed
# 32-bit -1, matching protoc's ValidDataScalar.ENUM over-width cases.
{
    my $codec = codec_for('enum');
    my $d = $codec->decode(
        'M', "\x08\xff\xff\xff\xff\xff\xff\xff\xff\xff\x01" );
    is( $d->{f}, -1, 'enum over-width all-ones varint -> -1 (signed 32-bit)' );
}

# enum: 0xFFFFFFFF wraps to -1 as a signed 32-bit value.
{
    my $codec = codec_for('enum');
    my $d = $codec->decode( 'M', "\x08\xff\xff\xff\xff\x0f" );
    is( $d->{f}, -1, 'enum 0xFFFFFFFF -> -1 (signed 32-bit)' );
}

# enum: 0x200000000 overflows 32 bits -> 0.
{
    my $codec = codec_for('enum');
    my $d = $codec->decode( 'M', "\x08\x80\x80\x80\x80\x20" );
    is( $d->{f}, 0, 'enum wraps an over-width varint to 32 bits (-> 0)' );
}

# A normal small enum value is unaffected.
{
    my $codec = codec_for('enum');
    my $d = $codec->decode( 'M', "\x08\x02" );
    is( $d->{f}, 2, 'in-range enum unchanged' );
}

# An unknown but in-range positive enumerator is still preserved as-is.
{
    my $codec = codec_for('enum');
    my $d = $codec->decode( 'M', "\x08\x99\x01" );
    is( $d->{f}, 153, 'unknown positive enumerator preserved' );
}

done_testing;
