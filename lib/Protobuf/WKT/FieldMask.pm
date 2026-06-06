# ABOUTME: WKT google.protobuf.FieldMask — JSON form is a comma-separated string
# of dot-paths whose segments are camelCased on the wire (§4.8, T-wkt-4).
use v5.38;
use feature 'class';
no warnings 'experimental::class';

use Protobuf::Schema::Message;
use Protobuf::Schema::Field;
use Protobuf::Exception;

class Protobuf::WKT::FieldMask {

    # The canonical Schema::Message for google.protobuf.FieldMask: a single
    # `repeated string paths` field (number 1). A fresh instance per call.
    sub schema_message ($class) {
        return Protobuf::Schema::Message->new(
            name      => 'FieldMask',
            full_name => 'google.protobuf.FieldMask',
            fields    => [
                Protobuf::Schema::Field->new(
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
        return join ',', map { _path_to_camel_checked($_) } @$paths;
    }

    # snake_case -> camelCase for a single path, rejecting any path that does NOT
    # round-trip (proto3 JSON spec, §4.8 — FieldMask*DontRoundTrip). A proto path
    # whose camelCase form cannot be converted back to the original is not
    # serializable: this covers a segment already carrying an uppercase letter
    # (FieldMaskPathsDontRoundTrip, e.g. "fooBar"), a digit after an underscore
    # (FieldMaskNumbersDontRoundTrip, e.g. "foo_3_bar"), and a doubled or trailing
    # underscore (FieldMaskTooManyUnderscore, e.g. "foo__bar").
    sub _path_to_camel_checked ($path) {
        my $camel = _path_to_camel($path);
        if ( _path_to_snake($camel) ne $path ) {
            Protobuf::Exception::JSON::WKT->throw(
                message => "FieldMask path '$path' does not round-trip to camelCase",
            );
        }
        return $camel;
    }

    # from_json_value($string) -> hashref { paths => [...] }.
    #
    # Split the comma-separated string and convert each path's segments back from
    # camelCase to snake_case. The empty string decodes to an empty path list.
    # A non-string value raises Protobuf::Exception::JSON::WKT.
    sub from_json_value ( $class, $string ) {
        if ( !defined $string || ref $string ) {
            Protobuf::Exception::JSON::WKT->throw(
                message => 'FieldMask JSON value must be a string',
            );
        }
        return { paths => [] } if $string eq '';
        # The JSON form is camelCase: an input path segment must not itself carry
        # an underscore (FieldMaskInvalidCharacter, e.g. "bar_bar"). Such a value
        # is rejected rather than silently snake-cased.
        if ( $string =~ /_/ ) {
            Protobuf::Exception::JSON::WKT->throw(
                message => "FieldMask JSON path contains an invalid character '_'",
            );
        }
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

Protobuf::WKT::FieldMask - the google.protobuf.FieldMask well-known type

=head1 SYNOPSIS

    use Protobuf::WKT::FieldMask;

    my $json = Protobuf::WKT::FieldMask->to_json_value(
        { paths => [ 'foo_bar.baz', 'a.b' ] } );    # 'fooBar.baz,a.b'
    my $back = Protobuf::WKT::FieldMask->from_json_value('fooBar.baz,a.b');

=head1 DESCRIPTION

Specialization for C<google.protobuf.FieldMask>. The binary wire form is the
generic C<repeated string paths> encoding handled by L<Protobuf::Codec>; the
proto3 JSON form is a single comma-separated string whose dotted-path segments
are camelCased.

=head1 JSON FORM

In proto3 JSON a FieldMask is a string such as C<"fooBar.baz,a.b">: paths joined
by commas, each path's segments converted from C<snake_case> to C<camelCase>.
The empty path list is the empty string.

=head1 METHODS

=head2 schema_message

Return a fresh canonical L<Protobuf::Schema::Message> for the type.

=head2 to_json_value( $value ) / from_json_value( $string )

Convert between C<{ paths => [...] }> and the comma-separated camelCase string. A
non-string decode input raises L<Protobuf::Exception::JSON::WKT>.

=head1 LICENSE

This software is licensed under the MIT license. See the C<LICENSE> file.

=cut
