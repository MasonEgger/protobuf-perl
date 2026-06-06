# ABOUTME: Unit tests for Protobuf::Schema::Features (T0.2) — the edition feature
# model: edition defaults, override merge, and proto3/proto2/edition2023 resolution.
use v5.38;
use warnings;
use Test::More;

use Protobuf::Schema::Features;
use Protobuf::Schema::Field;
use Protobuf::Schema::File;
use Protobuf::Schema::Enum;
use Protobuf::Schema::Message;
use Protobuf::Schema;

# --- (a) edition default FeatureSets ----------------------------------------
{
    my $p2 = Protobuf::Schema::Features->for_edition('proto2');
    is( $p2->field_presence,          'EXPLICIT',        'proto2 field_presence' );
    is( $p2->enum_type,               'CLOSED',          'proto2 enum_type' );
    is( $p2->repeated_field_encoding, 'EXPANDED',        'proto2 repeated_field_encoding' );
    is( $p2->message_encoding,        'LENGTH_PREFIXED', 'proto2 message_encoding' );
    is( $p2->utf8_validation,         'NONE',            'proto2 utf8_validation' );
    is( $p2->json_format,             'ALLOW',           'proto2 json_format' );

    my $p3 = Protobuf::Schema::Features->for_edition('proto3');
    is( $p3->field_presence,          'IMPLICIT',        'proto3 field_presence' );
    is( $p3->enum_type,               'OPEN',            'proto3 enum_type' );
    is( $p3->repeated_field_encoding, 'PACKED',          'proto3 repeated_field_encoding' );
    is( $p3->message_encoding,        'LENGTH_PREFIXED', 'proto3 message_encoding' );
    is( $p3->utf8_validation,         'VERIFY',          'proto3 utf8_validation' );
    is( $p3->json_format,             'ALLOW',           'proto3 json_format' );

    my $e23 = Protobuf::Schema::Features->for_edition('2023');
    is( $e23->field_presence,          'EXPLICIT',        'edition2023 field_presence' );
    is( $e23->enum_type,               'OPEN',            'edition2023 enum_type' );
    is( $e23->repeated_field_encoding, 'PACKED',          'edition2023 repeated_field_encoding' );
    is( $e23->message_encoding,        'LENGTH_PREFIXED', 'edition2023 message_encoding' );
    is( $e23->utf8_validation,         'VERIFY',          'edition2023 utf8_validation' );
    is( $e23->json_format,             'ALLOW',           'edition2023 json_format' );
}

# --- (b) override merging: parent override flows to child unless overridden --
{
    my $base = Protobuf::Schema::Features->for_edition('2023');

    # File-level override sets enum_type=CLOSED; merged over base.
    my $file_level = Protobuf::Schema::Features->merge( $base, { enum_type => 'CLOSED' } );
    is( $file_level->enum_type,    'CLOSED',   'file override applies enum_type=CLOSED' );
    is( $file_level->field_presence, 'EXPLICIT', 'unrelated feature inherited from base' );

    # Field inherits file-level CLOSED unless it overrides.
    my $field_inherit = Protobuf::Schema::Features->merge( $file_level, {} );
    is( $field_inherit->enum_type, 'CLOSED', 'empty field override inherits parent CLOSED' );

    # Field overrides back to OPEN.
    my $field_override = Protobuf::Schema::Features->merge( $file_level, { enum_type => 'OPEN' } );
    is( $field_override->enum_type, 'OPEN', 'field override beats parent' );
    is( $field_override->field_presence, 'EXPLICIT', 'other features still inherited' );
}

# --- (c) proto3 schema resolves to today's presence/packed/open-enum --------
{
    # Repeated packable scalar — packed by default under proto3.
    my $rep = Protobuf::Schema::Field->new(
        name => 'nums', number => 1, type => 'int32', label => 'repeated',
    );
    # Singular scalar — implicit presence under proto3.
    my $sing = Protobuf::Schema::Field->new(
        name => 'x', number => 2, type => 'int32',
    );
    # optional scalar — explicit presence under proto3.
    my $opt = Protobuf::Schema::Field->new(
        name => 'y', number => 3, type => 'int32', label => 'optional',
    );
    my $msg = Protobuf::Schema::Message->new(
        name => 'M', full_name => 'pkg.M', fields => [ $rep, $sing, $opt ],
    );
    my $enum = Protobuf::Schema::Enum->new(
        name => 'E', full_name => 'pkg.E', values => [ { name => 'Z', number => 0 } ],
    );
    my $file = Protobuf::Schema::File->new(
        name => 'a.proto', package => 'pkg', syntax => 'proto3',
        messages => [$msg], enums => [$enum],
    );
    my $schema = Protobuf::Schema->new;
    $schema->add_file($file);
    $schema->resolve;

    is( $rep->is_packed,  1, 'proto3 repeated scalar packs by default' );
    is( $sing->presence, 'implicit', 'proto3 singular scalar is implicit presence' );
    is( $sing->has_presence, 0, 'implicit field has_presence is false' );
    is( $opt->presence,  'explicit', 'proto3 optional scalar is explicit presence' );
    is( $opt->has_presence, 1, 'optional field has_presence is true' );
    is( $enum->closed, 0, 'proto3 enum is open' );

    is( $sing->features->field_presence, 'IMPLICIT', 'resolved field features: proto3 IMPLICIT' );
    is( $sing->features->enum_type, 'OPEN', 'resolved field features: proto3 OPEN' );
    is( $enum->features->enum_type, 'OPEN', 'resolved enum features: proto3 OPEN' );
    is( $file->edition, 'proto3', 'proto3 syntax derives proto3 edition' );
}

# --- (d) proto2 schema resolves to EXPLICIT/CLOSED/EXPANDED ------------------
{
    my $rep = Protobuf::Schema::Field->new(
        name => 'nums', number => 1, type => 'int32', label => 'repeated',
    );
    my $sing = Protobuf::Schema::Field->new(
        name => 'x', number => 2, type => 'int32',
    );
    my $msg = Protobuf::Schema::Message->new(
        name => 'M', full_name => 'p2.M', fields => [ $rep, $sing ],
    );
    my $enum = Protobuf::Schema::Enum->new(
        name => 'E', full_name => 'p2.E', values => [ { name => 'Z', number => 0 } ],
    );
    my $file = Protobuf::Schema::File->new(
        name => 'b.proto', package => 'p2', syntax => 'proto2',
        messages => [$msg], enums => [$enum],
    );
    my $schema = Protobuf::Schema->new;
    $schema->add_file($file);
    $schema->resolve;

    is( $file->edition, 'proto2', 'proto2 syntax derives proto2 edition' );
    is( $sing->features->field_presence, 'EXPLICIT', 'proto2 field EXPLICIT' );
    is( $sing->features->enum_type, 'CLOSED', 'proto2 field CLOSED' );
    is( $rep->features->repeated_field_encoding, 'EXPANDED', 'proto2 repeated EXPANDED' );
    is( $sing->presence, 'explicit', 'proto2 singular scalar is explicit presence' );
    is( $sing->has_presence, 1, 'proto2 singular has_presence true' );
    is( $rep->is_packed, 0, 'proto2 repeated scalar is NOT packed (EXPANDED)' );
    is( $enum->closed, 1, 'proto2 enum is closed' );
    is( $enum->features->enum_type, 'CLOSED', 'proto2 enum features CLOSED' );
}

# --- (e) edition 2023 resolves to EXPLICIT/OPEN/PACKED ----------------------
{
    my $rep = Protobuf::Schema::Field->new(
        name => 'nums', number => 1, type => 'int32', label => 'repeated',
    );
    my $sing = Protobuf::Schema::Field->new(
        name => 'x', number => 2, type => 'int32',
    );
    my $msg = Protobuf::Schema::Message->new(
        name => 'M', full_name => 'e.M', fields => [ $rep, $sing ],
    );
    my $enum = Protobuf::Schema::Enum->new(
        name => 'E', full_name => 'e.E', values => [ { name => 'Z', number => 0 } ],
    );
    my $file = Protobuf::Schema::File->new(
        name => 'c.proto', package => 'e', edition => '2023',
        messages => [$msg], enums => [$enum],
    );
    my $schema = Protobuf::Schema->new;
    $schema->add_file($file);
    $schema->resolve;

    is( $file->edition, '2023', 'explicit edition 2023 preserved' );
    is( $sing->features->field_presence, 'EXPLICIT', 'edition2023 field EXPLICIT' );
    is( $sing->features->enum_type, 'OPEN', 'edition2023 field OPEN' );
    is( $rep->features->repeated_field_encoding, 'PACKED', 'edition2023 repeated PACKED' );
    is( $sing->presence, 'explicit', 'edition2023 singular explicit presence' );
    is( $rep->is_packed, 1, 'edition2023 repeated scalar packs' );
    is( $enum->closed, 0, 'edition2023 enum is open' );
}

# --- (f) file-level feature override flows to fields ------------------------
{
    # An edition-2023 file overriding enum_type=CLOSED at file level: a field
    # inherits CLOSED; a field with its own override of OPEN wins.
    my $f_inherit = Protobuf::Schema::Field->new(
        name => 'a', number => 1, type => 'enum', type_name => '.e.Color',
    );
    my $f_override = Protobuf::Schema::Field->new(
        name => 'b', number => 2, type => 'enum', type_name => '.e.Color',
        features => { enum_type => 'OPEN' },
    );
    my $enum = Protobuf::Schema::Enum->new(
        name => 'Color', full_name => 'e.Color',
        values => [ { name => 'RED', number => 0 } ],
    );
    my $msg = Protobuf::Schema::Message->new(
        name => 'M', full_name => 'e.M', fields => [ $f_inherit, $f_override ],
    );
    my $file = Protobuf::Schema::File->new(
        name => 'd.proto', package => 'e', edition => '2023',
        features => { enum_type => 'CLOSED' },
        messages => [$msg], enums => [$enum],
    );
    my $schema = Protobuf::Schema->new;
    $schema->add_file($file);
    $schema->resolve;

    is( $f_inherit->features->enum_type, 'CLOSED', 'field inherits file-level CLOSED override' );
    is( $f_override->features->enum_type, 'OPEN', 'field-level override beats file CLOSED' );
}

# --- (g) resolution is idempotent -------------------------------------------
{
    my $sing = Protobuf::Schema::Field->new( name => 'x', number => 1, type => 'int32' );
    my $msg = Protobuf::Schema::Message->new(
        name => 'M', full_name => 'i.M', fields => [$sing],
    );
    my $file = Protobuf::Schema::File->new(
        name => 'e.proto', package => 'i', syntax => 'proto3', messages => [$msg],
    );
    my $schema = Protobuf::Schema->new;
    $schema->add_file($file);
    $schema->resolve;
    my $first = $sing->features;
    $schema->resolve;
    is( $sing->features, $first, 'resolve is idempotent: same FeatureSet identity' );
}

# --- (h) extension registry --------------------------------------------------
{
    my $ext = Protobuf::Schema::Field->new(
        name => 'my_ext', number => 100, type => 'int32',
        is_extension => 1, extendee => '.x.Base',
    );
    my $base = Protobuf::Schema::Message->new(
        name => 'Base', full_name => 'x.Base', fields => [],
        extension_ranges => [ [ 100, 200 ] ],
    );
    my $holder = Protobuf::Schema::Message->new(
        name => 'Holder', full_name => 'x.Holder', fields => [],
        extensions => [$ext],
    );
    my $file = Protobuf::Schema::File->new(
        name => 'f.proto', package => 'x', syntax => 'proto2',
        messages => [ $base, $holder ],
    );
    my $schema = Protobuf::Schema->new;
    $schema->add_file($file);
    $schema->resolve;

    is( $ext->is_extension, 1, 'extension field flagged' );
    is( $ext->extendee, '.x.Base', 'extension field extendee' );
    is_deeply( $base->extension_ranges, [ [ 100, 200 ] ], 'message extension_ranges' );
    my $exts = $schema->extensions_for('x.Base');
    is( scalar @$exts, 1, 'extension registry has one ext for x.Base' );
    is( $exts->[0]->name, 'my_ext', 'registered extension is my_ext' );
    is_deeply( $schema->extensions_for('x.Unknown'), [], 'unknown extendee -> empty arrayref' );
}

done_testing;
