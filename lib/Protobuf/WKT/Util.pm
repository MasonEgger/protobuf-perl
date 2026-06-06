# ABOUTME: Shared RFC3339 + fractional-seconds helpers for the WKT JSON forms.
# Used by Protobuf::WKT::Timestamp and Protobuf::WKT::Duration; not public API.
use v5.38;
use warnings;

package Protobuf::WKT::Util;

use POSIX qw(floor);
use Protobuf::Exception;

# Render the fractional part of a (seconds, nanos) pair as a JSON suffix string.
#
# The proto3 JSON spec renders sub-second precision at 3/6/9-digit granularity:
# milliseconds get 3 digits, microseconds 6, nanoseconds 9, and an exact whole
# second emits no fractional part at all. $nanos is the absolute (non-negative)
# nanosecond count; the caller owns the sign. Returns either '' or '.NNN...'.
sub fraction_suffix ($nanos) {
    return '' if $nanos == 0;

    # Nine-digit, zero-padded nanoseconds, then trim to the shortest of the
    # 3/6/9 buckets that preserves the value (matching protoc's canonical form).
    my $digits = sprintf( '%09d', $nanos );
    if ( $digits =~ /000000$/ ) {
        $digits = substr( $digits, 0, 3 );
    }
    elsif ( $digits =~ /000$/ ) {
        $digits = substr( $digits, 0, 6 );
    }
    return ".$digits";
}

# Parse a fractional-second string (the part after '.', e.g. '500' or '5') into
# an integer nanosecond count. A bare digit run scaled to nine digits: '5' ->
# 500_000_000, '789' -> 789_000_000. Dies JSON::WKT on a non-digit fraction.
sub parse_fraction ($frac) {
    if ( $frac !~ /\A[0-9]+\z/ || length($frac) > 9 ) {
        Protobuf::Exception::JSON::WKT->throw(
            message => "invalid fractional seconds: '.$frac'",
        );
    }
    # Right-pad to nine digits so the run is interpreted as nanoseconds.
    return $frac . ( '0' x ( 9 - length $frac ) );
}

# Convert a UTC epoch-seconds count into the date/time components of an RFC3339
# string (without the fractional part or trailing 'Z'). Returns the prefix
# 'YYYY-MM-DDTHH:MM:SS'. Uses POSIX::gmtime-equivalent civil-date math so the
# result is independent of the host time zone and of any DST quirks.
sub rfc3339_prefix ($seconds) {
    my @gm = gmtime($seconds);
    return sprintf(
        '%04d-%02d-%02dT%02d:%02d:%02d',
        $gm[5] + 1900, $gm[4] + 1, $gm[3], $gm[2], $gm[1], $gm[0],
    );
}

# Parse the date/time prefix of an RFC3339 string into epoch seconds (UTC).
# Accepts 'YYYY-MM-DDTHH:MM:SS'; the caller has already split off the optional
# fraction and zone. Dies JSON::WKT on a malformed prefix.
sub parse_rfc3339_prefix ($prefix) {
    my ( $y, $mon, $d, $h, $min, $s ) = $prefix =~ m{
        \A (\d{4}) - (\d{2}) - (\d{2}) T (\d{2}) : (\d{2}) : (\d{2}) \z
    }x;
    if ( !defined $y ) {
        Protobuf::Exception::JSON::WKT->throw(
            message => "malformed RFC3339 timestamp: '$prefix'",
        );
    }
    require Time::Local;
    return Time::Local::timegm_modern( $s, $min, $h, $d, $mon - 1, $y );
}

1;

__END__

=encoding utf-8

=head1 NAME

Protobuf::WKT::Util - RFC3339 and fractional-seconds helpers for well-known types

=head1 DESCRIPTION

Internal helpers shared by L<Protobuf::WKT::Timestamp> and L<Protobuf::WKT::Duration>
for converting between the C<(seconds, nanos)> representation and the proto3 JSON
string forms. Not part of the public API.

=head1 FUNCTIONS

=head2 fraction_suffix( $nanos )

Render an absolute nanosecond count as a C<.NNN> / C<.NNNNNN> / C<.NNNNNNNNN>
suffix (or the empty string for zero), trimmed to the shortest of the 3/6/9-digit
buckets that preserves the value.

=head2 parse_fraction( $frac )

Parse a fractional-second digit run into an integer nanosecond count, scaling to
nine digits. Dies C<Protobuf::Exception::JSON::WKT> on non-digit or over-long input.

=head2 rfc3339_prefix( $seconds )

Format UTC epoch seconds as C<YYYY-MM-DDTHH:MM:SS> (no fraction, no zone).

=head2 parse_rfc3339_prefix( $prefix )

Parse C<YYYY-MM-DDTHH:MM:SS> back into UTC epoch seconds. Dies
C<Protobuf::Exception::JSON::WKT> on a malformed prefix.

=head1 LICENSE

This software is licensed under the MIT license. See the C<LICENSE> file.

=cut
