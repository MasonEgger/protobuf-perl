# ABOUTME: Tests for Protobuf::Resolver — proto3 type-name scoping (spec §4.3).
# Covers fully-qualified vs relative lookup, innermost-first search order,
# nested-message scope, and the ordered search_path on UnresolvedType.
use v5.38;
use strict;
use warnings;
use utf8;
use Test::More;

use Protobuf::Resolver;
use Protobuf::Schema;
use Protobuf::Schema::File;
use Protobuf::Schema::Message;
use Protobuf::Schema::Enum;

# Helper: build a Schema from a list of message full_names. Each message is
# placed in a single file; package is irrelevant to the resolver (it indexes
# purely by fully-qualified name), so one synthetic file holds them all.
sub schema_with_messages (@full_names) {
    my @messages = map {
        my $full = $_;
        my ($short) = $full =~ /([^.]+)$/;
        Protobuf::Schema::Message->new(
            name => $short, full_name => $full, fields => [],
        );
    } @full_names;

    my $file = Protobuf::Schema::File->new(
        name => 'test.proto', package => '', messages => \@messages,
    );
    my $schema = Protobuf::Schema->new;
    $schema->add_file($file);
    return $schema;
}

# ---------------------------------------------------------------------------
# 8.1 / T-res-1: A leading-dot name is fully qualified; strip the dot and look
# up exactly, from any package.
{
    my $schema   = schema_with_messages('foo.bar.Baz');
    my $resolver = Protobuf::Resolver->new( schema => $schema );

    my $ref = $resolver->resolve(
        type_name       => '.foo.bar.Baz',
        current_package => 'totally.unrelated.pkg',
        current_message => undef,
    );
    is( $ref->full_name, 'foo.bar.Baz',
        'fully-qualified .foo.bar.Baz resolves directly (T-res-1)' );
}

# ---------------------------------------------------------------------------
# 8.2 / T-res-2: Relative common.X from package coresdk.workflow_activation,
# with coresdk.common.X defined, resolves to coresdk.common.X.
{
    my $schema   = schema_with_messages('coresdk.common.X');
    my $resolver = Protobuf::Resolver->new( schema => $schema );

    my $ref = $resolver->resolve(
        type_name       => 'common.X',
        current_package => 'coresdk.workflow_activation',
        current_message => undef,
    );
    is( $ref->full_name, 'coresdk.common.X',
        'relative common.X resolves to inner coresdk.common.X (T-res-2)' );
}

# ---------------------------------------------------------------------------
# 8.3 / T-res-3: Same relative ref with ONLY root common.X defined resolves to
# root common.X.
{
    my $schema   = schema_with_messages('common.X');
    my $resolver = Protobuf::Resolver->new( schema => $schema );

    my $ref = $resolver->resolve(
        type_name       => 'common.X',
        current_package => 'coresdk.workflow_activation',
        current_message => undef,
    );
    is( $ref->full_name, 'common.X',
        'relative common.X resolves to root when only root defined (T-res-3)' );
}

# ---------------------------------------------------------------------------
# 8.4 / T-res-4: With BOTH coresdk.common.X and root common.X defined, the
# innermost (coresdk.common.X) wins.
{
    my $schema   = schema_with_messages( 'coresdk.common.X', 'common.X' );
    my $resolver = Protobuf::Resolver->new( schema => $schema );

    my $ref = $resolver->resolve(
        type_name       => 'common.X',
        current_package => 'coresdk.workflow_activation',
        current_message => undef,
    );
    is( $ref->full_name, 'coresdk.common.X',
        'innermost wins when both inner and root defined (T-res-4)' );
}

# ---------------------------------------------------------------------------
# 8.5 / T-res-5: Nested-message scope. Reference `Bar` from inside
# foo.Outer.Inner searches foo.Outer.Inner.Bar, foo.Outer.Bar, foo.Bar, Bar.
{
    my $schema   = schema_with_messages('foo.Bar');
    my $resolver = Protobuf::Resolver->new( schema => $schema );

    my $ref = $resolver->resolve(
        type_name       => 'Bar',
        current_package => 'foo',
        current_message => 'foo.Outer.Inner',
    );
    is( $ref->full_name, 'foo.Bar',
        'nested-message search reaches foo.Bar (T-res-5)' );

    # The pure candidate-list helper must produce exactly the documented order.
    my @candidates = Protobuf::Resolver::candidate_names(
        'Bar', 'foo', 'foo.Outer.Inner',
    );
    is_deeply(
        \@candidates,
        [ 'foo.Outer.Inner.Bar', 'foo.Outer.Bar', 'foo.Bar', 'Bar' ],
        'candidate_names yields documented innermost-first order (T-res-5)',
    );
}

# candidate_names for a package-only scope (no current_message) walks the
# package components outward then root.
{
    my @candidates = Protobuf::Resolver::candidate_names(
        'common.X', 'foo.bar.baz', undef,
    );
    is_deeply(
        \@candidates,
        [
            'foo.bar.baz.common.X',
            'foo.bar.common.X',
            'foo.common.X',
            'common.X',
        ],
        'candidate_names walks package scopes innermost-first then root',
    );
}

# A fully-qualified name produces a single candidate (the stripped name).
{
    my @candidates = Protobuf::Resolver::candidate_names(
        '.foo.bar.Baz', 'anything', 'anything.Msg',
    );
    is_deeply(
        \@candidates, ['foo.bar.Baz'],
        'candidate_names for a leading-dot name yields only the exact name',
    );
}

# ---------------------------------------------------------------------------
# 8.6 / T-res-6: Unresolvable type raises UnresolvedType carrying the ordered
# search_path of exactly the fq names attempted, in order.
{
    my $schema   = schema_with_messages('coresdk.common.X');
    my $resolver = Protobuf::Resolver->new( schema => $schema );

    my $err = do {
        local $@;
        eval {
            $resolver->resolve(
                type_name       => 'common.Missing',
                current_package => 'coresdk.workflow_activation',
                current_message => undef,
            );
            1;
        } ? undef : $@;
    };

    ok( $err, 'unresolvable type dies' );
    isa_ok( $err, 'Protobuf::Exception::Schema::UnresolvedType',
        'unresolvable type raises UnresolvedType (T-res-6)' );
    is( $err->name, 'common.Missing', 'exception carries the dangling name' );
    is( $err->current_package, 'coresdk.workflow_activation',
        'exception carries current_package' );
    is_deeply(
        $err->search_path,
        [
            'coresdk.workflow_activation.common.Missing',
            'coresdk.common.Missing',
            'common.Missing',
        ],
        'search_path lists exactly the fq names attempted, in order (T-res-6)',
    );
    like( "$err", qr/common\.Missing/,
        'exception stringifies with the dangling name' );
}

# Enums resolve through the same index as messages.
{
    my $color = Protobuf::Schema::Enum->new(
        name => 'Color', full_name => 'pkg.Color', values => [],
    );
    my $file = Protobuf::Schema::File->new(
        name => 'e.proto', package => 'pkg', enums => [$color],
    );
    my $schema = Protobuf::Schema->new;
    $schema->add_file($file);
    my $resolver = Protobuf::Resolver->new( schema => $schema );

    my $ref = $resolver->resolve(
        type_name       => 'Color',
        current_package => 'pkg',
        current_message => undef,
    );
    is( $ref->full_name, 'pkg.Color', 'enums resolve via the same index' );
}

done_testing;
