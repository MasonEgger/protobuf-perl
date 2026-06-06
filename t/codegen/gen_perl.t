# ABOUTME: Tests for the AOT code generator (bin/protobuf-gen-perl + Codegen):
# package mapping, deterministic byte-identical output, generated-class round-trip (§4.12).
use v5.38;
use warnings;
use Test::More;
use lib 'lib';

use File::Temp ();
use File::Spec ();
use File::Path ();

use Protobuf::Class::Codegen;

# --- helpers ------------------------------------------------------------

# Write $content into $dir/$rel, creating intermediate directories. Returns
# the absolute path written.
my sub write_proto ( $dir, $rel, $content ) {
    my $abs = File::Spec->catfile( $dir, $rel );
    my ( undef, $parent ) = ( $abs, ( File::Spec->splitpath($abs) )[1] );
    File::Path::make_path($parent);
    open my $fh, '>', $abs or die "cannot write $abs: $!";
    print {$fh} $content;
    close $fh;
    return $abs;
}

# Run bin/protobuf-gen-perl with the given args; returns ($stdout, $exit).
my sub run_gen (@args) {
    my @cmd = ( $^X, '-Ilib', 'bin/protobuf-gen-perl', @args );
    my $out = qx{@{[ join ' ', map { quotemeta } @cmd ]} 2>&1};
    return ( $out, $? >> 8 );
}

# --- package mapping (32.2) ---------------------------------------------

is(
    Protobuf::Class::Codegen::package_for( 'temporal.api.common.v1', 'T::Api' ),
    'T::Api::Common::V1',
    '32.2: temporal.api.common.v1 under prefix T::Api -> T::Api::Common::V1',
);

is(
    Protobuf::Class::Codegen::package_for( 'temporal.api.common.v1', undef ),
    'Temporal::Api::Common::V1',
    '32.2: no prefix PascalCases every component',
);

is(
    Protobuf::Class::Codegen::package_for( '', 'T::Api' ),
    'T::Api',
    '32.2: empty proto package maps to the bare prefix',
);

# A nested message full_name (pkg + dotted message path) maps to a Perl class.
is(
    Protobuf::Class::Codegen::perl_class_for(
        'temporal.api.common.v1.Payload', 'temporal.api.common.v1', 'T::Api',
    ),
    'T::Api::Common::V1::Payload',
    '32.2: message full_name maps to its Perl class name',
);

# --- T-gen-1: generate a trivial .proto, it loads + round-trips ---------

{
    my $src = File::Temp->newdir;
    write_proto(
        "$src", 'demo/thing.proto', <<'PROTO' );
syntax = "proto3";
package demo;

message Thing {
  string name = 1;
  int32  count = 2;
  repeated string tags = 3;
}
PROTO

    my $out = File::Temp->newdir;
    my ( $log, $exit ) = run_gen(
        '--include', "$src",
        '--output',  "$out",
        '--package-prefix', 'Demo',
        'demo/thing.proto',
    );
    is( $exit, 0, "T-gen-1: generator exits 0 ($log)" );

    my $pm = File::Spec->catfile( "$out", 'Demo', 'Thing.pm' );
    ok( -f $pm, 'T-gen-1: emitted Demo/Thing.pm' );

    # 32.5: generated module must NOT pull in the parser.
    my $generated = do { open my $fh, '<', $pm or die $!; local $/; <$fh> };
    unlike( $generated, qr/Protobuf::Parser/,
        '32.5: generated module does not reference Protobuf::Parser' );
    unlike( $generated, qr/Protobuf::DescriptorSet/,
        '32.5: generated module does not reference DescriptorSet code' );

    # Load it and round-trip a message at RUNTIME (perl -c won't catch this).
    local @INC = ( "$out", @INC );
    require Demo::Thing;
    my $obj = Demo::Thing->new( { name => 'widget', count => 5 } );
    $obj->add_tags('a')->add_tags('b');
    is( $obj->name,  'widget', 'T-gen-1: reader returns constructed value' );
    is( $obj->count, 5,        'T-gen-1: int reader' );

    my $bytes   = $obj->encode;
    my $decoded = Demo::Thing->decode($bytes);
    is_deeply(
        $decoded->to_hashref,
        { name => 'widget', count => 5, tags => [ 'a', 'b' ] },
        'T-gen-1: encode -> decode round-trips the message',
    );
}

# --- T-gen-3: regeneration is byte-identical ----------------------------

{
    my $src = File::Temp->newdir;
    write_proto(
        "$src", 'demo/thing.proto', <<'PROTO' );
syntax = "proto3";
package demo;

message Thing {
  string name = 1;
  int32  count = 2;
  repeated string tags = 3;
}
PROTO

    my $read_pm = sub {
        my $out = File::Temp->newdir;
        my ( $log, $exit ) = run_gen(
            '--include', "$src",
            '--output',  "$out",
            '--package-prefix', 'Demo',
            'demo/thing.proto',
        );
        is( $exit, 0, "T-gen-3: generator exits 0 ($log)" );
        my $pm = File::Spec->catfile( "$out", 'Demo', 'Thing.pm' );
        open my $fh, '<', $pm or die "cannot read $pm: $!";
        local $/;
        return scalar <$fh>;
    };

    is( $read_pm->(), $read_pm->(),
        'T-gen-3: regenerating produces byte-identical output' );
}

# --- T-gen-2 shape: generated classes match runtime round-trip ----------

{
    # A message with a nested message field + a map, exercising the shared
    # accessor/codec spec. The generated classes must round-trip the same way
    # the runtime-generated classes do.
    my $src = File::Temp->newdir;
    write_proto(
        "$src", 'demo/graph.proto', <<'PROTO' );
syntax = "proto3";
package demo;

message Inner {
  int32 a = 1;
  string b = 2;
}

message Outer {
  Inner inner = 1;
  repeated Inner items = 2;
  map<string, int32> counts = 3;
  int32 tail = 4;
}
PROTO

    my $out = File::Temp->newdir;
    my ( $log, $exit ) = run_gen(
        '--include', "$src",
        '--output',  "$out",
        '--package-prefix', 'Demo',
        'demo/graph.proto',
    );
    is( $exit, 0, "T-gen-2: generator exits 0 ($log)" );

    local @INC = ( "$out", @INC );
    require Demo::Graph;    # one .pm per .proto file (named after the file)

    my $outer = Demo::Outer->new( { tail => 9 } );
    $outer->set_inner( Demo::Inner->new( { a => 7, b => 'hi' } ) );
    $outer->add_items( Demo::Inner->new( { a => 1, b => 'x' } ) );
    $outer->add_items( Demo::Inner->new( { a => 2, b => 'y' } ) );
    $outer->set_counts_entry( 'k', 3 );

    my $back = Demo::Outer->decode( $outer->encode );
    isa_ok( $back->inner, 'Demo::Inner',
        'T-gen-2: nested message decodes into the generated nested class' );
    is( $back->inner->a, 7, 'T-gen-2: nested scalar reads back' );
    is( scalar @{ $back->items }, 2, 'T-gen-2: repeated nested count' );
    isa_ok( $back->items->[0], 'Demo::Inner',
        'T-gen-2: repeated nested element is the generated class' );
    is( $back->counts->{k}, 3, 'T-gen-2: map entry round-trips' );
    is( $back->tail, 9, 'T-gen-2: trailing scalar round-trips' );
}

done_testing;
