# ABOUTME: Protobuf::Schema::Serializer — renders a Schema::File tree as a static
# Perl constructor expression, so AOT-generated modules rebuild it with no parser (§4.12).
use v5.38;
use warnings;

package Protobuf::Schema::Serializer;

use Scalar::Util ();

# render_file($file) -> a Perl expression string that, when evaluated,
# reconstructs an equivalent Protobuf::Schema::File. Output is deterministic: hash
# keys (options) and structural lists are emitted in a stable order so two runs
# over the same input produce byte-identical text.
sub render_file ($file) {
    my %args = (
        name     => _scalar( $file->name ),
        package  => _scalar( $file->package ),
        syntax   => _scalar( $file->syntax ),
        imports  => _data( $file->imports ),
        options  => _data( $file->options ),
        messages => _list( [ map { _message($_) } @{ $file->messages } ] ),
        enums    => _list( [ map { _enum($_) } @{ $file->enums } ] ),
    );
    return _ctor( 'Protobuf::Schema::File', \%args );
}

# Render one Schema::Message (recursively over nested messages/enums).
sub _message ($message) {
    my %args = (
        name            => _scalar( $message->name ),
        full_name       => _scalar( $message->full_name ),
        is_map_entry    => _scalar( $message->is_map_entry ),
        oneof_index     => _scalar( $message->oneof_index ),
        reserved_names  => _data( $message->reserved_names ),
        reserved_numbers => _data( $message->reserved_numbers ),
        options         => _data( $message->options ),
        fields  => _list( [ map { _field($_) } @{ $message->fields } ] ),
        oneofs  => _list( [ map { _oneof($_) } @{ $message->oneofs } ] ),
        nested_messages =>
            _list( [ map { _message($_) } @{ $message->nested_messages } ] ),
        nested_enums =>
            _list( [ map { _enum($_) } @{ $message->nested_enums } ] ),
    );
    return _ctor( 'Protobuf::Schema::Message', \%args );
}

# Render one Schema::Field. type_ref is intentionally omitted — the generated
# module calls $schema->resolve at load time to repopulate it.
sub _field ($field) {
    my %args = (
        name        => _scalar( $field->name ),
        number      => _scalar( $field->number ),
        type        => _scalar( $field->type ),
        label       => _scalar( $field->label ),
        type_name   => _scalar( $field->type_name ),
        json_name   => _scalar( $field->json_name ),
        packed      => _scalar( $field->packed ),
        map_entry   => _scalar( $field->map_entry ),
        oneof_index => _scalar( $field->oneof_index ),
        options     => _data( $field->options ),
    );
    return _ctor( 'Protobuf::Schema::Field', \%args );
}

# Render one Schema::Oneof. Its fields are the same Field objects already emitted
# inline on the owning message; re-render them here so the oneof carries its own
# member list (Class::Generator reads oneof->fields for sibling clearing).
sub _oneof ($oneof) {
    my %args = (
        name        => _scalar( $oneof->name ),
        oneof_index => _scalar( $oneof->oneof_index ),
        fields => _list( [ map { _field($_) } @{ $oneof->fields } ] ),
    );
    return _ctor( 'Protobuf::Schema::Oneof', \%args );
}

# Render one Schema::Enum.
sub _enum ($enum) {
    my %args = (
        name        => _scalar( $enum->name ),
        full_name   => _scalar( $enum->full_name ),
        allow_alias => _scalar( $enum->allow_alias ),
        values      => _data( $enum->values ),
        options     => _data( $enum->options ),
    );
    return _ctor( 'Protobuf::Schema::Enum', \%args );
}

# Render a 'Class->new( key => val, ... )' expression with keys sorted for
# determinism. Undef-valued args are dropped (the constructor defaults apply).
sub _ctor ( $class, $args ) {
    my @parts;
    for my $key ( sort keys %$args ) {
        my $val = $args->{$key};
        next unless defined $val;    # skip undef -> use constructor default
        push @parts, "$key => $val";
    }
    return "$class\->new( " . join( ', ', @parts ) . " )";
}

# Render an arrayref of already-rendered expression strings as '[ ... ]'.
# Returns undef for an empty list so _ctor drops the key (defaults apply).
sub _list ($items) {
    return undef unless @$items;
    return '[ ' . join( ', ', @$items ) . ' ]';
}

# Render a plain scalar as a Perl literal: numbers bare, strings single-quoted,
# undef -> undef (dropped by _ctor).
sub _scalar ($value) {
    return undef unless defined $value;
    if ( !ref $value && $value =~ /\A-?[0-9]+\z/ ) {
        return $value;    # integer literal
    }
    return _string($value);
}

# Render an arbitrary plain data structure (hashref/arrayref/scalar) as a
# deterministic Perl literal. Hash keys are sorted. Returns undef for an empty
# hashref/arrayref so _ctor drops the key.
sub _data ($value) {
    if ( !defined $value ) {
        return undef;
    }
    if ( ref $value eq 'ARRAY' ) {
        return undef unless @$value;
        return '[ ' . join( ', ', map { _data($_) // 'undef' } @$value ) . ' ]';
    }
    if ( ref $value eq 'HASH' ) {
        return undef unless %$value;
        my @parts;
        for my $key ( sort keys %$value ) {
            my $rendered = _data( $value->{$key} ) // 'undef';
            push @parts, _string($key) . " => $rendered";
        }
        return '{ ' . join( ', ', @parts ) . ' }';
    }
    # plain scalar
    if ( $value =~ /\A-?[0-9]+\z/ ) {
        return $value;
    }
    return _string($value);
}

# Single-quoted Perl string literal, escaping backslash and single quote.
sub _string ($value) {
    $value =~ s/([\\'])/\\$1/g;
    return "'$value'";
}

1;

__END__

=head1 NAME

Protobuf::Schema::Serializer - Render a Schema::File as static Perl

=head1 SYNOPSIS

    use Protobuf::Schema::Serializer;

    my $expr = Protobuf::Schema::Serializer::render_file($file);
    # 'Protobuf::Schema::File->new( ... )'

=head1 DESCRIPTION

Produces a Perl source expression that reconstructs a L<Protobuf::Schema::File>
(and its full tree of messages, fields, oneofs, enums, and nested types) without
involving the parser. The AOT code generator (L<Protobuf::Class::Codegen>) embeds
the result so generated modules carry B<no> parser or descriptor-set dependency.

The output is B<deterministic>: hash keys are sorted, C<undef>-valued
constructor arguments are dropped (the class defaults apply), and empty
lists/hashes are omitted — so rendering the same input twice is byte-identical.
The field-level C<type_ref> link is intentionally not serialized; the generated
module calls C<< $schema->resolve >> at load time to repopulate it.

=head1 FUNCTIONS

=head2 render_file

    render_file($file)

Returns the Perl constructor expression for a L<Protobuf::Schema::File>.

=head1 LICENSE

This software is licensed under the MIT license. See the C<LICENSE> file.

=cut
