# ABOUTME: WKT google.protobuf.Any — JSON form inlines the wrapped message's
# fields beside an "@type" URL, encoding/decoding the inner bytes (§4.8, T-wkt-3).
use v5.38;
use feature 'class';
no warnings 'experimental::class';

use Proto3::Schema::Message;
use Proto3::Schema::Field;
use Proto3::Exception;

class Proto3::WKT::Any {

    # The canonical Schema::Message for google.protobuf.Any: a `type_url` string
    # (field 1) and the serialized inner message `value` bytes (field 2). The
    # generic codec handles the binary form. A fresh instance per call.
    sub schema_message ($class) {
        return Proto3::Schema::Message->new(
            name      => 'Any',
            full_name => 'google.protobuf.Any',
            fields    => [
                Proto3::Schema::Field->new(
                    name => 'type_url', number => 1, type => 'string' ),
                Proto3::Schema::Field->new(
                    name => 'value', number => 2, type => 'bytes' ),
            ],
        );
    }

    # to_json_value($value, $codec) -> hashref { '@type' => $url, ...inner... }.
    #
    # The Any JSON form decodes the wrapped bytes into the inner message's fields
    # and inlines them beside an "@type" key carrying the type URL (proto3 JSON
    # spec, §4.8). The inner type's fully-qualified name is the last path segment
    # of the type_url; $codec must know that message. The merged hashref is the
    # inner fields plus the reserved "@type" key.
    sub to_json_value ( $class, $value, $codec ) {
        my $type_url = $value->{type_url} // '';
        my $bytes    = $value->{value}    // '';

        my $full_name = _full_name_from_url($type_url);
        my $inner     = $codec->decode( $full_name, $bytes );

        return { '@type' => $type_url, %$inner };
    }

    # from_json_value($json, $codec) -> hashref { type_url, value }.
    #
    # Reverse of to_json_value: pull the "@type" key off the object, encode the
    # remaining fields as the inner message, and return the codec's { type_url,
    # value } form. A missing "@type" raises Proto3::Exception::JSON::WKT.
    sub from_json_value ( $class, $json, $codec ) {
        if ( ref $json ne 'HASH' || !defined $json->{'@type'} ) {
            Proto3::Exception::JSON::WKT->throw(
                message => 'Any JSON value must be an object with "@type"',
            );
        }

        my $type_url  = $json->{'@type'};
        my $full_name = _full_name_from_url($type_url);

        my %inner = %$json;
        delete $inner{'@type'};
        my $bytes = $codec->encode( $full_name, \%inner );

        return { type_url => $type_url, value => $bytes };
    }

    # The inner message's fully-qualified name is the last '/'-separated segment
    # of the type URL (e.g. 'type.googleapis.com/demo.Point' -> 'demo.Point').
    sub _full_name_from_url ($type_url) {
        if ( $type_url !~ m{/} ) {
            Proto3::Exception::JSON::WKT->throw(
                message => "Any type_url must contain '/': '$type_url'",
            );
        }
        ( my $name = $type_url ) =~ s{.*/}{};
        return $name;
    }
}

1;

__END__

=head1 NAME

Proto3::WKT::Any - the google.protobuf.Any well-known type

=head1 SYNOPSIS

    use Proto3::WKT::Any;

    my $any = {
        type_url => 'type.googleapis.com/demo.Point',
        value    => $packed_inner_bytes,
    };
    my $json = Proto3::WKT::Any->to_json_value( $any, $codec );
    # { '@type' => 'type.googleapis.com/demo.Point', x => 3, y => 4 }
    my $back = Proto3::WKT::Any->from_json_value( $json, $codec );

=head1 DESCRIPTION

Specialization for C<google.protobuf.Any>, which wraps an arbitrary serialized
message plus a type URL. The binary wire form is the generic two-field
(C<type_url> string, C<value> bytes) encoding handled by L<Proto3::Codec>; the
proto3 JSON form inlines the wrapped message's fields beside an C<@type> key.

=head1 JSON FORM

In proto3 JSON an Any is an object such as
C<{ "@type": "type.googleapis.com/foo.Bar", "field": ... }>: the C<@type> URL
plus the wrapped message's own JSON fields. The inner type's fully-qualified
name is the last C<'/'>-separated segment of the URL. Both conversions need a
L<Proto3::Codec> that knows the inner message so the wrapped bytes can be
decoded (encode) and re-encoded (decode).

=head1 METHODS

=head2 schema_message

Return a fresh canonical L<Proto3::Schema::Message> for the type.

=head2 to_json_value( $value, $codec ) / from_json_value( $json, $codec )

Convert between the C<{ type_url, value }> codec form and the inlined-fields
JSON object. A decode input without C<@type>, or a type URL without a C<'/'>,
raises L<Proto3::Exception::JSON::WKT>.

=head1 LICENSE

This software is licensed under the MIT license. See the C<LICENSE> file.

=cut
