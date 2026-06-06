# ABOUTME: Protobuf::Resolver — proto3 type-name scoping resolution (spec §4.3).
# Indexes a Schema by fully-qualified name and resolves relative/absolute refs
# using innermost-first scope search, the rule GPB::Dynamic gets wrong.
use v5.38;
use feature 'class';
no warnings 'experimental::class';

use Protobuf::Exception;

# Pure helper (a plain sub, not a method, so its output is directly assertable
# in tests without constructing a Resolver). Given a type reference, the package
# it was written in, and the enclosing message (or undef), return the ordered
# list of fully-qualified candidate names to try, innermost scope first.
#
# - A leading-dot name is fully qualified: strip the dot, single candidate.
# - Otherwise the starting scope is the enclosing message's fq name when given,
#   else the package. Walk that scope outward one dotted component at a time
#   down to the empty root, prefixing each scope onto the reference.
#
# Two feature 'class' traps drive how this is declared: a signatured plain sub
# before the class block trips the parser, and a sub declared with a bare name
# at file scope lands in 'main', not this package. Naming it fully-qualified
# (sub Protobuf::Resolver::candidate_names) plus @_ unpacking sidesteps both, so
# resolve() and tests can call Protobuf::Resolver::candidate_names reliably.
sub Protobuf::Resolver::candidate_names {
    my ( $type_name, $current_package, $current_message ) = @_;

    if ( index( $type_name, '.' ) == 0 ) {
        return ( substr( $type_name, 1 ) );
    }

    my $scope = defined $current_message && length $current_message
        ? $current_message
        : ( $current_package // '' );

    my @candidates;
    while (1) {
        push @candidates,
            length $scope ? "$scope.$type_name" : $type_name;
        last unless length $scope;
        # Trim the innermost (last) dotted component to move one scope outward.
        if ( ( my $dot = rindex( $scope, '.' ) ) >= 0 ) {
            $scope = substr( $scope, 0, $dot );
        }
        else {
            $scope = '';
        }
    }
    return @candidates;
}

class Protobuf::Resolver {
    field $schema :param;
    field $index;     # fq name -> Schema::Message|Schema::Enum

    # Build the fully-qualified-name index once from the schema's flattened
    # messages and enums.
    ADJUST {
        $index = {};
        $index->{ $_->full_name } = $_ for @{ $schema->all_messages };
        $index->{ $_->full_name } = $_ for @{ $schema->all_enums };
    }

    # Resolve a type reference to its Schema::Message or Schema::Enum, following
    # proto3 scoping rules. Dies with UnresolvedType (carrying the ordered
    # search_path) when no candidate matches.
    method resolve (%args) {
        my $type_name       = $args{type_name};
        my $current_package = $args{current_package};
        my $current_message = $args{current_message};

        my @search_path = candidate_names(
            $type_name, $current_package, $current_message,
        );

        for my $fq (@search_path) {
            return $index->{$fq} if exists $index->{$fq};
        }

        Protobuf::Exception::Schema::UnresolvedType->throw(
            message => sprintf(
                "could not resolve type '%s' in package '%s'; tried: %s",
                $type_name,
                $current_package // '',
                join( ', ', @search_path ),
            ),
            name            => $type_name,
            current_package => $current_package,
            search_path     => \@search_path,
        );
    }
}

1;

__END__

=head1 NAME

Protobuf::Resolver - proto3 type-name scoping resolution

=head1 SYNOPSIS

    use Protobuf::Resolver;

    my $resolver = Protobuf::Resolver->new( schema => $schema );

    my $ref = $resolver->resolve(
        type_name       => 'common.WorkerDeploymentVersion',
        current_package => 'coresdk.workflow_activation',
        current_message => undef,   # or an enclosing message fq name
    );
    # $ref is a Protobuf::Schema::Message or Protobuf::Schema::Enum, or dies.

=head1 DESCRIPTION

Implements the proto3 type-reference lookup rules exactly. This is the single
component the reference Perl protobuf libraries get wrong; correctness here is a
primary success criterion.

On construction the resolver builds an index keyed by fully-qualified name over
C<< $schema->all_messages >> and C<< $schema->all_enums >> (nested types
flattened by the schema facade).

=head1 SCOPING RULES

For a type reference C<T>:

=over 4

=item *

B<Fully qualified.> If C<T> begins with a leading dot (e.g. C<.foo.Other>),
strip the dot and look up exactly. No scope search.

=item *

B<Relative.> Otherwise search each enclosing scope B<innermost first>. The
starting scope is the enclosing message's fully-qualified name when
C<current_message> is given, otherwise C<current_package>. Each scope is walked
outward one dotted component at a time down to the root. The first candidate
present in the index wins. For C<T = common.X> in package C<foo.bar.baz> the
candidates, in order, are:

    foo.bar.baz.common.X
    foo.bar.common.X
    foo.common.X
    common.X

For a reference inside a nested message, the message name participates in the
prefix: C<Bar> from inside C<foo.Outer.Inner> tries C<foo.Outer.Inner.Bar>,
C<foo.Outer.Bar>, C<foo.Bar>, then C<Bar>.

=back

=head1 FUNCTIONS

=over 4

=item candidate_names($type_name, $current_package, $current_message)

A pure function (not a method) returning the ordered list of fully-qualified
candidate names that L</resolve> will try, innermost scope first. Exposed so the
exact search order is directly assertable in tests.

=back

=head1 METHODS

=over 4

=item new(schema => $schema)

Construct a resolver over a L<Protobuf::Schema>, building the fully-qualified-name
index once.

=item resolve(type_name => ..., current_package => ..., current_message => ...)

Resolve a type reference to its L<Protobuf::Schema::Message> or
L<Protobuf::Schema::Enum>. On no match, throws
L<Protobuf::Exception::Schema::UnresolvedType> carrying C<name>,
C<current_package>, and the ordered C<search_path>.

=back

=head1 LICENSE

This software is licensed under the MIT license. See the C<LICENSE> file.

=cut
