# ABOUTME: Shared construction-time validation helpers for Schema element classes.
# assert_unique flags duplicate keys (field numbers/names, enum numbers) at build.
use v5.38;
use warnings;

package Protobuf::Schema::Util;

use Protobuf::Exception;

# assert_unique( \@keys, $exception_class, $message_template )
#
# Dies with an instance of $exception_class if any value in @keys repeats.
# $message_template may contain a single %s placeholder for the duplicate key.
# Called fully-qualified from inside Schema element class methods/ADJUST blocks
# (Protobuf::Schema::Util::assert_unique(...)) to avoid the feature 'class'
# package-scoping trap where an imported sub lands in the wrong package.
sub assert_unique ( $keys, $exception_class, $message_template ) {
    my %seen;
    for my $key ( @$keys ) {
        if ( $seen{$key}++ ) {
            $exception_class->throw(
                message => sprintf( $message_template, $key ),
            );
        }
    }
    return 1;
}

1;

__END__

=head1 NAME

Protobuf::Schema::Util - Construction-time validation helpers for the schema model

=head1 DESCRIPTION

Internal helper used by the C<Protobuf::Schema::*> element classes to enforce
uniqueness invariants at construction time. Not part of the public API.

=head1 FUNCTIONS

=head2 assert_unique( \@keys, $exception_class, $message_template )

Throws an instance of C<$exception_class> (via its inherited C<throw>) if any
value in C<\@keys> appears more than once. C<$message_template> is passed to
C<sprintf> with the offending key as its single argument.

=head1 LICENSE

This software is licensed under the MIT license. See the C<LICENSE> file.

=cut
