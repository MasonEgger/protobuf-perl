# ABOUTME: WKT google.protobuf.Empty — a fieldless message whose JSON form is
# the empty object {} (§4.8, Step 27). Binary form is the generic codec's.
use v5.38;
use feature 'class';
no warnings 'experimental::class';

use Protobuf::Schema::Message;

class Protobuf::WKT::Empty {

    # The canonical Schema::Message for google.protobuf.Empty: no fields. The
    # generic codec encodes it to the empty byte string. A fresh instance per
    # call so callers never share mutable schema state.
    sub schema_message ($class) {
        return Protobuf::Schema::Message->new(
            name      => 'Empty',
            full_name => 'google.protobuf.Empty',
            fields    => [],
        );
    }

    # to_json_value($value) -> {}. Empty has no fields, so its JSON form is
    # always the empty object regardless of the (ignored) input hashref.
    sub to_json_value ( $class, $value ) {
        return {};
    }

    # from_json_value($json) -> {}. The JSON object form decodes to the empty
    # value hashref the codec consumes.
    sub from_json_value ( $class, $json ) {
        return {};
    }
}

1;

__END__

=encoding utf-8

=head1 NAME

Protobuf::WKT::Empty - the google.protobuf.Empty well-known type

=head1 SYNOPSIS

    use Protobuf::WKT::Empty;

    my $json = Protobuf::WKT::Empty->to_json_value( {} );    # {}
    my $back = Protobuf::WKT::Empty->from_json_value( {} );  # {}

=head1 DESCRIPTION

Specialization for C<google.protobuf.Empty>, a fieldless message. The binary
wire form is the empty byte string (handled by L<Protobuf::Codec>); the proto3
JSON form is the empty object C<{}>.

=head1 METHODS

=head2 schema_message

Return a fresh canonical L<Protobuf::Schema::Message> for the type (no fields).

=head2 to_json_value( $value ) / from_json_value( $json )

Convert between the empty value hashref and the JSON empty object C<{}>.

=head1 LICENSE

This software is licensed under the MIT license. See the C<LICENSE> file.

=cut
