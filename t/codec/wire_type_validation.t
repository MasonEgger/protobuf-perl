# ABOUTME: decode MUST reject malformed tags — non-existent wire types 6/7, a
# field number above 2**29-1, and an overlong tag varint — as parse errors.
use v5.38;
use warnings;
use Test::More;
use lib 'lib';

use Proto3::Exception;
use Proto3::Schema;
use Proto3::Schema::File;
use Proto3::Schema::Message;
use Proto3::Schema::Field;
use Proto3::Codec;

my sub codec_for () {
    my $f = Proto3::Schema::Field->new(
        name => 'f', json_name => 'f', number => 1,
        label => 'singular', type => 'int32',
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

# Wire types 6 and 7 do not exist in the protobuf wire format. A tag carrying
# one is malformed regardless of the field number (conformance UnknownWireType6
# / UnknownWireType7). Tag byte = (field << 3) | wire; wire 6 = "\x0e" (field 1),
# wire 7 = "\x0f" (field 1).
for my $case (
    [ "\x0e\x00", 'wire type 6, field 1' ],
    [ "\x0f\x00", 'wire type 7, field 1' ],
    [ "\x16\x00", 'wire type 6, field 2' ],
    [ "\x17\x00", 'wire type 7, field 2' ],
  )
{
    my ( $bytes, $label ) = @$case;
    my $codec = codec_for();
    my $ok = eval { $codec->decode( 'M', $bytes ); 1 };
    ok( !$ok, "decode rejects $label" );
    isa_ok( $@, 'Proto3::Exception::Wire', "$label throws a wire exception" );
}

# Wire types 3 (SGROUP) and 4 (EGROUP) are VALID group delimiters and must NOT
# be rejected by the wire-type check (they are handled by the group skip path).
# A bare unknown SGROUP for field 5 closed by its EGROUP round-trips as an
# unknown group rather than a parse error.
{
    my $codec = codec_for();
    # field 5 SGROUP (tag 0x2b), then field 5 EGROUP (tag 0x2c).
    my $ok = eval { $codec->decode( 'M', "\x2b\x2c" ); 1 };
    ok( $ok, 'wire types 3/4 (groups) are not rejected by wire-type validation' );
}

# A field number above 2**29-1 is malformed (conformance BadTag_FieldNumberTooHigh
# and BadTag_FieldNumberSlightlyTooHigh). These tag varints decode to an
# out-of-range field number.
for my $case (
    [ "\x88\x80\x80\x80\x40",             'field number slightly too high' ],
    [ "\x88\x80\x80\x80\x80\x80\x0f",     'field number too high' ],
  )
{
    my ( $bytes, $label ) = @$case;
    my $codec = codec_for();
    my $ok = eval { $codec->decode( 'M', $bytes ); 1 };
    ok( !$ok, "decode rejects $label" );
    isa_ok( $@, 'Proto3::Exception::Wire', "$label throws a wire exception" );
}

# An overlong tag varint (continuation bytes beyond the canonical encoding) is
# malformed (conformance BadTag_OverlongVarint). This encodes field 17 / wire 0
# in 9 bytes where 1 would do.
{
    my $codec = codec_for();
    my $bytes = "\x88\x80\x80\x80\x80\x80\x80\x80\x00";
    my $ok = eval { $codec->decode( 'M', $bytes ); 1 };
    ok( !$ok, 'decode rejects an overlong tag varint' );
    isa_ok( $@, 'Proto3::Exception::Wire',
        'overlong tag varint throws a wire exception' );
}

# A well-formed tag for the declared field still decodes (sanity: validation
# does not reject the canonical form).
{
    my $codec = codec_for();
    my $d = $codec->decode( 'M', "\x08\x2a" );
    is( $d->{f}, 42, 'a canonical tag still decodes' );
}

done_testing;
