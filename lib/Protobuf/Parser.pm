# ABOUTME: Protobuf::Parser — facade over the lexer/grammar (spec §4.4): resolves
# .proto files against include_paths, parses them, caches by absolute path, and
# offers a canonical serializer for round-tripping a parsed Schema::File.
use v5.38;
use feature 'class';
no warnings 'experimental::class';

use File::Spec;
use Cwd ();
use Scalar::Util ();

use Protobuf::Parser::Grammar;
use Protobuf::Schema;
use Protobuf::Exception;

class Protobuf::Parser {
    field $include_paths :param = [];   # arrayref of search-root directories

    # Cache of parsed files keyed by absolute path, so a file imported (or
    # re-requested) more than once yields the identical Schema::File object.
    field $cache = {};

    # Locate $rel under the include_paths (first match wins) and return its
    # absolute path; raises ImportNotFound when no root contains it.
    method _resolve_path ($rel) {
        for my $root (@$include_paths) {
            my $candidate = File::Spec->catfile( $root, $rel );
            next unless -f $candidate;
            return Cwd::abs_path($candidate);
        }
        Protobuf::Exception::Parser::ImportNotFound->throw(
            message => "imported file not found in include_paths: $rel",
        );
    }

    # Parse the .proto named $rel, searching include_paths (first match wins).
    # Caches by absolute path: repeated requests return the same object.
    method parse_file ($rel) {
        my $abs = $self->_resolve_path($rel);
        return $cache->{$abs} if exists $cache->{$abs};

        open my $fh, '<', $abs
            or Protobuf::Exception::Parser::ImportNotFound->throw(
            message => "cannot read $abs: $!",
            );
        my $source = do { local $/; <$fh> };
        close $fh;

        my $file = $self->parse_string( $rel, $source );
        $cache->{$abs} = $file;
        return $file;
    }

    # Parse $rel and every file it transitively imports, returning a
    # Protobuf::Schema with all of them added. Imports are followed via parse_file,
    # so the abs-path cache deduplicates diamond imports (each file loads once).
    # A circular import chain raises Protobuf::Exception::Parser::ImportCycle.
    method parse_with_imports ($rel, %opts) {
        my $schema = Protobuf::Schema->new;
        $self->_collect_imports( $rel, $schema, {}, {} );

        # Resolve cross-file type references by default so the returned schema is
        # immediately usable (B-014). Pass resolve => 0 to get the unresolved
        # form (e.g. to inspect a partial graph whose referenced types live in
        # files outside the import closure).
        my $resolve = exists $opts{resolve} ? $opts{resolve} : 1;
        $schema->resolve if $resolve;
        return $schema;
    }

    # Recursively parse $rel and its imports into $schema. $in_progress holds the
    # absolute paths currently on the import stack (cycle detection); $visited
    # holds those already added to $schema (so each file is added exactly once,
    # even across diamond imports).
    method _collect_imports ($rel, $schema, $in_progress, $visited) {
        my $abs = $self->_resolve_path($rel);

        if ( $in_progress->{$abs} ) {
            Protobuf::Exception::Parser::ImportCycle->throw(
                message => "circular import detected at $rel",
            );
        }
        return if $visited->{$abs};

        $in_progress->{$abs} = 1;

        my $file = $self->parse_file($rel);
        $self->_collect_imports( $_->{path}, $schema, $in_progress, $visited )
            for @{ $file->imports };

        delete $in_progress->{$abs};
        $visited->{$abs} = 1;
        $schema->add_file($file);
        return;
    }

    # Parse proto3 $source as if it were the file named $name. Does not touch the
    # include-path cache (callers that want caching go through parse_file).
    method parse_string ( $name, $source ) {
        return Protobuf::Parser::Grammar->new(
            source    => $source,
            file_name => $name,
        )->parse;
    }

    # Render a Schema::File back into canonical proto3 source text. The output
    # round-trips: parsing it yields an equivalent schema (spec T-parse-1). The
    # full grammar is emitted — file/message options, imports, file- and
    # nested-scope enums, services, oneofs, maps, reserved ranges/names, and
    # extension (`extend`) blocks — not just trivial messages.
    sub serialize ( $class, $file ) {
        my @lines = ( 'syntax = "proto3";' );

        my $package = $file->package;
        push @lines, "package $package;" if length $package;

        for my $import ( @{ $file->imports } ) {
            my $kind = $import->{kind} // 'normal';
            my $qual = $kind eq 'public' ? 'public '
                : $kind eq 'weak'        ? 'weak '
                :                          '';
            push @lines, qq{import $qual"$import->{path}";};
        }

        push @lines, _serialize_option_line( $_, $file->options->{$_}, '' )
            for sort keys %{ $file->options };

        push @lines, _serialize_enum( $_, '' )    for @{ $file->enums };
        push @lines, _serialize_message( $_, '' ) for @{ $file->messages };
        push @lines, _serialize_service( $_, '' ) for @{ $file->services };
        push @lines, _serialize_extends( $file->extensions, '' );

        return join( "\n", grep { length } @lines ) . "\n";
    }

    # Render one Schema::Message (recursively) at the given indent.
    sub _serialize_message ($message, $indent) {
        my $inner = "$indent  ";
        my @body;

        push @body, _serialize_option_line( $_, $message->options->{$_}, $inner )
            for sort keys %{ $message->options };

        # Map a field's owning entry message (the synthetic <Field>Entry) by name,
        # so a map field renders as map<K,V> and its entry is not emitted twice.
        my %entry_by_name =
            map { $_->full_name => $_ }
            grep { $_->is_map_entry } @{ $message->nested_messages };

        # Group oneof member field numbers so they render inside their oneof block
        # rather than as standalone fields.
        my %in_oneof;
        for my $oneof ( @{ $message->oneofs } ) {
            $in_oneof{ $_->number } = 1 for @{ $oneof->fields };
        }

        for my $field ( @{ $message->fields } ) {
            next if $in_oneof{ $field->number };
            if ( $field->is_map ) {
                push @body,
                    _serialize_map_field( $field,
                    $entry_by_name{ $field->map_entry }, $inner );
            }
            else {
                push @body, $inner . _serialize_field($field);
            }
        }

        push @body, _serialize_oneof( $_, $inner ) for @{ $message->oneofs };

        push @body, _serialize_enum( $_, $inner ) for @{ $message->nested_enums };

        for my $nested ( @{ $message->nested_messages } ) {
            next if $nested->is_map_entry;    # synthetic; rendered as map<K,V>
            push @body, _serialize_message( $nested, $inner );
        }

        push @body, _serialize_reserved( $message, $inner );
        push @body, _serialize_extends( $message->extensions, $inner );

        my $name = $message->name;
        return "$indent" . "message $name {\n"
            . join( "\n", grep { length } @body )
            . "\n$indent}";
    }

    # Render one Schema::Field as a `[label ]type name = number[ options];`.
    sub _serialize_field ($field) {
        my $prefix =
            $field->label eq 'repeated' ? 'repeated '
            : $field->label eq 'optional' ? 'optional '
            :                               '';
        my $type = $field->is_message ? $field->type_name : $field->type;
        return sprintf '%s%s %s = %d%s;', $prefix, $type, $field->name,
            $field->number, _serialize_field_options($field);
    }

    # Render a map<K,V> field from its synthetic entry message (key=field 1,
    # value=field 2). Falls back to the raw field when the entry is unavailable.
    sub _serialize_map_field ($field, $entry, $indent) {
        return $indent . _serialize_field($field) unless $entry;
        my ($key)   = grep { $_->number == 1 } @{ $entry->fields };
        my ($value) = grep { $_->number == 2 } @{ $entry->fields };
        my $vtype = $value->is_message ? $value->type_name : $value->type;
        return sprintf '%smap<%s, %s> %s = %d%s;', $indent, $key->type,
            $vtype, $field->name, $field->number,
            _serialize_field_options($field);
    }

    # Render a oneof block with its member fields (members carry no label).
    sub _serialize_oneof ($oneof, $indent) {
        my $inner = "$indent  ";
        my @members = map { $inner . _serialize_field($_) } @{ $oneof->fields };
        return "$indent" . 'oneof ' . $oneof->name . " {\n"
            . join( "\n", @members ) . "\n$indent}";
    }

    # Render an enum (recursively scoped) at the given indent.
    sub _serialize_enum ($enum, $indent) {
        my $inner = "$indent  ";
        my @body;
        push @body, _serialize_option_line( $_, $enum->options->{$_}, $inner )
            for sort keys %{ $enum->options };
        push @body, sprintf( '%s%s = %d;', $inner, $_->{name}, $_->{number} )
            for @{ $enum->values };
        return "$indent" . 'enum ' . $enum->name . " {\n"
            . join( "\n", @body ) . "\n$indent}";
    }

    # Render a service and its rpc methods at the given indent.
    sub _serialize_service ($service, $indent) {
        my $inner = "$indent  ";
        my @body;
        push @body, _serialize_option_line( $_, $service->options->{$_}, $inner )
            for sort keys %{ $service->options };
        for my $m ( @{ $service->methods } ) {
            my $cs = $m->{client_streaming} ? 'stream ' : '';
            my $ss = $m->{server_streaming} ? 'stream ' : '';
            push @body,
                sprintf( '%srpc %s (%s%s) returns (%s%s);',
                $inner, $m->{name}, $cs, $m->{input_type}, $ss,
                $m->{output_type} );
        }
        return "$indent" . 'service ' . $service->name . " {\n"
            . join( "\n", @body ) . "\n$indent}";
    }

    # Render the message's reserved number ranges and names, or '' when none.
    sub _serialize_reserved ($message, $indent) {
        my @lines;
        if ( @{ $message->reserved_numbers } ) {
            my @ranges = map {
                my ( $lo, $hi ) = @$_;
                $lo == $hi ? "$lo" : "$lo to $hi";
            } @{ $message->reserved_numbers };
            push @lines, $indent . 'reserved ' . join( ', ', @ranges ) . ';';
        }
        if ( @{ $message->reserved_names } ) {
            my @names = map {qq{"$_"}} @{ $message->reserved_names };
            push @lines, $indent . 'reserved ' . join( ', ', @names ) . ';';
        }
        return join "\n", @lines;
    }

    # Render extension declarations, grouped by extendee, or '' when none.
    sub _serialize_extends ($extensions, $indent) {
        return '' unless $extensions && @$extensions;
        my $inner = "$indent  ";
        my ( @order, %by_extendee );
        for my $ext (@$extensions) {
            push @order, $ext->extendee unless exists $by_extendee{ $ext->extendee };
            push @{ $by_extendee{ $ext->extendee } }, $ext;
        }
        my @blocks;
        for my $extendee (@order) {
            my @fields =
                map { $inner . _serialize_field($_) } @{ $by_extendee{$extendee} };
            push @blocks, "$indent" . "extend $extendee {\n"
                . join( "\n", @fields ) . "\n$indent}";
        }
        return join "\n", @blocks;
    }

    # Render an `option name = value;` line at the given indent.
    sub _serialize_option_line ($name, $value, $indent) {
        return sprintf '%soption %s = %s;', $indent, $name,
            _serialize_option_value($value);
    }

    # Render a field's bracketed option list (` [a = 1, b = "x"]`), or '' when the
    # field has no options.
    sub _serialize_field_options ($field) {
        my $options = $field->options;
        return '' unless $options && %$options;
        my @pairs = map { "$_ = " . _serialize_option_value( $options->{$_} ) }
            sort keys %$options;
        return ' [' . join( ', ', @pairs ) . ']';
    }

    # Render an option value: an aggregate hashref as { k: v ... }, a number bare,
    # anything else as a quoted, escaped string. This round-trips through the
    # parser (which stores scalar option values uniformly).
    sub _serialize_option_value ($value) {
        if ( ref $value eq 'HASH' ) {
            my @pairs =
                map { "$_: " . _serialize_option_value( $value->{$_} ) }
                sort keys %$value;
            return '{ ' . join( ' ', @pairs ) . ' }';
        }
        return $value if Scalar::Util::looks_like_number($value);
        ( my $escaped = $value ) =~ s/(["\\])/\\$1/g;
        return qq{"$escaped"};
    }
}

1;

__END__

=encoding utf-8

=head1 NAME

Protobuf::Parser - parse .proto files into schema definitions

=head1 SYNOPSIS

    use Protobuf::Parser;

    my $parser = Protobuf::Parser->new(
        include_paths => [ '/path/to/protos', '/another/path' ],
    );
    my $file = $parser->parse_file('temporal/api/common/v1/message.proto');
    # $file is a Protobuf::Schema::File instance.

    # Or parse a string:
    my $file = $parser->parse_string('foo.proto', $proto_source);

    # Walk imports automatically into a full, resolved Protobuf::Schema:
    my $schema = $parser->parse_with_imports('top.proto');
    # (pass resolve => 0 to skip the resolve pass)

    # Round-trip a parsed file through canonical source:
    my $text = Protobuf::Parser->serialize($file);

=head1 DESCRIPTION

The public entry point for the proto3 parser (spec §4.4). It wraps
L<Protobuf::Parser::Lexer> and L<Protobuf::Parser::Grammar>, adding include-path
resolution and a per-parser cache so a file requested (or imported) more than
once yields the identical L<Protobuf::Schema::File> object.

=head1 METHODS

=over 4

=item new(include_paths => \@dirs)

Construct a parser. C<include_paths> is an ordered list of directories searched
by C<parse_file>; the first directory containing the requested relative path
wins.

=item parse_file($relative_path)

Search C<include_paths> for C<$relative_path> (first match wins), read it, and
parse it into a L<Protobuf::Schema::File>. The result is cached by I<absolute>
path, so a subsequent C<parse_file> of the same file returns the same object.
A file that no include path contains raises
L<Protobuf::Exception::Parser::ImportNotFound>.

=item parse_with_imports($relative_path, %opts)

Parse C<$relative_path> and every file it transitively C<import>s, returning a
L<Protobuf::Schema> with all of them registered. Each imported file is loaded
through C<parse_file>, so the absolute-path cache deduplicates diamond imports:
a file reachable by more than one path is parsed and added exactly once. Files
are added in dependency order (imports before their importers). A circular
import chain raises L<Protobuf::Exception::Parser::ImportCycle>; a missing
imported file raises L<Protobuf::Exception::Parser::ImportNotFound>.

The returned schema is B<resolved> by default — cross-file type references are
linked, so it is immediately usable by the codec. Pass C<< resolve => 0 >> to
skip the resolve pass and obtain the unresolved schema (for inspecting a partial
graph whose referenced types lie outside the import closure).

=item parse_string($name, $source)

Parse proto3 C<$source> directly, using C<$name> as the resulting file's name
and in error messages. Does not consult or populate the include-path cache.

=item Protobuf::Parser->serialize($file)

Render a L<Protobuf::Schema::File> back into canonical proto3 source text. The
output round-trips: parsing it produces an equivalent schema (spec T-parse-1).
Invoked as a class method.

=back

=head1 LICENSE

This software is licensed under the MIT license. See the C<LICENSE> file.

=cut
