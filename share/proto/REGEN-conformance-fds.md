# Regenerating share/proto/conformance-v34.fds

The conformance testee loads its schema from a binary FileDescriptorSet covering
the conformance protocol messages plus the five test-message types (proto2,
proto3, editions-proto2, editions-proto3, edition2023). It is regenerated with a
v34-capable protoc (the system protoc may be too old for editions):

    PROTOC=<path to protoc 34.x>
    INC=<protobuf-conformance npm package>/include
    PROTOC_INC=<protoc34>/include
    $PROTOC \
      --proto_path="$INC" --proto_path="$PROTOC_INC" --include_imports \
      --descriptor_set_out=share/proto/conformance-v34.fds \
      "$INC/conformance/conformance.proto" \
      "$INC/google/protobuf/test_messages_proto2.proto" \
      "$INC/google/protobuf/test_messages_proto3.proto" \
      "$INC/google/protobuf/test_messages_proto2_editions.proto" \
      "$INC/google/protobuf/test_messages_proto3_editions.proto" \
      "$INC/google/protobuf/test_messages_edition2023.proto"

Prebuilt protoc: https://github.com/protocolbuffers/protobuf/releases (protoc-34.1-linux-x86_64.zip)
Prebuilt runner + protos: npm protobuf-conformance@34.1.0
