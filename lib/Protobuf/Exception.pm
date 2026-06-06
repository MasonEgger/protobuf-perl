# ABOUTME: Typed exception hierarchy for Protobuf; every error is a thrown object.
# Base carries message + cause, stringifies to the message, and offers throw().
use v5.38;
use feature 'class';
no warnings 'experimental::class';

class Protobuf::Exception {
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
    # (Protobuf::Exception::Foo->throw(message => '...')). Under Perl 5.38's class
    # feature a `method` has no class invocant, which would break the
    # class-method form. Defined only here; inherited by every subclass, as are
    # the overload and the accessors.
    sub throw {
        my ( $invocant, @args ) = @_;
        die ref $invocant ? $invocant : $invocant->new(@args);
    }
}

# --- Argument -------------------------------------------------------------
class Protobuf::Exception::Argument :isa(Protobuf::Exception) {}

# --- Wire -----------------------------------------------------------------
class Protobuf::Exception::Wire :isa(Protobuf::Exception) {}
class Protobuf::Exception::Wire::Truncated       :isa(Protobuf::Exception::Wire) {}
class Protobuf::Exception::Wire::VarintTooLong   :isa(Protobuf::Exception::Wire) {}
class Protobuf::Exception::Wire::DeprecatedGroup :isa(Protobuf::Exception::Wire) {}
class Protobuf::Exception::Wire::InvalidWireType :isa(Protobuf::Exception::Wire) {}

# --- Schema ---------------------------------------------------------------
class Protobuf::Exception::Schema :isa(Protobuf::Exception) {}
class Protobuf::Exception::Schema::DuplicateField   :isa(Protobuf::Exception::Schema) {}
class Protobuf::Exception::Schema::DuplicateMessage :isa(Protobuf::Exception::Schema) {}

# UnresolvedType additionally carries the dangling reference (name), the
# package the reference was written in (current_package), and the ordered
# search_path of fully-qualified names the resolver attempted, for debugging.
class Protobuf::Exception::Schema::UnresolvedType :isa(Protobuf::Exception::Schema) {
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
class Protobuf::Exception::Parser :isa(Protobuf::Exception) {
    field $line   :param = undef;
    field $column :param = undef;

    method line   { $line }
    method column { $column }
}
class Protobuf::Exception::Parser::ImportNotFound    :isa(Protobuf::Exception::Parser) {}
class Protobuf::Exception::Parser::ImportCycle       :isa(Protobuf::Exception::Parser) {}
class Protobuf::Exception::Parser::UnsupportedSyntax :isa(Protobuf::Exception::Parser) {}

# --- Codec ----------------------------------------------------------------
class Protobuf::Exception::Codec :isa(Protobuf::Exception) {}
class Protobuf::Exception::Codec::TypeMismatch :isa(Protobuf::Exception::Codec) {}
class Protobuf::Exception::Codec::UnknownType  :isa(Protobuf::Exception::Codec) {}

# --- JSON -----------------------------------------------------------------
class Protobuf::Exception::JSON :isa(Protobuf::Exception) {}
class Protobuf::Exception::JSON::Parse :isa(Protobuf::Exception::JSON) {}
class Protobuf::Exception::JSON::WKT   :isa(Protobuf::Exception::JSON) {}

1;

__END__

=head1 NAME

Protobuf::Exception - Typed exception hierarchy for Protobuf

=head1 SYNOPSIS

    use Protobuf::Exception;

    # Throw as a constructor shortcut (class-method form):
    Protobuf::Exception::Argument->throw( message => 'field number must be > 0' );

    # Or build an object first, then throw it (instance form):
    my $exc = Protobuf::Exception::Wire::Truncated->new(
        message => 'buffer ended mid-varint',
    );
    $exc->throw;

    # Catch and inspect:
    eval { decode($bytes) };
    if ( my $err = $@ ) {
        if ( $err->isa('Protobuf::Exception::Wire') ) {
            warn "wire error: $err";      # stringifies to the message
        }
    }

=head1 DESCRIPTION

Every error Protobuf raises is an object in this hierarchy, never a bare string.
Catching code can branch on the type with C<< ->isa(...) >> at whatever
granularity it needs: a broad C<Protobuf::Exception::Wire> catch handles any
wire-format corruption, while a narrow C<Protobuf::Exception::Wire::Truncated>
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
C<cause> reader methods live only on C<Protobuf::Exception>; subclasses add no
code, only an C<:isa> relationship.

=back

=head1 METHODS

=over 4

=item C<throw>

Die with an exception object. As an instance method (C<< $exc->throw >>) it dies
with the existing object; as a class method
(C<< SomeClass->throw(message => '...') >>) it constructs an instance first.

=item C<message>

The human-readable error description (also the stringified form).

=item C<cause>

The optional wrapped underlying error, or C<undef>.

=item C<name>

I<(C<Protobuf::Exception::Schema::UnresolvedType> only.)> The dangling type
reference that could not be resolved.

=item C<current_package>

I<(C<UnresolvedType> only.)> The package the unresolved reference was written
in.

=item C<search_path>

I<(C<UnresolvedType> only.)> An arrayref of the fully-qualified names the
resolver tried, in order.

=item C<line>

I<(C<Protobuf::Exception::Parser> and subclasses only.)> The 1-based source line
where the parse error was detected.

=item C<column>

I<(C<Protobuf::Exception::Parser> and subclasses only.)> The 1-based source column
where the parse error was detected.

=back

=head1 HIERARCHY

    Protobuf::Exception                          base; stringifies to message
    |- Protobuf::Exception::Argument             bad public-API argument
    |- Protobuf::Exception::Wire                 wire-format corruption
    |  |- Protobuf::Exception::Wire::Truncated         buffer ended mid-value
    |  |- Protobuf::Exception::Wire::VarintTooLong     >10 bytes, no terminator
    |  '- Protobuf::Exception::Wire::DeprecatedGroup   wire type 3/4 encountered
    |- Protobuf::Exception::Schema               schema construction/validation
    |  |- Protobuf::Exception::Schema::DuplicateField     field number/name reused
    |  |- Protobuf::Exception::Schema::DuplicateMessage   FQ message name reused
    |  '- Protobuf::Exception::Schema::UnresolvedType     type name never resolved
    |       (extra fields: name, current_package, search_path)
    |- Protobuf::Exception::Parser               .proto syntax / semantic error
    |  |- Protobuf::Exception::Parser::ImportNotFound     import path missing
    |  |- Protobuf::Exception::Parser::ImportCycle        circular import
    |  '- Protobuf::Exception::Parser::UnsupportedSyntax  proto2 / unknown syntax
    |- Protobuf::Exception::Codec                runtime encode/decode error
    |  |- Protobuf::Exception::Codec::TypeMismatch        value/field type clash
    |  '- Protobuf::Exception::Codec::UnknownType         no such type in schema
    '- Protobuf::Exception::JSON                 JSON mapping error
       |- Protobuf::Exception::JSON::Parse               malformed JSON text
       '- Protobuf::Exception::JSON::WKT                 well-known-type mapping

All classes live in this single file (multiple C<class> blocks); the hierarchy
is small enough that splitting across files would hurt navigation.

=head1 LICENSE

This software is licensed under the MIT license. See the C<LICENSE> file.

=cut
