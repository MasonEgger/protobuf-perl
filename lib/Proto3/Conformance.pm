# ABOUTME: Proto3::Conformance — the conformance testee request handler (spec
# §4.11). Decodes a ConformanceRequest, processes per input/output format, and
# returns an encoded ConformanceResponse; all logic lives here, bin/ stays thin.
use v5.38;
use feature 'class';
no warnings 'experimental::class';

use File::Spec ();
use Proto3::DescriptorSet;
use Proto3::Codec;
use Proto3::JSON;

# The fully-qualified names of the conformance protocol messages and the single
# test message the suite always exchanges (conformance.proto). Pre-class file
# lexicals: a bareword constant would land in the file package and be invisible
# inside the class block under feature 'class' package scoping.
my $REQUEST_MESSAGE  = 'conformance.ConformanceRequest';
my $RESPONSE_MESSAGE = 'conformance.ConformanceResponse';

# WireFormat enum values from conformance.proto. PROTOBUF/JSON are the formats we
# support; JSPB/TEXT_FORMAT (and the UNSPECIFIED 0) are reported as `skipped`.
my $WIRE_PROTOBUF = 1;
my $WIRE_JSON     = 2;

# Lazily-built, cached singletons for the conformance schema and its codec/JSON.
# The schema comes from the vendored binary FileDescriptorSet so the testee needs
# no protoc at runtime. Pre-class lexicals shared by the class methods below.
my $SCHEMA;
my $CODEC;
my $JSON;

# Absolute path to the vendored FileDescriptorSet, resolved relative to this
# module so the testee works regardless of the process working directory.
my $fds_path = do {
    sub {
        my $here = __FILE__;
        my ( $vol, $dir ) = File::Spec->splitpath($here);
        # $dir is .../lib/Proto3/ ; the share tree sits at the dist root, two
        # directories up from lib/Proto3.
        my $root = File::Spec->catdir( $vol . $dir, File::Spec->updir,
            File::Spec->updir );
        return File::Spec->catfile( $root, 'share', 'proto', 'conformance.fds' );
    };
};

class Proto3::Conformance {

    # schema() -> the resolved Proto3::Schema for the conformance protocol plus
    # the protobuf_test_messages proto3 test message, loaded once from the
    # vendored FileDescriptorSet and cached.
    sub schema ($class) {
        $SCHEMA //= Proto3::DescriptorSet->load_file( $fds_path->() );
        return $SCHEMA;
    }

    # codec() / json() -> cached handlers built over schema().
    sub codec ($class) {
        $CODEC //= Proto3::Codec->new( schema => $class->schema );
        return $CODEC;
    }

    sub json ($class) {
        $JSON //= Proto3::JSON->new(
            codec  => $class->codec,
            schema => $class->schema,
        );
        return $JSON;
    }
}

# handle_request($request_bytes) -> $response_bytes
#
# The core testee step (spec §4.11): decode the ConformanceRequest (which always
# parses), parse its payload in the input format, re-serialize the message to the
# requested output format, and return an encoded ConformanceResponse. The result
# oneof is set to exactly one of:
#   parse_error      the payload could not be parsed
#   protobuf_payload / json_payload   the re-serialized message
#   skipped          the requested input/output format is unsupported
#   serialize_error  serialization failed after a successful parse
# A fully-qualified name keeps this callable as Proto3::Conformance::handle_request.
sub Proto3::Conformance::handle_request {
    my ($request_bytes) = @_;

    my $codec = Proto3::Conformance->codec;

    # The ConformanceRequest itself "should always succeed" to parse; a failure
    # here is a protocol-level error, not a test payload error.
    my $request = $codec->decode( $REQUEST_MESSAGE, $request_bytes );

    my $result = Proto3::Conformance::_process_request($request);
    return $codec->encode( $RESPONSE_MESSAGE, $result );
}

# Process a decoded ConformanceRequest hashref into a ConformanceResponse
# hashref (the result oneof). Splits cleanly into: pick input, parse, pick
# output, serialize — each unsupported branch short-circuits to `skipped`.
sub Proto3::Conformance::_process_request {
    my ($request) = @_;

    my $message_type = $request->{message_type} // '';
    my $output_format = $request->{requested_output_format} // 0;

    # We only handle proto3 binary / JSON output. Anything else (TEXT_FORMAT,
    # JSPB, UNSPECIFIED) is a feature we do not implement -> skipped.
    if ( $output_format != $WIRE_PROTOBUF && $output_format != $WIRE_JSON ) {
        return { skipped => "unsupported requested_output_format $output_format" };
    }

    # Parse the payload in whichever input format the request carries. A parse
    # failure becomes parse_error (not a crash); an unsupported input format
    # (jspb/text) becomes skipped.
    my ( $values, $error ) =
        Proto3::Conformance::_parse_payload( $request, $message_type );
    return $error if $error;    # { parse_error => ... } or { skipped => ... }

    # Serialize the parsed message to the requested output format.
    return Proto3::Conformance::_serialize_payload( $values, $message_type,
        $output_format );
}

# Parse the request payload into a codec hashref. Returns ($values, undef) on
# success or (undef, $response) where $response is a parse_error/skipped result.
sub Proto3::Conformance::_parse_payload {
    my ( $request, $message_type ) = @_;

    if ( exists $request->{protobuf_payload} ) {
        my $values = eval {
            Proto3::Conformance->codec->decode( $message_type,
                $request->{protobuf_payload} );
        };
        return ( undef, { parse_error => "$@" } ) if $@;
        return ( $values, undef );
    }

    if ( exists $request->{json_payload} ) {
        my $values = eval {
            Proto3::Conformance->json->decode( $message_type,
                $request->{json_payload} );
        };
        return ( undef, { parse_error => "$@" } ) if $@;
        return ( $values, undef );
    }

    # jspb_payload / text_payload (or no payload) — unsupported input format.
    return ( undef, { skipped => 'unsupported input payload format' } );
}

# Serialize a parsed codec hashref to the requested output format. Returns a
# ConformanceResponse result hashref; a serialization failure becomes
# serialize_error.
sub Proto3::Conformance::_serialize_payload {
    my ( $values, $message_type, $output_format ) = @_;

    if ( $output_format == $WIRE_PROTOBUF ) {
        my $bytes = eval {
            Proto3::Conformance->codec->encode( $message_type, $values );
        };
        return { serialize_error => "$@" } if $@;
        return { protobuf_payload => $bytes };
    }

    # $output_format == $WIRE_JSON (the only remaining supported value).
    my $string = eval {
        Proto3::Conformance->json->encode( $message_type, $values );
    };
    return { serialize_error => "$@" } if $@;
    return { json_payload => $string };
}

# parse_runner_output($text) -> a hashref summarizing a conformance run.
#
# Google's conformance_test_runner writes per-failure lines and a final summary
# line to stdout/stderr. We turn that text into a verdict the test harness (and
# CI) act on (spec §4.11, T-conf-1/2):
#
#   {
#     required_failures    => [ "Required.Proto3.<...>", ... ],  # MUST be empty
#     recommended_failures => [ "Recommended.Proto3.<...>", ... ],# reported only
#     summary              => "CONFORMANCE SUITE ...",            # final line
#     parsed_summary       => bool,  # whether a summary line was found
#   }
#
# A required proto3 failure is the bar: the harness FAILs if required_failures is
# non-empty. Recommended failures are counted and reported but do not fail the
# build (CI reports the count non-blocking, T-conf-3).
#
# Failure lines look like:  ERROR, test=Required.Proto3.ProtobufInput...: <msg>
# The summary line looks like:
#   CONFORMANCE SUITE PASSED: 1234 successes, 5 skipped, 6 expected failures, 0 unexpected failures.
#   CONFORMANCE SUITE FAILED: ... N unexpected failures.
sub Proto3::Conformance::parse_runner_output {
    my ($text) = @_;
    $text //= '';

    my @required;
    my @recommended;
    my $summary;
    my $parsed_summary = 0;

    for my $line ( split /\n/, $text ) {
        if ( $line =~ /^CONFORMANCE SUITE (?:PASSED|FAILED)\b/ ) {
            $summary        = $line;
            $parsed_summary = 1;
            next;
        }

        # Per-test failure lines name the test; the conformance suite prefixes
        # proto3 required tests with "Required.Proto3" and recommended ones with
        # "Recommended.Proto3". Match the test name wherever it appears.
        next unless $line =~ /\btest=(\S+?):/ or $line =~ /\b(Re(?:quired|commended)\.Proto3\.\S+)/;
        my $test = $1;
        # Strip a trailing colon left by the first alternation's capture.
        $test =~ s/:$//;

        if ( $test =~ /^Required\.Proto3\./ ) {
            push @required, $test;
        }
        elsif ( $test =~ /^Recommended\.Proto3\./ ) {
            push @recommended, $test;
        }
    }

    return {
        required_failures    => \@required,
        recommended_failures => \@recommended,
        summary              => $summary,
        parsed_summary       => $parsed_summary,
    };
}

# find_runner() -> the path to the conformance test runner, or undef.
#
# Looks at $ENV{CONFORMANCE_TEST_RUNNER} first (CI sets this to the built
# binary), then searches PATH for `conformance_test_runner`. Returns undef when
# no runner is available so callers can skip the live integration (this box has
# no runner installed).
sub Proto3::Conformance::find_runner {
    my $explicit = $ENV{CONFORMANCE_TEST_RUNNER};
    return $explicit if defined $explicit && length $explicit && -x $explicit;

    for my $dir ( File::Spec->path ) {
        my $candidate = File::Spec->catfile( $dir, 'conformance_test_runner' );
        return $candidate if -x $candidate;
    }
    return undef;
}

# run_stdio($in_fh, $out_fh) -> number of requests served.
#
# The conformance runner protocol: each message is framed by a 4-byte
# little-endian length prefix followed by that many bytes of a serialized
# ConformanceRequest. Read one frame, hand the bytes to handle_request, write the
# response back with the same 4-byte length framing, and loop until EOF. bin/
# is a one-line call to this so all I/O logic stays in the module.
sub Proto3::Conformance::run_stdio {
    my ( $in_fh, $out_fh ) = @_;
    binmode $in_fh;
    binmode $out_fh;
    # The runner reads each response over a pipe before sending the next
    # request, so every frame must leave Perl's buffer immediately. Without
    # autoflush a block-buffered pipe holds the response and the runner
    # deadlocks waiting for it. Use the select idiom so no IO::Handle load is
    # required for a bareword STDOUT glob.
    my $prev = select $out_fh;
    $| = 1;
    select $prev;

    my $served = 0;
    while ( defined( my $request_bytes = Proto3::Conformance::_read_frame($in_fh) ) ) {
        my $response_bytes = Proto3::Conformance::handle_request($request_bytes);
        Proto3::Conformance::_write_frame( $out_fh, $response_bytes );
        $served++;
    }
    return $served;
}

# Read one length-delimited frame from $fh: a 4-byte little-endian length, then
# that many payload bytes. Returns the payload bytes, or undef at a clean EOF
# (no more frames). A truncated length or body is a protocol error.
sub Proto3::Conformance::_read_frame {
    my ($fh) = @_;

    my $len_bytes = Proto3::Conformance::_read_exact( $fh, 4 );
    return undef unless defined $len_bytes;    # clean EOF before next frame

    my $length = unpack 'V', $len_bytes;
    my $payload = Proto3::Conformance::_read_exact( $fh, $length );
    die "conformance: truncated frame (wanted $length bytes)\n"
        unless defined $payload;
    return $payload;
}

# Read exactly $want bytes from $fh, looping over short reads. Returns the bytes,
# or undef if EOF is hit before ANY byte is read (a clean stream end). A partial
# read followed by EOF is a truncation error.
sub Proto3::Conformance::_read_exact {
    my ( $fh, $want ) = @_;
    return '' if $want == 0;

    my $buf = '';
    while ( length $buf < $want ) {
        my $got = read $fh, my $chunk, $want - length $buf;
        die "conformance: read error: $!\n" unless defined $got;
        if ( $got == 0 ) {                     # EOF
            return undef if length $buf == 0;    # clean end between frames
            die "conformance: truncated read (have "
                . length($buf)
                . " of $want bytes)\n";
        }
        $buf .= $chunk;
    }
    return $buf;
}

# Write $bytes to $fh with a leading 4-byte little-endian length prefix.
sub Proto3::Conformance::_write_frame {
    my ( $fh, $bytes ) = @_;
    print {$fh} pack( 'V', length $bytes ), $bytes
        or die "conformance: write error: $!\n";
    return;
}

1;

__END__

=head1 NAME

Proto3::Conformance - the proto3 conformance testee request handler

=head1 SYNOPSIS

    use Proto3::Conformance;

    # Drive the handler directly with serialized protocol messages:
    my $response_bytes = Proto3::Conformance::handle_request($request_bytes);

    # Or run the stdin/stdout loop the Google runner drives:
    #   $ proto3-conformance < requests > responses

=head1 DESCRIPTION

C<Proto3::Conformance> implements the testee side of Google's protobuf
conformance protocol (spec §4.11). The conformance test runner sends a
C<conformance.ConformanceRequest> and expects a C<conformance.ConformanceResponse>
in return, for each test case.

The protocol and the single exchanged test message
(C<protobuf_test_messages.proto3.TestAllTypesProto3>) are described by the binary
C<FileDescriptorSet> vendored at C<share/proto/conformance.fds>, loaded via
L<Proto3::DescriptorSet> — so the testee needs no C<protoc> at runtime. All
logic lives in this module; C<bin/proto3-conformance> is a thin stdin/stdout
loop on top of L</handle_request>.

=head1 FUNCTIONS

=head2 handle_request

    my $response_bytes = Proto3::Conformance::handle_request($request_bytes);

Decode a serialized C<ConformanceRequest>, process it, and return a serialized
C<ConformanceResponse>. The response's C<result> oneof is set to exactly one of:

=over 4

=item *

C<protobuf_payload> / C<json_payload> — the input message re-serialized to the
requested output format.

=item *

C<parse_error> — the input payload (protobuf or JSON) could not be parsed. This
is not a crash: invalid input is an expected part of the test suite.

=item *

C<skipped> — the requested input or output format is unsupported (JSPB,
TEXT_FORMAT, or an unspecified format). Only proto3 binary and JSON are handled.

=item *

C<serialize_error> — the message parsed but could not be re-serialized to the
requested format.

=back

=head2 parse_runner_output

    my $verdict = Proto3::Conformance::parse_runner_output($runner_stdout);

Parse the text Google's C<conformance_test_runner> writes into a verdict the test
harness and CI act on (spec §4.11). Returns a hashref:

=over 4

=item *

C<required_failures> — arrayref of C<Required.Proto3.*> test names that failed.
The conformance bar (T-conf-1): this B<must> be empty.

=item *

C<recommended_failures> — arrayref of C<Recommended.Proto3.*> test names that
failed. Reported and counted but non-blocking (T-conf-2/3).

=item *

C<summary> — the final C<CONFORMANCE SUITE PASSED/FAILED: ...> line, if present.

=item *

C<parsed_summary> — true when a summary line was found.

=back

=head2 find_runner

    my $path = Proto3::Conformance::find_runner;

Locate the conformance test runner: C<$ENV{CONFORMANCE_TEST_RUNNER}> if it points
at an executable, else C<conformance_test_runner> on C<PATH>. Returns C<undef>
when no runner is available, so the live integration test skips.

=head2 run_stdio

    my $count = Proto3::Conformance::run_stdio(\*STDIN, \*STDOUT);

Run the conformance runner's stdin/stdout loop: each message is framed by a
4-byte little-endian length prefix followed by the serialized message. Reads one
C<ConformanceRequest> frame, calls L</handle_request>, writes the
C<ConformanceResponse> back with the same framing, and loops until a clean EOF.
Returns the number of requests served. A truncated frame (length or body) is a
protocol error and dies.

=head1 CLASS METHODS

=head2 schema / codec / json

    my $schema = Proto3::Conformance->schema;
    my $codec  = Proto3::Conformance->codec;
    my $json   = Proto3::Conformance->json;

Lazily-built, cached singletons: the resolved L<Proto3::Schema> for the
conformance protocol (from C<share/proto/conformance.fds>), and the
L<Proto3::Codec> / L<Proto3::JSON> handlers built over it.

=head1 LICENSE

This software is licensed under the MIT license. See the C<LICENSE> file.

=cut
