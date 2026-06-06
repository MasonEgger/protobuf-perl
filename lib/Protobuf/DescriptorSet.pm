# ABOUTME: Protobuf::DescriptorSet — load a binary google.protobuf.FileDescriptorSet
# (protoc --descriptor_set_out) into a resolved Protobuf::Schema; spec §4.7.
use v5.38;
use feature 'class';
no warnings 'experimental::class';

use Protobuf::Schema;
use Protobuf::Schema::File;
use Protobuf::Schema::Message;
use Protobuf::Schema::Field;
use Protobuf::Schema::Enum;
use Protobuf::Schema::Oneof;
use Protobuf::Codec;
use Protobuf::DescriptorSet::Proto;
use Protobuf::Exception;
use Scalar::Util ();

# The protobuf FieldDescriptorProto.Type enum -> our string type identifiers
# (spec §4.7). TYPE_GROUP (10) is intentionally absent: proto3 forbids groups,
# so a descriptor carrying one is a malformed proto3 input. A pre-class lexical
# to dodge the feature 'class' package-scoping trap.
my %TYPE_ENUM_TO_STRING = (
    1  => 'double',
    2  => 'float',
    3  => 'int64',
    4  => 'uint64',
    5  => 'int32',
    6  => 'fixed64',
    7  => 'fixed32',
    8  => 'bool',
    9  => 'string',
    11 => 'message',
    12 => 'bytes',
    13 => 'uint32',
    14 => 'enum',
    15 => 'sfixed32',
    16 => 'sfixed64',
    17 => 'sint32',
    18 => 'sint64',
);

# FieldDescriptorProto.Label values. LABEL_REPEATED maps to a repeated field;
# LABEL_REQUIRED (proto2/editions only) maps to legacy_required presence;
# LABEL_OPTIONAL is the default singular/explicit case. Pre-class lexicals
# (scoping trap, as above).
my $LABEL_OPTIONAL = 1;
my $LABEL_REQUIRED = 2;
my $LABEL_REPEATED = 3;

# FieldDescriptorProto.Type.TYPE_GROUP — a tag-delimited aggregate. Modeled as a
# delimited message so the codec has a single message path (spec §E).
my $TYPE_GROUP = 10;

# FileDescriptorProto.Edition enum -> our File.edition string. Only the editions
# the conformance protos use are mapped; proto2/proto3 syntax files carry no
# edition and fall back to their syntax string. EDITION_2023 = 1000.
my %EDITION_ENUM_TO_STRING = (
    1000 => '2023',
);

# FeatureSet enum-int -> feature-value string tables, transcribed from
# descriptor.proto's FeatureSet sub-enums. Each maps a decoded int32 to the
# override-value string Schema::Features understands. Pre-class lexicals.
my %FIELD_PRESENCE = ( 1 => 'EXPLICIT', 2 => 'IMPLICIT', 3 => 'LEGACY_REQUIRED' );
my %ENUM_TYPE      = ( 1 => 'OPEN', 2 => 'CLOSED' );
my %REPEATED_ENC   = ( 1 => 'PACKED', 2 => 'EXPANDED' );
my %UTF8_VALIDATION = ( 2 => 'VERIFY', 3 => 'NONE' );
my %MESSAGE_ENC    = ( 1 => 'LENGTH_PREFIXED', 2 => 'DELIMITED' );
my %JSON_FORMAT    = ( 1 => 'ALLOW', 2 => 'LEGACY_BEST_EFFORT' );

# Maps a FeatureSet key to its enum-int -> string table. Keys absent from a
# decoded FeatureSet are simply not overridden (edition defaults stand).
my %FEATURE_TABLE = (
    field_presence          => \%FIELD_PRESENCE,
    enum_type               => \%ENUM_TYPE,
    repeated_field_encoding => \%REPEATED_ENC,
    utf8_validation         => \%UTF8_VALIDATION,
    message_encoding        => \%MESSAGE_ENC,
    json_format             => \%JSON_FORMAT,
);

class Protobuf::DescriptorSet {

    # The Type-enum -> string mapping table, exposed so its full contract is
    # directly assertable (spec §4.7). Returns a fresh copy so callers cannot
    # mutate the canonical table.
    sub type_enum_to_string ($class) {
        return { %TYPE_ENUM_TO_STRING };
    }

    # load_file($path) -> resolved Protobuf::Schema. Slurp the binary FDS at $path
    # and delegate to load_string.
    sub load_file ($class, $path) {
        open my $fh, '<', $path
            or Protobuf::Exception::Argument->throw(
            message => "cannot read descriptor set $path: $!",
            );
        binmode $fh;
        my $bytes = do { local $/; <$fh> };
        close $fh;
        return $class->load_string($bytes);
    }

    # load_string($bytes) -> resolved Protobuf::Schema. Decode the FDS with the
    # hand-written bootstrap descriptor schema + the ordinary codec, rebuild our
    # schema model from the decoded descriptors, then resolve. A corrupt FDS
    # surfaces as a Protobuf::Exception::Codec from the decode.
    sub load_string ($class, $bytes) {
        my $codec = Protobuf::Codec->new(
            schema => Protobuf::DescriptorSet::Proto->schema,
        );

        # A corrupt FDS surfaces as a Protobuf::Exception::Codec (spec §4.7
        # T-fds-3). The underlying wire layer may raise a more specific
        # Wire error (e.g. Truncated) on malformed input; wrap any
        # non-Codec decode failure as a Codec exception, preserving the
        # original as its cause, so callers can catch a single class.
        my $fds = eval {
            $codec->decode( 'google.protobuf.FileDescriptorSet', $bytes );
        };
        if ( my $err = $@ ) {
            die $err
                if Scalar::Util::blessed($err)
                && $err->isa('Protobuf::Exception::Codec');
            Protobuf::Exception::Codec->throw(
                message => "corrupt FileDescriptorSet: $err",
                cause   => $err,
            );
        }

        my $schema = Protobuf::Schema->new;
        for my $file_desc ( @{ $fds->{file} // [] } ) {
            $schema->add_file( Protobuf::DescriptorSet::_build_file($file_desc) );
        }
        $schema->resolve;
        return $schema;
    }
}

# Convert a decoded FeatureSet hashref (enum ints) into a Schema feature-override
# hashref (value strings). Unset features are omitted so edition defaults stand.
# Returns an empty hashref when $feature_set is undef.
sub Protobuf::DescriptorSet::_features_override {
    my ($feature_set) = @_;
    return {} unless defined $feature_set;

    my %override;
    for my $key ( keys %FEATURE_TABLE ) {
        next unless defined $feature_set->{$key};
        my $str = $FEATURE_TABLE{$key}{ $feature_set->{$key} };
        $override{$key} = $str if defined $str;
    }
    return \%override;
}

# Map a decoded FileDescriptorProto's edition enum + syntax to our File.edition
# string ('proto2'/'proto3'/'2023'). A file with a known edition enum wins;
# otherwise the legacy syntax is the edition. protoc omits the syntax field for
# proto2 files (proto2 is the wire default), so an absent syntax means proto2.
sub Protobuf::DescriptorSet::_file_edition {
    my ($file_desc) = @_;
    my $edition_num = $file_desc->{edition};
    if ( defined $edition_num && exists $EDITION_ENUM_TO_STRING{$edition_num} ) {
        return $EDITION_ENUM_TO_STRING{$edition_num};
    }
    return $file_desc->{syntax} // 'proto2';
}

# Build a Schema::File from a decoded FileDescriptorProto hashref. The scope for
# top-level definitions is the file package. File-level `extension` declarations
# are attached to a synthetic placeholder so the resolver registers them.
sub Protobuf::DescriptorSet::_build_file {
    my ($file_desc) = @_;
    my $package = $file_desc->{package} // '';

    my @messages =
        map { Protobuf::DescriptorSet::_build_message( $_, $package ) }
        @{ $file_desc->{message_type} // [] };

    my @enums =
        map { Protobuf::DescriptorSet::_build_enum( $_, $package ) }
        @{ $file_desc->{enum_type} // [] };

    # File-level extension fields (`extend Foo { ... }` at file scope). The
    # resolver's feature pass only walks message `extensions` lists, so a
    # synthetic, never-referenced carrier message holds the file-level extensions
    # and is registered for resolution. Its full_name is namespaced under the
    # file name so it cannot collide with a real message (file names are unique
    # within an FDS).
    my @file_extensions =
        map { Protobuf::DescriptorSet::_build_field( $_, {}, {}, is_extension => 1 ) }
        @{ $file_desc->{extension} // [] };

    if (@file_extensions) {
        my $carrier = '$file_extensions$:' . ( $file_desc->{name} // '' );
        push @messages, Protobuf::Schema::Message->new(
            name       => $carrier,
            full_name  => $carrier,
            extensions => \@file_extensions,
        );
    }

    return Protobuf::Schema::File->new(
        name     => $file_desc->{name} // '',
        package  => $package,
        # protoc omits syntax for proto2 files (proto2 is the default).
        syntax   => $file_desc->{syntax} // 'proto2',
        edition  => Protobuf::DescriptorSet::_file_edition($file_desc),
        features => Protobuf::DescriptorSet::_features_override(
            $file_desc->{options}{features}
        ),
        messages => \@messages,
        enums    => \@enums,
    );
}

# Build a Schema::Message from a decoded DescriptorProto hashref. $scope is the
# enclosing fully-qualified name (file package at top level), used to compute the
# message's full_name and to scope its nested definitions.
sub Protobuf::DescriptorSet::_build_message {
    my ( $desc, $scope ) = @_;

    my $name = $desc->{name} // '';
    my $full_name = length $scope ? "$scope.$name" : $name;

    # oneof_decl entries from a synthetic oneof (one generated per proto3
    # `optional` field) are not real oneofs; their sole member carries
    # proto3_optional=true. Collect the indexes of the real oneofs so a field's
    # oneof_index can be classified.
    my @oneof_decls = @{ $desc->{oneof_decl} // [] };
    my %synthetic_oneof = Protobuf::DescriptorSet::_synthetic_oneof_indexes( $desc->{field} // [],
        scalar @oneof_decls );

    # Build nested messages first so map fields can be detected before the
    # message's own fields are constructed (a Schema::Field is immutable, so
    # map_entry must be passed at construction rather than patched in later).
    my @nested =
        map { Protobuf::DescriptorSet::_build_message( $_, $full_name ) }
        @{ $desc->{nested_type} // [] };

    # The full names of any nested synthetic MapEntry messages: a field whose
    # message type points at one is a map field (the parser tags it the same
    # way via map_entry), so is_map() is true and the codec treats it as a map.
    my %map_entry_name =
        map  { $_->full_name => 1 }
        grep { $_->is_map_entry } @nested;

    my @fields =
        map { Protobuf::DescriptorSet::_build_field( $_, \%synthetic_oneof, \%map_entry_name ) }
        @{ $desc->{field} // [] };

    # Reconstruct the real (non-synthetic) oneofs with the member fields that
    # belong to each, preserving declaration order. Members are the same
    # Schema::Field objects that appear in the message's field list, mirroring
    # how the parser builds a oneof.
    my @oneofs;
    for my $i ( 0 .. $#oneof_decls ) {
        next if $synthetic_oneof{$i};
        my @members =
            grep { defined $_->oneof_index && $_->oneof_index == $i } @fields;
        push @oneofs, Protobuf::Schema::Oneof->new(
            name        => $oneof_decls[$i]{name} // '',
            fields      => \@members,
            oneof_index => $i,
        );
    }

    my @nested_enums =
        map { Protobuf::DescriptorSet::_build_enum( $_, $full_name ) } @{ $desc->{enum_type} // [] };

    # Nested `extend Foo { ... }` declarations inside this message. Registered on
    # their extendee by the resolver's feature pass.
    my @extensions =
        map { Protobuf::DescriptorSet::_build_field( $_, {}, {}, is_extension => 1 ) }
        @{ $desc->{extension} // [] };

    # Extension ranges: [start, end) pairs from the descriptor's extension_range.
    my @extension_ranges =
        map { [ $_->{start}, $_->{end} ] }
        @{ $desc->{extension_range} // [] };

    return Protobuf::Schema::Message->new(
        name            => $name,
        full_name       => $full_name,
        fields          => \@fields,
        oneofs          => \@oneofs,
        nested_messages => \@nested,
        nested_enums    => \@nested_enums,
        extensions      => \@extensions,
        extension_ranges => \@extension_ranges,
        message_set_wire_format =>
            ( $desc->{options}{message_set_wire_format} // 0 ) ? 1 : 0,
        reserved_names  => [ @{ $desc->{reserved_name} // [] } ],
        is_map_entry    => ( $desc->{options}{map_entry} // 0 ) ? 1 : 0,
        features => Protobuf::DescriptorSet::_features_override(
            $desc->{options}{features}
        ),
    );
}

# Identify which oneof_decl indexes are synthetic (a single proto3 `optional`
# field's generated oneof). $fields is the decoded field list; $count is the
# number of oneof_decl entries. Returns a hash of index => 1 for synthetic ones.
sub Protobuf::DescriptorSet::_synthetic_oneof_indexes {
    my ( $fields, $count ) = @_;
    my %synthetic;
    for my $f (@$fields) {
        next unless $f->{proto3_optional};
        next unless defined $f->{oneof_index};
        $synthetic{ $f->{oneof_index} } = 1;
    }
    return %synthetic;
}

# Build a Schema::Field from a decoded FieldDescriptorProto hashref.
# $synthetic_oneof maps synthetic oneof indexes to 1 so a proto3 `optional`
# field is modeled with the 'optional' label rather than as a oneof member.
# $map_entry_name maps the fully-qualified names of nested MapEntry messages to
# 1, so a field referencing one is tagged as a map field. %opts may carry
# is_extension => 1 for `extend`-declared fields.
sub Protobuf::DescriptorSet::_build_field {
    my ( $desc, $synthetic_oneof, $map_entry_name, %opts ) = @_;

    # TYPE_GROUP (10) is a tag-delimited aggregate: model it as a message with
    # delimited message_encoding so the codec keeps a single message path.
    my $type_num    = $desc->{type};
    my $is_group    = defined $type_num && $type_num == $TYPE_GROUP;
    my $lookup_type = $is_group ? 11 : $type_num;    # TYPE_MESSAGE
    my $type = defined $lookup_type ? $TYPE_ENUM_TO_STRING{$lookup_type} : undef;
    if ( !defined $type ) {
        Protobuf::Exception::Codec->throw(
            message => sprintf(
                "field %s has unsupported descriptor type %s",
                $desc->{name} // '?', $type_num // '(none)',
            ),
        );
    }

    # proto3 `optional` field: protoc wraps it in a synthetic single-member
    # oneof. We unwrap it back to the 'optional' label and drop the oneof
    # membership; a real oneof member keeps its (real) oneof_index.
    my $oneof_index = $desc->{oneof_index};
    my $is_synthetic = defined $oneof_index && $synthetic_oneof->{$oneof_index};

    my $label_num = $desc->{label};
    my $label =
          ( defined $label_num && $label_num == $LABEL_REPEATED ) ? 'repeated'
        : $is_synthetic ? 'optional'
        :                 'singular';

    # Detect a map field: a message-typed field whose (de-dotted) type_name
    # names a nested synthetic MapEntry message.
    my $map_entry;
    if ( $type eq 'message' && defined $desc->{type_name} ) {
        ( my $fq = $desc->{type_name} ) =~ s/^\.//;
        $map_entry = $fq if $map_entry_name->{$fq};
    }

    # Feature overrides: field-level FieldOptions.features, plus a synthesized
    # field_presence=LEGACY_REQUIRED for a proto2/editions `required` field so
    # the resolved presence is 'legacy_required'. The explicit option wins if
    # both are present (it won't be — required predates field_presence).
    my $features = Protobuf::DescriptorSet::_features_override(
        $desc->{options}{features}
    );
    if ( defined $label_num && $label_num == $LABEL_REQUIRED ) {
        $features->{field_presence} //= 'LEGACY_REQUIRED';
    }

    # An explicit FieldOptions.packed flag (the proto2-era `[packed = true]` /
    # `[packed = false]`) is an override of the edition's repeated_field_encoding
    # default for THIS field: packed=true means PACKED, packed=false means
    # EXPANDED. Translate it into a per-field repeated_field_encoding override so
    # the feature-resolution pass folds it over the edition default and is_packed
    # reflects it (proto2 [packed=true] overrides EXPANDED -> PACKED). An editions
    # field expresses this directly as features.repeated_field_encoding, which
    # _features_override already produced; that explicit override wins, so only
    # derive from the packed flag when one isn't already present.
    my $packed = $desc->{options}{packed};
    if ( defined $packed
        && !defined $features->{repeated_field_encoding} )
    {
        $features->{repeated_field_encoding} = $packed ? 'PACKED' : 'EXPANDED';
    }

    return Protobuf::Schema::Field->new(
        name        => $desc->{name} // '',
        number      => $desc->{number},
        type        => $type,
        type_name   => $desc->{type_name},      # protoc emits a .-qualified name
        label       => $label,
        json_name   => $desc->{json_name},
        map_entry   => $map_entry,
        oneof_index => $is_synthetic ? undef : $oneof_index,
        default_value => $desc->{default_value},
        extendee      => $desc->{extendee},
        is_extension  => $opts{is_extension} ? 1 : 0,
        packed        => $desc->{options}{packed},
        group_encoded => $is_group ? 1 : 0,
        features      => $features,
    );
}

# Build a Schema::Enum from a decoded EnumDescriptorProto hashref. $scope is the
# enclosing fully-qualified name; values become { name, number } hashrefs.
sub Protobuf::DescriptorSet::_build_enum {
    my ( $desc, $scope ) = @_;

    my $name = $desc->{name} // '';
    my $full_name = length $scope ? "$scope.$name" : $name;

    my @values =
        map { { name => $_->{name} // '', number => $_->{number} // 0 } }
        @{ $desc->{value} // [] };

    return Protobuf::Schema::Enum->new(
        name        => $name,
        full_name   => $full_name,
        values      => \@values,
        allow_alias => ( $desc->{options}{allow_alias} // 0 ) ? 1 : 0,
        features    => Protobuf::DescriptorSet::_features_override(
            $desc->{options}{features}
        ),
    );
}

1;

__END__

=encoding utf-8

=head1 NAME

Protobuf::DescriptorSet - load a protoc FileDescriptorSet into a Protobuf::Schema

=head1 SYNOPSIS

    use Protobuf::DescriptorSet;

    my $schema = Protobuf::DescriptorSet->load_file('/path/to/all.fds');
    my $schema = Protobuf::DescriptorSet->load_string($fds_bytes);

=head1 DESCRIPTION

C<Protobuf::DescriptorSet> loads the binary C<google.protobuf.FileDescriptorSet>
emitted by C<protoc --descriptor_set_out> into a fully-resolved
L<Protobuf::Schema>. This lets a caller use C<protoc> as the C<.proto> parser
instead of L<Protobuf::Parser>, and is the oracle for the resolver differential
test (spec §4.3 T-res-7).

The bootstrap schema for the descriptor messages themselves lives in
L<Protobuf::DescriptorSet::Proto>; the incoming FDS is decoded with that schema and
the ordinary L<Protobuf::Codec>, then the decoded descriptors are rebuilt into our
schema model and resolved.

=head1 METHODS

=head2 type_enum_to_string

    my $map = Protobuf::DescriptorSet->type_enum_to_string;

A fresh copy of the C<FieldDescriptorProto.Type> enum to string-type-identifier
mapping (e.g. C<5 =&gt; 'int32'>, C<11 =&gt; 'message'>, C<14 =&gt; 'enum'>).
C<TYPE_GROUP> is intentionally absent — proto3 forbids groups.

=head2 load_file

    my $schema = Protobuf::DescriptorSet->load_file($path);

Slurp the binary FDS at C<$path> and load it (see L</load_string>). An
unreadable path raises L<Protobuf::Exception::Argument>.

=head2 load_string

    my $schema = Protobuf::DescriptorSet->load_string($bytes);

Decode C<$bytes> as a C<FileDescriptorSet>, rebuild a L<Protobuf::Schema> from
each C<FileDescriptorProto> (messages, fields, enums, oneofs, nested types, map
entries), call C<resolve>, and return it. A corrupt FDS surfaces as
L<Protobuf::Exception::Codec> from the decode; an unresolvable C<type_name>
propagates L<Protobuf::Exception::Schema::UnresolvedType> from C<resolve>.

=head1 BEHAVIOR NOTES

=over 4

=item *

The C<FieldDescriptorProto.Type> enum is mapped to our string type identifiers
via L</type_enum_to_string>; C<TYPE_MESSAGE> becomes C<'message'> and
C<TYPE_ENUM> becomes C<'enum'>.

=item *

A proto3 C<optional> field is emitted by protoc as the sole member of a
B<synthetic> single-member oneof (its descriptor carries C<proto3_optional>).
The loader unwraps that back to the C<'optional'> label and does not treat it as
a oneof member; only B<real> oneofs are reconstructed as
L<Protobuf::Schema::Oneof> objects.

=item *

protoc emits C<type_name> as a fully-qualified, leading-dot name, which the
resolver accepts directly.

=back

=head1 LICENSE

This software is licensed under the MIT license. See the C<LICENSE> file.

=cut
