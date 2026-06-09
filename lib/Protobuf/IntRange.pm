# ABOUTME: Protobuf::IntRange — inclusive value bounds for each integer proto3 type.
# The single source of truth shared by the wire codec (encode range check) and the
# JSON codec (input range check); both must reject out-of-range integers like protoc.
use v5.38;
use strict;
use warnings;

package Protobuf::IntRange;

use Math::BigInt ();
use Scalar::Util ();

# Inclusive [min, max] per integer proto3 type, as Math::BigInt so the 64-bit
# bounds are exact (a native float cannot hold 2^64-1).
my %RANGE = (
    int32    => [ Math::BigInt->new('-2147483648'),          Math::BigInt->new('2147483647') ],
    sint32   => [ Math::BigInt->new('-2147483648'),          Math::BigInt->new('2147483647') ],
    sfixed32 => [ Math::BigInt->new('-2147483648'),          Math::BigInt->new('2147483647') ],
    uint32   => [ Math::BigInt->new('0'),                    Math::BigInt->new('4294967295') ],
    fixed32  => [ Math::BigInt->new('0'),                    Math::BigInt->new('4294967295') ],
    int64    => [ Math::BigInt->new('-9223372036854775808'), Math::BigInt->new('9223372036854775807') ],
    sint64   => [ Math::BigInt->new('-9223372036854775808'), Math::BigInt->new('9223372036854775807') ],
    sfixed64 => [ Math::BigInt->new('-9223372036854775808'), Math::BigInt->new('9223372036854775807') ],
    uint64   => [ Math::BigInt->new('0'),                    Math::BigInt->new('18446744073709551615') ],
    fixed64  => [ Math::BigInt->new('0'),                    Math::BigInt->new('18446744073709551615') ],
);

# range_for($type) -> ($min, $max) Math::BigInt pair, or an empty list when
# $type is not a bounded integer type (float/double/string/bytes/bool/enum/etc.).
sub range_for {
    my ($type) = @_;
    my $r = $RANGE{$type} or return ();
    return @$r;
}

# True when $type is one of the bounded integer types.
sub is_integer_type {
    my ($type) = @_;
    return exists $RANGE{$type};
}

# in_range($type, $value) -> true when $value lies within $type's inclusive
# range. A non-integer $type is always in range (the check does not apply). The
# comparison runs in Math::BigInt so 64-bit bounds are exact.
sub in_range {
    my ( $type, $value ) = @_;
    my $r = $RANGE{$type} or return 1;
    my ( $min, $max ) = @$r;
    my $n =
        ( Scalar::Util::blessed($value) && $value->isa('Math::BigInt') )
        ? $value
        : Math::BigInt->new("$value");
    return $n->bcmp($min) >= 0 && $n->bcmp($max) <= 0;
}

1;

__END__

=encoding utf-8

=head1 NAME

Protobuf::IntRange - inclusive value bounds for integer proto3 types

=head1 SYNOPSIS

    use Protobuf::IntRange;

    my ( $min, $max ) = Protobuf::IntRange::range_for('int32');
    Protobuf::IntRange::in_range( 'int32', 2**40 );   # false
    Protobuf::IntRange::is_integer_type('float');     # false

=head1 DESCRIPTION

The single source of truth for the inclusive C<[min, max]> range of each bounded
integer proto3 type (the C<int>/C<uint>/C<sint>/C<fixed>/C<sfixed> 32- and 64-bit
families). Bounds are L<Math::BigInt> so the 64-bit limits are exact.

Both the wire codec (which range-checks integer values on encode) and the JSON
codec (which range-checks integer input on decode) consult this module, so the
two paths cannot disagree about what protoc would accept.

=head1 FUNCTIONS

=over 4

=item range_for($type)

Return the C<($min, $max)> L<Math::BigInt> pair for C<$type>, or an empty list
when C<$type> is not a bounded integer type.

=item is_integer_type($type)

True when C<$type> is one of the bounded integer types.

=item in_range($type, $value)

True when C<$value> lies within C<$type>'s inclusive range. A non-integer
C<$type> is always in range. C<$value> may be a plain number or a
L<Math::BigInt>.

=back

=head1 LICENSE

This software is licensed under the MIT license. See the C<LICENSE> file.

=cut
