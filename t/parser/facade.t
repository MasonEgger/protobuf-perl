# ABOUTME: Tests for Protobuf::Parser facade — include_paths search + abs-path
# cache, import kinds, file/message/field options, services, T-parse-1 round-trip.
use v5.38;
use strict;
use warnings;
use Test::More;
use File::Temp qw(tempdir);
use File::Path qw(make_path);
use File::Spec;

use Protobuf::Parser;
use Protobuf::Exception;

# Helper: run $code and return the exception it throws (or undef).
sub exception_from ($code) {
    my $err;
    {
        local $@;
        eval { $code->(); 1 } or $err = $@;
    }
    return $err;
}

# Helper: write $content to $dir/$rel (creating intermediate dirs) and return
# the full path.
sub write_proto ($dir, $rel, $content) {
    my $path = File::Spec->catfile( $dir, $rel );
    my ( $vol, $dirs, $file ) = File::Spec->splitpath($path);
    make_path( File::Spec->catpath( $vol, $dirs, '' ) );
    open my $fh, '>', $path or die "cannot write $path: $!";
    print {$fh} $content;
    close $fh;
    return $path;
}

# --- 19.1 include_paths multi-root, first match wins, abs-path cache --------

subtest 'parse_file: multi-root search, first match wins' => sub {
    my $root_a = tempdir( CLEANUP => 1 );
    my $root_b = tempdir( CLEANUP => 1 );

    # Same relative name in both roots; root_a should win.
    write_proto( $root_a, 'pkg/thing.proto', <<'PROTO' );
syntax = "proto3";
package pkg;
message FromA { int32 x = 1; }
PROTO
    write_proto( $root_b, 'pkg/thing.proto', <<'PROTO' );
syntax = "proto3";
package pkg;
message FromB { int32 x = 1; }
PROTO

    my $parser =
        Protobuf::Parser->new( include_paths => [ $root_a, $root_b ] );
    my $file = $parser->parse_file('pkg/thing.proto');

    is $file->messages->[0]->name, 'FromA',
        'first include_path root wins on duplicate relative name';
    is $file->name, 'pkg/thing.proto', 'file keeps its relative name';
};

subtest 'parse_file: caches by absolute path (same object on re-parse)' => sub {
    my $root = tempdir( CLEANUP => 1 );
    write_proto( $root, 'a.proto', <<'PROTO' );
syntax = "proto3";
message A { int32 x = 1; }
PROTO

    my $parser = Protobuf::Parser->new( include_paths => [$root] );
    my $first  = $parser->parse_file('a.proto');
    my $second = $parser->parse_file('a.proto');

    is $first, $second, 're-parsing the same file returns the cached object';
};

# --- 19.2 import / import public / import weak kinds (T-parse-8) ------------

subtest 'import kinds parse correctly (T-parse-8)' => sub {
    my $src = <<'PROTO';
syntax = "proto3";
import "plain.proto";
import public "foo.proto";
import weak "bar.proto";
message M { int32 x = 1; }
PROTO
    my $parser = Protobuf::Parser->new;
    my $file   = $parser->parse_string( 'imp.proto', $src );

    my $imports = $file->imports;
    is scalar(@$imports), 3, 'three imports recorded';

    is $imports->[0]{path}, 'plain.proto', 'plain import path';
    is $imports->[0]{kind}, 'normal',      'plain import kind is normal';

    is $imports->[1]{path}, 'foo.proto', 'public import path';
    is $imports->[1]{kind}, 'public',    'public import kind';

    is $imports->[2]{path}, 'bar.proto', 'weak import path';
    is $imports->[2]{kind}, 'weak',      'weak import kind';
};

# --- 19.3 file + message + field options into hashref ----------------------

subtest 'file, message, and field options parse into hashrefs' => sub {
    my $src = <<'PROTO';
syntax = "proto3";
option java_package = "com.example";
option optimize_for = SPEED;
message M {
  option deprecated = true;
  int32 x = 1 [deprecated = true];
  string y = 2 [json_name = "yField"];
}
PROTO
    my $parser = Protobuf::Parser->new;
    my $file   = $parser->parse_string( 'opt.proto', $src );

    is $file->options->{java_package}, 'com.example',
        'file-level string option';
    is $file->options->{optimize_for}, 'SPEED',
        'file-level identifier option';

    my $m = $file->messages->[0];
    ok $m->options->{deprecated}, 'message-level option captured';

    my %by_name = map { $_->name => $_ } @{ $m->fields };
    ok $by_name{x}->options->{deprecated}, 'field-level option captured';
    is $by_name{y}->options->{json_name}, 'yField',
        'field option value captured';
};

# --- 19.4 service + rpc (incl. stream) parse-only into Schema::Service ------

subtest 'service and rpc methods parse into Schema::Service' => sub {
    my $src = <<'PROTO';
syntax = "proto3";
package svc;
message Req { int32 x = 1; }
message Resp { int32 y = 1; }
service Greeter {
  rpc Unary (Req) returns (Resp);
  rpc ClientStream (stream Req) returns (Resp);
  rpc ServerStream (Req) returns (stream Resp);
  rpc BiDi (stream Req) returns (stream Resp);
}
PROTO
    my $parser = Protobuf::Parser->new;
    my $file   = $parser->parse_string( 'svc.proto', $src );

    is scalar( @{ $file->services } ), 1, 'one service parsed';
    my $service = $file->services->[0];
    is $service->name,      'Greeter',     'service name';
    is $service->full_name, 'svc.Greeter', 'service full_name with package';

    my $methods = $service->methods;
    is scalar(@$methods), 4, 'four rpc methods';

    my %by_name = map { $_->{name} => $_ } @$methods;

    is $by_name{Unary}{input_type},  'Req',  'unary input type';
    is $by_name{Unary}{output_type}, 'Resp', 'unary output type';
    ok !$by_name{Unary}{client_streaming}, 'unary not client streaming';
    ok !$by_name{Unary}{server_streaming}, 'unary not server streaming';

    ok $by_name{ClientStream}{client_streaming},
        'client-stream marks client_streaming';
    ok !$by_name{ClientStream}{server_streaming},
        'client-stream not server streaming';

    ok $by_name{ServerStream}{server_streaming},
        'server-stream marks server_streaming';

    ok $by_name{BiDi}{client_streaming}, 'bidi client_streaming';
    ok $by_name{BiDi}{server_streaming}, 'bidi server_streaming';
};

# --- 19.5 parse -> serialize -> parse equivalent (T-parse-1) ---------------

subtest 'round-trip via canonical serialize (T-parse-1)' => sub {
    my $src = <<'PROTO';
syntax = "proto3";
package round.trip;
message Trivial {
  int32 id = 1;
  string name = 2;
  repeated bytes blobs = 3;
}
PROTO
    my $parser = Protobuf::Parser->new;
    my $first  = $parser->parse_string( 'rt.proto', $src );

    my $text   = Protobuf::Parser->serialize($first);
    my $second = $parser->parse_string( 'rt.proto', $text );

    is $second->package, $first->package, 'package preserved through round-trip';
    is scalar( @{ $second->messages } ), scalar( @{ $first->messages } ),
        'message count preserved';

    my $m1 = $first->messages->[0];
    my $m2 = $second->messages->[0];
    is $m2->full_name, $m1->full_name, 'message full_name preserved';

    my @f1 = @{ $m1->fields };
    my @f2 = @{ $m2->fields };
    is scalar(@f2), scalar(@f1), 'field count preserved';
    for my $i ( 0 .. $#f1 ) {
        is $f2[$i]->name,   $f1[$i]->name,   "field $i name preserved";
        is $f2[$i]->number, $f1[$i]->number, "field $i number preserved";
        is $f2[$i]->type,   $f1[$i]->type,   "field $i type preserved";
        is $f2[$i]->label,  $f1[$i]->label,  "field $i label preserved";
    }
};

# --- 19.6 missing imported file -> ImportNotFound --------------------------

subtest 'parse_file: missing file raises ImportNotFound' => sub {
    my $root = tempdir( CLEANUP => 1 );
    my $parser = Protobuf::Parser->new( include_paths => [$root] );

    my $err = exception_from( sub { $parser->parse_file('nope.proto') } );
    ok $err, 'missing file raises';
    isa_ok $err, 'Protobuf::Exception::Parser::ImportNotFound',
        'raises ImportNotFound';
    like "$err", qr/nope\.proto/, 'error names the missing file';
};

# --- 20.1 parse_with_imports collects transitive files (T-parse-9) ----------

subtest 'parse_with_imports: follows a 3-deep import chain' => sub {
    my $root = tempdir( CLEANUP => 1 );

    # top.proto -> mid.proto -> leaf.proto
    write_proto( $root, 'top.proto', <<'PROTO' );
syntax = "proto3";
package chain;
import "mid.proto";
message Top { Mid m = 1; }
PROTO
    write_proto( $root, 'mid.proto', <<'PROTO' );
syntax = "proto3";
package chain;
import "leaf.proto";
message Mid { Leaf l = 1; }
PROTO
    write_proto( $root, 'leaf.proto', <<'PROTO' );
syntax = "proto3";
package chain;
message Leaf { int32 v = 1; }
PROTO

    my $parser = Protobuf::Parser->new( include_paths => [$root] );
    my $schema = $parser->parse_with_imports('top.proto');

    isa_ok $schema, 'Protobuf::Schema', 'returns a Protobuf::Schema';
    ok $schema->file('top.proto'),  'top file present';
    ok $schema->file('mid.proto'),  'transitively-imported mid present';
    ok $schema->file('leaf.proto'), 'transitively-imported leaf present';
    is scalar @{ $schema->files }, 3, 'exactly three files collected';
    ok $schema->message('chain.Top'),  'Top indexed';
    ok $schema->message('chain.Mid'),  'Mid indexed';
    ok $schema->message('chain.Leaf'), 'Leaf indexed';
};

# --- 20.2 diamond imports load each file exactly once -----------------------

subtest 'parse_with_imports: diamond loads each file once' => sub {
    my $root = tempdir( CLEANUP => 1 );

    #   top -> left -> base
    #   top -> right -> base
    write_proto( $root, 'top.proto', <<'PROTO' );
syntax = "proto3";
package dia;
import "left.proto";
import "right.proto";
message Top { Left a = 1; Right b = 2; }
PROTO
    write_proto( $root, 'left.proto', <<'PROTO' );
syntax = "proto3";
package dia;
import "base.proto";
message Left { Base x = 1; }
PROTO
    write_proto( $root, 'right.proto', <<'PROTO' );
syntax = "proto3";
package dia;
import "base.proto";
message Right { Base y = 1; }
PROTO
    write_proto( $root, 'base.proto', <<'PROTO' );
syntax = "proto3";
package dia;
message Base { int32 v = 1; }
PROTO

    my $parser = Protobuf::Parser->new( include_paths => [$root] );
    my $schema = $parser->parse_with_imports('top.proto');

    is scalar @{ $schema->files }, 4, 'four distinct files (base once)';
    my @base = grep { $_->name eq 'base.proto' } @{ $schema->files };
    is scalar @base, 1, 'base.proto added exactly once';
    # The cache guarantees identity: both importers see the same object.
    is $parser->parse_file('base.proto'), $base[0],
        'cached base is the same object that was collected';
};

# --- 20.3 import cycle -> ImportCycle (T-parse-9) ---------------------------

subtest 'parse_with_imports: import cycle raises ImportCycle' => sub {
    my $root = tempdir( CLEANUP => 1 );

    # a -> b -> a
    write_proto( $root, 'a.proto', <<'PROTO' );
syntax = "proto3";
package cyc;
import "b.proto";
message A { int32 v = 1; }
PROTO
    write_proto( $root, 'b.proto', <<'PROTO' );
syntax = "proto3";
package cyc;
import "a.proto";
message B { int32 v = 1; }
PROTO

    my $parser = Protobuf::Parser->new( include_paths => [$root] );
    my $err = exception_from( sub { $parser->parse_with_imports('a.proto') } );
    ok $err, 'cyclic import raises';
    isa_ok $err, 'Protobuf::Exception::Parser::ImportCycle',
        'raises ImportCycle';
};

# --- 20.4 resolved cross-file reference links (parser + resolver) -----------

subtest 'parse_with_imports: resolved schema links cross-file reference' => sub {
    my $root = tempdir( CLEANUP => 1 );

    write_proto( $root, 'top.proto', <<'PROTO' );
syntax = "proto3";
package x;
import "dep.proto";
message Holder { Payload p = 1; }
PROTO
    write_proto( $root, 'dep.proto', <<'PROTO' );
syntax = "proto3";
package x;
message Payload { string s = 1; }
PROTO

    my $parser = Protobuf::Parser->new( include_paths => [$root] );
    my $schema = $parser->parse_with_imports('top.proto');
    $schema->resolve;

    my $holder = $schema->message('x.Holder');
    ok $holder, 'Holder resolved';
    my ($field) = @{ $holder->fields };
    is $field->name, 'p', 'field is p';
    ok $field->is_message, 'p is a message-typed field';
    is $field->type_ref, $schema->message('x.Payload'),
        'cross-file reference links to the imported definition';
};

done_testing;
