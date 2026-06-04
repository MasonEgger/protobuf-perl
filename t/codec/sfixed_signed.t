# ABOUTME: sfixed32/sfixed64 are SIGNED fixed-width integers — a high-bit-set
# wire value decodes to a negative number (fixed32/fixed64 stay unsigned).
use v5.38;
use warnings;
use Test::More;
use lib 'lib';

use Proto3::Schema;
use Proto3::Schema::File;
use Proto3::Schema::Message;
use Proto3::Schema::Field;
use Proto3::Codec;

sub codec_for ($type) {
    my $f = Proto3::Schema::Field->new(
        name => 'f', json_name => 'f', number => 1,
        label => 'singular', type => $type,
    );
    my $m = Proto3::Schema::Message->new(
        name => 'M', full_name => 'M', fields => [$f],
    );
    my $schema = Proto3::Schema->new;
    $schema->add_file(
        Proto3::Schema::File->new(
            name => 'x.proto', package => '',
            messages => [$m], enums => [], services => [], imports => [],
        )
    );
    $schema->resolve;
    return Proto3::Codec->new( schema => $schema );
}

# sfixed64 = -1 on the wire is 0d ff ff ff ff ff ff ff ff (tag 0x0d = field1 I64).
{
    my $codec = codec_for('sfixed64');
    my $d = $codec->decode( 'M', "\x09\xff\xff\xff\xff\xff\xff\xff\xff" );
    is( "$d->{f}", '-1', 'sfixed64 0xFFFFFFFFFFFFFFFF -> -1 (signed)' );
    # round-trip
    is( $codec->decode( 'M', $codec->encode( 'M', { f => -1 } ) )->{f},
        -1, 'sfixed64 -1 round-trips' );
}

# sfixed32 = -1 on the wire is 0d ff ff ff ff (tag 0x0d = field1 I32).
{
    my $codec = codec_for('sfixed32');
    my $d = $codec->decode( 'M', "\x0d\xff\xff\xff\xff" );
    is( $d->{f}, -1, 'sfixed32 0xFFFFFFFF -> -1 (signed)' );
    is( $codec->decode( 'M', $codec->encode( 'M', { f => -2 } ) )->{f},
        -2, 'sfixed32 -2 round-trips' );
}

# fixed64/fixed32 stay UNSIGNED: the same bytes are a large positive number.
{
    my $codec = codec_for('fixed64');
    my $d = $codec->decode( 'M', "\x09\xff\xff\xff\xff\xff\xff\xff\xff" );
    is( "$d->{f}", '18446744073709551615', 'fixed64 stays unsigned' );
}
{
    my $codec = codec_for('fixed32');
    my $d = $codec->decode( 'M', "\x0d\xff\xff\xff\xff" );
    is( $d->{f}, 4294967295, 'fixed32 stays unsigned' );
}

done_testing;
