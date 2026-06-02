# ABOUTME: Proto3::Class::Generator — installs a Perl class at runtime from a
# Schema::Message: typed reader/set/clear accessors, construction, descriptor (§4.6).
use v5.38;
use warnings;

package Proto3::Class::Generator;

use Scalar::Util ();
use Proto3::Exception;
use Proto3::Class::Accessor ();
use Proto3::Codec ();

# Registry of every class built by this module, keyed by the owning message's
# fully-qualified name. decode() consults it to materialize a nested message
# field's decoded hashref into the corresponding generated class instance,
# rather than leaving it as a bare hashref. A message with no generated class
# (absent from the registry) decodes into a plain hashref, unchanged.
my %CLASS_FOR_MESSAGE;    # full_name => target package

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
#   encode            (instance) serialize to wire bytes via the shared codec
#   decode($bytes)    (class) deserialize; nested message fields become their
#                     generated class instances (thin codec adapters, §4.6)
sub build {
    my ( $class, %args ) = @_;

    my $message = $args{message}
        or Proto3::Exception::Argument->throw(
        message => 'build requires a message' );
    my $schema = $args{schema}
        or Proto3::Exception::Argument->throw(
        message => 'build requires a schema' );
    my $target = $args{target_package}
        or Proto3::Exception::Argument->throw(
        message => 'build requires a target_package' );

    # Register this class so decode() can materialize it as a nested field of
    # some other generated message.
    $CLASS_FOR_MESSAGE{ $message->full_name } = $target;

    # One codec over the schema, shared by every instance's encode/decode (the
    # generated methods are thin adapters — all wire logic lives in the codec).
    my $codec = Proto3::Codec->new( schema => $schema );

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

    my $full_name = $message->full_name;

    # encode($self) -> wire bytes. A thin adapter over the shared codec: hand it
    # the message's hashref form (blessed nested instances are themselves
    # blessed hashrefs the codec reads through, so to_hashref's shallow copy is
    # sufficient — the codec recurses on field name lookups).
    *{"${target}::encode"} = sub {
        my ($self) = @_;
        return $codec->encode( $full_name, $self->to_hashref );
    };

    # $class->decode($bytes) -> an instance. Decodes to a plain hashref via the
    # codec, then materializes that hashref (and any nested message fields) into
    # generated class instances.
    *{"${target}::decode"} = sub {
        my ( $invocant, $bytes ) = @_;
        my $values = $codec->decode( $full_name, $bytes );
        return _materialize( $schema, $message, $values,
            ref $invocant || $invocant );
    };

    # Map each oneof's index to the proto field names of its members, so a
    # member setter can clear its siblings and which_<oneof> can report the set
    # one. A field belongs to a oneof iff its oneof_index matches a oneof.
    my %oneof_members;    # oneof_index => [ field name, ... ]
    for my $oneof ( @{ $message->oneofs } ) {
        my @names = map { $_->name } @{ $oneof->fields };
        # Fall back to the message's fields carrying this oneof_index when the
        # oneof was constructed without an explicit members list.
        unless (@names) {
            @names = map { $_->name }
                grep { defined $_->oneof_index
                    && $_->oneof_index == $oneof->oneof_index } @fields;
        }
        $oneof_members{ $oneof->oneof_index } = \@names;
    }

    for my $field (@fields) {
        my $siblings;
        if ( defined $field->oneof_index
            && $oneof_members{ $field->oneof_index } )
        {
            # Siblings = oneof members other than this field.
            $siblings = [ grep { $_ ne $field->name }
                    @{ $oneof_members{ $field->oneof_index } } ];
        }
        _install_field_accessors( $target, $field, $siblings );
    }

    # which_<oneof>($self) -> the proto field name of the set member, or undef.
    for my $oneof ( @{ $message->oneofs } ) {
        _install_which( $target, $oneof->name,
            $oneof_members{ $oneof->oneof_index } );
    }

    return $target;
}

# Per-field-kind helper emission is table-driven: _field_kind classifies a
# field, and %KIND_INSTALLERS maps the kind to the routine that installs that
# kind's extra helpers (add_/set_entry/etc.) on top of the common reader/
# set/clear. has_<name> is layered on independently for explicit-presence
# fields, and oneof sibling-clearing is layered onto the setter via $siblings.

# Classify a field for helper dispatch. Map is checked before repeated because
# a map field is also labeled 'repeated' at the schema level.
sub _field_kind ($field) {
    return 'map'      if $field->is_map;
    return 'repeated' if $field->is_repeated;
    return 'singular';
}

# Install the accessors for one field into $target's symbol table. The stored
# hash key is always the proto field name; the accessor base name may carry a
# trailing underscore on a Perl-keyword clash. $siblings (arrayref or undef) is
# the list of oneof sibling field names this setter must clear when it fires.
sub _install_field_accessors ($target, $field, $siblings = undef) {
    my $name = $field->name;
    my $base = Proto3::Class::Accessor::accessor_name($name);
    my $kind = _field_kind($field);

    no strict 'refs';    ## no critic (ProhibitNoStrict)

    state %KIND_READER = (
        singular => sub ($self, $n) { return $self->{$n}; },
        repeated => sub ($self, $n) { return $self->{$n} //= []; },
        map      => sub ($self, $n) { return $self->{$n} //= {}; },
    );
    my $reader = $KIND_READER{$kind};
    *{"${target}::${base}"} = sub { return $reader->( $_[0], $name ); };

    # set_<name>: replaces the whole value. Scalar singular fields type-check;
    # repeated/map values are stored verbatim (element validation is the
    # element-helper's job). Clears oneof siblings, then returns $self.
    *{"${target}::set_${base}"} = sub {
        my ( $self, $value ) = @_;
        _assert_scalar_type( $field, $value ) if $kind eq 'singular';
        $self->{$name} = $value;
        _clear_siblings( $self, $siblings );
        return $self;    # chainable
    };

    *{"${target}::clear_${base}"} = sub {
        my ($self) = @_;
        delete $self->{$name};
        return $self;    # chainable
    };

    # Kind-specific extra helpers (add_<name>, set_<name>_entry).
    state %KIND_INSTALLERS = (
        repeated => \&_install_repeated_helpers,
        map      => \&_install_map_helpers,
    );
    if ( my $installer = $KIND_INSTALLERS{$kind} ) {
        $installer->( $target, $field, $base, $name, $siblings );
    }

    # has_<name>: only for explicit-presence (optional-labeled) fields.
    if ( $field->label eq 'optional' ) {
        *{"${target}::has_${base}"} = sub {
            my ($self) = @_;
            return exists $self->{$name} ? 1 : 0;
        };
    }

    return;
}

# add_<name>($element): append to the repeated field's arrayref (autovivified).
sub _install_repeated_helpers ($target, $field, $base, $name, $siblings) {
    no strict 'refs';    ## no critic (ProhibitNoStrict)
    *{"${target}::add_${base}"} = sub {
        my ( $self, $element ) = @_;
        push @{ $self->{$name} //= [] }, $element;
        _clear_siblings( $self, $siblings );
        return $self;    # chainable
    };
    return;
}

# set_<name>_entry($key, $value): set one key of the map field's hashref
# (autovivified), overwriting any existing value for that key.
sub _install_map_helpers ($target, $field, $base, $name, $siblings) {
    no strict 'refs';    ## no critic (ProhibitNoStrict)
    *{"${target}::set_${base}_entry"} = sub {
        my ( $self, $key, $value ) = @_;
        ( $self->{$name} //= {} )->{$key} = $value;
        _clear_siblings( $self, $siblings );
        return $self;    # chainable
    };
    return;
}

# which_<oneof>($self): the proto field name of the currently-set oneof member,
# or undef if none is set. "Set" means the hash key exists.
sub _install_which ($target, $oneof_name, $members) {
    my $base = Proto3::Class::Accessor::accessor_name($oneof_name);
    $members //= [];
    no strict 'refs';    ## no critic (ProhibitNoStrict)
    *{"${target}::which_${base}"} = sub {
        my ($self) = @_;
        for my $member (@$members) {
            return $member if exists $self->{$member};
        }
        return undef;
    };
    return;
}

# Delete every sibling field's value (used by oneof member setters to enforce
# mutual exclusion). A no-op when $siblings is undef/empty.
sub _clear_siblings ($self, $siblings) {
    return unless $siblings;
    delete $self->{$_} for @$siblings;
    return;
}

# Turn a codec-decoded hashref into a generated class instance. $message is the
# Schema::Message describing $values; $target is the package to bless the result
# into. Each message-typed field's value (a hashref, or arrayref/hashref of
# hashrefs for repeated/map) is recursively materialized into its own generated
# class when one is registered; a field whose message type has no generated
# class is left as-is. The result is a blessed hashref keyed by proto field name
# (the same shape new/to_hashref use), so accessors work unchanged.
sub _materialize ($schema, $message, $values, $target) {
    my %materialized = %$values;

    for my $field ( @{ $message->fields } ) {
        next unless $field->is_message;

        my $name = $field->name;
        next unless exists $materialized{$name} && defined $materialized{$name};

        my $nested_message = _message_for_field( $schema, $field );
        next unless $nested_message;

        my $value = $materialized{$name};
        if ( $field->is_map ) {
            # Map message-valued entries: materialize each value hashref. The
            # map's value type is the MapEntry's field 2, not $field's type.
            my $value_message = _map_value_message( $schema, $nested_message );
            my $value_pkg =
                $value_message
                ? $CLASS_FOR_MESSAGE{ $value_message->full_name }
                : undef;
            next unless $value_message && $value_pkg;
            $materialized{$name} = {
                map {
                    $_ => _materialize( $schema, $value_message,
                        $value->{$_}, $value_pkg )
                } keys %$value
            };
        }
        else {
            my $nested_pkg = $CLASS_FOR_MESSAGE{ $nested_message->full_name };
            next unless $nested_pkg;    # no generated class -> leave as hashref
            if ( $field->is_repeated ) {
                $materialized{$name} = [
                    map {
                        _materialize( $schema, $nested_message, $_,
                            $nested_pkg )
                    } @$value
                ];
            }
            else {
                $materialized{$name} =
                    _materialize( $schema, $nested_message, $value,
                    $nested_pkg );
            }
        }
    }

    return bless \%materialized, $target;
}

# The Schema::Message a message-typed field points at: prefer the resolver-set
# type_ref, fall back to a schema lookup of the raw type_name. Returns undef
# when neither resolves to a message.
sub _message_for_field ($schema, $field) {
    my $ref = $field->type_ref;
    return $ref if $ref && Scalar::Util::blessed($ref) && $ref->can('fields');

    my $type_name = $field->type_name;
    return undef unless defined $type_name;
    ( my $bare = $type_name ) =~ s/^\.//;    # strip leading dot if fully-qualified
    return $schema->message($bare);
}

# Given a synthetic MapEntry Schema::Message, return the Schema::Message of its
# value field (number 2) when that value is itself a message, else undef.
sub _map_value_message ($schema, $map_entry) {
    my ($value_field) =
        grep { $_->number == 2 } @{ $map_entry->fields };
    return undef unless $value_field && $value_field->is_message;
    return _message_for_field( $schema, $value_field );
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

    my $bytes = $msg->encode;               # proto3 wire bytes
    my $back  = T::Api::Common::V1::Payload->decode($bytes);  # an instance

=head1 DESCRIPTION

C<build> installs a class, named by C<target_package>, whose shape is driven by
a L<Proto3::Schema::Message>. The generated class is a plain blessed hashref
keyed by B<proto field name>; accessors are installed directly into the
package's symbol table as closures. This avoids both string C<eval> and
C<feature 'class'> for the generated code, sidestepping the package-scoping
traps that affect generated class blocks under this Perl.

=head1 METHODS

=head2 build

    Proto3::Class::Generator->build(
        schema         => $schema,
        message        => $message,
        target_package => 'My::Class',
    );

Installs a Perl class named C<target_package> from a resolved
L<Proto3::Schema::Message> (C<message>) belonging to C<schema>. Returns nothing;
its effect is the newly-populated package symbol table. All three arguments are
required; a missing one raises L<Proto3::Exception::Argument>. The generated
class exposes the API documented under L</GENERATED CLASS API>.

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

=item C<< $obj->encode >>

Serializes the instance to proto3 wire bytes. A thin adapter over
L<Proto3::Codec>: equivalent to C<< $codec->encode($full_name, $obj->to_hashref) >>
for a codec built over the same schema. All wire logic lives in the codec; the
generated method only supplies the message name and the instance's hashref form.

=item C<< $class->decode($bytes) >>

Class method. Decodes proto3 wire C<$bytes> into a new instance. Equivalent to
the codec's hashref decode, except that B<nested message fields are materialized
into their corresponding generated class instances> (singular, repeated, and
message-valued map entries alike) rather than left as bare hashrefs — provided a
class has been generated for the nested message type. A nested message with no
generated class decodes into a plain hashref. Round-trips with C<encode>:
C<< $class->decode($obj->encode)->to_hashref >> equals C<< $obj->to_hashref >>.

=item C<< $obj->has_NAME >>

Presence check, B<generated only for explicit-presence fields> (those declared
C<optional> in proto3). Returns true once the field has been set — even to its
zero value — and false after C<clear_NAME>. Implicit-presence (plain singular)
fields get no C<has_> accessor.

=back

=head2 Repeated fields

A repeated field's reader returns an arrayref (an empty one if unset). In
addition to C<set_NAME> (which replaces the whole list) it gets:

=over 4

=item C<< $obj->add_NAME($element) >>

Appends C<$element> to the list and returns C<$self>.

=back

=head2 Map fields

A map field's reader returns a hashref (an empty one if unset). In addition to
C<set_NAME> (which replaces the whole map) it gets:

=over 4

=item C<< $obj->set_NAME_entry($key, $value) >>

Sets a single key, overwriting any existing value for that key, and returns
C<$self>.

=back

=head2 Oneofs

The members of a oneof are mutually exclusive: setting any member (via its
C<set_>, C<add_>, or C<set_>I<entry> helper) clears every other member of the
same oneof. Each oneof also gets:

=over 4

=item C<< $obj->which_ONEOF >>

Returns the proto field name of the currently-set member, or C<undef> when no
member is set.

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
