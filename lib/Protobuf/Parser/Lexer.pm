# ABOUTME: Protobuf::Parser::Lexer — hand-written tokenizer for .proto source (spec §4.4).
# Produces an ordered token stream (type, value, line, col); discards comments;
# raises Protobuf::Exception::Parser with line/column on unterminated string/comment.
use v5.38;
use strict;
use warnings;

package Protobuf::Parser::Lexer;

use Protobuf::Exception;

# Table-driven keyword recognition. A word matching one of these (exactly) is a
# 'keyword' token; anything else identifier-shaped is an 'ident'. Covers the
# proto3 grammar keywords plus the scalar type names, per spec §4.4.
my %KEYWORD = map { $_ => 1 } qw(
    syntax import weak public package option
    enum message service rpc returns stream
    repeated optional reserved to max oneof map
    double float int32 int64 uint32 uint64
    sint32 sint64 fixed32 fixed64 sfixed32 sfixed64
    bool string bytes
);

# Single-character punctuation marks, each its own token.
my %PUNCT = map { $_ => 1 }
    ( '{', '}', '(', ')', '[', ']', '=', ',', ';', '<', '>', '.' );

# Simple single-character string escapes -> their decoded byte.
my %SIMPLE_ESCAPE = (
    n  => "\n",
    t  => "\t",
    r  => "\r",
    a  => "\a",
    b  => "\b",
    f  => "\f",
    v  => "\013",
    q{\\} => q{\\},
    q{"}  => q{"},
    q{'}  => q{'},
    '?' => '?',
);

sub new {
    my ( $class, %args ) = @_;
    my $self = {
        source => $args{source},
        pos    => 0,
        line   => 1,
        col    => 1,
    };
    return bless $self, $class;
}

# Advance the cursor by one character, maintaining line/column. A newline resets
# the column to 1 and bumps the line.
sub _advance {
    my ($self) = @_;
    my $ch = substr $self->{source}, $self->{pos}, 1;
    $self->{pos}++;
    if ( $ch eq "\n" ) {
        $self->{line}++;
        $self->{col} = 1;
    }
    else {
        $self->{col}++;
    }
    return $ch;
}

sub _peek {
    my ( $self, $offset ) = @_;
    $offset //= 0;
    return substr $self->{source}, $self->{pos} + $offset, 1;
}

sub _at_end {
    my ($self) = @_;
    return $self->{pos} >= length $self->{source};
}

sub _error {
    my ( $self, $message, $line, $col ) = @_;
    Protobuf::Exception::Parser->throw(
        message => $message,
        line    => $line   // $self->{line},
        column  => $col    // $self->{col},
    );
}

# Tokenize the whole source, returning an arrayref of token hashes:
# { type => ..., value => ..., line => ..., col => ... }. Comments and
# whitespace are discarded and produce no tokens.
sub tokenize {
    my ($self) = @_;
    my @tokens;
    while ( !$self->_at_end ) {
        my $ch = $self->_peek;

        # Whitespace.
        if ( $ch =~ /\s/ ) {
            $self->_advance;
            next;
        }

        # Comments.
        if ( $ch eq '/' && $self->_peek(1) eq '/' ) {
            $self->_consume_line_comment;
            next;
        }
        if ( $ch eq '/' && $self->_peek(1) eq '*' ) {
            $self->_consume_block_comment;
            next;
        }

        # String literals.
        if ( $ch eq q{"} || $ch eq q{'} ) {
            push @tokens, $self->_read_string;
            next;
        }

        # Numbers: a digit, or a leading-dot float like .5.
        if ( $ch =~ /[0-9]/
            || ( $ch eq '.' && $self->_peek(1) =~ /[0-9]/ ) )
        {
            push @tokens, $self->_read_number;
            next;
        }

        # Identifiers / keywords / fullIdent: start with a letter or underscore.
        if ( $ch =~ /[A-Za-z_]/ ) {
            push @tokens, $self->_read_word;
            next;
        }

        # Punctuation.
        if ( $PUNCT{$ch} ) {
            my ( $line, $col ) = ( $self->{line}, $self->{col} );
            $self->_advance;
            push @tokens,
                { type => 'punct', value => $ch, line => $line, col => $col };
            next;
        }

        $self->_error("unexpected character '$ch'");
    }
    return \@tokens;
}

sub _consume_line_comment {
    my ($self) = @_;
    $self->_advance for 1 .. 2;    # consume '//'
    until ( $self->_at_end || $self->_peek eq "\n" ) {
        $self->_advance;
    }
    return;
}

sub _consume_block_comment {
    my ($self) = @_;
    my ( $start_line, $start_col ) = ( $self->{line}, $self->{col} );
    $self->_advance for 1 .. 2;    # consume '/*'
    while (1) {
        if ( $self->_at_end ) {
            $self->_error(
                'unterminated block comment',
                $start_line, $start_col,
            );
        }
        if ( $self->_peek eq '*' && $self->_peek(1) eq '/' ) {
            $self->_advance for 1 .. 2;    # consume '*/'
            last;
        }
        $self->_advance;
    }
    return;
}

# Read a quoted string, decoding escape sequences into their byte values.
sub _read_string {
    my ($self) = @_;
    my ( $line, $col ) = ( $self->{line}, $self->{col} );
    my $quote = $self->_advance;       # opening quote
    my $value = '';
    while (1) {
        if ( $self->_at_end ) {
            $self->_error( 'unterminated string literal', $line, $col );
        }
        my $ch = $self->_peek;
        if ( $ch eq $quote ) {
            $self->_advance;           # closing quote
            last;
        }
        if ( $ch eq "\n" ) {
            $self->_error( 'unterminated string literal', $line, $col );
        }
        if ( $ch eq q{\\} ) {
            $value .= $self->_read_escape;
            next;
        }
        $value .= $self->_advance;
    }
    return { type => 'string', value => $value, line => $line, col => $col };
}

# Decode one escape sequence (cursor is on the backslash) into its byte(s).
sub _read_escape {
    my ($self) = @_;
    $self->_advance;    # consume backslash
    my $ch = $self->_peek;

    # Hex escape: \xNN (one or two hex digits).
    if ( $ch eq 'x' || $ch eq 'X' ) {
        $self->_advance;
        my $hex = '';
        while ( length($hex) < 2 && $self->_peek =~ /[0-9A-Fa-f]/ ) {
            $hex .= $self->_advance;
        }
        $self->_error('invalid hex escape') unless length $hex;
        return chr hex $hex;
    }

    # Octal escape: \NNN (one to three octal digits).
    if ( $ch =~ /[0-7]/ ) {
        my $oct = '';
        while ( length($oct) < 3 && $self->_peek =~ /[0-7]/ ) {
            $oct .= $self->_advance;
        }
        return chr oct $oct;
    }

    # Simple single-character escape.
    if ( exists $SIMPLE_ESCAPE{$ch} ) {
        $self->_advance;
        return $SIMPLE_ESCAPE{$ch};
    }

    # Unknown escape: keep the character literally (lenient).
    return $self->_advance;
}

# Read an integer (dec/hex/oct) or float literal, decoding to a numeric value.
sub _read_number {
    my ($self) = @_;
    my ( $line, $col ) = ( $self->{line}, $self->{col} );
    my $start = $self->{pos};

    # Hex / octal integers begin with 0x / 0 (and have no dot or exponent).
    if ( $self->_peek eq '0'
        && ( $self->_peek(1) eq 'x' || $self->_peek(1) eq 'X' ) )
    {
        $self->_advance for 1 .. 2;    # consume '0x'
        my $digits = '';
        while ( $self->_peek =~ /[0-9A-Fa-f]/ ) {
            $digits .= $self->_advance;
        }
        $self->_error( 'invalid hex literal', $line, $col )
            unless length $digits;
        return {
            type  => 'int',
            value => hex $digits,
            line  => $line,
            col   => $col,
        };
    }

    # Scan the run of number characters to decide int vs float.
    my $text     = '';
    my $is_float = 0;
    while ( !$self->_at_end ) {
        my $c = $self->_peek;
        if ( $c =~ /[0-9]/ ) {
            $text .= $self->_advance;
        }
        elsif ( $c eq '.' ) {
            $is_float = 1;
            $text .= $self->_advance;
        }
        elsif ( $c eq 'e' || $c eq 'E' ) {
            $is_float = 1;
            $text .= $self->_advance;
            if ( $self->_peek eq '+' || $self->_peek eq '-' ) {
                $text .= $self->_advance;
            }
        }
        else {
            last;
        }
    }

    if ($is_float) {
        return {
            type  => 'float',
            value => ( $text + 0 ),
            line  => $line,
            col   => $col,
        };
    }

    # A leading-zero integer with only octal digits is octal; otherwise decimal.
    my $value;
    if ( $text =~ /\A0[0-7]+\z/ ) {
        $value = oct $text;
    }
    else {
        $value = $text + 0;
    }
    return { type => 'int', value => $value, line => $line, col => $col };
}

# Read an identifier / keyword / bool / fullIdent. Dotted runs become a single
# 'fullident' token; a bare word is matched against the keyword table.
sub _read_word {
    my ($self) = @_;
    my ( $line, $col ) = ( $self->{line}, $self->{col} );
    my $word     = '';
    my $is_dotted = 0;
    while ( !$self->_at_end ) {
        my $c = $self->_peek;
        if ( $c =~ /[A-Za-z0-9_]/ ) {
            $word .= $self->_advance;
        }
        elsif ( $c eq '.' && $self->_peek(1) =~ /[A-Za-z_]/ ) {
            $is_dotted = 1;
            $word .= $self->_advance;
        }
        else {
            last;
        }
    }

    if ($is_dotted) {
        return {
            type  => 'fullident',
            value => $word,
            line  => $line,
            col   => $col,
        };
    }
    if ( $word eq 'true' ) {
        return { type => 'bool', value => 1, line => $line, col => $col };
    }
    if ( $word eq 'false' ) {
        return { type => 'bool', value => 0, line => $line, col => $col };
    }
    if ( $KEYWORD{$word} ) {
        return { type => 'keyword', value => $word, line => $line, col => $col };
    }
    return { type => 'ident', value => $word, line => $line, col => $col };
}

1;

__END__

=head1 NAME

Protobuf::Parser::Lexer - hand-written tokenizer for .proto source

=head1 SYNOPSIS

    use Protobuf::Parser::Lexer;

    my $lexer  = Protobuf::Parser::Lexer->new( source => $proto_text );
    my $tokens = $lexer->tokenize;
    # $tokens is an arrayref of { type, value, line, col } hashes.

=head1 DESCRIPTION

Converts proto3 C<.proto> source text into an ordered stream of tokens for the
recursive-descent grammar (L<Protobuf::Parser::Grammar>) to consume. The lexer is
hand-written with no parser-generator dependency, per the project's zero-extra-
dependency goal.

Comments (C<//> line and C</* */> block) and whitespace are discarded and
produce no tokens. Every emitted token carries the 1-based source C<line> and
C<col> of its first character, so the grammar and downstream errors can point at
exact source positions.

=head1 TOKEN KINDS

Each token is a hashref with C<type>, C<value>, C<line>, and C<col>. The
C<type> is one of:

=over 4

=item C<ident>

A bare identifier (letters, digits, underscores; not starting with a digit) that
is not a keyword or boolean literal. C<value> is the identifier text.

=item C<fullident>

A dotted identifier such as C<foo.bar.Baz>. C<value> is the full dotted text.

=item C<keyword>

A reserved proto3 word or scalar type name (e.g. C<message>, C<repeated>,
C<int32>). Recognition is table-driven, so C<message> is a keyword while
C<messages> is an C<ident>.

=item C<int>

An integer literal in decimal, hexadecimal (C<0x1F>), or octal (C<0755>) form.
C<value> is the decoded numeric value.

=item C<float>

A floating-point literal, including exponent (C<1e3>) and leading-dot (C<.5>)
forms. C<value> is the decoded number.

=item C<bool>

C<true> or C<false>. C<value> is C<1> or C<0>.

=item C<string>

A single- or double-quoted string literal. Escape sequences (C<\n>, C<\t>,
C<\">, C<\\>, hex C<\xNN>, octal C<\NNN>) are decoded to their byte values in
C<value>.

=item C<punct>

A single punctuation mark: one of C<{ } ( ) [ ] = , ; E<lt> E<gt> .>. C<value>
is the character.

=back

=head1 METHODS

=over 4

=item new(source => $text)

Construct a lexer over a source string.

=item tokenize

Return an arrayref of token hashes in source order. Throws
L<Protobuf::Exception::Parser> (carrying C<line> and C<column>) on an unterminated
string literal or unterminated block comment.

=back

=head1 LICENSE

This software is licensed under the MIT license. See the C<LICENSE> file.

=cut
