# ABOUTME: Schema::File — one .proto file's top-level definitions; §4.2.
# FileDescriptorProto equivalent: package, messages, enums, services, imports.
use v5.38;
use feature 'class';
no warnings 'experimental::class';

class Proto3::Schema::File {
    field $name     :param;                 # 'temporal/api/common/v1/message.proto'
    field $package  :param = '';            # 'temporal.api.common.v1'
    field $messages :param = [];            # arrayref of Schema::Message
    field $enums    :param = [];            # arrayref of Schema::Enum
    field $services :param = [];            # arrayref of Schema::Service
    field $syntax   :param = 'proto3';
    field $imports  :param = [];            # arrayref of { path, kind } hashrefs
    field $options  :param = {};            # hashref of file-level options

    # Explicit readers (this Perl build has :param but not :reader).
    method name     { $name }
    method package  { $package }
    method messages { $messages }
    method enums    { $enums }
    method services { $services }
    method syntax   { $syntax }
    method imports  { $imports }
    method options  { $options }
}

1;

__END__

=head1 NAME

Proto3::Schema::File - One .proto file's top-level schema definitions

=head1 DESCRIPTION

The C<FileDescriptorProto> equivalent: file name, package, top-level messages,
enums, services, syntax, imports, and file-level options. C<imports> is an
arrayref of C<< { path => $rel, kind => 'normal'|'public'|'weak' } >> hashrefs;
C<options> is a hashref of file-level option name/value pairs. All fields are
immutable after construction.

=head1 LICENSE

This software is licensed under the MIT license. See the C<LICENSE> file.

=cut
