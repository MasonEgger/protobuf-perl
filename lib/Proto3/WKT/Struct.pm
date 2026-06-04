# ABOUTME: WKT google.protobuf.Struct/Value/ListValue/NullValue — the dynamic
# JSON-value family whose JSON forms are arbitrary JSON data (§4.8, T-wkt-6).
use v5.38;
use feature 'class';
no warnings 'experimental::class';

use Proto3::Schema::Message;
use Proto3::Schema::Field;
use Proto3::Schema::Enum;
use Proto3::Schema::Oneof;
use JSON::PP ();
use B ();
use Proto3::Exception;

# True when a non-ref, defined JSON scalar was decoded as a JSON number (it
# carries an integer or float SV flag) rather than a JSON string. proto3 maps a
# JSON number to Value.number_value but a JSON string to Value.string_value, so
# a quoted "5678" must NOT become number_value. A pre-class lexical: a file-scope
# bareword sub is invisible inside the feature-'class' methods below, so they
# close over this coderef instead. The do{} wrapper insulates the signatured sub
# from this Perl build's class-adjacent parse glitch.
my $is_json_number = do {
    sub ($value) {
        my $flags = B::svref_2object( \$value )->FLAGS;
        return ( $flags & ( B::SVf_IOK() | B::SVf_NOK() ) ) ? 1 : 0;
    };
};

# google.protobuf.NullValue — a singleton enum whose only value is NULL_VALUE=0.
# Its JSON form is the literal null. to_json_value ignores its (always-0) input
# and yields undef; from_json_value maps null back to the enum number 0.
class Proto3::WKT::NullValue {

    sub schema_enum ($class) {
        return Proto3::Schema::Enum->new(
            name      => 'NullValue',
            full_name => 'google.protobuf.NullValue',
            values    => [ { name => 'NULL_VALUE', number => 0 } ],
        );
    }

    sub to_json_value ( $class, $value ) { return undef }

    sub from_json_value ( $class, $json ) { return 0 }
}

# google.protobuf.Value — a dynamically typed value (the oneof over null, number,
# string, bool, struct, list). In the JSON mapping a Value IS its JSON value, so
# both conversions pass the JSON-shaped Perl data straight through.
class Proto3::WKT::Value {

    sub schema_message ($class) {
        my $null_field = Proto3::Schema::Field->new(
            name => 'null_value', number => 1, type => 'enum',
            type_name => '.google.protobuf.NullValue', oneof_index => 0 );
        my $number_field = Proto3::Schema::Field->new(
            name => 'number_value', number => 2, type => 'double',
            oneof_index => 0 );
        my $string_field = Proto3::Schema::Field->new(
            name => 'string_value', number => 3, type => 'string',
            oneof_index => 0 );
        my $bool_field = Proto3::Schema::Field->new(
            name => 'bool_value', number => 4, type => 'bool',
            oneof_index => 0 );
        my $struct_field = Proto3::Schema::Field->new(
            name => 'struct_value', number => 5, type => 'message',
            type_name => '.google.protobuf.Struct', oneof_index => 0 );
        my $list_field = Proto3::Schema::Field->new(
            name => 'list_value', number => 6, type => 'message',
            type_name => '.google.protobuf.ListValue', oneof_index => 0 );

        return Proto3::Schema::Message->new(
            name      => 'Value',
            full_name => 'google.protobuf.Value',
            fields    => [
                $null_field, $number_field, $string_field,
                $bool_field, $struct_field, $list_field,
            ],
            oneofs => [
                Proto3::Schema::Oneof->new(
                    name => 'kind', oneof_index => 0,
                    fields => [
                        $null_field, $number_field, $string_field,
                        $bool_field, $struct_field, $list_field,
                    ],
                ),
            ],
        );
    }

    # to_json_value($value) -> arbitrary JSON. The codec message shape is a
    # single-key hashref naming the set oneof member (number_value, string_value,
    # bool_value, null_value, struct_value, list_value); map it to the bare JSON
    # value of that kind. struct_value/list_value recurse through their own
    # handlers. An empty hashref (no oneof set) yields JSON null.
    sub to_json_value ( $class, $value ) {
        return undef unless ref $value eq 'HASH';

        return undef if exists $value->{null_value};
        if ( exists $value->{number_value} ) {
            my $n = $value->{number_value} + 0;
            # A google.protobuf.Value's number_value is a JSON number, and JSON
            # has no NaN/Infinity literal: a Value wrapping NaN or +/-Inf cannot
            # be serialized (ValueRejectNanNumberValue/ValueRejectInfNumberValue).
            if ( $n != $n || $n == 9**9**9 || $n == -9**9**9 ) {
                Proto3::Exception::JSON::WKT->throw(
                    message => 'google.protobuf.Value number_value '
                        . 'cannot be NaN or Infinity in JSON',
                );
            }
            return $n;
        }
        return "$value->{string_value}"   if exists $value->{string_value};
        return $value->{bool_value}
            ? JSON::PP::true
            : JSON::PP::false
            if exists $value->{bool_value};
        return Proto3::WKT::Struct->to_json_value( $value->{struct_value} )
            if exists $value->{struct_value};
        return Proto3::WKT::ListValue->to_json_value( $value->{list_value} )
            if exists $value->{list_value};

        # No oneof member set -> the proto3 default Value is null.
        return undef;
    }

    # from_json_value($json) -> message shape. Classify the arbitrary JSON value
    # and wrap it in the matching oneof member: undef->null_value, a JSON::PP
    # boolean->bool_value, an arrayref->list_value, a hashref->struct_value, a
    # numeric scalar->number_value, anything else->string_value.
    sub from_json_value ( $class, $json ) {
        return { null_value => 0 } unless defined $json;

        if ( JSON::PP::is_bool($json) ) {
            return { bool_value => $json ? 1 : 0 };
        }
        if ( ref $json eq 'ARRAY' ) {
            return { list_value =>
                    Proto3::WKT::ListValue->from_json_value($json) };
        }
        if ( ref $json eq 'HASH' ) {
            return { struct_value =>
                    Proto3::WKT::Struct->from_json_value($json) };
        }
        if ( $is_json_number->($json) ) {
            return { number_value => $json + 0 };
        }
        return { string_value => "$json" };
    }
}

# google.protobuf.ListValue — a wrapper around a repeated Value. Its codec shape
# is { values => [ <Value-shape>, ... ] }; its JSON form is a JSON array of the
# elements' JSON values.
class Proto3::WKT::ListValue {

    sub schema_message ($class) {
        return Proto3::Schema::Message->new(
            name      => 'ListValue',
            full_name => 'google.protobuf.ListValue',
            fields    => [
                Proto3::Schema::Field->new(
                    name => 'values', number => 1, type => 'message',
                    label => 'repeated',
                    type_name => '.google.protobuf.Value' ),
            ],
        );
    }

    # to_json_value($value) -> JSON array. Map each element of the values list
    # through the Value handler.
    sub to_json_value ( $class, $value ) {
        my $values = ( ref $value eq 'HASH' ? $value->{values} : undef ) // [];
        return [ map { Proto3::WKT::Value->to_json_value($_) } @$values ];
    }

    # from_json_value($json) -> { values => [ <Value-shape>, ... ] }. Each JSON
    # element becomes a Value message shape.
    sub from_json_value ( $class, $json ) {
        my $array = ref $json eq 'ARRAY' ? $json : [];
        return {
            values => [ map { Proto3::WKT::Value->from_json_value($_) } @$array ]
        };
    }
}

# google.protobuf.Struct — a map<string, Value>. Its codec shape is
# { fields => { key => <Value-shape> } }; its JSON form is a JSON object whose
# values are the fields' JSON values.
class Proto3::WKT::Struct {

    sub schema_message ($class) {
        my $entry = Proto3::Schema::Message->new(
            name        => 'FieldsEntry',
            full_name   => 'google.protobuf.Struct.FieldsEntry',
            is_map_entry => 1,
            fields      => [
                Proto3::Schema::Field->new(
                    name => 'key', number => 1, type => 'string' ),
                Proto3::Schema::Field->new(
                    name => 'value', number => 2, type => 'message',
                    type_name => '.google.protobuf.Value' ),
            ],
        );
        return Proto3::Schema::Message->new(
            name      => 'Struct',
            full_name => 'google.protobuf.Struct',
            nested_messages => [$entry],
            fields    => [
                Proto3::Schema::Field->new(
                    name => 'fields', number => 1, type => 'message',
                    label => 'repeated',
                    map_entry => $entry,
                    type_name => '.google.protobuf.Struct.FieldsEntry' ),
            ],
        );
    }

    # to_json_value($value) -> JSON object. Map each field value through the
    # Value handler, keyed by the field name.
    sub to_json_value ( $class, $value ) {
        my $fields = ( ref $value eq 'HASH' ? $value->{fields} : undef ) // {};
        return {
            map { $_ => Proto3::WKT::Value->to_json_value( $fields->{$_} ) }
                keys %$fields
        };
    }

    # from_json_value($json) -> { fields => { key => <Value-shape> } }. Each JSON
    # object value becomes a Value message shape.
    sub from_json_value ( $class, $json ) {
        my $obj = ref $json eq 'HASH' ? $json : {};
        return {
            fields => {
                map { $_ => Proto3::WKT::Value->from_json_value( $obj->{$_} ) }
                    keys %$obj
            }
        };
    }
}

1;

__END__

=head1 NAME

Proto3::WKT::Struct - the google.protobuf Struct/Value/ListValue/NullValue family

=head1 SYNOPSIS

    use Proto3::WKT::Struct;

    my $json = Proto3::WKT::Struct->to_json_value( { a => 1, b => [ 2, 3 ] } );
    my $back = Proto3::WKT::Struct->from_json_value($json);

    Proto3::WKT::NullValue->to_json_value(0);     # undef (JSON null)
    Proto3::WKT::NullValue->from_json_value(undef); # 0

=head1 DESCRIPTION

The dynamic-value well-known types. This module defines four cooperating
classes:

=over 4

=item * L<google.protobuf.Struct|/Proto3::WKT::Struct> — a C<map<string, Value>>;
JSON form is a JSON object.

=item * C<Proto3::WKT::Value> — the C<oneof> over null/number/string/bool/struct/
list; JSON form is any JSON value.

=item * C<Proto3::WKT::ListValue> — a repeated C<Value>; JSON form is a JSON array.

=item * C<Proto3::WKT::NullValue> — a singleton enum; JSON form is C<null>.

=back

=head1 JSON FORM

A Struct is a JSON object, a ListValue a JSON array, a Value any JSON value, and
a NullValue the literal C<null>. Because the proto3 JSON mapping makes each of
these I<be> its JSON value, the C<to_json_value> / C<from_json_value> pairs for
Struct, Value, and ListValue pass the JSON-shaped Perl data through unchanged;
NullValue maps between the enum number C<0> and C<undef> (JSON null).

=head1 METHODS

Each class in this family provides the same set of class methods:

=over 4

=item C<schema_message>

Returns a fresh canonical L<Proto3::Schema::Message> for the type.
(C<Proto3::WKT::NullValue> instead provides C<schema_enum>, since it is an enum.)

=item C<schema_enum>

I<(C<Proto3::WKT::NullValue> only.)> Returns a fresh canonical
L<Proto3::Schema::Enum> for C<google.protobuf.NullValue>.

=item C<to_json_value($value)>

Maps the internal value to its proto3 JSON form.

=item C<from_json_value($json)>

Maps a decoded JSON value back to the internal form.

=back

=head1 LICENSE

This software is licensed under the MIT license. See the C<LICENSE> file.

=cut
