# ABOUTME: Protobuf::Class::Accessor — computes a generated class's accessor base
# name from a proto field name, appending "_" on a Perl keyword clash (§4.6).
use v5.38;
use warnings;

package Protobuf::Class::Accessor;

# Proto field names that collide with a Perl keyword or builtin would, as a bare
# method name, read confusingly or shadow language constructs. Following
# protoc-gen-python's pattern, such a name gets a trailing underscore so the
# accessor is e.g. `package_` for a field named `package`. The set covers Perl's
# named operators and control keywords; a clashing name maps to "<name>_".
my %KEYWORD = map { $_ => 1 } qw(
    BEGIN END AUTOLOAD DESTROY
    if elsif else unless while until for foreach do
    sub package use no require my our local state
    and or not xor eq ne lt gt le ge cmp
    return last next redo goto
    print printf say
    open close read write
    chomp chop chr crypt
    each keys values delete exists
    push pop shift unshift splice
    map grep sort reverse join split
    wantarray ref bless tie untie
    defined undef scalar
    eval die warn
    new
);

# accessor_name($field_name) -> the base accessor name for the generated class.
# A field name that clashes with a Perl keyword/builtin gets a trailing
# underscore (matching protoc-gen-python); every other name is returned as-is.
sub accessor_name ($field_name) {
    return $KEYWORD{$field_name} ? "${field_name}_" : $field_name;
}

1;

__END__

=head1 NAME

Protobuf::Class::Accessor - Accessor-name computation for generated classes

=head1 DESCRIPTION

Maps a proto field name to the base name used for its generated accessors.
A field whose name collides with a Perl keyword or builtin (for example
C<package> or C<print>) receives a trailing underscore, so its reader is
C<package_> and its setter C<set_package_>. This mirrors the convention
C<protoc-gen-python> uses for Python keyword clashes. The underlying proto
field name (used as the C<to_hashref> key and on the wire) is unchanged.

=head1 FUNCTIONS

=head2 accessor_name

    my $base = Protobuf::Class::Accessor::accessor_name('package');  # 'package_'
    my $base = Protobuf::Class::Accessor::accessor_name('encoding'); # 'encoding'

Returns the accessor base name for a proto field name.

=head1 LICENSE

This software is licensed under the MIT license. See the C<LICENSE> file.

=cut
