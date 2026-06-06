# ABOUTME: WKT google.protobuf.Duration — canonical schema and the "1.500s"
# fractional-seconds JSON form, including signed durations (§4.8, T-wkt-2).
use v5.38;
use feature 'class';
no warnings 'experimental::class';

use Protobuf::Schema::Message;
use Protobuf::Schema::Field;
use Protobuf::WKT::Util;
use Protobuf::Exception;

# Inclusive seconds range the proto3 Duration type allows: +/- 315576000000
# seconds (about +/- 10000 years). protoc rejects a Duration outside this range
# on JSON input. Pre-class lexical for the feature 'class' scoping rule.
my $DURATION_MAX_SECONDS = 315_576_000_000;

class Protobuf::WKT::Duration {

    # The canonical Schema::Message for google.protobuf.Duration: an int64
    # `seconds` (field 1) and an int32 `nanos` (field 2). Plain proto3 scalars,
    # so the generic codec handles the binary form. A fresh instance per call.
    sub schema_message ($class) {
        return Protobuf::Schema::Message->new(
            name      => 'Duration',
            full_name => 'google.protobuf.Duration',
            fields    => [
                Protobuf::Schema::Field->new(
                    name => 'seconds', number => 1, type => 'int64' ),
                Protobuf::Schema::Field->new(
                    name => 'nanos', number => 2, type => 'int32' ),
            ],
        );
    }

    # from_seconds($seconds, $nanos = 0) -> hashref { seconds, nanos }.
    #
    # Convenience constructor mirroring Timestamp->from_epoch; the codec consumes
    # the plain hashref form.
    sub from_seconds ( $class, $seconds, $nanos = 0 ) {
        return { seconds => $seconds, nanos => $nanos };
    }

    # to_json_value($value) -> string like '1.500s', '60s', or '-1.500s'.
    #
    # Duration renders in JSON as a decimal-seconds string with a trailing 's'
    # (proto3 JSON spec, §4.8). For a negative duration BOTH seconds and nanos
    # are negative (per the proto3 spec); the magnitude is formatted once and a
    # single leading '-' is prepended, so the sign never appears twice.
    sub to_json_value ( $class, $value ) {
        my $seconds = $value->{seconds} // 0;
        my $nanos   = $value->{nanos}   // 0;

        # protoc refuses to serialize a Duration outside +/- 315576000000s, so a
        # protobuf-input-then-JSON-output of such a value must be an error too.
        if (   $seconds > $DURATION_MAX_SECONDS
            || $seconds < -$DURATION_MAX_SECONDS )
        {
            Protobuf::Exception::JSON::WKT->throw(
                message =>
                    "Duration seconds $seconds out of range [+/-${DURATION_MAX_SECONDS}s]",
            );
        }

        # A Duration's nanos magnitude must be 0 .. 999999999, and its sign must
        # agree with the seconds sign: a non-zero seconds and a non-zero nanos of
        # the opposite sign is invalid, as is |nanos| > 999999999. protoc refuses
        # to serialize such a value, so reject rather than emit a bad string.
        if ( $nanos > 999_999_999 || $nanos < -999_999_999 ) {
            Protobuf::Exception::JSON::WKT->throw(
                message =>
                    "Duration nanos $nanos out of range [+/-999999999]",
            );
        }
        if (   ( $seconds > 0 && $nanos < 0 )
            || ( $seconds < 0 && $nanos > 0 ) )
        {
            Protobuf::Exception::JSON::WKT->throw(
                message =>
                    "Duration nanos $nanos sign disagrees with seconds $seconds",
            );
        }

        my $negative = ( $seconds < 0 || $nanos < 0 ) ? 1 : 0;
        my $abs_seconds  = abs $seconds;
        my $abs_nanos    = abs $nanos;

        my $fraction = Protobuf::WKT::Util::fraction_suffix($abs_nanos);
        my $sign = $negative ? '-' : '';
        return "${sign}${abs_seconds}${fraction}s";
    }

    # from_json_value($string) -> hashref { seconds, nanos }.
    #
    # Parse a decimal-seconds-with-'s' duration string. The optional fractional
    # part scales to nanoseconds; a negative duration sets both seconds and nanos
    # negative. Anything not matching '[-]<digits>[.<digits>]s' raises
    # Protobuf::Exception::JSON::WKT.
    sub from_json_value ( $class, $string ) {
        if ( !defined $string || ref $string ) {
            Protobuf::Exception::JSON::WKT->throw(
                message => 'Duration JSON value must be a string',
            );
        }

        my ( $sign, $whole, $frac ) = $string =~ m{
            \A (-?) ([0-9]+) (?: \. ([0-9]+) )? s \z
        }x;

        if ( !defined $whole ) {
            Protobuf::Exception::JSON::WKT->throw(
                message => "malformed Duration: '$string'",
            );
        }

        my $seconds = $whole + 0;
        if ( $seconds > $DURATION_MAX_SECONDS ) {
            Protobuf::Exception::JSON::WKT->throw(
                message =>
                    "Duration '$string' out of range [+/-${DURATION_MAX_SECONDS}s]",
            );
        }

        my $nanos =
            defined $frac ? Protobuf::WKT::Util::parse_fraction($frac) + 0 : 0;

        if ( $sign eq '-' ) {
            $seconds = -$seconds;
            $nanos   = -$nanos;
        }
        return { seconds => $seconds, nanos => $nanos };
    }
}

1;

__END__

=head1 NAME

Protobuf::WKT::Duration - the google.protobuf.Duration well-known type

=head1 SYNOPSIS

    use Protobuf::WKT::Duration;

    my $d    = Protobuf::WKT::Duration->from_seconds( 1, 500_000_000 );
    my $json = Protobuf::WKT::Duration->to_json_value($d);    # '1.500s'
    my $back = Protobuf::WKT::Duration->from_json_value('1.500s');

=head1 DESCRIPTION

Specialization for C<google.protobuf.Duration>. The binary wire form is the
generic two-field (C<seconds> int64, C<nanos> int32) encoding handled by
L<Protobuf::Codec>; this module adds the canonical schema, a C<from_seconds>
convenience constructor, and the proto3 JSON decimal-seconds string form.

=head1 JSON FORM

In proto3 JSON a Duration is a string of seconds with a trailing C<s>, for
example C<"1.500s">, C<"60s">, or C<"-1.500s">. Fractional seconds are trimmed
to 3/6/9 digits. For a negative duration BOTH C<seconds> and C<nanos> are
negative, but the JSON form carries a single leading minus sign.

=head1 METHODS

=head2 schema_message

Return a fresh canonical L<Protobuf::Schema::Message> for the type.

=head2 from_seconds( $seconds, $nanos = 0 )

Return the hashref C<{ seconds, nanos }> value the codec consumes.

=head2 to_json_value( $value ) / from_json_value( $string )

Convert between C<{ seconds, nanos }> and the decimal-seconds JSON string. A
malformed string raises L<Protobuf::Exception::JSON::WKT>.

=head1 LICENSE

This software is licensed under the MIT license. See the C<LICENSE> file.

=cut
