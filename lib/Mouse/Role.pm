package Mouse::Role;
use strict;
use warnings;
use base 'Exporter';

use Carp 'confess', 'croak';
use Scalar::Util 'blessed';

use Mouse::Meta::Role;
use Mouse::Util;

our @EXPORT = qw(before after around super override inner augment has extends with requires excludes confess blessed);
our %is_removable = map{ $_ => undef } @EXPORT;
delete $is_removable{confess};
delete $is_removable{blessed};

sub before {
    my $meta = Mouse::Meta::Role->initialize(caller);

    my $code = pop;
    for (@_) {
        $meta->add_before_method_modifier($_ => $code);
    }
}

sub after {
    my $meta = Mouse::Meta::Role->initialize(caller);

    my $code = pop;
    for (@_) {
        $meta->add_after_method_modifier($_ => $code);
    }
}

sub around {
    my $meta = Mouse::Meta::Role->initialize(caller);

    my $code = pop;
    for (@_) {
        $meta->add_around_method_modifier($_ => $code);
    }
}


sub super {
    return unless $Mouse::SUPER_BODY; 
    $Mouse::SUPER_BODY->(@Mouse::SUPER_ARGS);
}

sub override {
    my $classname = caller;
    my $meta = Mouse::Meta::Role->initialize($classname);

    my $name = shift;
    my $code = shift;
    my $fullname = "${classname}::${name}";

    defined &$fullname
        && confess "Cannot add an override of method '$fullname' " .
                   "because there is a local version of '$fullname'";

    $meta->add_override_method_modifier($name => sub {
        local $Mouse::SUPER_PACKAGE = shift;
        local $Mouse::SUPER_BODY = shift;
        local @Mouse::SUPER_ARGS = @_;

        $code->(@_);
    });
}

# We keep the same errors messages as Moose::Role emits, here.
sub inner {
    croak "Moose::Role cannot support 'inner'";
}

sub augment {
    croak "Moose::Role cannot support 'augment'";
}

sub has {
    my $meta = Mouse::Meta::Role->initialize(caller);

    my $name = shift;
    my %opts = @_;

    $meta->add_attribute($name => \%opts);
}

sub extends  { confess "Roles do not currently support 'extends'" }

sub with     {
    my $meta = Mouse::Meta::Role->initialize(caller);
    my $role  = shift;
    my $args  = shift || {};
    confess "Mouse::Role only supports 'with' on individual roles at a time" if @_ || !ref $args;

    Mouse::load_class($role);
    $role->meta->apply($meta, %$args);
}

sub requires {
    my $meta = Mouse::Meta::Role->initialize(caller);
    Carp::croak "Must specify at least one method" unless @_;
    $meta->add_required_methods(@_);
}

sub excludes { confess "Mouse::Role does not currently support 'excludes'" }

sub import {
    my $class = shift;

    strict->import;
    warnings->import;

    my $caller = caller;

    # we should never export to main
    if ($caller eq 'main') {
        warn qq{$class does not export its sugar to the 'main' package.\n};
        return;
    }

    my $meta_method = sub{
        Mouse::Meta::Role->initialize(ref($_[0]) || $_[0]);
    };

    Mouse::Meta::Role->initialize($caller)->add_method(meta => sub {
        return Mouse::Meta::Role->initialize(ref($_[0]) || $_[0]);
    });

    Mouse::Role->export_to_level(1, @_);
}

sub unimport {
    my $caller = caller;

    my $stash = do{
        no strict 'refs';
        \%{$caller . '::'}
    };

    for my $keyword (@EXPORT) {
        my $code;
        if(exists $is_removable{$keyword}
            && ($code = $caller->can($keyword))
            && (Mouse::Util::get_code_info($code))[0] eq __PACKAGE__){

            delete $stash->{$keyword};
        }
    }
    return;
}

1;

__END__

=head1 NAME

Mouse::Role - define a role in Mouse

=head1 KEYWORDS

=head2 meta -> Mouse::Meta::Role

Returns this role's metaclass instance.

=head2 before (method|methods) => Code

Sets up a "before" method modifier. See L<Moose/before> or
L<Class::Method::Modifiers/before>.

=head2 after (method|methods) => Code

Sets up an "after" method modifier. See L<Moose/after> or
L<Class::Method::Modifiers/after>.

=head2 around (method|methods) => Code

Sets up an "around" method modifier. See L<Moose/around> or
L<Class::Method::Modifiers/around>.

=over 4

=item B<super>

Sets up the "super" keyword. See L<Moose/super>.

=item B<override ($name, &sub)>

Sets up an "override" method modifier. See L<Moose/Role/override>.

=item B<inner>

This is not supported and emits an error. See L<Moose/Role>.

=item B<augment ($name, &sub)>

This is not supported and emits an error. See L<Moose/Role>.

=back

=head2 has (name|names) => parameters

Sets up an attribute (or if passed an arrayref of names, multiple attributes) to
this role. See L<Mouse/has>.

=head2 confess error -> BOOM

L<Carp/confess> for your convenience.

=head2 blessed value -> ClassName | undef

L<Scalar::Util/blessed> for your convenience.

=head1 MISC

=head2 import

Importing Mouse::Role will give you sugar.

=head2 unimport

Please unimport Mouse (C<no Mouse::Role>) so that if someone calls one of the
keywords (such as L</has>) it will break loudly instead breaking subtly.

=cut

