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
use Proto3::Exception;

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
    while ( !$self->_at_end ) {
        if ( $self->_is_keyword('package') ) {
            $self->_parse_package;
        }
        elsif ( $self->_is_keyword('message') ) {
            push @messages, $self->_parse_message;
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

# message Name { <fields> }
sub _parse_message {
    my ( $self, $scope ) = @_;
    $self->_expect( 'keyword', 'message' );
    my $name = $self->_expect('ident')->{value};
    my $full_name = $self->_full_name( $scope, $name );

    $self->_expect( 'punct', '{' );
    my @fields;
    until ( $self->_is_punct('}') ) {
        $self->_error('unexpected end of input in message body')
            if $self->_at_end;
        push @fields, $self->_parse_field;
    }
    $self->_expect( 'punct', '}' );

    return Proto3::Schema::Message->new(
        name      => $name,
        full_name => $full_name,
        fields    => \@fields,
    );
}

# Compute a message's fully-qualified name from the enclosing scope (a dotted
# prefix) and its simple name. At top level the scope is the file package.
sub _full_name {
    my ( $self, $scope, $name ) = @_;
    my $prefix = defined $scope && length $scope ? $scope : $self->{package};
    return length $prefix ? "$prefix.$name" : $name;
}

# [label] type name = number;
sub _parse_field {
    my ($self) = @_;

    my $label = 'singular';
    my $token = $self->_peek;
    if ( $token && $token->{type} eq 'keyword' && $LABEL{ $token->{value} } ) {
        $label = $self->_next->{value};
    }

    my $type = $self->_parse_field_type;
    my $name = $self->_expect('ident')->{value};
    $self->_expect( 'punct', '=' );
    my $number = $self->_expect('int')->{value};
    $self->_expect( 'punct', ';' );

    return Proto3::Schema::Field->new(
        name      => $name,
        number    => $number,
        type      => $type,
        label     => $label,
        json_name => _camel_case($name),
    );
}

# Parse a field's type token, returning the proto3 type-name string. Only scalar
# types are handled at the core-grammar stage (Step 17).
sub _parse_field_type {
    my ($self) = @_;
    my $token = $self->_peek;
    if ( $token && $token->{type} eq 'keyword' && $SCALAR_TYPE{ $token->{value} } )
    {
        return $self->_next->{value};
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
by L<Proto3::Parser::Lexer> and builds a L<Proto3::Schema::File>. This core stage
(spec §4.4) handles the file C<syntax> declaration, the C<package> directive, and
messages whose fields use any of the proto3 scalar types. Later stages extend it
with nested messages, enums, oneofs, maps, reserved ranges, imports, options, and
services.

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
