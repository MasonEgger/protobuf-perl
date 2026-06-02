# ABOUTME: Proto3::DescriptorSet::Proto — hand-written bootstrap schema for the
# google.protobuf descriptor messages, enough to DECODE a binary FileDescriptorSet.
use v5.38;
use feature 'class';
no warnings 'experimental::class';

use Proto3::Schema;
use Proto3::Schema::File;
use Proto3::Schema::Message;
use Proto3::Schema::Field;

# The bootstrap problem (spec §4.7): a FileDescriptorSet is itself a protobuf
# message (google.protobuf.FileDescriptorSet), so to decode one we need its
# schema — but our parser/loader path is exactly what we're bootstrapping. The
# resolution is to hand-write the subset of descriptor.proto needed to read an
# FDS as a Proto3::Schema, then feed it to the ordinary Proto3::Codec. Only the
# fields Proto3::DescriptorSet consumes are modeled; the many descriptor fields
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
# death). Naming them Proto3::DescriptorSet::Proto::* sidesteps that — the same
# trick Proto3::Resolver uses for candidate_names. @_ unpacking (rather than a
# signature) avoids the 5.38.2 "signature before a class block" parse trap.

# Build a Schema::Field for a singular scalar descriptor field. Modeled as
# `optional` (explicit presence) on purpose: descriptor.proto declares these as
# proto2 `optional`, and the loader depends on the distinction. proto3 implicit
# presence would default-fill an absent oneof_index/proto3_optional/type to 0,
# making "field has no oneof" indistinguishable from "field is in oneof 0";
# explicit presence keeps an absent scalar absent so protoc's presence semantics
# survive the decode.
sub Proto3::DescriptorSet::Proto::_scalar {
    my ( $name, $number, $type ) = @_;
    return Proto3::Schema::Field->new(
        name => $name, number => $number, type => $type, label => 'optional',
    );
}

# Build a Schema::Field for a repeated scalar descriptor field.
sub Proto3::DescriptorSet::Proto::_rep_scalar {
    my ( $name, $number, $type ) = @_;
    return Proto3::Schema::Field->new(
        name => $name, number => $number, type => $type, label => 'repeated',
    );
}

# Build a Schema::Field for a repeated message descriptor field. type_name is the
# fully-qualified descriptor message name; type_ref is linked by Schema->resolve.
sub Proto3::DescriptorSet::Proto::_rep_message {
    my ( $name, $number, $type_name ) = @_;
    return Proto3::Schema::Field->new(
        name      => $name,
        number    => $number,
        type      => 'message',
        type_name => $type_name,
        label     => 'repeated',
    );
}

# Build a Schema::Field for a singular message descriptor field.
sub Proto3::DescriptorSet::Proto::_message {
    my ( $name, $number, $type_name ) = @_;
    return Proto3::Schema::Field->new(
        name      => $name,
        number    => $number,
        type      => 'message',
        type_name => $type_name,
        label     => 'singular',
    );
}

class Proto3::DescriptorSet::Proto {

    # Return a resolved Proto3::Schema modeling the google.protobuf descriptor
    # messages needed to decode a FileDescriptorSet. A fresh schema is built on
    # each call so callers never share mutable resolver state.
    sub schema ($class) {
        my $G = 'google.protobuf';

        my $file_descriptor_set = Proto3::Schema::Message->new(
            name      => 'FileDescriptorSet',
            full_name => "$G.FileDescriptorSet",
            fields    => [
                Proto3::DescriptorSet::Proto::_rep_message( 'file', 1, "$G.FileDescriptorProto" ),
            ],
        );

        my $file_descriptor_proto = Proto3::Schema::Message->new(
            name      => 'FileDescriptorProto',
            full_name => "$G.FileDescriptorProto",
            fields    => [
                Proto3::DescriptorSet::Proto::_scalar( 'name',              1,  'string' ),
                Proto3::DescriptorSet::Proto::_scalar( 'package',           2,  'string' ),
                Proto3::DescriptorSet::Proto::_rep_scalar( 'dependency',    3,  'string' ),
                Proto3::DescriptorSet::Proto::_rep_message( 'message_type', 4,  "$G.DescriptorProto" ),
                Proto3::DescriptorSet::Proto::_rep_message( 'enum_type',    5,  "$G.EnumDescriptorProto" ),
                Proto3::DescriptorSet::Proto::_rep_scalar( 'public_dependency', 10, 'int32' ),
                Proto3::DescriptorSet::Proto::_rep_scalar( 'weak_dependency',   11, 'int32' ),
                Proto3::DescriptorSet::Proto::_scalar( 'syntax',            12, 'string' ),
            ],
        );

        my $descriptor_proto = Proto3::Schema::Message->new(
            name      => 'DescriptorProto',
            full_name => "$G.DescriptorProto",
            fields    => [
                Proto3::DescriptorSet::Proto::_scalar( 'name',           1, 'string' ),
                Proto3::DescriptorSet::Proto::_rep_message( 'field',     2, "$G.FieldDescriptorProto" ),
                Proto3::DescriptorSet::Proto::_rep_message( 'nested_type', 3, "$G.DescriptorProto" ),
                Proto3::DescriptorSet::Proto::_rep_message( 'enum_type', 4, "$G.EnumDescriptorProto" ),
                Proto3::DescriptorSet::Proto::_message( 'options',       7, "$G.MessageOptions" ),
                Proto3::DescriptorSet::Proto::_rep_message( 'oneof_decl', 8, "$G.OneofDescriptorProto" ),
                Proto3::DescriptorSet::Proto::_rep_message( 'reserved_range', 9,
                    "$G.DescriptorProto.ReservedRange" ),
                Proto3::DescriptorSet::Proto::_rep_scalar( 'reserved_name', 10, 'string' ),
            ],
        );

        my $reserved_range = Proto3::Schema::Message->new(
            name      => 'ReservedRange',
            full_name => "$G.DescriptorProto.ReservedRange",
            fields    => [
                Proto3::DescriptorSet::Proto::_scalar( 'start', 1, 'int32' ),
                Proto3::DescriptorSet::Proto::_scalar( 'end',   2, 'int32' ),
            ],
        );

        my $message_options = Proto3::Schema::Message->new(
            name      => 'MessageOptions',
            full_name => "$G.MessageOptions",
            fields    => [
                Proto3::DescriptorSet::Proto::_scalar( 'map_entry', 7, 'bool' ),
            ],
        );

        my $field_descriptor_proto = Proto3::Schema::Message->new(
            name      => 'FieldDescriptorProto',
            full_name => "$G.FieldDescriptorProto",
            fields    => [
                Proto3::DescriptorSet::Proto::_scalar( 'name',            1,  'string' ),
                Proto3::DescriptorSet::Proto::_scalar( 'number',          3,  'int32' ),
                Proto3::DescriptorSet::Proto::_scalar( 'label',           4,  'int32' ),  # Label enum
                Proto3::DescriptorSet::Proto::_scalar( 'type',            5,  'int32' ),  # Type enum
                Proto3::DescriptorSet::Proto::_scalar( 'type_name',       6,  'string' ),
                Proto3::DescriptorSet::Proto::_scalar( 'oneof_index',     9,  'int32' ),
                Proto3::DescriptorSet::Proto::_scalar( 'json_name',       10, 'string' ),
                Proto3::DescriptorSet::Proto::_scalar( 'proto3_optional', 17, 'bool' ),
            ],
        );

        my $enum_descriptor_proto = Proto3::Schema::Message->new(
            name      => 'EnumDescriptorProto',
            full_name => "$G.EnumDescriptorProto",
            fields    => [
                Proto3::DescriptorSet::Proto::_scalar( 'name',  1, 'string' ),
                Proto3::DescriptorSet::Proto::_rep_message( 'value', 2, "$G.EnumValueDescriptorProto" ),
            ],
        );

        my $enum_value_descriptor_proto = Proto3::Schema::Message->new(
            name      => 'EnumValueDescriptorProto',
            full_name => "$G.EnumValueDescriptorProto",
            fields    => [
                Proto3::DescriptorSet::Proto::_scalar( 'name',   1, 'string' ),
                Proto3::DescriptorSet::Proto::_scalar( 'number', 2, 'int32' ),
            ],
        );

        my $oneof_descriptor_proto = Proto3::Schema::Message->new(
            name      => 'OneofDescriptorProto',
            full_name => "$G.OneofDescriptorProto",
            fields    => [
                Proto3::DescriptorSet::Proto::_scalar( 'name', 1, 'string' ),
            ],
        );

        my $file = Proto3::Schema::File->new(
            name     => 'google/protobuf/descriptor.proto',
            package  => $G,
            messages => [
                $file_descriptor_set,
                $file_descriptor_proto,
                $descriptor_proto,
                $reserved_range,
                $message_options,
                $field_descriptor_proto,
                $enum_descriptor_proto,
                $enum_value_descriptor_proto,
                $oneof_descriptor_proto,
            ],
        );

        my $schema = Proto3::Schema->new;
        $schema->add_file($file);
        $schema->resolve;
        return $schema;
    }
}

1;

__END__

=head1 NAME

Proto3::DescriptorSet::Proto - bootstrap schema for the google.protobuf
descriptor messages

=head1 SYNOPSIS

    use Proto3::DescriptorSet::Proto;

    my $schema = Proto3::DescriptorSet::Proto->schema;
    my $codec  = Proto3::Codec->new( schema => $schema );
    my $fds    = $codec->decode( 'google.protobuf.FileDescriptorSet', $bytes );

=head1 DESCRIPTION

A C<.proto> file is, when compiled by C<protoc --descriptor_set_out>, emitted as
a binary C<google.protobuf.FileDescriptorSet> message. To read one we need the
schema of the descriptor messages themselves — but that schema is exactly what
this library exists to load, hence the B<bootstrap>: this module hand-writes a
L<Proto3::Schema> for the subset of C<descriptor.proto> that
L<Proto3::DescriptorSet> consumes, so the ordinary L<Proto3::Codec> can decode an
incoming FileDescriptorSet.

Only the descriptor fields the loader reads are modeled; everything else
(C<source_code_info>, services, extensions, the bulk of the C<*Options>
messages) is omitted and skipped as an unknown field on decode. The field
numbers are transcribed verbatim from the vendored
C<share/proto/google/protobuf/descriptor.proto> and are asserted against
C<protoc>'s own output by C<t/descriptor/load.t>.

=head1 METHODS

=head2 schema

    my $schema = Proto3::DescriptorSet::Proto->schema;

Return a freshly-built, resolved L<Proto3::Schema> containing the descriptor
messages. A new schema is built on each call so callers do not share mutable
state.

=head1 LICENSE

This software is licensed under the MIT license. See the C<LICENSE> file.

=cut
