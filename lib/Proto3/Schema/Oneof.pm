# ABOUTME: Schema::Oneof — a oneof group naming its member fields; §4.2.
# Immutable value object; members are Schema::Field instances.
use v5.38;
use feature 'class';
no warnings 'experimental::class';

class Proto3::Schema::Oneof {
    field $name        :param;
    field $fields      :param = [];     # arrayref of Schema::Field members
    field $oneof_index :param = undef;

    # Explicit readers (this Perl build has :param but not :reader).
    method name        { $name }
    method fields      { $fields }
    method oneof_index { $oneof_index }
}

1;

__END__

=head1 NAME

Proto3::Schema::Oneof - A oneof group within a message schema

=head1 DESCRIPTION

Models a oneof: a named set of mutually-exclusive member fields. The members
are C<Proto3::Schema::Field> instances that also appear in the owning message's
field list, each carrying the matching C<oneof_index>.

=head1 LICENSE

This software is licensed under the MIT license. See the C<LICENSE> file.

=cut
