# ABOUTME: Protobuf::DescriptorSet::Proto — hand-written bootstrap schema for the
# google.protobuf descriptor messages, enough to DECODE a binary FileDescriptorSet.
use v5.38;
use feature 'class';
no warnings 'experimental::class';

use Protobuf::Schema;
use Protobuf::Schema::File;
use Protobuf::Schema::Message;
use Protobuf::Schema::Field;

# The bootstrap problem (spec §4.7): a FileDescriptorSet is itself a protobuf
# message (google.protobuf.FileDescriptorSet), so to decode one we need its
# schema — but our parser/loader path is exactly what we're bootstrapping. The
# resolution is to hand-write the subset of descriptor.proto needed to read an
# FDS as a Protobuf::Schema, then feed it to the ordinary Protobuf::Codec. Only the
# fields Protobuf::DescriptorSet consumes are modeled; the many descriptor fields
# we ignore (source_code_info, options sub-messages beyond map_entry, services,
# extensions) are simply absent and skipped as unknown fields on decode.
#
# Field numbers below are transcribed verbatim from upstream descriptor.proto
# (vendored at share/proto/google/protobuf/descriptor.proto). They are the
# contract: a wrong number silently mis-decodes an FDS, so they are asserted by
# t/descriptor/load.t against protoc's own output.

# Field-builder helpers. They are declared with FULLY-QUALIFIED names (not bare
# `sub _scalar`) and called the same way below: under feature 'class', a bareword
# sub call inside the class block resolves against the class's package, so a
# plain file-scope helper is invisible there (a runtime "Undefined subroutine"
# death). Naming them Protobuf::DescriptorSet::Proto::* sidesteps that — the same
# trick Protobuf::Resolver uses for candidate_names. @_ unpacking (rather than a
# signature) avoids the 5.38.2 "signature before a class block" parse trap.

# Build a Schema::Field for a singular scalar descriptor field. Modeled as
# `optional` (explicit presence) on purpose: descriptor.proto declares these as
# proto2 `optional`, and the loader depends on the distinction. proto3 implicit
# presence would default-fill an absent oneof_index/proto3_optional/type to 0,
# making "field has no oneof" indistinguishable from "field is in oneof 0";
# explicit presence keeps an absent scalar absent so protoc's presence semantics
# survive the decode.
sub Protobuf::DescriptorSet::Proto::_scalar {
    my ( $name, $number, $type ) = @_;
    return Protobuf::Schema::Field->new(
        name => $name, number => $number, type => $type, label => 'optional',
    );
}

# Build a Schema::Field for a repeated scalar descriptor field.
sub Protobuf::DescriptorSet::Proto::_rep_scalar {
    my ( $name, $number, $type ) = @_;
    return Protobuf::Schema::Field->new(
        name => $name, number => $number, type => $type, label => 'repeated',
    );
}

# Build a Schema::Field for a repeated message descriptor field. type_name is the
# fully-qualified descriptor message name; type_ref is linked by Schema->resolve.
sub Protobuf::DescriptorSet::Proto::_rep_message {
    my ( $name, $number, $type_name ) = @_;
    return Protobuf::Schema::Field->new(
        name      => $name,
        number    => $number,
        type      => 'message',
        type_name => $type_name,
        label     => 'repeated',
    );
}

# Build a Schema::Field for a singular message descriptor field.
sub Protobuf::DescriptorSet::Proto::_message {
    my ( $name, $number, $type_name ) = @_;
    return Protobuf::Schema::Field->new(
        name      => $name,
        number    => $number,
        type      => 'message',
        type_name => $type_name,
        label     => 'singular',
    );
}

class Protobuf::DescriptorSet::Proto {

    # Return a resolved Protobuf::Schema modeling the google.protobuf descriptor
    # messages needed to decode a FileDescriptorSet. A fresh schema is built on
    # each call so callers never share mutable resolver state.
    sub schema ($class) {
        my $G = 'google.protobuf';

        my $file_descriptor_set = Protobuf::Schema::Message->new(
            name      => 'FileDescriptorSet',
            full_name => "$G.FileDescriptorSet",
            fields    => [
                Protobuf::DescriptorSet::Proto::_rep_message( 'file', 1, "$G.FileDescriptorProto" ),
            ],
        );

        my $file_descriptor_proto = Protobuf::Schema::Message->new(
            name      => 'FileDescriptorProto',
            full_name => "$G.FileDescriptorProto",
            fields    => [
                Protobuf::DescriptorSet::Proto::_scalar( 'name',              1,  'string' ),
                Protobuf::DescriptorSet::Proto::_scalar( 'package',           2,  'string' ),
                Protobuf::DescriptorSet::Proto::_rep_scalar( 'dependency',    3,  'string' ),
                Protobuf::DescriptorSet::Proto::_rep_message( 'message_type', 4,  "$G.DescriptorProto" ),
                Protobuf::DescriptorSet::Proto::_rep_message( 'enum_type',    5,  "$G.EnumDescriptorProto" ),
                Protobuf::DescriptorSet::Proto::_rep_message( 'extension',    7,  "$G.FieldDescriptorProto" ),
                Protobuf::DescriptorSet::Proto::_message( 'options',          8,  "$G.FileOptions" ),
                Protobuf::DescriptorSet::Proto::_rep_scalar( 'public_dependency', 10, 'int32' ),
                Protobuf::DescriptorSet::Proto::_rep_scalar( 'weak_dependency',   11, 'int32' ),
                Protobuf::DescriptorSet::Proto::_scalar( 'syntax',            12, 'string' ),
                Protobuf::DescriptorSet::Proto::_scalar( 'edition',           14, 'int32' ),  # Edition enum
            ],
        );

        my $descriptor_proto = Protobuf::Schema::Message->new(
            name      => 'DescriptorProto',
            full_name => "$G.DescriptorProto",
            fields    => [
                Protobuf::DescriptorSet::Proto::_scalar( 'name',           1, 'string' ),
                Protobuf::DescriptorSet::Proto::_rep_message( 'field',     2, "$G.FieldDescriptorProto" ),
                Protobuf::DescriptorSet::Proto::_rep_message( 'nested_type', 3, "$G.DescriptorProto" ),
                Protobuf::DescriptorSet::Proto::_rep_message( 'enum_type', 4, "$G.EnumDescriptorProto" ),
                Protobuf::DescriptorSet::Proto::_rep_message( 'extension_range', 5,
                    "$G.DescriptorProto.ExtensionRange" ),
                Protobuf::DescriptorSet::Proto::_rep_message( 'extension', 6, "$G.FieldDescriptorProto" ),
                Protobuf::DescriptorSet::Proto::_message( 'options',       7, "$G.MessageOptions" ),
                Protobuf::DescriptorSet::Proto::_rep_message( 'oneof_decl', 8, "$G.OneofDescriptorProto" ),
                Protobuf::DescriptorSet::Proto::_rep_message( 'reserved_range', 9,
                    "$G.DescriptorProto.ReservedRange" ),
                Protobuf::DescriptorSet::Proto::_rep_scalar( 'reserved_name', 10, 'string' ),
            ],
        );

        my $extension_range = Protobuf::Schema::Message->new(
            name      => 'ExtensionRange',
            full_name => "$G.DescriptorProto.ExtensionRange",
            fields    => [
                Protobuf::DescriptorSet::Proto::_scalar( 'start', 1, 'int32' ),
                Protobuf::DescriptorSet::Proto::_scalar( 'end',   2, 'int32' ),
            ],
        );

        my $reserved_range = Protobuf::Schema::Message->new(
            name      => 'ReservedRange',
            full_name => "$G.DescriptorProto.ReservedRange",
            fields    => [
                Protobuf::DescriptorSet::Proto::_scalar( 'start', 1, 'int32' ),
                Protobuf::DescriptorSet::Proto::_scalar( 'end',   2, 'int32' ),
            ],
        );

        my $message_options = Protobuf::Schema::Message->new(
            name      => 'MessageOptions',
            full_name => "$G.MessageOptions",
            fields    => [
                Protobuf::DescriptorSet::Proto::_scalar( 'message_set_wire_format', 1, 'bool' ),
                Protobuf::DescriptorSet::Proto::_scalar( 'map_entry', 7, 'bool' ),
                Protobuf::DescriptorSet::Proto::_message( 'features', 12, "$G.FeatureSet" ),
            ],
        );

        # FileOptions: only the features sub-message is consumed (file-level
        # editions feature overrides like message_encoding=DELIMITED).
        my $file_options = Protobuf::Schema::Message->new(
            name      => 'FileOptions',
            full_name => "$G.FileOptions",
            fields    => [
                Protobuf::DescriptorSet::Proto::_message( 'features', 50, "$G.FeatureSet" ),
            ],
        );

        # FieldOptions: the packed flag (proto2 [packed=...]) and per-field
        # editions feature overrides.
        my $field_options = Protobuf::Schema::Message->new(
            name      => 'FieldOptions',
            full_name => "$G.FieldOptions",
            fields    => [
                Protobuf::DescriptorSet::Proto::_scalar( 'packed', 2, 'bool' ),
                Protobuf::DescriptorSet::Proto::_message( 'features', 21, "$G.FeatureSet" ),
            ],
        );

        # FeatureSet: the six editions features, each an int32 enum (see the
        # enum-value tables in Protobuf::DescriptorSet). Only the values the loader
        # reads are modeled.
        my $feature_set = Protobuf::Schema::Message->new(
            name      => 'FeatureSet',
            full_name => "$G.FeatureSet",
            fields    => [
                Protobuf::DescriptorSet::Proto::_scalar( 'field_presence',          1, 'int32' ),
                Protobuf::DescriptorSet::Proto::_scalar( 'enum_type',               2, 'int32' ),
                Protobuf::DescriptorSet::Proto::_scalar( 'repeated_field_encoding', 3, 'int32' ),
                Protobuf::DescriptorSet::Proto::_scalar( 'utf8_validation',         4, 'int32' ),
                Protobuf::DescriptorSet::Proto::_scalar( 'message_encoding',        5, 'int32' ),
                Protobuf::DescriptorSet::Proto::_scalar( 'json_format',             6, 'int32' ),
            ],
        );

        my $field_descriptor_proto = Protobuf::Schema::Message->new(
            name      => 'FieldDescriptorProto',
            full_name => "$G.FieldDescriptorProto",
            fields    => [
                Protobuf::DescriptorSet::Proto::_scalar( 'name',            1,  'string' ),
                Protobuf::DescriptorSet::Proto::_scalar( 'extendee',        2,  'string' ),
                Protobuf::DescriptorSet::Proto::_scalar( 'number',          3,  'int32' ),
                Protobuf::DescriptorSet::Proto::_scalar( 'label',           4,  'int32' ),  # Label enum
                Protobuf::DescriptorSet::Proto::_scalar( 'type',            5,  'int32' ),  # Type enum
                Protobuf::DescriptorSet::Proto::_scalar( 'type_name',       6,  'string' ),
                Protobuf::DescriptorSet::Proto::_scalar( 'default_value',   7,  'string' ),
                Protobuf::DescriptorSet::Proto::_message( 'options',        8,  "$G.FieldOptions" ),
                Protobuf::DescriptorSet::Proto::_scalar( 'oneof_index',     9,  'int32' ),
                Protobuf::DescriptorSet::Proto::_scalar( 'json_name',       10, 'string' ),
                Protobuf::DescriptorSet::Proto::_scalar( 'proto3_optional', 17, 'bool' ),
            ],
        );

        my $enum_descriptor_proto = Protobuf::Schema::Message->new(
            name      => 'EnumDescriptorProto',
            full_name => "$G.EnumDescriptorProto",
            fields    => [
                Protobuf::DescriptorSet::Proto::_scalar( 'name',  1, 'string' ),
                Protobuf::DescriptorSet::Proto::_rep_message( 'value', 2, "$G.EnumValueDescriptorProto" ),
                Protobuf::DescriptorSet::Proto::_message( 'options', 3, "$G.EnumOptions" ),
            ],
        );

        my $enum_options = Protobuf::Schema::Message->new(
            name      => 'EnumOptions',
            full_name => "$G.EnumOptions",
            fields    => [
                Protobuf::DescriptorSet::Proto::_scalar( 'allow_alias', 2, 'bool' ),
                Protobuf::DescriptorSet::Proto::_message( 'features', 7, "$G.FeatureSet" ),
            ],
        );

        my $enum_value_descriptor_proto = Protobuf::Schema::Message->new(
            name      => 'EnumValueDescriptorProto',
            full_name => "$G.EnumValueDescriptorProto",
            fields    => [
                Protobuf::DescriptorSet::Proto::_scalar( 'name',   1, 'string' ),
                Protobuf::DescriptorSet::Proto::_scalar( 'number', 2, 'int32' ),
                Protobuf::DescriptorSet::Proto::_message( 'options', 3, "$G.EnumValueOptions" ),
            ],
        );

        my $enum_value_options = Protobuf::Schema::Message->new(
            name      => 'EnumValueOptions',
            full_name => "$G.EnumValueOptions",
            fields    => [
                Protobuf::DescriptorSet::Proto::_message( 'features', 2, "$G.FeatureSet" ),
            ],
        );

        my $oneof_descriptor_proto = Protobuf::Schema::Message->new(
            name      => 'OneofDescriptorProto',
            full_name => "$G.OneofDescriptorProto",
            fields    => [
                Protobuf::DescriptorSet::Proto::_scalar( 'name', 1, 'string' ),
            ],
        );

        my $file = Protobuf::Schema::File->new(
            name     => 'google/protobuf/descriptor.proto',
            package  => $G,
            messages => [
                $file_descriptor_set,
                $file_descriptor_proto,
                $descriptor_proto,
                $extension_range,
                $reserved_range,
                $message_options,
                $file_options,
                $field_options,
                $feature_set,
                $field_descriptor_proto,
                $enum_descriptor_proto,
                $enum_options,
                $enum_value_descriptor_proto,
                $enum_value_options,
                $oneof_descriptor_proto,
            ],
        );

        my $schema = Protobuf::Schema->new;
        $schema->add_file($file);
        $schema->resolve;
        return $schema;
    }
}

1;

__END__

=encoding utf-8

=head1 NAME

Protobuf::DescriptorSet::Proto - bootstrap schema for the google.protobuf
descriptor messages

=head1 SYNOPSIS

    use Protobuf::DescriptorSet::Proto;

    my $schema = Protobuf::DescriptorSet::Proto->schema;
    my $codec  = Protobuf::Codec->new( schema => $schema );
    my $fds    = $codec->decode( 'google.protobuf.FileDescriptorSet', $bytes );

=head1 DESCRIPTION

A C<.proto> file is, when compiled by C<protoc --descriptor_set_out>, emitted as
a binary C<google.protobuf.FileDescriptorSet> message. To read one we need the
schema of the descriptor messages themselves — but that schema is exactly what
this library exists to load, hence the B<bootstrap>: this module hand-writes a
L<Protobuf::Schema> for the subset of C<descriptor.proto> that
L<Protobuf::DescriptorSet> consumes, so the ordinary L<Protobuf::Codec> can decode an
incoming FileDescriptorSet.

Only the descriptor fields the loader reads are modeled; everything else
(C<source_code_info>, services, extensions, the bulk of the C<*Options>
messages) is omitted and skipped as an unknown field on decode. The field
numbers are transcribed verbatim from the vendored
C<share/proto/google/protobuf/descriptor.proto> and are asserted against
C<protoc>'s own output by C<t/descriptor/load.t>.

=head1 METHODS

=head2 schema

    my $schema = Protobuf::DescriptorSet::Proto->schema;

Return a freshly-built, resolved L<Protobuf::Schema> containing the descriptor
messages. A new schema is built on each call so callers do not share mutable
state.

=head1 LICENSE

This software is licensed under the MIT license. See the C<LICENSE> file.

=cut
