# ABOUTME: Protobuf::Parser::Grammar — recursive-descent parser over Lexer tokens (§4.4).
# Core constructs: syntax + package + messages with all scalar field types,
# producing Protobuf::Schema::File / Message / Field with computed json_name.
use v5.38;
use strict;
use warnings;

package Protobuf::Parser::Grammar;

use Protobuf::Parser::Lexer;
use Protobuf::Schema::File;
use Protobuf::Schema::Message;
use Protobuf::Schema::Field;
use Protobuf::Schema::Enum;
use Protobuf::Schema::Oneof;
use Protobuf::Schema::Service;
use Protobuf::Exception;

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

# proto2-only constructs proto3 forbids (spec §4.4). These tokenize as plain
# identifiers (they are not proto3 keywords), so the grammar checks for them
# explicitly and reports which one was used. `optional` is intentionally absent:
# proto3 3.15+ accepts it for explicit presence. `extend` is intentionally
# absent too: proto3 allows it for declaring custom options (extending the
# google.protobuf.*Options messages), so the grammar parses extend blocks.
my %PROTO2_FORBIDDEN = map { $_ => 1 } qw( required group extensions );

# Bracketed field options proto3 forbids. A scalar default value is a proto2-only
# construct; proto3 fixes scalar defaults to the zero value.
my %FORBIDDEN_FIELD_OPTION = ( default => 1 );

sub new {
    my ( $class, %args ) = @_;
    my $tokens =
        Protobuf::Parser::Lexer->new( source => $args{source} )->tokenize;
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

# True when the NEXT token (one past current) is punctuation equal to $char.
# Used for one-token lookahead disambiguation (e.g. an enum value named
# `option` — `option = 0;` — vs an `option ... = ...;` statement).
sub _next_is_punct {
    my ( $self, $char ) = @_;
    my $token = $self->_peek(1);
    return $token && $token->{type} eq 'punct' && $token->{value} eq $char;
}

# True when the current token is the keyword $word.
sub _is_keyword {
    my ( $self, $word ) = @_;
    my $token = $self->_peek;
    return $token && $token->{type} eq 'keyword' && $token->{value} eq $word;
}

# Consume and return a NAME token: an identifier or any keyword. proto3 keywords
# are contextual (spec §4.4) — `message`, `service`, `map`, etc. are reserved
# only in their structural position and are valid field/message/enum-value/rpc/
# oneof names everywhere else. The grammar still recognizes keywords positionally
# (a leading `message`/`enum`/`oneof`/... at statement start dispatches), so a
# keyword only reaches here when a plain name is expected.
sub _expect_name {
    my ($self) = @_;
    my $token = $self->_peek;
    if ( $token
        && ( $token->{type} eq 'ident' || $token->{type} eq 'keyword' ) )
    {
        return $self->_next;
    }
    my $found = $token ? "$token->{type} '$token->{value}'" : 'end of input';
    $self->_error( "expected a name but found $found", $token );
}

sub _error {
    my ( $self, $message, $token ) = @_;
    Protobuf::Exception::Parser->throw(
        message => "$message (in $self->{file_name})",
        line    => $token ? $token->{line} : undef,
        column  => $token ? $token->{col}  : undef,
    );
}

# Like _error but raises the UnsupportedSyntax subclass, used for a wholesale
# wrong/absent file syntax declaration (proto2 or none).
sub _error_unsupported {
    my ( $self, $message, $token ) = @_;
    Protobuf::Exception::Parser::UnsupportedSyntax->throw(
        message => "$message (in $self->{file_name})",
        line    => $token ? $token->{line} : undef,
        column  => $token ? $token->{col}  : undef,
    );
}

# --- grammar --------------------------------------------------------------

# Parse the whole file into a Protobuf::Schema::File. The first non-comment
# statement MUST be `syntax = "proto3";`.
sub parse {
    my ($self) = @_;
    $self->_parse_syntax;

    my @messages;
    my @enums;
    my @services;
    my @imports;
    my @extensions;
    my %options;
    while ( !$self->_at_end ) {
        if ( $self->_is_punct(';') ) {    # empty statement at file scope
            $self->_next;
        }
        elsif ( $self->_is_keyword('package') ) {
            $self->_parse_package;
        }
        elsif ( $self->_is_keyword('import') ) {
            push @imports, $self->_parse_import;
        }
        elsif ( $self->_is_keyword('option') ) {
            my ( $name, $value ) = $self->_parse_option;
            $options{$name} = $value;
        }
        elsif ( $self->_is_keyword('message') ) {
            push @messages, $self->_parse_message;
        }
        elsif ( $self->_is_keyword('enum') ) {
            push @enums, $self->_parse_enum;
        }
        elsif ( $self->_is_keyword('service') ) {
            push @services, $self->_parse_service;
        }
        elsif ( $self->_is_keyword('extend') ) {
            push @extensions, $self->_parse_extend( $self->{package} );
        }
        else {
            my $token = $self->_peek;
            $self->_error(
                "unexpected token '$token->{value}' at file scope", $token );
        }
    }

    return Protobuf::Schema::File->new(
        name       => $self->{file_name},
        package    => $self->{package},
        syntax     => 'proto3',
        messages   => \@messages,
        enums      => \@enums,
        services   => \@services,
        imports    => \@imports,
        extensions => \@extensions,
        options    => \%options,
    );
}

# import [public|weak] "path"; — returns { path => $rel, kind => $kind } where
# $kind is 'normal', 'public', or 'weak'.
sub _parse_import {
    my ($self) = @_;
    $self->_expect( 'keyword', 'import' );

    my $kind = 'normal';
    if ( $self->_is_keyword('public') ) {
        $self->_next;
        $kind = 'public';
    }
    elsif ( $self->_is_keyword('weak') ) {
        $self->_next;
        $kind = 'weak';
    }

    my $path = $self->_expect('string')->{value};
    $self->_expect( 'punct', ';' );
    return { path => $path, kind => $kind };
}

# syntax = "proto3"; — required as the first statement. A missing declaration or
# a non-proto3 value (e.g. proto2) is an unsupported-syntax error, not a generic
# parse error: proto3 is the only dialect this library accepts (spec §4.4).
sub _parse_syntax {
    my ($self) = @_;
    my $first = $self->_peek;
    if ( !$first || !( $first->{type} eq 'keyword' && $first->{value} eq 'syntax' ) )
    {
        $self->_error_unsupported(
            'missing `syntax = "proto3";` declaration (proto3 is required)',
            $first );
    }
    $self->_expect( 'keyword', 'syntax' );
    $self->_expect( 'punct',   '=' );
    my $value = $self->_expect('string');
    if ( $value->{value} ne 'proto3' ) {
        $self->_error_unsupported(
            "unsupported syntax '$value->{value}' (only proto3 is supported)",
            $value );
    }
    $self->_expect( 'punct', ';' );
    return;
}

# package a.b.c; — at most one per file (spec §4.4). A second declaration is a
# user error protoc rejects ("Package already set").
sub _parse_package {
    my ($self) = @_;
    my $token = $self->_peek;
    $self->_expect( 'keyword', 'package' );
    $self->_error( 'package already set; only one package declaration is allowed',
        $token )
        if length $self->{package};
    $self->{package} = $self->_parse_dotted_name;
    $self->_expect( 'punct', ';' );
    return;
}

# A dotted name token (fullident), a single ident, or a contextual keyword used
# as a name (e.g. a type reference or package component named like a keyword).
sub _parse_dotted_name {
    my ($self) = @_;
    my $token = $self->_peek;
    if ( $token
        && (   $token->{type} eq 'fullident'
            || $token->{type} eq 'ident'
            || $token->{type} eq 'keyword' ) )
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
    my $name = $self->_expect_name->{value};
    my $full_name = $self->_full_name( $scope, $name );

    $self->_expect( 'punct', '{' );

    my @fields;
    my @oneofs;
    my @nested_messages;
    my @nested_enums;
    my @reserved_numbers;
    my @reserved_names;
    my @extensions;
    my %options;

    until ( $self->_is_punct('}') ) {
        $self->_error('unexpected end of input in message body')
            if $self->_at_end;

        if ( $self->_is_punct(';') ) {    # empty statement (e.g. after a oneof)
            $self->_next;
        }
        elsif ( $self->_is_keyword('option') ) {
            my ( $opt_name, $opt_value ) = $self->_parse_option;
            $options{$opt_name} = $opt_value;
        }
        elsif ( $self->_is_keyword('message') ) {
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
        elsif ( $self->_is_keyword('extend') ) {
            push @extensions, $self->_parse_extend($full_name);
        }
        else {
            push @fields, $self->_parse_field;
        }
    }
    $self->_expect( 'punct', '}' );

    return Protobuf::Schema::Message->new(
        name             => $name,
        full_name        => $full_name,
        fields           => \@fields,
        oneofs           => \@oneofs,
        nested_messages  => \@nested_messages,
        nested_enums     => \@nested_enums,
        reserved_numbers => \@reserved_numbers,
        reserved_names   => \@reserved_names,
        extensions       => \@extensions,
        options          => \%options,
    );
}

# enum Name { [option allow_alias = true;] VALUE = N; ... }
sub _parse_enum {
    my ( $self, $scope ) = @_;
    $self->_expect( 'keyword', 'enum' );
    my $name = $self->_expect_name->{value};
    my $full_name = $self->_full_name( $scope, $name );

    $self->_expect( 'punct', '{' );
    my @values;
    my @reserved_numbers;
    my @reserved_names;
    my $allow_alias = 0;
    until ( $self->_is_punct('}') ) {
        $self->_error('unexpected end of input in enum body')
            if $self->_at_end;

        # A bare `;` is a legal empty statement (spec emptyStatement).
        if ( $self->_is_punct(';') ) { $self->_next; next; }

        # `reserved` ranges/names, like a message's (spec §4.4).
        if ( $self->_is_keyword('reserved') ) {
            $self->_parse_reserved( \@reserved_numbers, \@reserved_names );
            next;
        }

        # `option` introduces an option statement only when it is NOT immediately
        # an enum value: `option allow_alias = true;` vs a value literally named
        # `option` (`option = 0;`). The lookahead at the `=` disambiguates.
        if ( $self->_is_keyword('option') && !$self->_next_is_punct('=') ) {
            my ( $opt_name, $opt_value ) = $self->_parse_option;
            $allow_alias = $opt_value ? 1 : 0 if $opt_name eq 'allow_alias';
            next;
        }

        my $value_name = $self->_expect_name->{value};
        $self->_expect( 'punct', '=' );
        my $number  = $self->_expect('int')->{value};
        my $options = $self->_parse_field_options;    # optional [opt = ...]
        $self->_expect( 'punct', ';' );
        push @values,
            { name => $value_name, number => $number, options => $options };
    }
    $self->_expect( 'punct', '}' );

    return Protobuf::Schema::Enum->new(
        name             => $name,
        full_name        => $full_name,
        values           => \@values,
        allow_alias      => $allow_alias,
        reserved_numbers => \@reserved_numbers,
        reserved_names   => \@reserved_names,
    );
}

# service Name { rpc ...; [option ...;] } — parse-only into a Schema::Service
# (this library does not dispatch RPCs).
sub _parse_service {
    my ($self) = @_;
    $self->_expect( 'keyword', 'service' );
    my $name = $self->_expect_name->{value};
    my $full_name = $self->_full_name( undef, $name );

    $self->_expect( 'punct', '{' );
    my @methods;
    my %options;
    until ( $self->_is_punct('}') ) {
        $self->_error('unexpected end of input in service body')
            if $self->_at_end;

        if ( $self->_is_punct(';') ) {    # empty statement between rpcs
            $self->_next;
        }
        elsif ( $self->_is_keyword('rpc') ) {
            push @methods, $self->_parse_rpc;
        }
        elsif ( $self->_is_keyword('option') ) {
            my ( $opt_name, $opt_value ) = $self->_parse_option;
            $options{$opt_name} = $opt_value;
        }
        else {
            my $token = $self->_peek;
            $self->_error(
                "unexpected token '$token->{value}' in service body", $token );
        }
    }
    $self->_expect( 'punct', '}' );

    return Protobuf::Schema::Service->new(
        name      => $name,
        full_name => $full_name,
        methods   => \@methods,
        options   => \%options,
    );
}

# rpc Name (stream? InType) returns (stream? OutType) ( ; | { [option ...;] } )
# — returns a method hashref with streaming flags. The (un)qualified type names
# are recorded verbatim; resolution happens later.
sub _parse_rpc {
    my ($self) = @_;
    $self->_expect( 'keyword', 'rpc' );
    my $name = $self->_expect_name->{value};

    my ( $client_streaming, $input_type )  = $self->_parse_rpc_type;
    $self->_expect( 'keyword', 'returns' );
    my ( $server_streaming, $output_type ) = $self->_parse_rpc_type;

    # Body may be an empty `;` or a `{ ... }` block carrying options.
    if ( $self->_is_punct('{') ) {
        $self->_next;
        until ( $self->_is_punct('}') ) {
            $self->_error('unexpected end of input in rpc body')
                if $self->_at_end;
            $self->_parse_option if $self->_is_keyword('option');
        }
        $self->_expect( 'punct', '}' );
    }
    else {
        $self->_expect( 'punct', ';' );
    }

    return {
        name             => $name,
        input_type       => $input_type,
        output_type      => $output_type,
        client_streaming => $client_streaming,
        server_streaming => $server_streaming,
    };
}

# ( [stream] TypeName ) — returns ($is_streaming, $type_name).
sub _parse_rpc_type {
    my ($self) = @_;
    $self->_expect( 'punct', '(' );
    my $streaming = 0;
    if ( $self->_is_keyword('stream') ) {
        $self->_next;
        $streaming = 1;
    }
    my $type = $self->_parse_dotted_name;
    $self->_expect( 'punct', ')' );
    return ( $streaming, $type );
}

# option name = value; — returns ($name, $value). The name may be a plain
# (dotted) identifier or a custom-option name in parentheses, optionally with a
# trailing field path: option (foo.bar).baz = ...;. The value may be a scalar,
# adjacent-concatenated strings, or an aggregate { ... } (returned as a hashref).
sub _parse_option {
    my ($self) = @_;
    $self->_expect( 'keyword', 'option' );
    my $name = $self->_parse_option_name;
    $self->_expect( 'punct', '=' );
    my $value = $self->_parse_option_value;
    $self->_expect( 'punct', ';' );
    return ( $name, $value );
}

# An option name: a plain (dotted) identifier, or a parenthesized custom-option
# name — (foo.bar) — optionally followed by a .field.path. The parentheses are
# preserved in the returned string so the option round-trips through serialize.
sub _parse_option_name {
    my ($self) = @_;
    my $name;
    if ( $self->_is_punct('(') ) {
        $self->_next;
        $name = '(' . $self->_parse_dotted_name . ')';
        $self->_expect( 'punct', ')' );
    }
    else {
        $name = $self->_parse_dotted_name;
    }
    while ( $self->_is_punct('.') ) {
        $self->_next;
        $name .= '.' . $self->_parse_dotted_name;
    }
    return $name;
}

# An option value: an aggregate { ... } (hashref), a list [ ... ] (arrayref), or
# a single scalar token with adjacent string-literal concatenation ("a" "b" ->
# "ab", spec §4.4 / B-009). Lists hold repeated-field option values and may
# contain aggregates (e.g. swagger `tags: [ {name: ...}, {name: ...} ]`).
sub _parse_option_value {
    my ($self) = @_;
    return $self->_parse_aggregate_value if $self->_is_punct('{');
    return $self->_parse_list_value      if $self->_is_punct('[');

    my $token = $self->_next;
    my $value = $token->{value};
    if ( $token->{type} eq 'string' ) {
        while ( my $next = $self->_peek ) {
            last unless $next->{type} eq 'string';
            $value .= $self->_next->{value};
        }
    }
    return $value;
}

# A list option value: [ value, value, ... ] (comma-separated). Each element is a
# recursive option value, so lists of aggregates work. Returns an arrayref.
sub _parse_list_value {
    my ($self) = @_;
    $self->_expect( 'punct', '[' );
    my @list;
    until ( $self->_is_punct(']') ) {
        $self->_error('unexpected end of input in list option value')
            if $self->_at_end;
        push @list, $self->_parse_option_value;
        $self->_consume_comma;    # optional trailing comma tolerated
    }
    $self->_expect( 'punct', ']' );
    return \@list;
}

# An aggregate option value: { name: value name: value ... } used for nested
# option messages (e.g. (google.api.http) = { get: "/v1" }). Entries are
# whitespace-separated; commas and semicolons between them are tolerated, and the
# `:` before a nested { } sub-message is optional (protoc syntax). Returns a
# hashref; nested aggregates recurse.
sub _parse_aggregate_value {
    my ($self) = @_;
    $self->_expect( 'punct', '{' );
    my %aggregate;
    until ( $self->_is_punct('}') ) {
        $self->_error('unexpected end of input in aggregate option value')
            if $self->_at_end;

        my $key = $self->_parse_option_name;
        $self->_next if $self->_is_punct(':');    # optional before a { } value
        $aggregate{$key} = $self->_parse_option_value;

        # Tolerate an optional separator between entries.
        $self->_next if $self->_is_punct(',') || $self->_is_punct(';');
    }
    $self->_expect( 'punct', '}' );
    return \%aggregate;
}

# oneof Name { type field = N; ... } — members are appended to @$fields with the
# given $index set, and a Schema::Oneof recording the same members is returned.
sub _parse_oneof {
    my ( $self, $scope, $fields, $index ) = @_;
    $self->_expect( 'keyword', 'oneof' );
    my $name = $self->_expect_name->{value};

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

    return Protobuf::Schema::Oneof->new(
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

    my $name = $self->_expect_name->{value};
    $self->_expect( 'punct', '=' );
    my $number  = $self->_parse_field_number;
    my $options = $self->_parse_field_options;    # optional [opt = ...]
    $self->_expect( 'punct', ';' );

    # MapEntry name is the CamelCase field name + 'Entry' (protoc convention).
    my $entry_simple = _camel_case_upper($name) . 'Entry';
    my $entry_full   = "$scope.$entry_simple";

    my $entry = Protobuf::Schema::Message->new(
        name         => $entry_simple,
        full_name    => $entry_full,
        is_map_entry => 1,
        fields       => [
            Protobuf::Schema::Field->new(
                name      => 'key',
                number    => 1,
                type      => $key_type,
                json_name => 'key',
            ),
            Protobuf::Schema::Field->new(
                name      => 'value',
                number    => 2,
                type      => $value_type,
                type_name => $value_type_name,
                json_name => 'value',
            ),
        ],
    );

    my $field = Protobuf::Schema::Field->new(
        name      => $name,
        number    => $number,
        type      => 'message',
        type_name => $entry_full,
        label     => 'repeated',
        map_entry => $entry_full,
        json_name => $options->{json_name} // _camel_case($name),
        options   => $options,
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

# Raise a Parser error naming the keyword when a message-body statement starts
# with a proto2-only construct (`required`, `group`, `extensions`, `extend`).
# These lex as plain identifiers, so we inspect the leading token's value and
# report precisely which forbidden keyword was used (spec §4.4).
sub _reject_proto2_construct {
    my ($self) = @_;
    my $token = $self->_peek;
    return unless $token && $PROTO2_FORBIDDEN{ $token->{value} };
    $self->_error(
        "`$token->{value}` is not allowed in proto3 (proto2-only)", $token );
}

# [label] type name = number;  — $oneof_index, when defined, marks the field as
# a member of the oneof at that index (oneof members carry no label). $extendee,
# when defined, marks the field as an extension of that message (an `extend`
# block member).
sub _parse_field {
    my ( $self, $oneof_index, $extendee ) = @_;

    $self->_reject_proto2_construct;

    my $label = 'singular';
    my $token = $self->_peek;
    if ( $token && $token->{type} eq 'keyword' && $LABEL{ $token->{value} } ) {
        $label = $self->_next->{value};
    }

    my ( $type, $type_name ) = $self->_parse_field_type;
    my $name = $self->_expect_name->{value};
    $self->_expect( 'punct', '=' );
    my $number  = $self->_parse_field_number;
    my $options = $self->_parse_field_options;
    $self->_expect( 'punct', ';' );

    # A json_name option overrides the camelCase default.
    my $json_name = $options->{json_name} // _camel_case($name);

    return Protobuf::Schema::Field->new(
        name        => $name,
        number      => $number,
        type        => $type,
        type_name   => $type_name,
        label       => $label,
        oneof_index => $oneof_index,
        json_name   => $json_name,
        options     => $options,
        ( defined $extendee
            ? ( is_extension => 1, extendee => $extendee )
            : () ),
    );
}

# Parse and validate a field number (spec §4.4): 1..536870911, excluding the
# 19000..19999 range the protobuf implementation reserves. 0, the reserved
# range, and out-of-range values are rejected at parse time, matching protoc.
sub _parse_field_number {
    my ($self) = @_;
    my $token  = $self->_peek;
    my $number = $self->_expect('int')->{value};
    if (   $number < 1
        || $number > $MAX_FIELD_NUMBER
        || ( $number >= 19_000 && $number <= 19_999 ) )
    {
        $self->_error( "invalid field number $number", $token );
    }
    return $number;
}

# extend TypeName { [label] type name = number; ... } — declares extension fields
# of $extendee (proto3 allows this only for custom options). Returns the list of
# extension Schema::Field objects, each tagged is_extension with its extendee.
sub _parse_extend {
    my ( $self, $scope ) = @_;
    $self->_expect( 'keyword', 'extend' );
    my $extendee = $self->_parse_dotted_name;
    $self->_expect( 'punct', '{' );

    my @extensions;
    until ( $self->_is_punct('}') ) {
        $self->_error('unexpected end of input in extend body')
            if $self->_at_end;
        push @extensions, $self->_parse_field( undef, $extendee );
    }
    $self->_expect( 'punct', '}' );
    return @extensions;
}

# [ name = value, name = value, ... ] — an optional bracketed field-option list.
# Returns a hashref (empty when no bracket is present).
sub _parse_field_options {
    my ($self) = @_;
    my %options;
    return \%options unless $self->_is_punct('[');

    $self->_next;    # consume '['
    do {
        my $name_token = $self->_peek;
        my $name       = $self->_parse_option_name;
        if ( $FORBIDDEN_FIELD_OPTION{$name} ) {
            $self->_error(
                "the `$name` field option is not allowed in proto3 "
                    . '(scalar default values are proto2-only)',
                $name_token );
        }
        $self->_expect( 'punct', '=' );
        $options{$name} = $self->_parse_option_value;
    } while ( $self->_consume_comma );
    $self->_expect( 'punct', ']' );

    return \%options;
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
    # A (dotted) identifier — or a non-scalar keyword used contextually as a type
    # name — is a message-or-enum reference; message vs enum is settled later by
    # the resolver, which models both as embedded messages on the wire.
    if ( $token
        && (   $token->{type} eq 'ident'
            || $token->{type} eq 'fullident'
            || $token->{type} eq 'keyword' ) )
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

=encoding utf-8

=head1 NAME

Protobuf::Parser::Grammar - recursive-descent parser for .proto source

=head1 SYNOPSIS

    use Protobuf::Parser::Grammar;

    my $file = Protobuf::Parser::Grammar->new(
        source    => $proto_text,
        file_name => 'thing.proto',
    )->parse;
    # $file is a Protobuf::Schema::File.

=head1 DESCRIPTION

A hand-written recursive-descent parser that consumes the token stream produced
by L<Protobuf::Parser::Lexer> and builds a L<Protobuf::Schema::File>. It handles the
file C<syntax> declaration, the C<package> directive, C<import> statements
(plain/public/weak), file-, message-, service-, and field-level C<option>s,
top-level and nested messages and enums, C<service>/C<rpc> definitions
(including C<stream>), and message bodies containing scalar/message/enum fields,
C<oneof> groups, C<map> fields, and C<reserved> declarations (spec §4.4).

A single token-cursor abstraction (C<_peek> / C<_next> / C<_expect>) drives the
whole grammar.

=head1 BEHAVIOR

=over 4

=item *

C<syntax = "proto3";> is required as the first statement. A missing declaration
or any non-C<proto3> syntax value (e.g. C<"proto2">) raises
L<Protobuf::Exception::Parser::UnsupportedSyntax> carrying the offending source
C<line>/C<column>; the message names the rejected syntax value.

=item *

proto3 rejects proto2-only constructs. Using C<required>, C<group>,
C<extensions>, or C<extend> raises L<Protobuf::Exception::Parser> with a message
naming the forbidden keyword and its C<line>/C<column>. A scalar default-value
expression (C<< int32 x = 1 [default = 5]; >>) likewise raises, since proto3
fixes scalar defaults to the zero value. The proto3 C<optional> keyword (added
in protobuf 3.15 for explicit presence) is I<accepted> and marks the field with
the C<optional> label.

=item *

Field labels: a bare field is C<singular>; a C<repeated> field is C<repeated>; an
C<optional> field is C<optional> (proto3 explicit presence, per spec §4.4).

=item *

Each field's default C<json_name> is the camelCase form of its name
(C<data_blob> becomes C<dataBlob>).

=item *

Duplicate field numbers (or names) within a message are detected by
L<Protobuf::Schema::Message> at construction and surface as
C<Protobuf::Exception::Schema::DuplicateField>.

=item *

Nested messages and enums recurse, each receiving a dotted C<full_name> built
from the enclosing message's full name (C<a.b.Outer.Inner>).

=item *

C<enum> declarations build L<Protobuf::Schema::Enum>; C<option allow_alias = true;>
inside the body permits duplicate value numbers (otherwise duplicates raise
C<Protobuf::Exception::Schema> at construction).

=item *

A C<oneof> group records a L<Protobuf::Schema::Oneof> and appends its member fields
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

C<import>, C<import public>, and C<import weak> statements record
C<< { path => $rel, kind => 'normal'|'public'|'weak' } >> hashrefs on the file.

=item *

C<option name = value;> at file, message, service, or RPC scope populates the
corresponding C<options> hashref; bracketed field options
(C<[deprecated = true, json_name = "x"]>) populate the field's C<options> (and a
C<json_name> option overrides the camelCase default).

=item *

C<service> definitions build L<Protobuf::Schema::Service> with one method hashref
per C<rpc>, carrying C<input_type>/C<output_type> and C<client_streaming>/
C<server_streaming> flags driven by the C<stream> keyword. Parsing is
structural only — RPCs are never dispatched.

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

Parse the token stream and return a L<Protobuf::Schema::File>.

=back

=head1 GRAMMAR REFERENCE

A copy of the proto3 formal grammar is kept alongside this module in
F<lib/Protobuf/Parser/grammar.txt> (spec §4.4).

=head1 LICENSE

This software is licensed under the MIT license. See the C<LICENSE> file.

=cut
