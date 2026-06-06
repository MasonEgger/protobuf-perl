# ABOUTME: Protobuf::Parser — facade over the lexer/grammar (spec §4.4): resolves
# .proto files against include_paths, parses them, caches by absolute path, and
# offers a canonical serializer for round-tripping a parsed Schema::File.
use v5.38;
use feature 'class';
no warnings 'experimental::class';

use File::Spec;
use Cwd ();

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
    method parse_with_imports ($rel) {
        my $schema = Protobuf::Schema->new;
        $self->_collect_imports( $rel, $schema, {}, {} );
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

    # Render a Schema::File back into canonical proto3 source text. Enough to
    # round-trip a parsed file through parse -> serialize -> parse into an
    # equivalent schema (spec T-parse-1).
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

        push @lines, _serialize_message($_) for @{ $file->messages };

        return join( "\n", @lines ) . "\n";
    }

    # Render one Schema::Message (recursively) as canonical proto3 text.
    sub _serialize_message ($message) {
        my @body;
        for my $field ( @{ $message->fields } ) {
            push @body, '  ' . _serialize_field($field);
        }
        push @body, _indent( _serialize_message($_) )
            for @{ $message->nested_messages };

        my $name = $message->name;
        return "message $name {\n" . join( "\n", @body ) . "\n}";
    }

    # Render one Schema::Field as a `[label ]type name = number;` declaration.
    sub _serialize_field ($field) {
        my $prefix =
            $field->label eq 'repeated' ? 'repeated '
            : $field->label eq 'optional' ? 'optional '
            :                               '';
        my $type = $field->is_message ? $field->type_name : $field->type;
        return sprintf '%s%s %s = %d;', $prefix, $type, $field->name,
            $field->number;
    }

    # Indent every line of $text by two spaces (for nested-message bodies).
    sub _indent ($text) {
        return join "\n", map { "  $_" } split /\n/, $text;
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

    # Walk imports automatically into a full Protobuf::Schema:
    my $schema = $parser->parse_with_imports('top.proto');
    $schema->resolve;   # cross-file type references now linked

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

=item parse_with_imports($relative_path)

Parse C<$relative_path> and every file it transitively C<import>s, returning a
L<Protobuf::Schema> with all of them registered. Each imported file is loaded
through C<parse_file>, so the absolute-path cache deduplicates diamond imports:
a file reachable by more than one path is parsed and added exactly once. Files
are added in dependency order (imports before their importers). A circular
import chain raises L<Protobuf::Exception::Parser::ImportCycle>; a missing
imported file raises L<Protobuf::Exception::Parser::ImportNotFound>. Call
C<< $schema->resolve >> on the result to link cross-file type references.

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
