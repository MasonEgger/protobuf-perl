# ABOUTME: WKT google.protobuf.Timestamp — canonical schema, from_epoch ctor,
# and the RFC3339 JSON form (§4.8, T-wkt-1). Binary form is the generic codec's.
use v5.38;
use feature 'class';
no warnings 'experimental::class';

use Proto3::Schema::Message;
use Proto3::Schema::Field;
use Proto3::WKT::Util;
use Proto3::Exception;

class Proto3::WKT::Timestamp {

    # The canonical Schema::Message for google.protobuf.Timestamp: an int64
    # `seconds` (field 1) and an int32 `nanos` (field 2). Both are plain proto3
    # singular scalars, so the generic Proto3::Codec encodes/decodes the binary
    # form with no WKT-specific handling. A fresh instance is built per call.
    sub schema_message ($class) {
        return Proto3::Schema::Message->new(
            name      => 'Timestamp',
            full_name => 'google.protobuf.Timestamp',
            fields    => [
                Proto3::Schema::Field->new(
                    name => 'seconds', number => 1, type => 'int64' ),
                Proto3::Schema::Field->new(
                    name => 'nanos', number => 2, type => 'int32' ),
            ],
        );
    }

    # from_epoch($seconds, $nanos = 0) -> hashref { seconds, nanos }.
    #
    # Convenience constructor: returns the plain-hashref value the codec consumes
    # (the codec interface is hashref-based; there is no blessed Timestamp object).
    sub from_epoch ( $class, $seconds, $nanos = 0 ) {
        return { seconds => $seconds, nanos => $nanos };
    }

    # to_json_value($value) -> RFC3339 string, e.g. '2023-11-14T22:13:20.789Z'.
    #
    # Timestamps render in JSON as an RFC3339 UTC string with optional fractional
    # seconds (trimmed to 3/6/9 digits) and a trailing 'Z', NOT as a
    # { seconds, nanos } object (proto3 JSON spec, §4.8). nanos are non-negative
    # per the spec, so the fraction is always rendered after the whole second.
    sub to_json_value ( $class, $value ) {
        my $seconds = $value->{seconds} // 0;
        my $nanos   = $value->{nanos}   // 0;

        my $prefix   = Proto3::WKT::Util::rfc3339_prefix($seconds);
        my $fraction = Proto3::WKT::Util::fraction_suffix($nanos);
        return "$prefix${fraction}Z";
    }

    # from_json_value($string) -> hashref { seconds, nanos }.
    #
    # Parse an RFC3339 string back into seconds/nanos. Only the canonical UTC 'Z'
    # form with an optional fractional part is accepted; anything malformed raises
    # Proto3::Exception::JSON::WKT.
    sub from_json_value ( $class, $string ) {
        if ( !defined $string || ref $string ) {
            Proto3::Exception::JSON::WKT->throw(
                message => 'Timestamp JSON value must be an RFC3339 string',
            );
        }

        my ( $prefix, $frac ) = $string =~ m{
            \A ( \d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2} )
               (?: \. ([0-9]+) )?
               Z \z
        }x;

        if ( !defined $prefix ) {
            Proto3::Exception::JSON::WKT->throw(
                message => "malformed RFC3339 timestamp: '$string'",
            );
        }

        my $seconds = Proto3::WKT::Util::parse_rfc3339_prefix($prefix);
        my $nanos =
            defined $frac ? Proto3::WKT::Util::parse_fraction($frac) : 0;
        return { seconds => $seconds, nanos => $nanos };
    }
}

1;

__END__

=head1 NAME

Proto3::WKT::Timestamp - the google.protobuf.Timestamp well-known type

=head1 SYNOPSIS

    use Proto3::WKT::Timestamp;

    my $ts   = Proto3::WKT::Timestamp->from_epoch( 1_700_000_000, 789_000_000 );
    my $json = Proto3::WKT::Timestamp->to_json_value($ts); # '2023-11-14T22:13:20.789Z'
    my $back = Proto3::WKT::Timestamp->from_json_value($json);

=head1 DESCRIPTION

Specialization for C<google.protobuf.Timestamp>. The binary wire form is the
generic two-field (C<seconds> int64, C<nanos> int32) encoding handled by
L<Proto3::Codec>; this module adds the canonical schema, a C<from_epoch>
convenience constructor, and the proto3 JSON RFC3339 string form.

=head1 JSON FORM

In proto3 JSON, a Timestamp is an RFC3339 UTC string such as
C<"2023-11-14T22:13:20.789Z"> (fractional seconds trimmed to 3/6/9 digits, or
omitted for a whole second), NOT a C<{ seconds, nanos }> object.

=head1 METHODS

=head2 schema_message

Return a fresh canonical L<Proto3::Schema::Message> for the type.

=head2 from_epoch( $seconds, $nanos = 0 )

Return the hashref C<{ seconds, nanos }> value the codec consumes.

=head2 to_json_value( $value ) / from_json_value( $string )

Convert between C<{ seconds, nanos }> and the RFC3339 JSON string. A malformed
string raises L<Proto3::Exception::JSON::WKT>.

=head1 LICENSE

This software is licensed under the MIT license. See the C<LICENSE> file.

=cut
