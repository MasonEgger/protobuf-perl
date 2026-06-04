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
