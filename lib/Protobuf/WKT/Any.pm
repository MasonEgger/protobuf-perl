# ABOUTME: WKT google.protobuf.Any — JSON form inlines the wrapped message's
# fields beside an "@type" URL, encoding/decoding the inner bytes (§4.8, T-wkt-3).
use v5.38;
use feature 'class';
no warnings 'experimental::class';

use Protobuf::Schema::Message;
use Protobuf::Schema::Field;
use Protobuf::Exception;

class Protobuf::WKT::Any {

    # The canonical Schema::Message for google.protobuf.Any: a `type_url` string
    # (field 1) and the serialized inner message `value` bytes (field 2). The
    # generic codec handles the binary form. A fresh instance per call.
    sub schema_message ($class) {
        return Protobuf::Schema::Message->new(
            name      => 'Any',
            full_name => 'google.protobuf.Any',
            fields    => [
                Protobuf::Schema::Field->new(
                    name => 'type_url', number => 1, type => 'string' ),
                Protobuf::Schema::Field->new(
                    name => 'value', number => 2, type => 'bytes' ),
            ],
        );
    }

    # to_json_value($value, $codec, $json) -> hashref { '@type' => $url, ... }.
    #
    # The Any JSON form decodes the wrapped bytes into the inner message and
    # embeds its JSON beside an "@type" key carrying the type URL (proto3 JSON
    # spec, §4.8). $codec (the binary codec) turns the stored bytes into the
    # inner message's codec shape; $json (the Protobuf::JSON encoder) turns that
    # shape into the inner message's JSON. For an ordinary message the inner JSON
    # is an object whose fields inline beside "@type"; for a well-known type with
    # a special JSON form (Timestamp/Duration/Struct/Value/wrappers/Any/...) the
    # special form is carried under a reserved "value" key.
    sub to_json_value ( $class, $value, $codec, $json ) {
        my $type_url = $value->{type_url} // '';
        my $bytes    = $value->{value}    // '';

        # An empty Any (no type_url) is valid and serializes to the empty JSON
        # object {} — the round-trip partner of from_json_value({}) accepting an
        # empty object as an empty Any (conformance AnyWithNoType).
        if ( $type_url eq '' ) {
            return {};
        }

        my $full_name = _full_name_from_url($type_url);
        my $inner     = $codec->decode( $full_name, $bytes );
        my $structure = $json->json_structure_for( $full_name, $inner );

        if ( $json->wkt_has_special_form($full_name) ) {
            return { '@type' => $type_url, value => $structure };
        }
        return { '@type' => $type_url, %$structure };
    }

    # from_json_value($json_value, $codec, $json) -> hashref { type_url, value }.
    #
    # Reverse of to_json_value: read the "@type" URL (which may appear in any key
    # position), reconstruct the inner message's JSON (either the "value"-wrapped
    # special form of a well-known type, or the remaining inlined fields of an
    # ordinary message), JSON-decode it to the inner message's codec shape, and
    # binary-encode that to the stored bytes. A missing "@type" raises JSON::WKT.
    sub from_json_value ( $class, $json_value, $codec, $json ) {
        if ( ref $json_value ne 'HASH' ) {
            Protobuf::Exception::JSON::WKT->throw(
                message => 'Any JSON value must be an object',
            );
        }

        # An empty JSON object {} is a VALID empty Any (no type_url, no value),
        # per the proto3 JSON spec and the conformance suite (AnyWithNoType).
        # Only a non-empty object is required to carry an "@type".
        if ( !%$json_value ) {
            return { type_url => '', value => '' };
        }

        if ( !defined $json_value->{'@type'} ) {
            Protobuf::Exception::JSON::WKT->throw(
                message => 'Any JSON value must be an object with "@type"',
            );
        }

        my $type_url  = $json_value->{'@type'};
        my $full_name = _full_name_from_url($type_url);

        my $inner_json;
        if ( $json->wkt_has_special_form($full_name) ) {
            $inner_json = $json_value->{value};
        }
        else {
            my %inner = %$json_value;
            delete $inner{'@type'};
            $inner_json = \%inner;
        }

        my $shape = $json->message_from_json( $full_name, $inner_json );
        my $bytes = $codec->encode( $full_name, $shape );

        return { type_url => $type_url, value => $bytes };
    }

    # The inner message's fully-qualified name is the last '/'-separated segment
    # of the type URL (e.g. 'type.googleapis.com/demo.Point' -> 'demo.Point').
    sub _full_name_from_url ($type_url) {
        if ( $type_url !~ m{/} ) {
            Protobuf::Exception::JSON::WKT->throw(
                message => "Any type_url must contain '/': '$type_url'",
            );
        }
        ( my $name = $type_url ) =~ s{.*/}{};
        return $name;
    }
}

1;

__END__

=encoding utf-8

=head1 NAME

Protobuf::WKT::Any - the google.protobuf.Any well-known type

=head1 SYNOPSIS

    use Protobuf::WKT::Any;

    my $any = {
        type_url => 'type.googleapis.com/demo.Point',
        value    => $packed_inner_bytes,
    };
    my $json = Protobuf::WKT::Any->to_json_value( $any, $codec );
    # { '@type' => 'type.googleapis.com/demo.Point', x => 3, y => 4 }
    my $back = Protobuf::WKT::Any->from_json_value( $json, $codec );

=head1 DESCRIPTION

Specialization for C<google.protobuf.Any>, which wraps an arbitrary serialized
message plus a type URL. The binary wire form is the generic two-field
(C<type_url> string, C<value> bytes) encoding handled by L<Protobuf::Codec>; the
proto3 JSON form inlines the wrapped message's fields beside an C<@type> key.

=head1 JSON FORM

In proto3 JSON an Any is an object such as
C<{ "@type": "type.googleapis.com/foo.Bar", "field": ... }>: the C<@type> URL
plus the wrapped message's own JSON fields. The inner type's fully-qualified
name is the last C<'/'>-separated segment of the URL. Both conversions need a
L<Protobuf::Codec> that knows the inner message so the wrapped bytes can be
decoded (encode) and re-encoded (decode).

=head1 METHODS

=head2 schema_message

Return a fresh canonical L<Protobuf::Schema::Message> for the type.

=head2 to_json_value( $value, $codec ) / from_json_value( $json, $codec )

Convert between the C<{ type_url, value }> codec form and the inlined-fields
JSON object. A decode input without C<@type>, or a type URL without a C<'/'>,
raises L<Protobuf::Exception::JSON::WKT>.

=head1 LICENSE

This software is licensed under the MIT license. See the C<LICENSE> file.

=cut
