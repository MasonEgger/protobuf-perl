# ABOUTME: CPAN dependency manifest for the Proto3 distribution.
# Runtime and test prerequisites; grows as features land.

requires 'perl', '5.038000';

# Runtime (both core in modern Perl, declared for clarity).
requires 'Math::BigInt';
requires 'Encode';

on 'test' => sub {
    requires 'Test2::V0';
};
