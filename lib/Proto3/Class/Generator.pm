# ABOUTME: Proto3::Class::Generator — installs a Perl class at runtime from a
# Schema::Message: typed reader/set/clear accessors, construction, descriptor (§4.6).
use v5.38;
use warnings;

package Proto3::Class::Generator;

use Scalar::Util ();
use Proto3::Exception;
use Proto3::Class::Accessor ();

# The set of proto3 scalar types whose values must look like a number. A wrong-
# type value assigned to such a field (via the constructor or a setter) raises
# Proto3::Exception::Codec::TypeMismatch. string/bytes accept any non-reference
# scalar; message/enum-as-int validation lands in later steps. Mirrors the
# Codec scalar table's is_num flag without coupling to its private internals.
my %NUMERIC_TYPE = map { $_ => 1 } qw(
    int32 int64 uint32 uint64 sint32 sint64
    fixed32 fixed64 sfixed32 sfixed64
    bool float double enum
);

# build(schema => $schema, message => $message, target_package => 'Foo::Bar')
#
# Install a class named target_package backed by the given Schema::Message. The
# generated class is a plain blessed hashref keyed by proto field NAME (so
# to_hashref and the codec see the wire names regardless of any accessor
# keyword-mangling). Accessors are installed as closures directly into the
# package's symbol table — no string eval, no `feature 'class'` for the
# generated code, which sidesteps the package-scoping traps that bite generated
# class blocks. Returns the target package name.
#
# Per-field accessors (accessor base name from Proto3::Class::Accessor):
#   <name>            reader; returns the stored value (or undef if unset)
#   set_<name>($v)    validates scalar type, stores, returns $self (chainable)
#   clear_<name>      deletes the field, returns $self
#
# Class/instance methods:
#   new(\%fields)     construct; an unknown key raises Argument naming it
#   to_hashref        shallow copy of stored fields, keyed by proto field name
#   descriptor        returns the Schema::Message (callable on class or instance)
sub build {
    my ( $class, %args ) = @_;

    my $message = $args{message}
        or Proto3::Exception::Argument->throw(
        message => 'build requires a message' );
    my $target = $args{target_package}
        or Proto3::Exception::Argument->throw(
        message => 'build requires a target_package' );

    my @fields = @{ $message->fields };

    # Index legal constructor keys (proto field names) for O(1) validation, and
    # remember each field's type for setter type-checking.
    my %field_by_name = map { $_->name => $_ } @fields;

    no strict 'refs';    ## no critic (ProhibitNoStrict)

    # descriptor: the owning Schema::Message, callable as a class OR instance
    # method (the invocant is ignored either way).
    *{"${target}::descriptor"} = sub { return $message };

    # new(\%fields): blessed hashref keyed by proto field name. An unknown key
    # (not a declared field) raises Argument naming the offending key. Field
    # values are stored verbatim; per-field setters are the typed entry point,
    # but the constructor validates scalar types too for symmetry.
    *{"${target}::new"} = sub {
        my ( $invocant, $init ) = @_;
        my $self = bless {}, ( ref $invocant || $invocant );
        $init //= {};

        for my $key ( keys %$init ) {
            my $field = $field_by_name{$key};
            if ( !$field ) {
                Proto3::Exception::Argument->throw(
                    message => "unknown field '$key' for $target",
                );
            }
            _assert_scalar_type( $field, $init->{$key} );
            $self->{$key} = $init->{$key};
        }
        return $self;
    };

    # to_hashref: a shallow copy of the stored fields, keyed by proto field
    # name (NOT the possibly-mangled accessor name).
    *{"${target}::to_hashref"} = sub {
        my ($self) = @_;
        return { %$self };
    };

    for my $field (@fields) {
        _install_field_accessors( $target, $field );
    }

    return $target;
}

# Install the reader/set/clear accessors for one field into $target's symbol
# table. The stored hash key is always the proto field name; the accessor base
# name may carry a trailing underscore on a Perl-keyword clash.
sub _install_field_accessors ($target, $field) {
    my $name = $field->name;
    my $base = Proto3::Class::Accessor::accessor_name($name);

    no strict 'refs';    ## no critic (ProhibitNoStrict)

    *{"${target}::${base}"} = sub {
        my ($self) = @_;
        return $self->{$name};
    };

    *{"${target}::set_${base}"} = sub {
        my ( $self, $value ) = @_;
        _assert_scalar_type( $field, $value );
        $self->{$name} = $value;
        return $self;    # chainable
    };

    *{"${target}::clear_${base}"} = sub {
        my ($self) = @_;
        delete $self->{$name};
        return $self;    # chainable
    };

    return;
}

# Raise Codec::TypeMismatch when $value is unusable for a numeric scalar field.
# A numeric field requires a number-looking value (a blessed Math::BigInt is
# allowed); string/bytes and non-scalar field kinds accept the value here
# (their validation, where applicable, lands in later steps). undef is allowed
# (an explicit clear/unset). Mirrors Proto3::Codec's type-mismatch contract.
sub _assert_scalar_type ($field, $value) {
    return unless defined $value;
    return unless $NUMERIC_TYPE{ $field->type };

    my $ok;
    if ( ref $value ) {
        $ok = Scalar::Util::blessed($value)
            && $value->isa('Math::BigInt');
    }
    else {
        $ok = Scalar::Util::looks_like_number($value);
    }
    return if $ok;

    my $got = ref $value ? ( ref $value ) : "'$value'";
    Proto3::Exception::Codec::TypeMismatch->throw(
        message => sprintf(
            'field %s expected %s, got %s',
            $field->name, $field->type, $got,
        ),
    );
}

1;

__END__

=head1 NAME

Proto3::Class::Generator - Build a Perl class at runtime from a Schema::Message

=head1 SYNOPSIS

    use Proto3::Class::Generator;

    Proto3::Class::Generator->build(
        schema         => $schema,
        message        => $message,             # a Proto3::Schema::Message
        target_package => 'T::Api::Common::V1::Payload',
    );

    my $msg = T::Api::Common::V1::Payload->new({ encoding => 'json/plain' });
    $msg->encoding;                         # 'json/plain'
    $msg->set_encoding('proto/binary')->set_data('...');   # chainable
    $msg->clear_encoding;
    $msg->to_hashref;                       # { ... } keyed by proto field name
    T::Api::Common::V1::Payload->descriptor;  # the Schema::Message

=head1 DESCRIPTION

C<build> installs a class, named by C<target_package>, whose shape is driven by
a L<Proto3::Schema::Message>. The generated class is a plain blessed hashref
keyed by B<proto field name>; accessors are installed directly into the
package's symbol table as closures. This avoids both string C<eval> and
C<feature 'class'> for the generated code, sidestepping the package-scoping
traps that affect generated class blocks under this Perl.

=head1 GENERATED CLASS API

=over 4

=item C<< $class->new(\%fields) >>

Construct an instance from a hashref keyed by proto field name. An B<unknown>
key (one that is not a declared field) raises
L<Proto3::Exception::Argument> naming the offending key. Numeric scalar fields
reject a non-number value with L<Proto3::Exception::Codec::TypeMismatch>.

=item C<< $obj->NAME >>

Reader for the field. Returns the stored value, or C<undef> if unset. When the
proto field name clashes with a Perl keyword (e.g. C<package>), the accessor
carries a trailing underscore (C<package_>), matching C<protoc-gen-python>.

=item C<< $obj->set_NAME($value) >>

Validates a numeric scalar field's value type (raising
L<Proto3::Exception::Codec::TypeMismatch> on a mismatch), stores it, and
returns C<$self> so setters chain.

=item C<< $obj->clear_NAME >>

Removes the field's value and returns C<$self>.

=item C<< $obj->to_hashref >>

A shallow copy of the stored fields, keyed by B<proto field name> (not the
possibly-underscored accessor name), suitable for passing to L<Proto3::Codec>.

=item C<< $class->descriptor >> / C<< $obj->descriptor >>

Returns the L<Proto3::Schema::Message> the class was built from. Callable as
either a class or instance method.

=back

=head1 LICENSE

This software is licensed under the MIT license. See the C<LICENSE> file.

=cut
