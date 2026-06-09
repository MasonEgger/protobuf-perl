# ABOUTME: Schema::Enum — an enum type and its values; §4.2.
# Construction rejects duplicate value numbers unless allow_alias is set.
use v5.38;
use feature 'class';
no warnings 'experimental::class';

use Protobuf::Schema::Util;
use Protobuf::Exception;

class Protobuf::Schema::Enum {
    field $name        :param;
    field $full_name   :param;
    field $values      :param = [];     # arrayref of { name, number }
    field $allow_alias :param = 0;
    field $options     :param = {};
    field $closed      :param = undef;  # 1=closed (proto2), 0=open (proto3);
                                        # resolver derives from enum_type feature
    field $features    :param = {};     # explicit overrides -> resolved FeatureSet

    # Explicit readers (this Perl build has :param but not :reader).
    method name        { $name }
    method full_name   { $full_name }
    method values      { $values }
    method allow_alias { $allow_alias }
    method options     { $options }
    method features    { $features }

    # Closedness: 0 (open) by default — the proto3 default. The resolver sets it
    # from the effective enum_type feature (CLOSED -> 1) when resolving.
    method closed { $closed // 0 }

    # The resolver installs the enum's effective FeatureSet and derives the
    # closed flag from it. Idempotent like the Field setter.
    method set_features ($resolved) {
        $features = $resolved;
        $closed   = $resolved->enum_type eq 'CLOSED' ? 1 : 0;
        return $self;
    }

    # Construction invariant: without allow_alias, value numbers must be unique.
    ADJUST {
        unless ( $allow_alias ) {
            my @numbers = map { $_->{number} } @$values;
            Protobuf::Schema::Util::assert_unique(
                \@numbers,
                'Protobuf::Exception::Schema',
                "enum $full_name has duplicate value number %s (allow_alias not set)",
            );
        }
    }
}

1;

__END__

=encoding utf-8

=head1 NAME

Protobuf::Schema::Enum - An enum type within a schema

=head1 SYNOPSIS

    use Protobuf::Schema::Enum;

    my $enum = Protobuf::Schema::Enum->new(
        name      => 'Status',
        full_name => 'pkg.Status',
        values    => [
            { name => 'UNKNOWN', number => 0 },
            { name => 'ACTIVE',  number => 1 },
        ],
    );

    $enum->name;      # 'Status'
    $enum->values;    # arrayref of { name, number } hashrefs
    $enum->closed;    # 0 (open) until the resolver sets it from features

Enum objects are usually produced by L<Protobuf::Parser> or
L<Protobuf::DescriptorSet> rather than constructed by hand.

=head1 DESCRIPTION

Models a proto3 enum: its short and fully-qualified names plus its values
(C<{ name, number }> hashrefs).

=head1 ACCESSORS

Each returns the correspondingly-named construction value.

=over 4

=item C<name>

The enum's short name.

=item C<full_name>

The enum's fully-qualified, package-prefixed name.

=item C<values>

An arrayref of C<< { name, number } >> value hashrefs.

=item C<allow_alias>

True when the enum permits two values to share a number.

=item C<options>

A hashref of enum-level options.

=item C<closed>

True when the enum is CLOSED (proto2/editions-proto2 semantics: an unknown
numeric value is not preserved in-field); false (open) by default. The resolver
derives this from the effective C<enum_type> feature.

=item C<features>

The enum's explicit feature overrides before resolution, or its resolved
L<Protobuf::Schema::Features> afterward.

=item C<set_features($resolved)>

The resolver installs the enum's effective L<Protobuf::Schema::Features> and
derives C<closed> from it. Returns C<$self>.

=back

=head1 CONSTRUCTION INVARIANTS

When C<allow_alias> is false (the default), two values may not share the same
number; construction raises C<Protobuf::Exception::Schema> if they do. Setting
C<allow_alias> to a true value permits aliasing, matching proto3's
C<option allow_alias = true;>.

=head1 LICENSE

This software is licensed under the MIT license. See the C<LICENSE> file.

=cut
