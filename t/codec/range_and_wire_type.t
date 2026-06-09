# ABOUTME: encode-time integer range checks (B-007) and decode-time wire-type
# mismatch detection (B-008) — both raise typed Protobuf::Exception::Codec errors.
use v5.38;
use warnings;
use Test::More;
use lib 'lib';

use Protobuf::Parser;
use Protobuf::Schema;
use Protobuf::Codec;
use Protobuf::Exception;

sub codec_for ($src) {
    my $schema = Protobuf::Schema->new;
    $schema->add_file( Protobuf::Parser->new->parse_string( 't.proto', $src ) );
    $schema->resolve;
    return Protobuf::Codec->new( schema => $schema );
}

# --- B-007: out-of-range integer encode raises OutOfRange ------------------
{
    my $codec = codec_for('syntax = "proto3"; message M { int32 x = 1; }');

    my $err = do { local $@; eval { $codec->encode( 'M', { x => 2**40 } ); 1 }; $@ };
    isa_ok( $err, 'Protobuf::Exception::Codec::OutOfRange',
        'int32 = 2**40 raises OutOfRange' );

    ok( eval { $codec->encode( 'M', { x => 2147483647 } ); 1 },
        'int32 max encodes' );
    ok( eval { $codec->encode( 'M', { x => -2147483648 } ); 1 },
        'int32 min encodes' );

    my $over = do { local $@; eval { $codec->encode( 'M', { x => 2147483648 } ); 1 }; $@ };
    isa_ok( $over, 'Protobuf::Exception::Codec::OutOfRange', 'int32 max+1 rejected' );
}

# uint32 rejects negatives; uint64/int64 bounds enforced.
{
    my $c = codec_for('syntax = "proto3"; message M { uint32 u = 1; }');
    my $err = do { local $@; eval { $c->encode( 'M', { u => -1 } ); 1 }; $@ };
    isa_ok( $err, 'Protobuf::Exception::Codec::OutOfRange', 'uint32 = -1 rejected' );
}

# --- B-008: wrong wire type on decode raises WireTypeMismatch --------------
{
    my $codec = codec_for('syntax = "proto3"; message M { int32 x = 1; }');

    # field 1 declared int32 (wire 0 = VARINT) but the tag carries wire 5 (I32).
    my $tag   = ( 1 << 3 ) | 5;                       # 0x0d
    my $bytes = pack( 'C', $tag ) . pack( 'V', 1 );   # 4-byte I32 payload
    my $err = do { local $@; eval { $codec->decode( 'M', $bytes ); 1 }; $@ };
    isa_ok( $err, 'Protobuf::Exception::Codec::WireTypeMismatch',
        'int32 field with I32 wire type rejected' );

    # The correct wire type still decodes.
    my $ok_tag = ( 1 << 3 ) | 0;                      # VARINT
    my $good   = pack( 'C', $ok_tag ) . pack( 'C', 42 );
    is( $codec->decode( 'M', $good )->{x}, 42, 'correct wire type decodes' );
}

done_testing;
