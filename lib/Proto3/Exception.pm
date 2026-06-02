# ABOUTME: Typed exception hierarchy for Proto3; every error is a thrown object.
# Base carries message + cause, stringifies to the message, and offers throw().
use v5.38;
use feature 'class';
no warnings 'experimental::class';

class Proto3::Exception {
    use overload
        q{""}    => sub { $_[0]->message // '' },
        fallback => 1;

    field $message :param = undef;
    field $cause   :param = undef;

    # Explicit reader methods rather than the :reader field attribute: this
    # Perl 5.38.2 build supports :param but not :reader.
    method message { $message }
    method cause   { $cause }

    # throw() is a plain sub (not a `method`) so it works both as an instance
    # method ($exc->throw) and as a constructor shortcut
    # (Proto3::Exception::Foo->throw(message => '...')). Under Perl 5.38's class
    # feature a `method` has no class invocant, which would break the
    # class-method form. Defined only here; inherited by every subclass, as are
    # the overload and the accessors.
    sub throw {
        my ( $invocant, @args ) = @_;
        die ref $invocant ? $invocant : $invocant->new(@args);
    }
}

# --- Argument -------------------------------------------------------------
class Proto3::Exception::Argument :isa(Proto3::Exception) {}

# --- Wire -----------------------------------------------------------------
class Proto3::Exception::Wire :isa(Proto3::Exception) {}
class Proto3::Exception::Wire::Truncated       :isa(Proto3::Exception::Wire) {}
class Proto3::Exception::Wire::VarintTooLong   :isa(Proto3::Exception::Wire) {}
class Proto3::Exception::Wire::DeprecatedGroup :isa(Proto3::Exception::Wire) {}
class Proto3::Exception::Wire::InvalidWireType :isa(Proto3::Exception::Wire) {}

# --- Schema ---------------------------------------------------------------
class Proto3::Exception::Schema :isa(Proto3::Exception) {}
class Proto3::Exception::Schema::DuplicateField   :isa(Proto3::Exception::Schema) {}
class Proto3::Exception::Schema::DuplicateMessage :isa(Proto3::Exception::Schema) {}

# UnresolvedType additionally carries the dangling reference (name), the
# package the reference was written in (current_package), and the ordered
# search_path of fully-qualified names the resolver attempted, for debugging.
class Proto3::Exception::Schema::UnresolvedType :isa(Proto3::Exception::Schema) {
    field $name            :param = undef;
    field $current_package :param = undef;
    field $search_path     :param = [];

    method name            { $name }
    method current_package { $current_package }
    method search_path     { $search_path }
}

# --- Parser ---------------------------------------------------------------
# Parser errors additionally carry the 1-based source line and column where the
# problem was detected, so callers can point at the offending .proto location.
class Proto3::Exception::Parser :isa(Proto3::Exception) {
    field $line   :param = undef;
    field $column :param = undef;

    method line   { $line }
    method column { $column }
}
class Proto3::Exception::Parser::ImportNotFound    :isa(Proto3::Exception::Parser) {}
class Proto3::Exception::Parser::ImportCycle       :isa(Proto3::Exception::Parser) {}
class Proto3::Exception::Parser::UnsupportedSyntax :isa(Proto3::Exception::Parser) {}

# --- Codec ----------------------------------------------------------------
class Proto3::Exception::Codec :isa(Proto3::Exception) {}
class Proto3::Exception::Codec::TypeMismatch :isa(Proto3::Exception::Codec) {}
class Proto3::Exception::Codec::UnknownType  :isa(Proto3::Exception::Codec) {}

# --- JSON -----------------------------------------------------------------
class Proto3::Exception::JSON :isa(Proto3::Exception) {}
class Proto3::Exception::JSON::Parse :isa(Proto3::Exception::JSON) {}
class Proto3::Exception::JSON::WKT   :isa(Proto3::Exception::JSON) {}

1;

__END__

=head1 NAME

Proto3::Exception - Typed exception hierarchy for Proto3

=head1 SYNOPSIS

    use Proto3::Exception;

    # Throw as a constructor shortcut (class-method form):
    Proto3::Exception::Argument->throw( message => 'field number must be > 0' );

    # Or build an object first, then throw it (instance form):
    my $exc = Proto3::Exception::Wire::Truncated->new(
        message => 'buffer ended mid-varint',
    );
    $exc->throw;

    # Catch and inspect:
    eval { decode($bytes) };
    if ( my $err = $@ ) {
        if ( $err->isa('Proto3::Exception::Wire') ) {
            warn "wire error: $err";      # stringifies to the message
        }
    }

=head1 DESCRIPTION

Every error Proto3 raises is an object in this hierarchy, never a bare string.
Catching code can branch on the type with C<< ->isa(...) >> at whatever
granularity it needs: a broad C<Proto3::Exception::Wire> catch handles any
wire-format corruption, while a narrow C<Proto3::Exception::Wire::Truncated>
catch handles just a short read.

The base class carries two fields:

=over 4

=item C<message>

Human-readable description of what went wrong. The object stringifies to this
text via an overload, so C<"$err"> and string interpolation yield the message.

=item C<cause>

Optional underlying error being wrapped, so a higher-level failure can retain
the low-level error that triggered it. Defaults to C<undef>.

=back

=head1 CONTRACT

=over 4

=item *

B<Throwing.> C<throw> is defined only on the base and inherited by every
subclass. It works two ways:

    $exc->throw;                          # die with the existing object
    SomeClass->throw( message => '...' ); # construct, then die with it

In both cases it dies with an object of the invoking class.

=item *

B<Stringification.> The C<q{""}> overload (defined only on the base, inherited
everywhere) returns C<message>. A message-less exception stringifies to the
empty string rather than dying.

=item *

B<Inheritance.> C<throw>, the stringification overload, and the C<message> /
C<cause> reader methods live only on C<Proto3::Exception>; subclasses add no
code, only an C<:isa> relationship.

=back

=head1 HIERARCHY

    Proto3::Exception                          base; stringifies to message
    |- Proto3::Exception::Argument             bad public-API argument
    |- Proto3::Exception::Wire                 wire-format corruption
    |  |- Proto3::Exception::Wire::Truncated         buffer ended mid-value
    |  |- Proto3::Exception::Wire::VarintTooLong     >10 bytes, no terminator
    |  '- Proto3::Exception::Wire::DeprecatedGroup   wire type 3/4 encountered
    |- Proto3::Exception::Schema               schema construction/validation
    |  |- Proto3::Exception::Schema::DuplicateField     field number/name reused
    |  |- Proto3::Exception::Schema::DuplicateMessage   FQ message name reused
    |  '- Proto3::Exception::Schema::UnresolvedType     type name never resolved
    |       (extra fields: name, current_package, search_path)
    |- Proto3::Exception::Parser               .proto syntax / semantic error
    |  |- Proto3::Exception::Parser::ImportNotFound     import path missing
    |  |- Proto3::Exception::Parser::ImportCycle        circular import
    |  '- Proto3::Exception::Parser::UnsupportedSyntax  proto2 / unknown syntax
    |- Proto3::Exception::Codec                runtime encode/decode error
    |  |- Proto3::Exception::Codec::TypeMismatch        value/field type clash
    |  '- Proto3::Exception::Codec::UnknownType         no such type in schema
    '- Proto3::Exception::JSON                 JSON mapping error
       |- Proto3::Exception::JSON::Parse               malformed JSON text
       '- Proto3::Exception::JSON::WKT                 well-known-type mapping

All classes live in this single file (multiple C<class> blocks); the hierarchy
is small enough that splitting across files would hurt navigation.

=head1 LICENSE

This software is licensed under the MIT license. See the C<LICENSE> file.

=cut
