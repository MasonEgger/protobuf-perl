# ABOUTME: Tests for the Protobuf::Schema facade — file registry, fully-qualified
# name index (incl. nested), flattening, duplicate detection, and lookups.
use v5.38;
use strict;
use warnings;
use utf8;
use Test::More;

use Protobuf::Schema;
use Protobuf::Schema::File;
use Protobuf::Schema::Message;
use Protobuf::Schema::Enum;
use Protobuf::Schema::Field;
use Protobuf::Schema::Service;

# Build an inner enum nested under Outer.
my $inner_enum = Protobuf::Schema::Enum->new(
    name      => 'Color',
    full_name => 'pkg.Outer.Color',
    values    => [],
);

# Build a nested message Outer.Inner.
my $inner_msg = Protobuf::Schema::Message->new(
    name      => 'Inner',
    full_name => 'pkg.Outer.Inner',
    fields    => [],
);

# Build the Outer message with a nested message and a nested enum.
my $outer = Protobuf::Schema::Message->new(
    name            => 'Outer',
    full_name       => 'pkg.Outer',
    fields          => [
        Protobuf::Schema::Field->new(
            name => 'id', number => 1, type => 'int32', label => 'singular',
        ),
    ],
    nested_messages => [$inner_msg],
    nested_enums    => [$inner_enum],
);

# A top-level enum.
my $top_enum = Protobuf::Schema::Enum->new(
    name => 'Status', full_name => 'pkg.Status', values => [],
);

my $file = Protobuf::Schema::File->new(
    name     => 'pkg.proto',
    package  => 'pkg',
    messages => [$outer],
    enums    => [$top_enum],
);

# 7.1 — add_file / files / file round-trip.
my $schema = Protobuf::Schema->new;
$schema->add_file($file);

is( scalar @{ $schema->files }, 1, 'files() returns the one added file' );
is( $schema->files->[0], $file, 'files() returns the same File object' );
is( $schema->file('pkg.proto'), $file, "file('pkg.proto') round-trips" );
is( $schema->file('nope.proto'), undef, 'unknown file name returns undef' );

# 7.2 — message/enum lookup by fully-qualified name incl. nested.
is( $schema->message('pkg.Outer'), $outer,
    'message() finds top-level message by fq name' );
is( $schema->message('pkg.Outer.Inner'), $inner_msg,
    'message() finds nested message by fq name (Outer.Inner)' );
is( $schema->enum('pkg.Status'), $top_enum,
    'enum() finds top-level enum by fq name' );
is( $schema->enum('pkg.Outer.Color'), $inner_enum,
    'enum() finds nested enum by fq name (Outer.Color)' );

# 7.5 — unknown lookups return undef (not die).
is( $schema->message('pkg.Missing'), undef, 'unknown message lookup -> undef' );
is( $schema->enum('pkg.Missing'),    undef, 'unknown enum lookup -> undef' );
is( $schema->message('pkg.Status'),  undef, 'enum fq name is not a message' );
is( $schema->enum('pkg.Outer'),      undef, 'message fq name is not an enum' );

# 7.3 — all_messages / all_enums flatten nested definitions.
my %msg_names = map { $_->full_name => 1 } @{ $schema->all_messages };
is_deeply(
    \%msg_names,
    { 'pkg.Outer' => 1, 'pkg.Outer.Inner' => 1 },
    'all_messages flattens nested messages',
);

my %enum_names = map { $_->full_name => 1 } @{ $schema->all_enums };
is_deeply(
    \%enum_names,
    { 'pkg.Status' => 1, 'pkg.Outer.Color' => 1 },
    'all_enums flattens nested enums',
);

# service lookup works against File services.
{
    my $schema2 = Protobuf::Schema->new;
    my $svc = Protobuf::Schema::Service->new(
        name => 'Greeter', full_name => 'pkg.Greeter', methods => [],
    );
    my $f2 = Protobuf::Schema::File->new(
        name => 'svc.proto', package => 'pkg', services => [$svc],
    );
    $schema2->add_file($f2);
    is( $schema2->service('pkg.Greeter'), $svc, 'service() finds by fq name' );
    is( $schema2->service('pkg.Nope'), undef, 'unknown service lookup -> undef' );
}

# 7.4 — duplicate full_name across files raises DuplicateMessage.
{
    my $schema3 = Protobuf::Schema->new;
    my $dup1 = Protobuf::Schema::Message->new(
        name => 'Dup', full_name => 'pkg.Dup', fields => [],
    );
    my $dup2 = Protobuf::Schema::Message->new(
        name => 'Dup', full_name => 'pkg.Dup', fields => [],
    );
    my $fa = Protobuf::Schema::File->new(
        name => 'a.proto', package => 'pkg', messages => [$dup1],
    );
    my $fb = Protobuf::Schema::File->new(
        name => 'b.proto', package => 'pkg', messages => [$dup2],
    );
    $schema3->add_file($fa);
    my $err = do {
        local $@;
        eval { $schema3->add_file($fb); 1 } ? undef : $@;
    };
    ok( $err, 'duplicate full_name on add_file dies' );
    isa_ok( $err, 'Protobuf::Exception::Schema::DuplicateMessage',
        'duplicate full_name raises DuplicateMessage' );
}

# resolve stub: callable and returns the schema for chaining.
{
    my $schema4 = Protobuf::Schema->new;
    $schema4->add_file($file);
    my $ret = $schema4->resolve;
    is( $ret, $schema4, 'resolve() returns the schema (chainable stub)' );
}

done_testing;
