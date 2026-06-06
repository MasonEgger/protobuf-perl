# ABOUTME: Schema::Features — the editions FeatureSet model and resolution.
# Holds the six protobuf features, edition defaults, and an override-merge pass.
use v5.38;
use feature 'class';
no warnings 'experimental::class';

use Protobuf::Exception;

# Edition-default FeatureSets, held as a pre-class lexical so methods inside the
# class block can read it without tripping the feature 'class' package-scoping
# trap. Keyed by edition string: 'proto2', 'proto3', '2023'.
my %EDITION_DEFAULTS = (
    proto2 => {
        field_presence          => 'EXPLICIT',
        enum_type               => 'CLOSED',
        repeated_field_encoding => 'EXPANDED',
        message_encoding        => 'LENGTH_PREFIXED',
        utf8_validation         => 'NONE',
        json_format             => 'ALLOW',
    },
    proto3 => {
        field_presence          => 'IMPLICIT',
        enum_type               => 'OPEN',
        repeated_field_encoding => 'PACKED',
        message_encoding        => 'LENGTH_PREFIXED',
        utf8_validation         => 'VERIFY',
        json_format             => 'ALLOW',
    },
    '2023' => {
        field_presence          => 'EXPLICIT',
        enum_type               => 'OPEN',
        repeated_field_encoding => 'PACKED',
        message_encoding        => 'LENGTH_PREFIXED',
        utf8_validation         => 'VERIFY',
        json_format             => 'ALLOW',
    },
);

# The recognized feature names, used to validate override keys.
my %FEATURE_NAMES = map { $_ => 1 } qw(
    field_presence enum_type repeated_field_encoding
    message_encoding utf8_validation json_format
);

class Protobuf::Schema::Features {
    field $field_presence          :param;
    field $enum_type               :param;
    field $repeated_field_encoding :param;
    field $message_encoding        :param;
    field $utf8_validation         :param;
    field $json_format             :param;

    # Explicit readers (this Perl build has :param but not :reader).
    method field_presence          { $field_presence }
    method enum_type               { $enum_type }
    method repeated_field_encoding { $repeated_field_encoding }
    method message_encoding        { $message_encoding }
    method utf8_validation         { $utf8_validation }
    method json_format             { $json_format }

    # The FeatureSet as a plain hashref (a copy; mutating it does not affect us).
    method to_hash {
        return {
            field_presence          => $field_presence,
            enum_type               => $enum_type,
            repeated_field_encoding => $repeated_field_encoding,
            message_encoding        => $message_encoding,
            utf8_validation         => $utf8_validation,
            json_format             => $json_format,
        };
    }
}

# Build the edition-default FeatureSet for 'proto2', 'proto3', or '2023'. Dies
# with Protobuf::Exception::Schema for an unknown edition — defaults are a closed
# set, an unexpected edition is a bug we want surfaced loudly.
sub Protobuf::Schema::Features::for_edition ($class, $edition) {
    my $defaults = $EDITION_DEFAULTS{$edition}
        or Protobuf::Exception::Schema->throw(
            message => "unknown edition '$edition'",
        );
    return $class->new(%$defaults);
}

# Merge an override hashref over a base FeatureSet, returning a NEW FeatureSet.
# $base may be a Features object or a plain hashref; $override is a hashref whose
# present keys win over the base. Unknown override keys die loudly (boundary
# validation). This is the single merge primitive the resolver composes to fold
# edition defaults <- parent features <- explicit overrides.
sub Protobuf::Schema::Features::merge ($class, $base, $override = {}) {
    my $merged = ref $base eq 'HASH' ? { %$base } : $base->to_hash;

    for my $key ( keys %$override ) {
        $FEATURE_NAMES{$key}
            or Protobuf::Exception::Schema->throw(
                message => "unknown feature override key '$key'",
            );
        my $val = $override->{$key};
        $merged->{$key} = $val if defined $val;
    }

    return $class->new(%$merged);
}

1;

__END__

=head1 NAME

Protobuf::Schema::Features - The editions FeatureSet model and resolution

=head1 SYNOPSIS

    use Protobuf::Schema::Features;

    my $p3 = Protobuf::Schema::Features->for_edition('proto3');
    $p3->field_presence;   # 'IMPLICIT'

    my $merged = Protobuf::Schema::Features->merge(
        $p3, { field_presence => 'EXPLICIT' },
    );

=head1 DESCRIPTION

Models a protobuf C<FeatureSet>: the six features that drive editions-aware
encoding and presence semantics. Provides per-edition default FeatureSets and an
override-merge primitive the schema resolver folds to compute each scope's
effective features.

=head1 FEATURES

=over 4

=item C<field_presence> — C<EXPLICIT> / C<IMPLICIT> / C<LEGACY_REQUIRED>

=item C<enum_type> — C<OPEN> / C<CLOSED>

=item C<repeated_field_encoding> — C<PACKED> / C<EXPANDED>

=item C<message_encoding> — C<LENGTH_PREFIXED> / C<DELIMITED>

=item C<utf8_validation> — C<VERIFY> / C<NONE>

=item C<json_format> — C<ALLOW> / C<LEGACY_BEST_EFFORT>

=back

=head1 EDITION DEFAULTS

=over 4

=item proto2

EXPLICIT, CLOSED, EXPANDED, LENGTH_PREFIXED, NONE, ALLOW.

=item proto3

IMPLICIT, OPEN, PACKED, LENGTH_PREFIXED, VERIFY, ALLOW.

=item 2023

EXPLICIT, OPEN, PACKED, LENGTH_PREFIXED, VERIFY, ALLOW.

=back

=head1 CLASS METHODS

=over 4

=item C<< Protobuf::Schema::Features->for_edition($edition) >>

Return the default FeatureSet for C<'proto2'>, C<'proto3'>, or C<'2023'>. Dies
with L<Protobuf::Exception::Schema> for an unknown edition.

=item C<< Protobuf::Schema::Features->merge($base, $override) >>

Return a new FeatureSet with C<$override>'s defined keys applied over C<$base>
(a Features object or a plain hashref). Unknown override keys die. This is the
primitive the resolver composes to fold edition defaults under inherited parent
features under explicit overrides.

=back

=head1 INSTANCE METHODS

=over 4

=item C<to_hash>

A plain-hashref copy of the FeatureSet's six values.

=back

=head1 LICENSE

This software is licensed under the MIT license. See the C<LICENSE> file.

=cut
