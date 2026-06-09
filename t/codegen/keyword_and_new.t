# ABOUTME: accessor keyword-mangle completeness (B-012) and strict generated
# new() argument handling (B-013).
use v5.38;
use warnings;
use Test::More;
use lib 'lib';

use Protobuf::Exception;
use Protobuf::Schema;
use Protobuf::Schema::File;
use Protobuf::Schema::Message;
use Protobuf::Schema::Field;
use Protobuf::Class::Generator;
use Protobuf::Class::Accessor;

# --- B-012: builtins and generated-method names are mangled ----------------
for my $kw (
    qw( length lc uc lcfirst ucfirst sprintf time int abs sqrt
    index rindex substr pack unpack vec ord hex oct
    encode decode to_hashref descriptor )
    )
{
    is( Protobuf::Class::Accessor::accessor_name($kw),
        "${kw}_", "field '$kw' mangles to '${kw}_'" );
}
is( Protobuf::Class::Accessor::accessor_name('encoding'),
    'encoding', 'non-keyword name is unchanged' );

# --- B-013: generated new() requires a single hashref ----------------------
my $msg = Protobuf::Schema::Message->new(
    name      => 'M',
    full_name => 'pkg.M',
    fields    => [
        Protobuf::Schema::Field->new( name => 'a', number => 1, type => 'int32' ),
        Protobuf::Schema::Field->new( name => 'b', number => 2, type => 'int32' ),
    ],
);
my $schema = Protobuf::Schema->new;
$schema->add_file(
    Protobuf::Schema::File->new(
        name => 'm.proto', package => 'pkg', messages => [$msg],
    )
);
my $target = 'T::Codegen::NewArgs';
Protobuf::Class::Generator->build(
    message => $msg, schema => $schema, target_package => $target,
);

# Hashref form works.
my $ok = $target->new( { a => 1, b => 2 } );
is( $ok->{a}, 1, 'hashref new() stores fields' );

# Empty / no-arg form works.
ok( $target->new,        'no-arg new() works' );
ok( $target->new(undef), 'new(undef) works' );

# Bare hash-list form is rejected (was silently dropping fields).
my $list_err = do { local $@; eval { $target->new( a => 1, b => 2 ); 1 }; $@ };
isa_ok( $list_err, 'Protobuf::Exception::Argument',
    'new(a => 1, b => 2) hash-list form is rejected' );

# A non-hashref single arg is rejected.
my $scalar_err = do { local $@; eval { $target->new('a'); 1 }; $@ };
isa_ok( $scalar_err, 'Protobuf::Exception::Argument',
    'new(scalar) is rejected' );

done_testing;
