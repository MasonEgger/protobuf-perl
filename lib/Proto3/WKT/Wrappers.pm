# ABOUTME: WKT google.protobuf.*Value wrappers — one parametric handler for all
# nine primitive wrappers, whose JSON form is the bare inner value (§4.8, T-wkt-5).
use v5.38;
use feature 'class';
no warnings 'experimental::class';

use Proto3::Schema::Message;
use Proto3::Schema::Field;
use Proto3::Exception;

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

class Proto3::WKT::Wrappers {

    # full_names() -> the list of all nine wrapper fully-qualified names, so the
    # facade can register a schema and JSON handler for each from one place.
    sub full_names ($class) {
        return sort keys %WRAPPER_TYPE;
    }

    # schema_message($full_name) -> the canonical Schema::Message for one wrapper:
    # a single `value` field (number 1) of the wrapper's scalar type. A fresh
    # instance per call. An unknown name raises Proto3::Exception::Argument.
    sub schema_message ( $class, $full_name ) {
        my $type = $WRAPPER_TYPE{$full_name}
            or Proto3::Exception::Argument->throw(
            message => "not a wrapper type: '$full_name'" );

        ( my $simple = $full_name ) =~ s/.*\.//;
        return Proto3::Schema::Message->new(
            name      => $simple,
            full_name => $full_name,
            fields    => [
                Proto3::Schema::Field->new(
                    name => 'value', number => 1, type => $type ),
            ],
        );
    }

    # to_json_value($full_name, $value) -> the bare inner value.
    #
    # A wrapper renders in JSON as its inner value directly: Int32Value(42)
    # becomes 42, NOT { "value": 42 } (proto3 JSON spec, §4.8). The same path
    # serves all nine wrapper types; an absent `value` defaults per proto3.
    sub to_json_value ( $class, $full_name, $value ) {
        _assert_wrapper($full_name);
        return $value->{value};
    }

    # from_json_value($full_name, $json) -> hashref { value => $json }.
    #
    # Wrap the bare JSON value back into the { value => ... } codec form. The
    # same path serves all nine wrapper types.
    sub from_json_value ( $class, $full_name, $json ) {
        _assert_wrapper($full_name);
        return { value => $json };
    }

    # Raise Proto3::Exception::Argument unless $full_name is a known wrapper.
    sub _assert_wrapper ($full_name) {
        return if exists $WRAPPER_TYPE{$full_name};
        Proto3::Exception::Argument->throw(
            message => "not a wrapper type: '$full_name'" );
    }
}

1;

__END__

=head1 NAME

Proto3::WKT::Wrappers - the google.protobuf primitive wrapper well-known types

=head1 SYNOPSIS

    use Proto3::WKT::Wrappers;

    my $json = Proto3::WKT::Wrappers->to_json_value(
        'google.protobuf.Int32Value', { value => 42 } );   # 42
    my $back = Proto3::WKT::Wrappers->from_json_value(
        'google.protobuf.Int32Value', 42 );                # { value => 42 }

=head1 DESCRIPTION

One parametric handler for all nine C<google.protobuf.*Value> wrappers
(C<Bool>, C<Int32>, C<Int64>, C<UInt32>, C<UInt64>, C<Float>, C<Double>,
C<String>, C<Bytes>). Each wraps a single primitive C<value> field; the binary
wire form is the generic one-field encoding handled by L<Proto3::Codec>.

=head1 JSON FORM

A wrapper renders in JSON as its B<inner value directly>, not as an object:
C<Int32Value(42)> is C<42>, never C<{ "value": 42 }> (proto3 JSON spec, §4.8).

=head1 METHODS

=head2 full_names

Return the sorted list of all nine wrapper fully-qualified names.

=head2 schema_message( $full_name )

Return a fresh canonical L<Proto3::Schema::Message> for one wrapper type.

=head2 to_json_value( $full_name, $value ) / from_json_value( $full_name, $json )

Convert between the C<{ value => ... }> codec form and the bare JSON value.

=head1 LICENSE

This software is licensed under the MIT license. See the C<LICENSE> file.

=cut
