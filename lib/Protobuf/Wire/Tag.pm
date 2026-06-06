# ABOUTME: Field tag pack/unpack for the proto3 wire format — (field_number, wire_type).
# A tag is the varint (field_number << 3) | wire_type prefixing every record.
use v5.38;
use warnings;

package Protobuf::Wire::Tag;

use Exporter 'import';

use Protobuf::Exception;
use Protobuf::Wire::Varint qw(encode_varint decode_varint);

our @EXPORT_OK = qw(
    encode_tag decode_tag
    WIRE_VARINT WIRE_I64 WIRE_LEN WIRE_I32
    WIRE_GROUP_START WIRE_GROUP_END
);

# The six protobuf wire types. proto3 uses four of them; types 3/4 (group
# start/end) carry proto2 groups and editions DELIMITED message encoding.
use constant {
    WIRE_VARINT => 0,    # int32/64, uint32/64, sint*, bool, enum
    WIRE_I64    => 1,    # fixed64, sfixed64, double
    WIRE_LEN    => 2,    # string, bytes, embedded messages, packed repeated
    WIRE_I32    => 5,    # fixed32, sfixed32, float
};

# Group wire types: a delimited (group) message is framed by an SGROUP tag and a
# matching EGROUP tag for the same field number, with the message records in
# between (no length prefix).
use constant {
    WIRE_GROUP_START => 3,
    WIRE_GROUP_END   => 4,
};

# Field numbers run 1 .. 2**29 - 1 in proto3 (the low 3 bits of the packed tag
# hold the wire type). 0 is never a valid field number.
use constant MAX_FIELD_NUMBER => ( 1 << 29 ) - 1;

# encode_tag($field_number, $wire_type) -> bytes. Packs the pair into the varint
# (field_number << 3) | wire_type. A field number of 0 (or otherwise out of the
# 1 .. 2**29-1 range) raises Protobuf::Exception::Argument.
sub encode_tag ( $field_number, $wire_type ) {
    if ( $field_number < 1 || $field_number > MAX_FIELD_NUMBER ) {
        Protobuf::Exception::Argument->throw( message =>
                "field number must be 1 .. @{[MAX_FIELD_NUMBER]}, got $field_number"
        );
    }
    return encode_varint( ( $field_number << 3 ) | $wire_type );
}

# decode_tag($bytes) -> (field_number, wire_type, rest). Decodes the leading tag
# varint, splitting off the low 3 bits as the wire type and the rest as the
# field number; returns the remaining bytes untouched. All six wire types are
# returned, including 3 (SGROUP) and 4 (EGROUP) — proto2 groups and editions
# DELIMITED message encoding use them. Whether a group is legal in a given
# message is a schema-layer concern (a proto3 message has none); the raw tag
# layer is syntax-neutral. Wire types 6 and 7 do not exist and would be a
# malformed tag, surfaced by the codec when it tries to use them.
sub decode_tag ($bytes) {
    my ( $tag, $rest ) = decode_varint($bytes);
    my $wire_type    = $tag & 0x7;
    my $field_number = $tag >> 3;
    return ( $field_number, $wire_type, $rest );
}

1;

__END__

=encoding utf-8

=head1 NAME

Protobuf::Wire::Tag - field tag packing for the proto3 wire format

=head1 SYNOPSIS

    use Protobuf::Wire::Tag qw(
        encode_tag decode_tag
        WIRE_VARINT WIRE_I64 WIRE_LEN WIRE_I32
    );

    my $tag = encode_tag( 1, WIRE_VARINT );        # "\x08"
    my ( $field, $wire, $rest ) = decode_tag( $tag . $payload );

=head1 DESCRIPTION

Every record in the protobuf binary wire format is prefixed by a I<tag>: a
varint that packs the field number and a 3-bit wire type as
C<< (field_number << 3) | wire_type >>. This module encodes and decodes that
tag, building on L<Protobuf::Wire::Varint> for the varint itself.

=head1 WIRE TYPES

Proto3 uses four of the eight possible wire types. Types 3 and 4 are the
deprecated proto2 group delimiters and are never emitted by proto3.

    Constant      Value  Used by
    -----------   -----  ---------------------------------------------
    WIRE_VARINT     0    int32/64, uint32/64, sint32/64, bool, enum
    WIRE_I64        1    fixed64, sfixed64, double
    WIRE_LEN        2    string, bytes, embedded messages, packed repeated
    (group start)   3    deprecated proto2 group — rejected
    (group end)     4    deprecated proto2 group — rejected
    WIRE_I32        5    fixed32, sfixed32, float

=head1 FUNCTIONS

All functions and the wire-type constants are exported on request (none by
default).

=head2 encode_tag

    my $bytes = encode_tag( $field_number, $wire_type );

Pack C<$field_number> and C<$wire_type> into the tag varint
C<< (field_number << 3) | wire_type >>. Field numbers run C<1 .. 2**29 - 1>; a
field number outside that range (including C<0>) raises
L<Protobuf::Exception::Argument>.

=head2 decode_tag

    my ( $field_number, $wire_type, $rest ) = decode_tag( $bytes );

Decode the tag varint at the start of C<$bytes>. Returns the field number, the
wire type, and the bytes after the tag (only the leading tag is consumed). A
wire type of 3 or 4 (a deprecated proto2 group) raises
L<Protobuf::Exception::Wire::DeprecatedGroup>. Truncated or over-long tag varints
propagate the errors from L<Protobuf::Wire::Varint/decode_varint>.

=head1 LICENSE

This software is licensed under the MIT license. See the C<LICENSE> file.

=cut
