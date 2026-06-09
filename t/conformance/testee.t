# ABOUTME: Step 30 — drives Protobuf::Conformance::handle_request directly with a
# ConformanceRequest and asserts the ConformanceResponse (no external runner).
use v5.38;
use warnings;
use Test::More;
use lib 'lib';

use Protobuf::Conformance;
use Protobuf::DescriptorSet;
use Protobuf::Codec;
use Protobuf::JSON;

# ----------------------------------------------------------------------
# The conformance schema (ConformanceRequest/Response + the test message
# protobuf_test_messages.proto3.TestAllTypesProto3) is vendored as a binary
# FileDescriptorSet at share/proto/conformance.fds. handle_request builds its
# own codec/JSON from that schema; here we build a parallel codec/JSON to
# author request payloads and verify response payloads.
# ----------------------------------------------------------------------

my $schema = Protobuf::DescriptorSet->load_file('share/proto/conformance.fds');
my $codec  = Protobuf::Codec->new( schema => $schema );
my $json   = Protobuf::JSON->new( codec => $codec, schema => $schema );

my $REQUEST  = 'conformance.ConformanceRequest';
my $RESPONSE = 'conformance.ConformanceResponse';
my $TESTMSG  = 'protobuf_test_messages.proto3.TestAllTypesProto3';

# WireFormat enum: PROTOBUF=1, JSON=2.
my $WIRE_PROTOBUF = 1;
my $WIRE_JSON     = 2;

# Build a ConformanceRequest hashref into wire bytes, run the handler, and decode
# the ConformanceResponse it returns. handle_request takes/returns raw bytes.
sub run_request ($request_hashref) {
    my $request_bytes  = $codec->encode( $REQUEST, $request_hashref );
    my $response_bytes = Protobuf::Conformance::handle_request($request_bytes);
    return $codec->decode( $RESPONSE, $response_bytes );
}

# A simple TestAllTypesProto3 payload exercised across formats. optional_int32 is
# field 1, optional_string is field 14 in the test message.
my $PAYLOAD = { optional_int32 => 42, optional_string => 'conformance' };

# --- 30.1: proto-input -> proto-output re-encodes correctly -------------------
{
    my $payload_bytes = $codec->encode( $TESTMSG, $PAYLOAD );
    my $resp = run_request(
        {
            protobuf_payload        => $payload_bytes,
            requested_output_format => $WIRE_PROTOBUF,
            message_type            => $TESTMSG,
        }
    );

    ok( exists $resp->{protobuf_payload}, '30.1 proto->proto sets protobuf_payload' );
    ok( !exists $resp->{parse_error}, '30.1 proto->proto has no parse_error' );

    my $decoded = $codec->decode( $TESTMSG, $resp->{protobuf_payload} );
    is( $decoded->{optional_int32},  42,            '30.1 round-trips optional_int32' );
    is( $decoded->{optional_string}, 'conformance', '30.1 round-trips optional_string' );
}

# --- 30.2: unparseable protobuf payload -> parse_error ------------------------
{
    # 0x08 is a tag for field 1 varint; truncating the varint body makes the
    # payload undecodable, so parsing the inner test message must fail.
    my $resp = run_request(
        {
            protobuf_payload        => "\x08",
            requested_output_format => $WIRE_PROTOBUF,
            message_type            => $TESTMSG,
        }
    );

    ok( exists $resp->{parse_error}, '30.2 unparseable -> parse_error set' );
    ok( length $resp->{parse_error}, '30.2 parse_error carries a message' );
    ok( !exists $resp->{protobuf_payload},
        '30.2 unparseable -> no protobuf_payload' );
}

# --- 30.3: unsupported feature (JSPB / TEXT_FORMAT output) -> skipped ----------
{
    my $WIRE_TEXT_FORMAT = 4;
    my $payload_bytes    = $codec->encode( $TESTMSG, $PAYLOAD );
    my $resp = run_request(
        {
            protobuf_payload        => $payload_bytes,
            requested_output_format => $WIRE_TEXT_FORMAT,
            message_type            => $TESTMSG,
        }
    );

    ok( exists $resp->{skipped}, '30.3 unsupported output format -> skipped' );
    ok( length $resp->{skipped}, '30.3 skipped carries a reason' );
}

# --- 30.4a: JSON-input -> proto-output round-trips ----------------------------
{
    my $json_payload = $json->encode( $TESTMSG, $PAYLOAD );
    my $resp = run_request(
        {
            json_payload            => $json_payload,
            requested_output_format => $WIRE_PROTOBUF,
            message_type            => $TESTMSG,
        }
    );

    ok( exists $resp->{protobuf_payload}, '30.4a JSON->proto sets protobuf_payload' );
    my $decoded = $codec->decode( $TESTMSG, $resp->{protobuf_payload} );
    is( $decoded->{optional_int32},  42,            '30.4a JSON->proto int32' );
    is( $decoded->{optional_string}, 'conformance', '30.4a JSON->proto string' );
}

# --- 30.4b: proto-input -> JSON-output round-trips ----------------------------
{
    my $payload_bytes = $codec->encode( $TESTMSG, $PAYLOAD );
    my $resp = run_request(
        {
            protobuf_payload        => $payload_bytes,
            requested_output_format => $WIRE_JSON,
            message_type            => $TESTMSG,
        }
    );

    ok( exists $resp->{json_payload}, '30.4b proto->JSON sets json_payload' );
    my $decoded = $json->decode( $TESTMSG, $resp->{json_payload} );
    is( $decoded->{optional_int32},  42,            '30.4b proto->JSON int32' );
    is( $decoded->{optional_string}, 'conformance', '30.4b proto->JSON string' );
}

# --- 30.4c: invalid JSON input -> parse_error (not a crash) -------------------
{
    my $resp = run_request(
        {
            json_payload            => '{ this is not json',
            requested_output_format => $WIRE_PROTOBUF,
            message_type            => $TESTMSG,
        }
    );

    ok( exists $resp->{parse_error}, '30.4c invalid JSON -> parse_error' );
    ok( !exists $resp->{protobuf_payload},
        '30.4c invalid JSON -> no protobuf_payload' );
}

# --- end-to-end stdio framing: the real binary must FLUSH each response -------
# The conformance runner keeps the testee alive and reads its response over a
# pipe before sending the next request. If run_stdio writes a response into a
# block-buffered handle without flushing, the runner blocks forever waiting for
# bytes stuck in Perl's buffer and the whole suite deadlocks. Drive the actual
# bin/protobuf-conformance over pipes and require a framed response back BEFORE
# closing stdin; an unflushed write makes this read hang (caught by alarm).
SKIP: {
    require IPC::Open2;
    my $payload_bytes = $codec->encode( $TESTMSG, $PAYLOAD );
    my $req_bytes     = $codec->encode(
        $REQUEST,
        {
            protobuf_payload        => $payload_bytes,
            requested_output_format => $WIRE_PROTOBUF,
            message_type            => $TESTMSG,
        }
    );

    my ( $out, $in );
    my $pid = eval {
        IPC::Open2::open2( $out, $in, $^X, '-Ilib', 'bin/protobuf-conformance' );
    };
    skip "cannot spawn testee: $@", 2 unless $pid;
    binmode $in;
    binmode $out;

    my $resp_bytes = eval {
        local $SIG{ALRM} = sub { die "timeout\n" };
        alarm 20;
        # Send one framed request but DO NOT close stdin — the testee must
        # respond to this frame while still waiting for more, exactly as the
        # runner drives it.
        print {$in} pack( 'V', length $req_bytes ), $req_bytes;
        $in->flush;
        my $len_raw = '';
        read( $out, $len_raw, 4 ) == 4 or die "no length prefix\n";
        my $len = unpack 'V', $len_raw;
        my $body = '';
        while ( length $body < $len ) {
            my $n = read( $out, my $c, $len - length $body );
            last if !$n;
            $body .= $c;
        }
        alarm 0;
        $body;
    };
    my $err = $@;

    # Clean up the child regardless of outcome.
    close $in  if $in;
    close $out if $out;
    waitpid( $pid, 0 ) if $pid;

    ok( !$err, 'run_stdio responds without deadlock (flushes each frame)' )
        or diag("stdio round-trip failed: $err");

    # The framed body is a ConformanceResponse; decode it as such, then decode
    # its protobuf_payload as the test message. (The earlier shortcut decoded the
    # response bytes directly as TESTMSG, which only ever "worked" by exploiting
    # the lenient wire-type mis-segmentation that B-008 now rejects.)
    my $resp = $err ? undef : eval { $codec->decode( $RESPONSE, $resp_bytes ) };
    my $decoded =
        ( $resp && $resp->{protobuf_payload} )
        ? eval { $codec->decode( $TESTMSG, $resp->{protobuf_payload} ) }
        : undef;
    is( $decoded && $decoded->{optional_int32},
        42, 'stdio round-trip returns the re-encoded payload' );
}

done_testing;
