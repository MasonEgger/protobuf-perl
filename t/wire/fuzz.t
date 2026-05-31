# ABOUTME: Fuzz test (T-wire-9) for the proto3 wire decoder robustness.
# Feeds 10000 seeded random byte strings through decode_tag + skip_field; every
# input must either fully decode or raise a typed Proto3::Exception::Wire.
package main;

use v5.38;
use warnings;
use Test::More;
use Proto3::Wire qw(decode_tag skip_field);
use Proto3::Exception;
use Scalar::Util qw(blessed);

# Fixed seed for reproducibility: the same 10000 inputs every run.
srand(0x50524F33);    # "PRO3"

my $ITERATIONS = 10000;
my $bad        = 0;

for my $iter (1 .. $ITERATIONS) {
    # Random length 0..40 bytes of random octets.
    my $len   = int(rand(41));
    my $bytes = join '', map { chr(int(rand(256))) } 1 .. $len;

    my $ok = eval {
        my $rest = $bytes;
        # Decode tag-then-skip repeatedly until the buffer is exhausted.
        while (length $rest) {
            my ($field, $wire, $after_tag) = decode_tag($rest);
            $rest = skip_field($wire, $after_tag);
        }
        1;
    };

    next if $ok;    # Clean full decode is acceptable.

    my $err = $@;
    # A failure is acceptable ONLY if it is a typed Wire exception, never an
    # untyped die.
    unless ( blessed($err) && $err->isa('Proto3::Exception::Wire') ) {
        $bad++;
        diag sprintf(
            "iter %d: input %s raised non-Wire error: %s",
            $iter,
            join( ' ', map { sprintf '%02x', ord } split //, $bytes ),
            ( blessed($err) ? ref($err) : "$err" ),
        ) if $bad <= 10;
    }
}

is $bad, 0, "all $ITERATIONS seeded inputs decoded or raised a typed Wire exception";

done_testing;
