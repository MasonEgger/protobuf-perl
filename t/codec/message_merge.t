# ABOUTME: proto3 decode MERGES repeated occurrences of a singular message field
# recursively (later scalars overwrite, submessages merge) instead of replacing.
use v5.38;
use warnings;
use Test::More;
use lib 'lib';

use Proto3::Schema;
use Proto3::Schema::File;
use Proto3::Schema::Message;
use Proto3::Schema::Field;
use Proto3::Schema::Oneof;
use Proto3::Codec;

my sub codec_for (@messages) {
    my $file = Proto3::Schema::File->new(
        name     => 'm.proto',
        package  => 'pkg',
        messages => [@messages],
    );
    my $schema = Proto3::Schema->new;
    $schema->add_file($file);
    return Proto3::Codec->new( schema => $schema );
}

# pkg.Inner { int32 a = 1; int32 b = 2 }
# pkg.Outer { Inner inner = 1 }
my sub merge_messages () {
    my $inner = Proto3::Schema::Message->new(
        name      => 'Inner',
        full_name => 'pkg.Inner',
        fields    => [
            Proto3::Schema::Field->new( name => 'a', number => 1, type => 'int32' ),
            Proto3::Schema::Field->new( name => 'b', number => 2, type => 'int32' ),
        ],
    );
    my $outer = Proto3::Schema::Message->new(
        name      => 'Outer',
        full_name => 'pkg.Outer',
        fields    => [
            Proto3::Schema::Field->new(
                name => 'inner', number => 1, type => 'message',
                type_name => 'pkg.Inner',
            ),
        ],
    );
    return ( $outer, $inner );
}

# Two occurrences of the singular message field: first sets a=1, second sets
# b=2. proto3 merges them so BOTH survive (the earlier a=1 is not dropped).
{
    my $codec = codec_for( merge_messages() );

    my $first  = "\x0a\x02\x08\x01";    # inner { a = 1 }
    my $second = "\x0a\x02\x10\x02";    # inner { b = 2 }
    my $decoded = $codec->decode( 'pkg.Outer', $first . $second );

    is( $decoded->{inner}{a}, 1, 'merge keeps the earlier sub-field a=1' );
    is( $decoded->{inner}{b}, 2, 'merge adds the later sub-field b=2' );
}

# A later occurrence overwrites a scalar set by an earlier one (last wins for
# the same sub-field).
{
    my $codec = codec_for( merge_messages() );

    my $first  = "\x0a\x02\x08\x01";    # inner { a = 1 }
    my $second = "\x0a\x02\x08\x09";    # inner { a = 9 }
    my $decoded = $codec->decode( 'pkg.Outer', $first . $second );

    is( $decoded->{inner}{a}, 9, 'merge overwrites the same scalar (last wins)' );
}

# Nested submessages merge recursively across occurrences.
{
    # pkg.Deep { int32 x = 1; int32 y = 2 }
    my $deep = Proto3::Schema::Message->new(
        name => 'Deep', full_name => 'pkg.Deep',
        fields => [
            Proto3::Schema::Field->new( name => 'x', number => 1, type => 'int32' ),
            Proto3::Schema::Field->new( name => 'y', number => 2, type => 'int32' ),
        ],
    );
    # pkg.Mid { Deep deep = 1 }
    my $mid = Proto3::Schema::Message->new(
        name => 'Mid', full_name => 'pkg.Mid',
        fields => [
            Proto3::Schema::Field->new(
                name => 'deep', number => 1, type => 'message', type_name => 'pkg.Deep',
            ),
        ],
    );
    # pkg.Top { Mid mid = 1 }
    my $top = Proto3::Schema::Message->new(
        name => 'Top', full_name => 'pkg.Top',
        fields => [
            Proto3::Schema::Field->new(
                name => 'mid', number => 1, type => 'message', type_name => 'pkg.Mid',
            ),
        ],
    );
    my $codec = codec_for( $top, $mid, $deep );

    # First: mid { deep { x = 1 } }   Second: mid { deep { y = 2 } }
    my $first  = $codec->encode( 'pkg.Top', { mid => { deep => { x => 1 } } } );
    my $second = $codec->encode( 'pkg.Top', { mid => { deep => { y => 2 } } } );
    my $decoded = $codec->decode( 'pkg.Top', $first . $second );

    is( $decoded->{mid}{deep}{x}, 1, 'recursive merge keeps inner x=1' );
    is( $decoded->{mid}{deep}{y}, 2, 'recursive merge adds inner y=2' );
}

# A oneof message member also merges across repeated occurrences (last member
# of the oneof still wins, but repeated occurrences of that member merge).
{
    my $inner = Proto3::Schema::Message->new(
        name      => 'Inner',
        full_name => 'pkg.Inner',
        fields    => [
            Proto3::Schema::Field->new( name => 'a', number => 1, type => 'int32' ),
            Proto3::Schema::Field->new( name => 'b', number => 2, type => 'int32' ),
        ],
    );
    my $msg_member = Proto3::Schema::Field->new(
        name => 'inner', number => 1, type => 'message',
        type_name => 'pkg.Inner', oneof_index => 0,
    );
    my $scalar_member = Proto3::Schema::Field->new(
        name => 'num', number => 2, type => 'int32', oneof_index => 0,
    );
    my $outer = Proto3::Schema::Message->new(
        name      => 'Outer',
        full_name => 'pkg.Outer',
        fields    => [ $msg_member, $scalar_member ],
        oneofs    => [
            Proto3::Schema::Oneof->new(
                name => 'choice', oneof_index => 0,
                fields => [ $msg_member, $scalar_member ],
            ),
        ],
    );
    my $codec = codec_for( $outer, $inner );

    my $first  = "\x0a\x02\x08\x01";    # inner { a = 1 }
    my $second = "\x0a\x02\x10\x02";    # inner { b = 2 }
    my $decoded = $codec->decode( 'pkg.Outer', $first . $second );

    is( $decoded->{inner}{a}, 1, 'oneof message member merges (keeps a=1)' );
    is( $decoded->{inner}{b}, 2, 'oneof message member merges (adds b=2)' );
    ok( !exists $decoded->{num}, 'oneof scalar sibling stays absent' );
}

done_testing;
