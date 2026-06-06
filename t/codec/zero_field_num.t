# ABOUTME: decode MUST reject a wire field number of 0 — it is illegal in proto3
# and parsing must fail rather than silently accept it.
use v5.38;
use warnings;
use Test::More;
use lib 'lib';

use Protobuf::Exception;
use Protobuf::Schema;
use Protobuf::Schema::File;
use Protobuf::Schema::Message;
use Protobuf::Schema::Field;
use Protobuf::Codec;

my sub codec_for () {
    my $f = Protobuf::Schema::Field->new(
        name => 'f', json_name => 'f', number => 1,
        label => 'singular', type => 'int32',
    );
    my $m = Protobuf::Schema::Message->new(
        name => 'M', full_name => 'M', fields => [$f],
    );
    my $schema = Protobuf::Schema->new;
    $schema->add_file(
        Protobuf::Schema::File->new(
            name => 'x.proto', package => '',
            messages => [$m], enums => [], services => [], imports => [],
        )
    );
    $schema->resolve;
    return Protobuf::Codec->new( schema => $schema );
}

# A tag byte whose field number is 0 is illegal. protoc's IllegalZeroFieldNum
# cases: "\x01..." (tag 1 = field 0, wire I64), "\x02\x01\x01" (tag 2 = field 0,
# wire LEN), "\x05..." (tag 5 = field 0, wire I32). Each must throw.
for my $wire (
    [ "\x01" . ( "\x00" x 8 ),        'field 0 / wire I64' ],
    [ "\x02\x01\x01",                 'field 0 / wire LEN' ],
    [ "\x05" . ( "\x00" x 4 ),        'field 0 / wire I32' ],
    [ "\x00\x01",                     'field 0 / wire VARINT' ],
  )
{
    my ( $bytes, $label ) = @$wire;
    my $codec = codec_for();
    my $ok = eval { $codec->decode( 'M', $bytes ); 1 };
    ok( !$ok, "decode rejects $label" );
    isa_ok( $@, 'Protobuf::Exception::Wire', "$label throws a wire exception" );
}

# A valid field number 1 is still accepted (sanity).
{
    my $codec = codec_for();
    my $d = $codec->decode( 'M', "\x08\x2a" );
    is( $d->{f}, 42, 'valid field number 1 still decodes' );
}

done_testing;
