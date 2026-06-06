# ABOUTME: Reusable test harness that shells out to the protoc binary for
# differential testing — the oracle that proves our wire format matches protoc.
package ProtobufTest::Protoc;

use v5.38;
use warnings;
use experimental 'signatures';

use Exporter 'import';
use File::Temp ();
use File::Spec ();
use IPC::Open3 ();
use Symbol ();

our @EXPORT_OK = qw(
    have_protoc
    protoc_decode
    protoc_encode
);

# True when a usable `protoc` binary is on PATH. Differential tests call this
# from `plan skip_all` so the suite degrades gracefully where protoc is absent.
# The lookup is cached after the first probe.
my $HAVE_PROTOC;
sub have_protoc () {
    return $HAVE_PROTOC if defined $HAVE_PROTOC;

    for my $dir ( File::Spec->path ) {
        my $candidate = File::Spec->catfile( $dir, 'protoc' );
        if ( -x $candidate && !-d $candidate ) {
            $HAVE_PROTOC = 1;
            return $HAVE_PROTOC;
        }
    }
    $HAVE_PROTOC = 0;
    return $HAVE_PROTOC;
}

# Write the .proto source to a temp file and return ($dir_object, $proto_path).
# The returned File::Temp::Dir keeps the directory alive while the caller holds
# it; let it go out of scope to clean up.
sub _write_proto ($proto_source) {
    my $dir = File::Temp->newdir;
    my $proto_path = File::Spec->catfile( "$dir", 'fixtures.proto' );
    open my $fh, '>', $proto_path
        or die "cannot write $proto_path: $!";
    binmode $fh;
    print {$fh} $proto_source;
    close $fh;
    return ( $dir, $proto_path );
}

# Run protoc with @args, feeding $stdin_bytes on stdin, and return the raw
# stdout bytes. Dies with protoc's stderr on a non-zero exit so a harness misuse
# (bad .proto, wrong message name) surfaces loudly rather than as a silent
# mismatch.
sub _run_protoc ($stdin_bytes, @args) {
    my $err = Symbol::gensym();
    my $pid = IPC::Open3::open3( my $in, my $out, $err, 'protoc', @args );

    binmode $in;
    binmode $out;
    binmode $err;

    print {$in} $stdin_bytes;
    close $in;

    local $/;
    my $stdout = <$out> // '';
    my $stderr = <$err> // '';
    close $out;
    close $err;

    waitpid $pid, 0;
    my $exit = $? >> 8;
    if ( $exit != 0 ) {
        die "protoc exited $exit: $stderr";
    }
    return $stdout;
}

# protoc_decode($proto_source, $message, $wire_bytes) -> normalized text.
#
# Feed $wire_bytes to `protoc --decode=$message`, which renders the message as
# protobuf text format. Returns the text with trailing whitespace trimmed per
# line so two semantically equal renderings compare equal. The caller supplies
# the full .proto source defining $message (a fully-qualified, dotted name).
sub protoc_decode ($proto_source, $message, $wire_bytes) {
    my ( $dir, $proto_path ) = _write_proto($proto_source);
    my $proto_dir = "$dir";

    my $text = _run_protoc(
        $wire_bytes,
        "--proto_path=$proto_dir",
        "--decode=$message",
        $proto_path,
    );
    return _normalize_text($text);
}

# protoc_encode($proto_source, $message, $text) -> wire bytes.
#
# Feed protobuf text format on stdin to `protoc --encode=$message` and return
# the resulting wire bytes. Used to build a protoc-authored buffer that our
# decoder must then read back correctly.
sub protoc_encode ($proto_source, $message, $text) {
    my ( $dir, $proto_path ) = _write_proto($proto_source);
    my $proto_dir = "$dir";

    return _run_protoc(
        $text,
        "--proto_path=$proto_dir",
        "--encode=$message",
        $proto_path,
    );
}

# Normalize protoc text-format output for comparison: strip trailing whitespace
# from every line and drop blank lines, so cosmetic spacing differences do not
# cause false mismatches. Field ordering from protoc is deterministic by field
# number, so no reordering is needed.
sub _normalize_text ($text) {
    my @lines = split /\n/, $text;
    s/\s+\z// for @lines;
    @lines = grep { length } @lines;
    return join "\n", @lines;
}

1;

__END__

=head1 NAME

ProtobufTest::Protoc - protoc differential-test harness

=head1 SYNOPSIS

    use ProtobufTest::Protoc qw(have_protoc protoc_decode protoc_encode);

    plan skip_all => 'protoc not on PATH' unless have_protoc();

    my $text = protoc_decode( $proto_source, 'pkg.M', $our_wire_bytes );
    my $wire = protoc_encode( $proto_source, 'pkg.M', $protobuf_text );

=head1 DESCRIPTION

A small, reusable test helper that shells out to the C<protoc> binary to act as
an independent oracle for our wire format. Differential tests encode a message
with our codec and ask C<protoc --decode> to read it (or encode with
C<protoc --encode> and read it back with our decoder), proving byte-level
compatibility with the reference implementation.

Reused by the codec, resolver, and JSON differential steps.

=over 4

=item have_protoc()

True when a C<protoc> binary is on C<PATH>. Tests guard themselves with
C<plan skip_all> on a false result so the suite passes where protoc is absent.

=item protoc_decode($proto_source, $message, $wire_bytes)

Render C<$wire_bytes> as protobuf text via C<protoc --decode>, normalized for
comparison.

=item protoc_encode($proto_source, $message, $text)

Encode protobuf C<$text> to wire bytes via C<protoc --encode>.

=back

=head1 LICENSE

This software is licensed under the MIT license. See the C<LICENSE> file.

=cut
