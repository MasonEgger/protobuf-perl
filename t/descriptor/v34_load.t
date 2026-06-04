# ABOUTME: T0.3 — the v34 FileDescriptorSet loads into the Schema model with
# correct presence/closed/encoding/default/extension attributes across proto2,
# proto3, and editions test messages.
use v5.38;
use warnings;
use Test::More;
use lib 'lib';

use Proto3::DescriptorSet;

use File::Spec ();

# Locate the vendored v34 FDS relative to the dist root.
my $FDS = File::Spec->catfile(qw(share proto conformance-v34.fds));
ok( -f $FDS, "v34 FDS present at $FDS" ) or BAIL_OUT("missing $FDS");

my $schema = Proto3::DescriptorSet->load_file($FDS);
isa_ok( $schema, 'Proto3::Schema', 'load_file returns a Schema' );

# ----------------------------------------------------------------------
# All five required test message types are present.
# ----------------------------------------------------------------------
my @required = qw(
    protobuf_test_messages.proto2.TestAllTypesProto2
    protobuf_test_messages.proto3.TestAllTypesProto3
    protobuf_test_messages.editions.proto2.TestAllTypesProto2
    protobuf_test_messages.editions.proto3.TestAllTypesProto3
    protobuf_test_messages.editions.TestAllTypesEdition2023
);
for my $fq (@required) {
    ok( $schema->message($fq), "message present: $fq" );
}

my $p2 = $schema->message('protobuf_test_messages.proto2.TestAllTypesProto2');
my $p3 = $schema->message('protobuf_test_messages.proto3.TestAllTypesProto3');
my $ed2023
    = $schema->message('protobuf_test_messages.editions.TestAllTypesEdition2023');

# Helper: find a field by name within a message.
sub field_named ($msg, $name) {
    for my $f ( @{ $msg->fields } ) {
        return $f if $f->name eq $name;
    }
    return undef;
}

# ----------------------------------------------------------------------
# Presence: a proto2 singular scalar is 'explicit'; a proto3 singular scalar
# is 'implicit'.
# ----------------------------------------------------------------------
is( field_named( $p2, 'optional_int32' )->presence, 'explicit',
    'proto2 singular scalar -> explicit presence' );
is( field_named( $p3, 'optional_int32' )->presence, 'implicit',
    'proto3 singular scalar -> implicit presence' );

# ----------------------------------------------------------------------
# Closed enums: proto2 enums are closed; proto3 enums are open.
# ----------------------------------------------------------------------
my $p2_enum = $schema->enum(
    'protobuf_test_messages.proto2.TestAllTypesProto2.NestedEnum');
my $p3_enum = $schema->enum(
    'protobuf_test_messages.proto3.TestAllTypesProto3.NestedEnum');
ok( $p2_enum, 'proto2 NestedEnum present' );
ok( $p3_enum, 'proto3 NestedEnum present' );
is( $p2_enum->closed, 1, 'proto2 enum is closed' );
is( $p3_enum->closed, 0, 'proto3 enum is open' );

# ----------------------------------------------------------------------
# A proto2 `required` field has presence 'legacy_required'.
# ----------------------------------------------------------------------
my $p2_req = $schema->message(
    'protobuf_test_messages.proto2.TestAllRequiredTypesProto2');
ok( $p2_req, 'TestAllRequiredTypesProto2 present' );
my $req_field = field_named( $p2_req, 'required_int32' );
ok( $req_field, 'required_int32 field present' );
is( $req_field->presence, 'legacy_required',
    'proto2 required field -> legacy_required presence' );

# ----------------------------------------------------------------------
# Repeated scalar packing: proto2 repeated scalar is EXPANDED (not packed);
# proto3 repeated scalar is PACKED.
# ----------------------------------------------------------------------
is( field_named( $p2, 'repeated_int32' )->is_packed, 0,
    'proto2 repeated scalar defaults to expanded (not packed)' );
is( field_named( $p3, 'repeated_int32' )->is_packed, 1,
    'proto3 repeated scalar defaults to packed' );

# ----------------------------------------------------------------------
# Explicit [packed = true] / [packed = false] override the edition default
# (spec §4.6). A proto2 field declared `[packed = true]` (packed_int32, field
# 75) overrides proto2's EXPANDED default and encodes PACKED; `[packed = false]`
# (unpacked_int32, field 89) keeps the EXPANDED default; a plain repeated proto2
# scalar with no flag stays EXPANDED. proto3 is the mirror: an explicit
# [packed = false] (unpacked_int32) overrides proto3's PACKED default.
# ----------------------------------------------------------------------
is( field_named( $p2, 'packed_int32' )->is_packed, 1,
    'proto2 [packed = true] overrides EXPANDED default -> packed' );
is( field_named( $p2, 'unpacked_int32' )->is_packed, 0,
    'proto2 [packed = false] stays expanded' );
is( field_named( $p3, 'unpacked_int32' )->is_packed, 0,
    'proto3 [packed = false] overrides PACKED default -> expanded' );
is( field_named( $p3, 'packed_int32' )->is_packed, 1,
    'proto3 [packed = true] stays packed' );

# ----------------------------------------------------------------------
# The override is observable on the wire: an explicitly-packed proto2 field
# encodes as one LEN-delimited run, while an explicitly-unpacked one encodes as
# repeated tag+value entries. packed_int32 is field 75 (LEN tag (75<<3)|2 =
# bytes DA 04); unpacked_int32 is field 89 (VARINT tag (89<<3)|0 = bytes C8 05).
# ----------------------------------------------------------------------
{
    require Proto3::Codec;
    my $codec = Proto3::Codec->new( schema => $schema );
    my $type  = 'protobuf_test_messages.proto2.TestAllTypesProto2';

    my $packed_wire = $codec->encode( $type, { packed_int32 => [ 1, 2, 3 ] } );
    like( $packed_wire, qr/\xDA\x04/,
        'proto2 [packed = true] field encodes a LEN-delimited packed run' );
    unlike( $packed_wire, qr/\xD8\x04/,
        'proto2 packed field emits no per-element VARINT tag (75<<3|0)' );

    my $unpacked_wire
        = $codec->encode( $type, { unpacked_int32 => [ 1, 2, 3 ] } );
    my $vtags = () = $unpacked_wire =~ /\xC8\x05/g;
    is( $vtags, 3,
        'proto2 [packed = false] field encodes one VARINT tag per element' );
}

# ----------------------------------------------------------------------
# Group field -> message_encoding 'delimited'.
# ----------------------------------------------------------------------
my $group_field = field_named( $p2, 'data' );
ok( $group_field, 'proto2 group field `data` present' );
is( $group_field->type, 'message', 'group field modeled as message' );
is( $group_field->message_encoding, 'delimited',
    'proto2 group field -> delimited message_encoding' );

# ----------------------------------------------------------------------
# A field with a [default = ...] carries its default_value.
# ----------------------------------------------------------------------
my $default_field = field_named( $p2, 'default_int32' );
ok( $default_field, 'default_int32 field present' );
is( $default_field->default_value, '-123456789',
    'default_int32 carries its declared default' );

# ----------------------------------------------------------------------
# The edition2023 file sets message_encoding=DELIMITED at the file level, so a
# message field with no per-field override inherits 'delimited'. (protoc emits
# an explicit message_encoding=LENGTH_PREFIXED override on most singular message
# fields; `delimited_field` deliberately carries none, so it shows the
# file-level default.)
# ----------------------------------------------------------------------
my $ed_msg_field = field_named( $ed2023, 'delimited_field' );
ok( $ed_msg_field, 'edition2023 delimited_field present' );
is( $ed_msg_field->type, 'message', 'delimited_field is a message field' );
is( $ed_msg_field->message_encoding, 'delimited',
    'edition2023 message field -> delimited (file-level DELIMITED)' );

# ----------------------------------------------------------------------
# Extension ranges + at least one registered extension on TestAllTypesProto2.
# ----------------------------------------------------------------------
ok( scalar @{ $p2->extension_ranges } > 0,
    'TestAllTypesProto2 has extension ranges' );
my $exts = $schema->extensions_for(
    'protobuf_test_messages.proto2.TestAllTypesProto2');
ok( scalar @$exts > 0,
    'TestAllTypesProto2 has at least one registered extension' );
my ($ext_int32) = grep { $_->name eq 'extension_int32' } @$exts;
ok( $ext_int32, 'extension_int32 registered on TestAllTypesProto2' );
ok( $ext_int32->is_extension, 'extension field marked is_extension' );

done_testing;
