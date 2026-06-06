# ABOUTME: WKT google.protobuf.*Value wrappers — one parametric handler for all
# nine primitive wrappers, whose JSON form is the bare inner value (§4.8, T-wkt-5).
use v5.38;
use feature 'class';
no warnings 'experimental::class';

use JSON::PP ();
use MIME::Base64 ();

use Protobuf::Schema::Message;
use Protobuf::Schema::Field;
use Protobuf::Exception;

# Full name -> the scalar proto3 type of the wrapper's single `value` field.
# Held as a pre-class lexical so methods read it without the feature 'class'
# package-scoping trap (an imported constant would land in the file package).
my %WRAPPER_TYPE = (
    'google.protobuf.DoubleValue' => 'double',
    'google.protobuf.FloatValue'  => 'float',
    'google.protobuf.Int64Value'  => 'int64',
    'google.protobuf.UInt64Value' => 'uint64',
    'google.protobuf.Int32Value'  => 'int32',
    'google.protobuf.UInt32Value' => 'uint32',
    'google.protobuf.BoolValue'   => 'bool',
    'google.protobuf.StringValue' => 'string',
    'google.protobuf.BytesValue'  => 'bytes',
);

class Protobuf::WKT::Wrappers {

    # full_names() -> the list of all nine wrapper fully-qualified names, so the
    # facade can register a schema and JSON handler for each from one place.
    sub full_names ($class) {
        my @names = sort keys %WRAPPER_TYPE;
        return @names;
    }

    # schema_message($full_name) -> the canonical Schema::Message for one wrapper:
    # a single `value` field (number 1) of the wrapper's scalar type. A fresh
    # instance per call. An unknown name raises Protobuf::Exception::Argument.
    sub schema_message ( $class, $full_name ) {
        my $type = $WRAPPER_TYPE{$full_name}
            or Protobuf::Exception::Argument->throw(
            message => "not a wrapper type: '$full_name'" );

        ( my $simple = $full_name ) =~ s/.*\.//;
        return Protobuf::Schema::Message->new(
            name      => $simple,
            full_name => $full_name,
            fields    => [
                Protobuf::Schema::Field->new(
                    name => 'value', number => 1, type => $type ),
            ],
        );
    }

    # to_json_value($full_name, $value) -> the bare inner value.
    #
    # A wrapper renders in JSON as its inner value directly: Int32Value(42)
    # becomes 42, NOT { "value": 42 } (proto3 JSON spec, §4.8). The inner value
    # is in the codec representation, so bool (a native 1/0) becomes a JSON
    # boolean and bytes (raw octets) become base64 — the same scalar mapping the
    # ordinary JSON encoder applies. Every other type passes through unchanged.
    sub to_json_value ( $class, $full_name, $value ) {
        _assert_wrapper($full_name);
        my $inner = $value->{value};
        return $inner unless defined $inner;

        my $type = $WRAPPER_TYPE{$full_name};
        return $inner ? JSON::PP::true : JSON::PP::false if $type eq 'bool';
        return MIME::Base64::encode_base64( $inner, '' ) if $type eq 'bytes';
        return $inner;
    }

    # from_json_value($full_name, $json) -> hashref { value => $json }.
    #
    # Map the bare JSON value back into the { value => ... } codec form. bool
    # (a JSON::PP::Boolean) is normalized to a native 1/0 and bytes (base64) are
    # decoded to raw octets, matching the codec representation the binary encoder
    # expects; every other type passes through unchanged.
    sub from_json_value ( $class, $full_name, $json ) {
        _assert_wrapper($full_name);
        return { value => $json } unless defined $json;

        my $type = $WRAPPER_TYPE{$full_name};
        return { value => ( $json ? 1 : 0 ) } if $type eq 'bool';
        return { value => MIME::Base64::decode_base64("$json") }
            if $type eq 'bytes';
        return { value => $json };
    }

    # Raise Protobuf::Exception::Argument unless $full_name is a known wrapper.
    sub _assert_wrapper ($full_name) {
        return if exists $WRAPPER_TYPE{$full_name};
        Protobuf::Exception::Argument->throw(
            message => "not a wrapper type: '$full_name'" );
    }
}

1;

__END__

=encoding utf-8

=head1 NAME

Protobuf::WKT::Wrappers - the google.protobuf primitive wrapper well-known types

=head1 SYNOPSIS

    use Protobuf::WKT::Wrappers;

    my $json = Protobuf::WKT::Wrappers->to_json_value(
        'google.protobuf.Int32Value', { value => 42 } );   # 42
    my $back = Protobuf::WKT::Wrappers->from_json_value(
        'google.protobuf.Int32Value', 42 );                # { value => 42 }

=head1 DESCRIPTION

One parametric handler for all nine C<google.protobuf.*Value> wrappers
(C<Bool>, C<Int32>, C<Int64>, C<UInt32>, C<UInt64>, C<Float>, C<Double>,
C<String>, C<Bytes>). Each wraps a single primitive C<value> field; the binary
wire form is the generic one-field encoding handled by L<Protobuf::Codec>.

=head1 JSON FORM

A wrapper renders in JSON as its B<inner value directly>, not as an object:
C<Int32Value(42)> is C<42>, never C<{ "value": 42 }> (proto3 JSON spec, §4.8).

=head1 METHODS

=head2 full_names

Return the sorted list of all nine wrapper fully-qualified names.

=head2 schema_message( $full_name )

Return a fresh canonical L<Protobuf::Schema::Message> for one wrapper type.

=head2 to_json_value( $full_name, $value ) / from_json_value( $full_name, $json )

Convert between the C<{ value => ... }> codec form and the bare JSON value.

=head1 LICENSE

This software is licensed under the MIT license. See the C<LICENSE> file.

=cut
