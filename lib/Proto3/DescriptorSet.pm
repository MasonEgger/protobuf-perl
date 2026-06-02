# ABOUTME: Proto3::DescriptorSet — load a binary google.protobuf.FileDescriptorSet
# (protoc --descriptor_set_out) into a resolved Proto3::Schema; spec §4.7.
use v5.38;
use feature 'class';
no warnings 'experimental::class';

use Proto3::Schema;
use Proto3::Schema::File;
use Proto3::Schema::Message;
use Proto3::Schema::Field;
use Proto3::Schema::Enum;
use Proto3::Schema::Oneof;
use Proto3::Codec;
use Proto3::DescriptorSet::Proto;
use Proto3::Exception;
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

# FieldDescriptorProto.Label.LABEL_REPEATED — the only label that changes our
# field model (singular vs repeated); LABEL_OPTIONAL/LABEL_REQUIRED collapse to
# 'singular' for proto3. A pre-class lexical (scoping trap, as above).
my $LABEL_REPEATED = 3;

class Proto3::DescriptorSet {

    # The Type-enum -> string mapping table, exposed so its full contract is
    # directly assertable (spec §4.7). Returns a fresh copy so callers cannot
    # mutate the canonical table.
    sub type_enum_to_string ($class) {
        return { %TYPE_ENUM_TO_STRING };
    }

    # load_file($path) -> resolved Proto3::Schema. Slurp the binary FDS at $path
    # and delegate to load_string.
    sub load_file ($class, $path) {
        open my $fh, '<', $path
            or Proto3::Exception::Argument->throw(
            message => "cannot read descriptor set $path: $!",
            );
        binmode $fh;
        my $bytes = do { local $/; <$fh> };
        close $fh;
        return $class->load_string($bytes);
    }

    # load_string($bytes) -> resolved Proto3::Schema. Decode the FDS with the
    # hand-written bootstrap descriptor schema + the ordinary codec, rebuild our
    # schema model from the decoded descriptors, then resolve. A corrupt FDS
    # surfaces as a Proto3::Exception::Codec from the decode.
    sub load_string ($class, $bytes) {
        my $codec = Proto3::Codec->new(
            schema => Proto3::DescriptorSet::Proto->schema,
        );

        # A corrupt FDS surfaces as a Proto3::Exception::Codec (spec §4.7
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
                && $err->isa('Proto3::Exception::Codec');
            Proto3::Exception::Codec->throw(
                message => "corrupt FileDescriptorSet: $err",
                cause   => $err,
            );
        }

        my $schema = Proto3::Schema->new;
        for my $file_desc ( @{ $fds->{file} // [] } ) {
            $schema->add_file( Proto3::DescriptorSet::_build_file($file_desc) );
        }
        $schema->resolve;
        return $schema;
    }
}

# Build a Schema::File from a decoded FileDescriptorProto hashref. The scope for
# top-level definitions is the file package.
sub Proto3::DescriptorSet::_build_file {
    my ($file_desc) = @_;
    my $package = $file_desc->{package} // '';

    my @messages =
        map { Proto3::DescriptorSet::_build_message( $_, $package ) }
        @{ $file_desc->{message_type} // [] };

    my @enums =
        map { Proto3::DescriptorSet::_build_enum( $_, $package ) }
        @{ $file_desc->{enum_type} // [] };

    return Proto3::Schema::File->new(
        name     => $file_desc->{name} // '',
        package  => $package,
        syntax   => $file_desc->{syntax} // 'proto3',
        messages => \@messages,
        enums    => \@enums,
    );
}

# Build a Schema::Message from a decoded DescriptorProto hashref. $scope is the
# enclosing fully-qualified name (file package at top level), used to compute the
# message's full_name and to scope its nested definitions.
sub Proto3::DescriptorSet::_build_message {
    my ( $desc, $scope ) = @_;

    my $name = $desc->{name} // '';
    my $full_name = length $scope ? "$scope.$name" : $name;

    # oneof_decl entries from a synthetic oneof (one generated per proto3
    # `optional` field) are not real oneofs; their sole member carries
    # proto3_optional=true. Collect the indexes of the real oneofs so a field's
    # oneof_index can be classified.
    my @oneof_decls = @{ $desc->{oneof_decl} // [] };
    my %synthetic_oneof = Proto3::DescriptorSet::_synthetic_oneof_indexes( $desc->{field} // [],
        scalar @oneof_decls );

    # Build nested messages first so map fields can be detected before the
    # message's own fields are constructed (a Schema::Field is immutable, so
    # map_entry must be passed at construction rather than patched in later).
    my @nested =
        map { Proto3::DescriptorSet::_build_message( $_, $full_name ) }
        @{ $desc->{nested_type} // [] };

    # The full names of any nested synthetic MapEntry messages: a field whose
    # message type points at one is a map field (the parser tags it the same
    # way via map_entry), so is_map() is true and the codec treats it as a map.
    my %map_entry_name =
        map  { $_->full_name => 1 }
        grep { $_->is_map_entry } @nested;

    my @fields =
        map { Proto3::DescriptorSet::_build_field( $_, \%synthetic_oneof, \%map_entry_name ) }
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
        push @oneofs, Proto3::Schema::Oneof->new(
            name        => $oneof_decls[$i]{name} // '',
            fields      => \@members,
            oneof_index => $i,
        );
    }

    my @nested_enums =
        map { Proto3::DescriptorSet::_build_enum( $_, $full_name ) } @{ $desc->{enum_type} // [] };

    return Proto3::Schema::Message->new(
        name            => $name,
        full_name       => $full_name,
        fields          => \@fields,
        oneofs          => \@oneofs,
        nested_messages => \@nested,
        nested_enums    => \@nested_enums,
        reserved_names  => [ @{ $desc->{reserved_name} // [] } ],
        is_map_entry    => ( $desc->{options}{map_entry} // 0 ) ? 1 : 0,
    );
}

# Identify which oneof_decl indexes are synthetic (a single proto3 `optional`
# field's generated oneof). $fields is the decoded field list; $count is the
# number of oneof_decl entries. Returns a hash of index => 1 for synthetic ones.
sub Proto3::DescriptorSet::_synthetic_oneof_indexes {
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
# 1, so a field referencing one is tagged as a map field.
sub Proto3::DescriptorSet::_build_field {
    my ( $desc, $synthetic_oneof, $map_entry_name ) = @_;

    my $type_num = $desc->{type};
    my $type = defined $type_num ? $TYPE_ENUM_TO_STRING{$type_num} : undef;
    if ( !defined $type ) {
        Proto3::Exception::Codec->throw(
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

    my $label =
        ( defined $desc->{label} && $desc->{label} == $LABEL_REPEATED )
        ? 'repeated'
        : $is_synthetic ? 'optional'
        :                 'singular';

    # Detect a map field: a message-typed field whose (de-dotted) type_name
    # names a nested synthetic MapEntry message.
    my $map_entry;
    if ( $type eq 'message' && defined $desc->{type_name} ) {
        ( my $fq = $desc->{type_name} ) =~ s/^\.//;
        $map_entry = $fq if $map_entry_name->{$fq};
    }

    return Proto3::Schema::Field->new(
        name        => $desc->{name} // '',
        number      => $desc->{number},
        type        => $type,
        type_name   => $desc->{type_name},      # protoc emits a .-qualified name
        label       => $label,
        json_name   => $desc->{json_name},
        map_entry   => $map_entry,
        oneof_index => $is_synthetic ? undef : $oneof_index,
    );
}

# Build a Schema::Enum from a decoded EnumDescriptorProto hashref. $scope is the
# enclosing fully-qualified name; values become { name, number } hashrefs.
sub Proto3::DescriptorSet::_build_enum {
    my ( $desc, $scope ) = @_;

    my $name = $desc->{name} // '';
    my $full_name = length $scope ? "$scope.$name" : $name;

    my @values =
        map { { name => $_->{name} // '', number => $_->{number} // 0 } }
        @{ $desc->{value} // [] };

    return Proto3::Schema::Enum->new(
        name        => $name,
        full_name   => $full_name,
        values      => \@values,
        allow_alias => ( $desc->{options}{allow_alias} // 0 ) ? 1 : 0,
    );
}

1;

__END__

=head1 NAME

Proto3::DescriptorSet - load a protoc FileDescriptorSet into a Proto3::Schema

=head1 SYNOPSIS

    use Proto3::DescriptorSet;

    my $schema = Proto3::DescriptorSet->load_file('/path/to/all.fds');
    my $schema = Proto3::DescriptorSet->load_string($fds_bytes);

=head1 DESCRIPTION

C<Proto3::DescriptorSet> loads the binary C<google.protobuf.FileDescriptorSet>
emitted by C<protoc --descriptor_set_out> into a fully-resolved
L<Proto3::Schema>. This lets a caller use C<protoc> as the C<.proto> parser
instead of L<Proto3::Parser>, and is the oracle for the resolver differential
test (spec §4.3 T-res-7).

The bootstrap schema for the descriptor messages themselves lives in
L<Proto3::DescriptorSet::Proto>; the incoming FDS is decoded with that schema and
the ordinary L<Proto3::Codec>, then the decoded descriptors are rebuilt into our
schema model and resolved.

=head1 METHODS

=head2 type_enum_to_string

    my $map = Proto3::DescriptorSet->type_enum_to_string;

A fresh copy of the C<FieldDescriptorProto.Type> enum to string-type-identifier
mapping (e.g. C<5 =&gt; 'int32'>, C<11 =&gt; 'message'>, C<14 =&gt; 'enum'>).
C<TYPE_GROUP> is intentionally absent — proto3 forbids groups.

=head2 load_file

    my $schema = Proto3::DescriptorSet->load_file($path);

Slurp the binary FDS at C<$path> and load it (see L</load_string>). An
unreadable path raises L<Proto3::Exception::Argument>.

=head2 load_string

    my $schema = Proto3::DescriptorSet->load_string($bytes);

Decode C<$bytes> as a C<FileDescriptorSet>, rebuild a L<Proto3::Schema> from
each C<FileDescriptorProto> (messages, fields, enums, oneofs, nested types, map
entries), call C<resolve>, and return it. A corrupt FDS surfaces as
L<Proto3::Exception::Codec> from the decode; an unresolvable C<type_name>
propagates L<Proto3::Exception::Schema::UnresolvedType> from C<resolve>.

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
L<Proto3::Schema::Oneof> objects.

=item *

protoc emits C<type_name> as a fully-qualified, leading-dot name, which the
resolver accepts directly.

=back

=head1 LICENSE

This software is licensed under the MIT license. See the C<LICENSE> file.

=cut
