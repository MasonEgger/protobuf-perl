# ABOUTME: a proto3 `string` field (utf8_validation=VERIFY) must REJECT invalid
# UTF-8 octets on the binary wire; proto2 (NONE) keeps lenient decoding.
use v5.38;
use warnings;
use Test::More;
use lib 'lib';

use Proto3::Schema;
use Proto3::Schema::File;
use Proto3::Schema::Message;
use Proto3::Schema::Field;
use Proto3::Codec;

# Build a one-field message of the given type/label under the given edition
# syntax, resolve it (so utf8_validation features are populated), and return a
# ready codec. proto3 strings resolve to VERIFY; proto2 strings to NONE.
sub codec_for ( $type, %opt ) {
    my $label = $opt{label} // 'singular';
    my $f     = Proto3::Schema::Field->new(
        name  => 'f', json_name => 'f', number => 1,
        label => $label, type => $type,
    );
    my $m = Proto3::Schema::Message->new(
        name => 'M', full_name => 'M', fields => [$f],
    );
    my $schema = Proto3::Schema->new;
    $schema->add_file(
        Proto3::Schema::File->new(
            name     => 'x.proto', package => '',
            syntax   => $opt{syntax} // 'proto3',
            messages => [$m], enums => [], services => [], imports => [],
        )
    );
    $schema->resolve;
    return Proto3::Codec->new( schema => $schema );
}

# The conformance RejectInvalidUtf8 payload: field 1 (LEN), 4 bytes a0 b0 c0 d0,
# none of which is a valid UTF-8 lead/continuation sequence.
my $BAD = "\x0a\x04\xa0\xb0\xc0\xd0";

# --- proto3 singular string: invalid UTF-8 is rejected -----------------------
{
    my $codec = codec_for('string');
    is( $codec->schema->message('M')->fields->[0]->utf8_validation,
        'VERIFY', 'proto3 string field resolves to utf8_validation=VERIFY' );
    my $ok = eval { $codec->decode( 'M', $BAD ); 1 };
    ok( !$ok, 'proto3 string rejects invalid UTF-8 on the wire' );
    isa_ok( $@, 'Proto3::Exception::Codec::TypeMismatch',
        'rejection raises a Codec::TypeMismatch' );
}

# --- proto3 repeated string: invalid UTF-8 is rejected -----------------------
{
    my $codec = codec_for( 'string', label => 'repeated' );
    my $ok = eval { $codec->decode( 'M', $BAD ); 1 };
    ok( !$ok, 'proto3 repeated string rejects invalid UTF-8 on the wire' );
}

# --- proto3 valid UTF-8 still decodes ----------------------------------------
{
    my $codec = codec_for('string');
    my $good  = "\x0a\x05" . 'hello';
    my $back  = $codec->decode( 'M', $good );
    is( $back->{f}, 'hello', 'valid UTF-8 string still decodes' );
}

# --- proto2 string: NONE, invalid UTF-8 is NOT rejected (lenient) ------------
{
    my $codec = codec_for( 'string', syntax => 'proto2' );
    is( $codec->schema->message('M')->fields->[0]->utf8_validation,
        'NONE', 'proto2 string field resolves to utf8_validation=NONE' );
    my $ok = eval { $codec->decode( 'M', $BAD ); 1 };
    ok( $ok, 'proto2 string does NOT reject invalid UTF-8 (lenient decode)' );
}

# --- bytes field with the same octets is always accepted ---------------------
{
    my $codec = codec_for('bytes');
    my $back  = $codec->decode( 'M', $BAD );
    is( $back->{f}, "\xa0\xb0\xc0\xd0",
        'bytes field accepts the same octets verbatim' );
}

done_testing;
