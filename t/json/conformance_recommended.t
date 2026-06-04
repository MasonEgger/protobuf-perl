# ABOUTME: regression tests for the Recommended.Proto3 JSON conformance fixes:
# duplicate-field rejection, base64url bytes, null-in-repeated-message rejection,
# ignore-unknown enum strings, and NullValue JSON-null encoding.
use v5.38;
use warnings;
use Test::More;
use lib 'lib';

use Proto3::Exception;
use Proto3::Schema;
use Proto3::Schema::File;
use Proto3::Schema::Message;
use Proto3::Schema::Field;
use Proto3::Schema::Enum;
use Proto3::Schema::Oneof;
use Proto3::Codec;
use Proto3::WKT::Struct;

# Build a codec over the given messages/enums and resolve it.
my sub codec_for {
    my (%args) = @_;
    my $file = Proto3::Schema::File->new(
        name     => 'm.proto', package => 'pkg',
        messages => $args{messages} // [],
        enums    => $args{enums}    // [],
    );
    my $schema = Proto3::Schema->new;
    $schema->add_file($file);
    $schema->resolve;
    return Proto3::Codec->new( schema => $schema );
}

# A message with one bytes field, for base64url decode tests.
my sub bytes_codec {
    my $m = Proto3::Schema::Message->new(
        name => 'M', full_name => 'pkg.M',
        fields => [ Proto3::Schema::Field->new(
            name => 'data', json_name => 'data', number => 1, type => 'bytes',
        ) ],
    );
    return codec_for( messages => [$m] );
}

# --- Group 7: base64url bytes input ------------------------------------------
{
    my $codec = bytes_codec();

    # "\xfb" standard base64 is "+w==" ; URL-safe is "-w" (no padding).
    my $standard = $codec->decode_json( 'pkg.M', '{"data":"+w=="}' );
    is( $standard->{data}, "\xfb", 'standard base64 with padding decodes' );

    my $urlsafe = $codec->decode_json( 'pkg.M', '{"data":"-w"}' );
    is( $urlsafe->{data}, "\xfb",
        'URL-safe base64 without padding decodes (BytesFieldBase64Url)' );

    my $urlsafe_underscore =
        $codec->decode_json( 'pkg.M', '{"data":"a_-b"}' );
    my $std = $codec->decode_json( 'pkg.M', '{"data":"a/+b"}' );
    is( $urlsafe_underscore->{data}, $std->{data},
        'URL-safe -_ alphabet maps to the standard +/ bytes' );
}

# --- Group 4: duplicate field rejection --------------------------------------
{
    my $inner = Proto3::Schema::Message->new(
        name => 'Inner', full_name => 'pkg.Inner',
        fields => [ Proto3::Schema::Field->new(
            name => 'a', json_name => 'a', number => 1, type => 'int32',
        ) ],
    );
    my $m = Proto3::Schema::Message->new(
        name => 'M', full_name => 'pkg.M',
        fields => [ Proto3::Schema::Field->new(
            name => 'nested_msg', json_name => 'nestedMsg', number => 1,
            type => 'message', type_name => '.pkg.Inner',
        ) ],
    );
    my $codec = codec_for( messages => [ $m, $inner ] );

    # Literal duplicate key (FieldNameDuplicate).
    my $ok1 = eval {
        $codec->decode_json( 'pkg.M',
            '{"nestedMsg":{"a":1},"nestedMsg":{}}' );
        1;
    };
    ok( !$ok1, 'literal duplicate JSON key is rejected (FieldNameDuplicate)' );

    # camelCase + snake_case of the same field (FieldNameDuplicateDifferentCasing).
    my $ok2 = eval {
        $codec->decode_json( 'pkg.M',
            '{"nested_msg":{"a":1},"nestedMsg":{}}' );
        1;
    };
    ok( !$ok2,
        'snake_case + camelCase of one field is rejected (DifferentCasing)' );

    # A single key still decodes fine.
    my $ok3 = $codec->decode_json( 'pkg.M', '{"nestedMsg":{"a":1}}' );
    is( $ok3->{nested_msg}{a}, 1, 'a single field decodes normally' );
}

# --- Group 5: null element in a repeated message field is rejected -----------
{
    my $inner = Proto3::Schema::Message->new(
        name => 'Inner', full_name => 'pkg.Inner',
        fields => [ Proto3::Schema::Field->new(
            name => 'a', json_name => 'a', number => 1, type => 'int32',
        ) ],
    );
    my $m = Proto3::Schema::Message->new(
        name => 'M', full_name => 'pkg.M',
        fields => [ Proto3::Schema::Field->new(
            name => 'rep', json_name => 'rep', number => 1,
            label => 'repeated', type => 'message', type_name => '.pkg.Inner',
        ) ],
    );
    my $codec = codec_for( messages => [ $m, $inner ] );

    my $ok = eval {
        $codec->decode_json( 'pkg.M', '{"rep":[{"a":1},null,{"a":2}]}' );
        1;
    };
    ok( !$ok,
        'a null element in a repeated message field is rejected' );

    my $good = $codec->decode_json( 'pkg.M', '{"rep":[{"a":1},{"a":2}]}' );
    is( scalar @{ $good->{rep} }, 2, 'a null-free repeated field decodes' );
}

# --- Group 2: ignore unknown enum string values ------------------------------
{
    my $enum = Proto3::Schema::Enum->new(
        name => 'E', full_name => 'pkg.E',
        values => [ { name => 'FOO', number => 0 }, { name => 'BAR', number => 1 } ],
    );
    my $optional = Proto3::Schema::Field->new(
        name => 'e', json_name => 'e', number => 1,
        type => 'enum', type_name => '.pkg.E',
    );
    my $repeated = Proto3::Schema::Field->new(
        name => 'es', json_name => 'es', number => 2, label => 'repeated',
        type => 'enum', type_name => '.pkg.E',
    );
    my $m = Proto3::Schema::Message->new(
        name => 'M', full_name => 'pkg.M', fields => [ $optional, $repeated ],
    );
    my $codec = codec_for( messages => [$m], enums => [$enum] );

    # Without ignore: an unknown enum string is an error.
    my $strict = eval {
        $codec->decode_json( 'pkg.M', '{"e":"NOPE"}' );
        1;
    };
    ok( !$strict, 'unknown enum string errors by default' );

    # With ignore_unknown_fields: the field is left UNSET.
    my $opt = $codec->decode_json( 'pkg.M', '{"e":"NOPE"}',
        ignore_unknown_fields => 1 );
    ok( !exists $opt->{e},
        'ignored unknown singular enum string leaves the field unset' );

    # Repeated: the unknown element is dropped, known ones kept in order.
    my $rep = $codec->decode_json( 'pkg.M', '{"es":["FOO","NOPE","BAR"]}',
        ignore_unknown_fields => 1 );
    is_deeply( $rep->{es}, [ 0, 1 ],
        'ignored unknown enum string is dropped from a repeated field' );
}

# --- Group 5: google.protobuf.NullValue encodes as JSON null -----------------
{
    # Build a NullValue enum field; encode value 0 (NULL_VALUE) in a oneof
    # (explicit presence) must emit JSON null, not "NULL_VALUE".
    my $null_enum = Proto3::WKT::NullValue->schema_enum;
    my $field = Proto3::Schema::Field->new(
        name => 'oneof_null', json_name => 'oneofNull', number => 1,
        type => 'enum', type_name => '.google.protobuf.NullValue',
        oneof_index => 0,
    );
    my $m = Proto3::Schema::Message->new(
        name => 'M', full_name => 'pkg.M', fields => [$field],
        oneofs => [ Proto3::Schema::Oneof->new(
            name => 'kind', oneof_index => 0, fields => [$field] ) ],
    );
    my $file = Proto3::Schema::File->new(
        name => 'm.proto', package => 'pkg',
        messages => [$m], enums => [$null_enum],
    );
    my $schema = Proto3::Schema->new;
    $schema->add_file($file);
    $schema->resolve;
    my $codec = Proto3::Codec->new( schema => $schema );

    my $json = $codec->encode_json( 'pkg.M', { oneof_null => 0 } );
    like( $json, qr/"oneofNull":null/,
        'a oneof NullValue field at 0 encodes as JSON null' );
}

done_testing;
