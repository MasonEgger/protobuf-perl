# ABOUTME: WKT google.protobuf.FieldMask — JSON form is a comma-separated string
# of dot-paths whose segments are camelCased on the wire (§4.8, T-wkt-4).
use v5.38;
use feature 'class';
no warnings 'experimental::class';

use Proto3::Schema::Message;
use Proto3::Schema::Field;
use Proto3::Exception;

class Proto3::WKT::FieldMask {

    # The canonical Schema::Message for google.protobuf.FieldMask: a single
    # `repeated string paths` field (number 1). A fresh instance per call.
    sub schema_message ($class) {
        return Proto3::Schema::Message->new(
            name      => 'FieldMask',
            full_name => 'google.protobuf.FieldMask',
            fields    => [
                Proto3::Schema::Field->new(
                    name   => 'paths',
                    number => 1,
                    type   => 'string',
                    label  => 'repeated',
                ),
            ],
        );
    }

    # to_json_value($value) -> comma-joined camelCase string.
    #
    # FieldMask renders in JSON as a single string of comma-separated paths; each
    # dotted path's segments are converted from snake_case to camelCase (proto3
    # JSON spec, §4.8). An empty path list yields the empty string.
    sub to_json_value ( $class, $value ) {
        my $paths = $value->{paths} // [];
        return join ',', map { _path_to_camel($_) } @$paths;
    }

    # from_json_value($string) -> hashref { paths => [...] }.
    #
    # Split the comma-separated string and convert each path's segments back from
    # camelCase to snake_case. The empty string decodes to an empty path list.
    # A non-string value raises Proto3::Exception::JSON::WKT.
    sub from_json_value ( $class, $string ) {
        if ( !defined $string || ref $string ) {
            Proto3::Exception::JSON::WKT->throw(
                message => 'FieldMask JSON value must be a string',
            );
        }
        return { paths => [] } if $string eq '';
        my @paths = map { _path_to_snake($_) } split /,/, $string;
        return { paths => \@paths };
    }

    # Convert a dotted path's segments from snake_case to camelCase.
    sub _path_to_camel ($path) {
        return join '.', map { _camel($_) } split /\./, $path, -1;
    }

    # Convert a dotted path's segments from camelCase to snake_case.
    sub _path_to_snake ($path) {
        return join '.', map { _snake($_) } split /\./, $path, -1;
    }

    # snake_case -> camelCase: drop each underscore, upper-case the next char.
    sub _camel ($s) {
        $s =~ s/_(.)/\U$1/g;
        return $s;
    }

    # camelCase -> snake_case: lower-case each upper-case char, prefixing '_'.
    sub _snake ($s) {
        $s =~ s/([A-Z])/'_' . lc $1/ge;
        return $s;
    }
}

1;

__END__

=head1 NAME

Proto3::WKT::FieldMask - the google.protobuf.FieldMask well-known type

=head1 SYNOPSIS

    use Proto3::WKT::FieldMask;

    my $json = Proto3::WKT::FieldMask->to_json_value(
        { paths => [ 'foo_bar.baz', 'a.b' ] } );    # 'fooBar.baz,a.b'
    my $back = Proto3::WKT::FieldMask->from_json_value('fooBar.baz,a.b');

=head1 DESCRIPTION

Specialization for C<google.protobuf.FieldMask>. The binary wire form is the
generic C<repeated string paths> encoding handled by L<Proto3::Codec>; the
proto3 JSON form is a single comma-separated string whose dotted-path segments
are camelCased.

=head1 JSON FORM

In proto3 JSON a FieldMask is a string such as C<"fooBar.baz,a.b">: paths joined
by commas, each path's segments converted from C<snake_case> to C<camelCase>.
The empty path list is the empty string.

=head1 METHODS

=head2 schema_message

Return a fresh canonical L<Proto3::Schema::Message> for the type.

=head2 to_json_value( $value ) / from_json_value( $string )

Convert between C<{ paths => [...] }> and the comma-separated camelCase string. A
non-string decode input raises L<Proto3::Exception::JSON::WKT>.

=head1 LICENSE

This software is licensed under the MIT license. See the C<LICENSE> file.

=cut
