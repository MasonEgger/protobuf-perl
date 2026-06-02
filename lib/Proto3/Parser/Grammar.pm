# ABOUTME: Proto3::Parser::Grammar — recursive-descent parser over Lexer tokens (§4.4).
# Core constructs: syntax + package + messages with all scalar field types,
# producing Proto3::Schema::File / Message / Field with computed json_name.
use v5.38;
use strict;
use warnings;

package Proto3::Parser::Grammar;

use Proto3::Parser::Lexer;
use Proto3::Schema::File;
use Proto3::Schema::Message;
use Proto3::Schema::Field;
use Proto3::Schema::Enum;
use Proto3::Schema::Oneof;
use Proto3::Exception;

# Highest valid proto field number (2^29 - 1); the upper bound `reserved N to max`
# expands to.
my $MAX_FIELD_NUMBER = 536_870_911;

# Scalar proto3 type names recognized as field types (each arrives as a 'keyword'
# token from the lexer). Held as a file lexical the methods can read directly.
my %SCALAR_TYPE = map { $_ => 1 } qw(
    double float int32 int64 uint32 uint64
    sint32 sint64 fixed32 fixed64 sfixed32 sfixed64
    bool string bytes
);

# Field-label keywords that may precede a field type.
my %LABEL = ( repeated => 1, optional => 1 );

sub new {
    my ( $class, %args ) = @_;
    my $tokens =
        Proto3::Parser::Lexer->new( source => $args{source} )->tokenize;
    my $self = {
        tokens    => $tokens,
        pos       => 0,
        file_name => $args{file_name} // 'unknown.proto',
        package   => '',
    };
    return bless $self, $class;
}

# --- token cursor ---------------------------------------------------------
# A single peek/next/expect abstraction reused throughout the grammar.

# Look at the current token (or one $offset ahead) without consuming it.
# Returns undef past the end of the stream.
sub _peek {
    my ( $self, $offset ) = @_;
    $offset //= 0;
    return $self->{tokens}[ $self->{pos} + $offset ];
}

# Consume and return the current token. Errors at end of input.
sub _next {
    my ($self) = @_;
    my $token = $self->{tokens}[ $self->{pos} ];
    $self->_error('unexpected end of input') unless $token;
    $self->{pos}++;
    return $token;
}

sub _at_end {
    my ($self) = @_;
    return $self->{pos} >= scalar @{ $self->{tokens} };
}

# Consume the current token, requiring it to match $type (and, if given,
# $value). Returns the consumed token; raises Parser otherwise.
sub _expect {
    my ( $self, $type, $value ) = @_;
    my $token = $self->_peek;
    if ( !$token ) {
        $self->_error("expected $type but reached end of input");
    }
    if ( $token->{type} ne $type
        || ( defined $value && $token->{value} ne $value ) )
    {
        my $want = defined $value ? "$type '$value'" : $type;
        $self->_error(
            "expected $want but found $token->{type} '$token->{value}'",
            $token,
        );
    }
    return $self->_next;
}

# True when the current token is punctuation equal to $char.
sub _is_punct {
    my ( $self, $char ) = @_;
    my $token = $self->_peek;
    return $token && $token->{type} eq 'punct' && $token->{value} eq $char;
}

# True when the current token is the keyword $word.
sub _is_keyword {
    my ( $self, $word ) = @_;
    my $token = $self->_peek;
    return $token && $token->{type} eq 'keyword' && $token->{value} eq $word;
}

sub _error {
    my ( $self, $message, $token ) = @_;
    Proto3::Exception::Parser->throw(
        message => "$message (in $self->{file_name})",
        line    => $token ? $token->{line} : undef,
        column  => $token ? $token->{col}  : undef,
    );
}

# --- grammar --------------------------------------------------------------

# Parse the whole file into a Proto3::Schema::File. The first non-comment
# statement MUST be `syntax = "proto3";`.
sub parse {
    my ($self) = @_;
    $self->_parse_syntax;

    my @messages;
    my @enums;
    while ( !$self->_at_end ) {
        if ( $self->_is_keyword('package') ) {
            $self->_parse_package;
        }
        elsif ( $self->_is_keyword('message') ) {
            push @messages, $self->_parse_message;
        }
        elsif ( $self->_is_keyword('enum') ) {
            push @enums, $self->_parse_enum;
        }
        else {
            my $token = $self->_peek;
            $self->_error(
                "unexpected token '$token->{value}' at file scope", $token );
        }
    }

    return Proto3::Schema::File->new(
        name     => $self->{file_name},
        package  => $self->{package},
        syntax   => 'proto3',
        messages => \@messages,
        enums    => \@enums,
    );
}

# syntax = "proto3"; — required as the first statement.
sub _parse_syntax {
    my ($self) = @_;
    my $first = $self->_peek;
    if ( !$first || !( $first->{type} eq 'keyword' && $first->{value} eq 'syntax' ) )
    {
        $self->_error(
            'expected `syntax = "proto3";` as the first statement', $first );
    }
    $self->_expect( 'keyword', 'syntax' );
    $self->_expect( 'punct',   '=' );
    my $value = $self->_expect('string');
    if ( $value->{value} ne 'proto3' ) {
        $self->_error( "unsupported syntax '$value->{value}'", $value );
    }
    $self->_expect( 'punct', ';' );
    return;
}

# package a.b.c;
sub _parse_package {
    my ($self) = @_;
    $self->_expect( 'keyword', 'package' );
    $self->{package} = $self->_parse_dotted_name;
    $self->_expect( 'punct', ';' );
    return;
}

# A dotted name token (fullident) or a single ident.
sub _parse_dotted_name {
    my ($self) = @_;
    my $token = $self->_peek;
    if ( $token && ( $token->{type} eq 'fullident' || $token->{type} eq 'ident' ) )
    {
        return $self->_next->{value};
    }
    $self->_error( 'expected a (dotted) name', $token );
}

# message Name { <body> } — body may contain fields, nested messages and
# enums, oneof groups, map fields (which synthesize a nested MapEntry message),
# and reserved declarations.
sub _parse_message {
    my ( $self, $scope ) = @_;
    $self->_expect( 'keyword', 'message' );
    my $name = $self->_expect('ident')->{value};
    my $full_name = $self->_full_name( $scope, $name );

    $self->_expect( 'punct', '{' );

    my @fields;
    my @oneofs;
    my @nested_messages;
    my @nested_enums;
    my @reserved_numbers;
    my @reserved_names;

    until ( $self->_is_punct('}') ) {
        $self->_error('unexpected end of input in message body')
            if $self->_at_end;

        if ( $self->_is_keyword('message') ) {
            push @nested_messages, $self->_parse_message($full_name);
        }
        elsif ( $self->_is_keyword('enum') ) {
            push @nested_enums, $self->_parse_enum($full_name);
        }
        elsif ( $self->_is_keyword('oneof') ) {
            push @oneofs,
                $self->_parse_oneof( $full_name, \@fields, scalar @oneofs );
        }
        elsif ( $self->_is_keyword('map') ) {
            my ( $field, $entry ) = $self->_parse_map_field($full_name);
            push @fields,          $field;
            push @nested_messages, $entry;
        }
        elsif ( $self->_is_keyword('reserved') ) {
            $self->_parse_reserved( \@reserved_numbers, \@reserved_names );
        }
        else {
            push @fields, $self->_parse_field;
        }
    }
    $self->_expect( 'punct', '}' );

    return Proto3::Schema::Message->new(
        name             => $name,
        full_name        => $full_name,
        fields           => \@fields,
        oneofs           => \@oneofs,
        nested_messages  => \@nested_messages,
        nested_enums     => \@nested_enums,
        reserved_numbers => \@reserved_numbers,
        reserved_names   => \@reserved_names,
    );
}

# enum Name { [option allow_alias = true;] VALUE = N; ... }
sub _parse_enum {
    my ( $self, $scope ) = @_;
    $self->_expect( 'keyword', 'enum' );
    my $name = $self->_expect('ident')->{value};
    my $full_name = $self->_full_name( $scope, $name );

    $self->_expect( 'punct', '{' );
    my @values;
    my $allow_alias = 0;
    until ( $self->_is_punct('}') ) {
        $self->_error('unexpected end of input in enum body')
            if $self->_at_end;

        if ( $self->_is_keyword('option') ) {
            my ( $opt_name, $opt_value ) = $self->_parse_option;
            $allow_alias = $opt_value ? 1 : 0 if $opt_name eq 'allow_alias';
            next;
        }

        my $value_name = $self->_expect('ident')->{value};
        $self->_expect( 'punct', '=' );
        my $number = $self->_expect('int')->{value};
        $self->_expect( 'punct', ';' );
        push @values, { name => $value_name, number => $number };
    }
    $self->_expect( 'punct', '}' );

    return Proto3::Schema::Enum->new(
        name        => $name,
        full_name   => $full_name,
        values      => \@values,
        allow_alias => $allow_alias,
    );
}

# option name = value; — returns ($name, $value). Used for enum allow_alias.
sub _parse_option {
    my ($self) = @_;
    $self->_expect( 'keyword', 'option' );
    my $name = $self->_parse_dotted_name;
    $self->_expect( 'punct', '=' );
    my $value = $self->_next->{value};
    $self->_expect( 'punct', ';' );
    return ( $name, $value );
}

# oneof Name { type field = N; ... } — members are appended to @$fields with the
# given $index set, and a Schema::Oneof recording the same members is returned.
sub _parse_oneof {
    my ( $self, $scope, $fields, $index ) = @_;
    $self->_expect( 'keyword', 'oneof' );
    my $name = $self->_expect('ident')->{value};

    $self->_expect( 'punct', '{' );
    my @members;
    until ( $self->_is_punct('}') ) {
        $self->_error('unexpected end of input in oneof body')
            if $self->_at_end;
        my $member = $self->_parse_field($index);
        push @members, $member;
        push @$fields, $member;
    }
    $self->_expect( 'punct', '}' );

    return Proto3::Schema::Oneof->new(
        name        => $name,
        fields      => \@members,
        oneof_index => $index,
    );
}

# map<key, value> name = N; — desugars to a repeated message field whose element
# is a synthetic MapEntry message (key=field 1, value=field 2), per proto3.
# Returns ($map_field, $entry_message); the caller nests the entry message.
sub _parse_map_field {
    my ( $self, $scope ) = @_;
    $self->_expect( 'keyword', 'map' );
    $self->_expect( 'punct',   '<' );
    my ($key_type) = $self->_parse_field_type;
    $self->_expect( 'punct', ',' );
    my ( $value_type, $value_type_name ) = $self->_parse_field_type;
    $self->_expect( 'punct', '>' );

    my $name = $self->_expect('ident')->{value};
    $self->_expect( 'punct', '=' );
    my $number = $self->_expect('int')->{value};
    $self->_expect( 'punct', ';' );

    # MapEntry name is the CamelCase field name + 'Entry' (protoc convention).
    my $entry_simple = _camel_case_upper($name) . 'Entry';
    my $entry_full   = "$scope.$entry_simple";

    my $entry = Proto3::Schema::Message->new(
        name         => $entry_simple,
        full_name    => $entry_full,
        is_map_entry => 1,
        fields       => [
            Proto3::Schema::Field->new(
                name      => 'key',
                number    => 1,
                type      => $key_type,
                json_name => 'key',
            ),
            Proto3::Schema::Field->new(
                name      => 'value',
                number    => 2,
                type      => $value_type,
                type_name => $value_type_name,
                json_name => 'value',
            ),
        ],
    );

    my $field = Proto3::Schema::Field->new(
        name      => $name,
        number    => $number,
        type      => 'message',
        type_name => $entry_full,
        label     => 'repeated',
        map_entry => $entry_full,
        json_name => _camel_case($name),
    );

    return ( $field, $entry );
}

# reserved 5, 10 to 15, 20 to max;  -> reserved_numbers ([lo,hi] pairs)
# reserved "foo", "bar";            -> reserved_names
# Appends into the two passed-in arrayrefs.
sub _parse_reserved {
    my ( $self, $numbers, $names ) = @_;
    $self->_expect( 'keyword', 'reserved' );

    my $first = $self->_peek;
    if ( $first && $first->{type} eq 'string' ) {
        do {
            push @$names, $self->_expect('string')->{value};
        } while ( $self->_consume_comma );
    }
    else {
        do {
            push @$numbers, $self->_parse_range;
        } while ( $self->_consume_comma );
    }

    $self->_expect( 'punct', ';' );
    return;
}

# Parse one reserved-range element: a single number N (-> [N,N]) or `N to M`
# (-> [N,M]), where M may be the keyword `max`.
sub _parse_range {
    my ($self) = @_;
    my $lo = $self->_expect('int')->{value};
    if ( $self->_is_keyword('to') ) {
        $self->_next;    # consume 'to'
        my $hi =
            $self->_is_keyword('max')
            ? do { $self->_next; $MAX_FIELD_NUMBER }
            : $self->_expect('int')->{value};
        return [ $lo, $hi ];
    }
    return [ $lo, $lo ];
}

# If the current token is a comma, consume it and return true; else false. Used
# to drive comma-separated list parsing.
sub _consume_comma {
    my ($self) = @_;
    return 0 unless $self->_is_punct(',');
    $self->_next;
    return 1;
}

# Compute a message's fully-qualified name from the enclosing scope (a dotted
# prefix) and its simple name. At top level the scope is the file package.
sub _full_name {
    my ( $self, $scope, $name ) = @_;
    my $prefix = defined $scope && length $scope ? $scope : $self->{package};
    return length $prefix ? "$prefix.$name" : $name;
}

# [label] type name = number;  — $oneof_index, when defined, marks the field as
# a member of the oneof at that index (oneof members carry no label).
sub _parse_field {
    my ( $self, $oneof_index ) = @_;

    my $label = 'singular';
    my $token = $self->_peek;
    if ( $token && $token->{type} eq 'keyword' && $LABEL{ $token->{value} } ) {
        $label = $self->_next->{value};
    }

    my ( $type, $type_name ) = $self->_parse_field_type;
    my $name = $self->_expect('ident')->{value};
    $self->_expect( 'punct', '=' );
    my $number = $self->_expect('int')->{value};
    $self->_expect( 'punct', ';' );

    return Proto3::Schema::Field->new(
        name        => $name,
        number      => $number,
        type        => $type,
        type_name   => $type_name,
        label       => $label,
        oneof_index => $oneof_index,
        json_name   => _camel_case($name),
    );
}

# Parse a field's type, returning ($type, $type_name). A scalar keyword returns
# its name with an undef type_name. A (dotted) identifier is a message-or-enum
# reference: it returns ('message', $reference) — message vs enum is settled
# later by the resolver, which models both as embedded messages on the wire.
sub _parse_field_type {
    my ($self) = @_;
    my $token = $self->_peek;
    if ( $token && $token->{type} eq 'keyword' && $SCALAR_TYPE{ $token->{value} } )
    {
        return ( $self->_next->{value}, undef );
    }
    if ( $token
        && ( $token->{type} eq 'ident' || $token->{type} eq 'fullident' ) )
    {
        return ( 'message', $self->_next->{value} );
    }
    $self->_error( 'expected a field type', $token );
}

# Compute the default json_name: camelCase of a snake_case field name. Each
# underscore is dropped and the following character upper-cased (data_blob ->
# dataBlob, a_b_c_d -> aBCD). A leading character is left as-is.
sub _camel_case {
    my ($name) = @_;
    $name =~ s/_(.)/\U$1/g;
    return $name;
}

# Compute the PascalCase MapEntry base name from a field name: camelCase with the
# leading character also upper-cased (attrs -> Attrs, user_id -> UserId), so the
# synthetic entry message is `<Field>Entry` per the protoc convention.
sub _camel_case_upper {
    my ($name) = @_;
    return ucfirst _camel_case($name);
}

1;

__END__

=head1 NAME

Proto3::Parser::Grammar - recursive-descent parser for .proto source

=head1 SYNOPSIS

    use Proto3::Parser::Grammar;

    my $file = Proto3::Parser::Grammar->new(
        source    => $proto_text,
        file_name => 'thing.proto',
    )->parse;
    # $file is a Proto3::Schema::File.

=head1 DESCRIPTION

A hand-written recursive-descent parser that consumes the token stream produced
by L<Proto3::Parser::Lexer> and builds a L<Proto3::Schema::File>. It handles the
file C<syntax> declaration, the C<package> directive, top-level and nested
messages and enums, and message bodies containing scalar/message/enum fields,
C<oneof> groups, C<map> fields, and C<reserved> declarations (spec §4.4). Later
stages extend it with imports, options, and services.

A single token-cursor abstraction (C<_peek> / C<_next> / C<_expect>) drives the
whole grammar.

=head1 BEHAVIOR

=over 4

=item *

C<syntax = "proto3";> is required as the first statement. A missing declaration,
a different first statement, or any non-C<proto3> syntax value raises
L<Proto3::Exception::Parser> carrying the offending source C<line>/C<column>.

=item *

Field labels: a bare field is C<singular>; a C<repeated> field is C<repeated>; an
C<optional> field is C<optional> (proto3 explicit presence, per spec §4.4).

=item *

Each field's default C<json_name> is the camelCase form of its name
(C<data_blob> becomes C<dataBlob>).

=item *

Duplicate field numbers (or names) within a message are detected by
L<Proto3::Schema::Message> at construction and surface as
C<Proto3::Exception::Schema::DuplicateField>.

=item *

Nested messages and enums recurse, each receiving a dotted C<full_name> built
from the enclosing message's full name (C<a.b.Outer.Inner>).

=item *

C<enum> declarations build L<Proto3::Schema::Enum>; C<option allow_alias = true;>
inside the body permits duplicate value numbers (otherwise duplicates raise
C<Proto3::Exception::Schema> at construction).

=item *

A C<oneof> group records a L<Proto3::Schema::Oneof> and appends its member fields
to the owning message, each carrying the matching C<oneof_index>.

=item *

A C<< map<K, V> >> field desugars (per proto3) into a C<repeated> message field
backed by a synthetic nested I<MapEntry> message (C<is_map_entry>) with C<key> at
field 1 and C<value> at field 2. The entry message is named C<< <Field>Entry >>.

=item *

C<reserved> declarations populate the message's C<reserved_numbers> (as
C<[lo, hi]> pairs, with C<N to max> expanding to the proto field-number maximum)
and C<reserved_names>.

=item *

Comments are discarded by the lexer, so they may appear freely between any
message- or field-body tokens without affecting parsing.

=back

=head1 METHODS

=over 4

=item new(source => $text, file_name => $name)

Tokenize C<$text> and construct a parser. C<file_name> is used for the resulting
C<Schema::File> name and in error messages.

=item parse

Parse the token stream and return a L<Proto3::Schema::File>.

=back

=head1 GRAMMAR REFERENCE

A copy of the proto3 formal grammar is kept alongside this module in
F<lib/Proto3/Parser/grammar.txt> (spec §4.4).

=head1 LICENSE

This software is licensed under the MIT license. See the C<LICENSE> file.

=cut
