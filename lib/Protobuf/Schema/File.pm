# ABOUTME: Schema::File — one .proto file's top-level definitions; §4.2.
# FileDescriptorProto equivalent: package, messages, enums, services, imports.
use v5.38;
use feature 'class';
no warnings 'experimental::class';

class Protobuf::Schema::File {
    field $name     :param;                 # 'temporal/api/common/v1/message.proto'
    field $package  :param = '';            # 'temporal.api.common.v1'
    field $messages :param = [];            # arrayref of Schema::Message
    field $enums    :param = [];            # arrayref of Schema::Enum
    field $services :param = [];            # arrayref of Schema::Service
    field $syntax   :param = 'proto3';
    field $imports  :param = [];            # arrayref of { path, kind } hashrefs
    field $options  :param = {};            # hashref of file-level options
    field $extensions :param = [];          # arrayref of extension Schema::Field decls
    field $edition  :param = undef;         # 'proto2','proto3','2023'; derived from syntax
    field $features :param = {};            # explicit file-level feature overrides

    # Default the edition from the legacy syntax when not given, preserving
    # backward compat: a file constructed with only syntax => 'proto3' resolves
    # to the proto3 edition (and thus proto3 feature defaults).
    ADJUST {
        $edition //= $syntax;
    }

    # Explicit readers (this Perl build has :param but not :reader).
    method name     { $name }
    method package  { $package }
    method messages { $messages }
    method enums    { $enums }
    method services { $services }
    method syntax   { $syntax }
    method imports  { $imports }
    method options  { $options }
    method extensions { $extensions }
    method edition  { $edition }
    method features { $features }
}

1;

__END__

=encoding utf-8

=head1 NAME

Protobuf::Schema::File - One .proto file's top-level schema definitions

=head1 SYNOPSIS

    use Protobuf::Schema::File;

    my $file = Protobuf::Schema::File->new(
        name     => 'hello.proto',
        package  => 'hello',
        syntax   => 'proto3',
        messages => [ $message ],   # Protobuf::Schema::Message objects
    );

    $file->package;   # 'hello'
    $file->edition;   # 'proto3' (defaulted from syntax when not given)
    $file->messages;  # arrayref of top-level Protobuf::Schema::Message

File objects are usually produced by L<Protobuf::Parser> (one per parsed
C<.proto>) or L<Protobuf::DescriptorSet>, then added to a L<Protobuf::Schema>.

=head1 DESCRIPTION

The C<FileDescriptorProto> equivalent: file name, package, top-level messages,
enums, services, syntax, imports, and file-level options. C<imports> is an
arrayref of C<< { path => $rel, kind => 'normal'|'public'|'weak' } >> hashrefs;
C<options> is a hashref of file-level option name/value pairs. All fields are
immutable after construction.

=head1 ACCESSORS

Each returns the correspondingly-named construction value.

=over 4

=item C<name>

The file's path-relative name (e.g. C<'temporal/api/common/v1/message.proto'>).

=item C<package>

The file's proto package (e.g. C<'temporal.api.common.v1'>), or the empty
string when none is declared.

=item C<messages>

An arrayref of top-level L<Protobuf::Schema::Message> objects.

=item C<enums>

An arrayref of top-level L<Protobuf::Schema::Enum> objects.

=item C<services>

An arrayref of L<Protobuf::Schema::Service> objects.

=item C<syntax>

The declared syntax string (C<'proto3'>).

=item C<imports>

An arrayref of C<< { path, kind } >> import hashrefs.

=item C<options>

A hashref of file-level options.

=item C<extensions>

An arrayref of file-scope extension L<Protobuf::Schema::Field> declarations (the
members of top-level C<extend> blocks), each tagged C<is_extension> with its
C<extendee>. Empty when the file declares no extensions.

=back

=head1 LICENSE

This software is licensed under the MIT license. See the C<LICENSE> file.

=cut
