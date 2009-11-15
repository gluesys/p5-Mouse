package Mouse::PurePerl;

require Mouse::Util;

package
    Mouse::Util;

use strict;
use warnings;

use warnings FATAL => 'redefine'; # to avoid to load Mouse::PurePerl

use B ();

sub is_class_loaded {
    my $class = shift;

    return 0 if ref($class) || !defined($class) || !length($class);

    # walk the symbol table tree to avoid autovififying
    # \*{${main::}{"Foo::"}} == \*main::Foo::

    my $pack = \%::;
    foreach my $part (split('::', $class)) {
        my $entry = \$pack->{$part . '::'};
        return 0 if ref($entry) ne 'GLOB';
        $pack = *{$entry}{HASH} or return 0;
    }

    # check for $VERSION or @ISA
    return 1 if exists $pack->{VERSION}
             && defined *{$pack->{VERSION}}{SCALAR} && defined ${ $pack->{VERSION} };
    return 1 if exists $pack->{ISA}
             && defined *{$pack->{ISA}}{ARRAY} && @{ $pack->{ISA} } != 0;

    # check for any method
    foreach my $name( keys %{$pack} ) {
        my $entry = \$pack->{$name};
        return 1 if ref($entry) ne 'GLOB' || defined *{$entry}{CODE};
    }

    # fail
    return 0;
}


# taken from Sub::Identify
sub get_code_info {
    my ($coderef) = @_;
    ref($coderef) or return;

    my $cv = B::svref_2object($coderef);
    $cv->isa('B::CV') or return;

    my $gv = $cv->GV;
    $gv->isa('B::GV') or return;

    return ($gv->STASH->NAME, $gv->NAME);
}

sub get_code_package{
    my($coderef) = @_;

    my $cv = B::svref_2object($coderef);
    $cv->isa('B::CV') or return '';

    my $gv = $cv->GV;
    $gv->isa('B::GV') or return '';

    return $gv->STASH->NAME;
}

sub get_code_ref{
    my($package, $name) = @_;
    no strict 'refs';
    no warnings 'once';
    use warnings FATAL => 'uninitialized';
    return *{$package . '::' . $name}{CODE};
}

sub generate_isa_predicate_for {
    my($for_class, $name) = @_;

    my $predicate = sub{ Scalar::Util::blessed($_[0]) && $_[0]->isa($for_class) };

    if(defined $name){
        no strict 'refs';
        *{ caller() . '::' . $name } = $predicate;
        return;
    }

    return $predicate;
}


package
    Mouse::Util::TypeConstraints;

use Scalar::Util qw(blessed looks_like_number openhandle);

sub Any        { 1 }
sub Item       { 1 }

sub Bool       { $_[0] ? $_[0] eq '1' : 1 }
sub Undef      { !defined($_[0]) }
sub Defined    {  defined($_[0])  }
sub Value      {  defined($_[0]) && !ref($_[0]) }
sub Num        { !ref($_[0]) && looks_like_number($_[0]) }
sub Int        {  defined($_[0]) && !ref($_[0]) && $_[0] =~ /^-?[0-9]+$/ }
sub Str        {  defined($_[0]) && !ref($_[0]) }

sub Ref        { ref($_[0]) }
sub ScalarRef  { ref($_[0]) eq 'SCALAR' }
sub ArrayRef   { ref($_[0]) eq 'ARRAY'  }
sub HashRef    { ref($_[0]) eq 'HASH'   }
sub CodeRef    { ref($_[0]) eq 'CODE'   }
sub RegexpRef  { ref($_[0]) eq 'Regexp' }
sub GlobRef    { ref($_[0]) eq 'GLOB'   }

sub FileHandle {
    openhandle($_[0])  || (blessed($_[0]) && $_[0]->isa("IO::Handle"))
}

sub Object     { blessed($_[0]) && blessed($_[0]) ne 'Regexp' }

sub ClassName  { Mouse::Util::is_class_loaded($_[0]) }
sub RoleName   { (Mouse::Util::class_of($_[0]) || return 0)->isa('Mouse::Meta::Role') }

sub _parameterize_ArrayRef_for {
    my($type_parameter) = @_;
    my $check = $type_parameter->_compiled_type_constraint;

    return sub {
        foreach my $value (@{$_}) {
            return undef unless $check->($value);
        }
        return 1;
    }
}

sub _parameterize_HashRef_for {
    my($type_parameter) = @_;
    my $check = $type_parameter->_compiled_type_constraint;

    return sub {
        foreach my $value(values %{$_}){
            return undef unless $check->($value);
        }
        return 1;
    };
}

# 'Maybe' type accepts 'Any', so it requires parameters
sub _parameterize_Maybe_for {
    my($type_parameter) = @_;
    my $check = $type_parameter->_compiled_type_constraint;

    return sub{
        return !defined($_) || $check->($_);
    };
};



package
    Mouse::Meta::Module;

sub name          { $_[0]->{package} }

sub _method_map   { $_[0]->{methods} }
sub _attribute_map{ $_[0]->{attributes} }

sub namespace{
    my $name = $_[0]->{package};
    no strict 'refs';
    return \%{ $name . '::' };
}

sub add_method {
    my($self, $name, $code) = @_;

    if(!defined $name){
        $self->throw_error('You must pass a defined name');
    }
    if(!defined $code){
        $self->throw_error('You must pass a defined code');
    }

    if(ref($code) ne 'CODE'){
        $code = \&{$code}; # coerce
    }

    $self->{methods}->{$name} = $code; # Moose stores meta object here.

    my $pkg = $self->name;
    no strict 'refs';
    no warnings 'redefine', 'once';
    *{ $pkg . '::' . $name } = $code;
    return;
}


package
    Mouse::Meta::Class;

sub is_anon_class{
    return exists $_[0]->{anon_serial_id};
}

sub roles { $_[0]->{roles} }

sub linearized_isa { @{ get_linear_isa($_[0]->{package}) } }

sub get_all_attributes {
    my($self) = @_;
    my %attrs = map { %{ $self->initialize($_)->{attributes} } } reverse $self->linearized_isa;
    return values %attrs;
}

package
    Mouse::Meta::Role;

sub is_anon_role{
    return exists $_[0]->{anon_serial_id};
}

sub get_roles { $_[0]->{roles} }

package
    Mouse::Meta::Attribute;

use Mouse::Meta::Method::Accessor;

# readers

sub name                 { $_[0]->{name}                   }
sub associated_class     { $_[0]->{associated_class}       }

sub accessor             { $_[0]->{accessor}               }
sub reader               { $_[0]->{reader}                 }
sub writer               { $_[0]->{writer}                 }
sub predicate            { $_[0]->{predicate}              }
sub clearer              { $_[0]->{clearer}                }
sub handles              { $_[0]->{handles}                }

sub _is_metadata         { $_[0]->{is}                     }
sub is_required          { $_[0]->{required}               }
sub default              { $_[0]->{default}                }
sub is_lazy              { $_[0]->{lazy}                   }
sub is_lazy_build        { $_[0]->{lazy_build}             }
sub is_weak_ref          { $_[0]->{weak_ref}               }
sub init_arg             { $_[0]->{init_arg}               }
sub type_constraint      { $_[0]->{type_constraint}        }

sub trigger              { $_[0]->{trigger}                }
sub builder              { $_[0]->{builder}                }
sub should_auto_deref    { $_[0]->{auto_deref}             }
sub should_coerce        { $_[0]->{coerce}                 }

sub documentation        { $_[0]->{documentation}          }

# predicates

sub has_accessor         { exists $_[0]->{accessor}        }
sub has_reader           { exists $_[0]->{reader}          }
sub has_writer           { exists $_[0]->{writer}          }
sub has_predicate        { exists $_[0]->{predicate}       }
sub has_clearer          { exists $_[0]->{clearer}         }
sub has_handles          { exists $_[0]->{handles}         }

sub has_default          { exists $_[0]->{default}         }
sub has_type_constraint  { exists $_[0]->{type_constraint} }
sub has_trigger          { exists $_[0]->{trigger}         }
sub has_builder          { exists $_[0]->{builder}         }

sub has_documentation    { exists $_[0]->{documentation}   }

sub accessor_metaclass(){ 'Mouse::Meta::Method::Accessor' }

package
    Mouse::Meta::TypeConstraint;

sub name    { $_[0]->{name}    }
sub parent  { $_[0]->{parent}  }
sub message { $_[0]->{message} }

sub _compiled_type_constraint{ $_[0]->{compiled_type_constraint} }

sub _compiled_type_coercion  { $_[0]->{_compiled_type_coercion}  }

sub has_coercion{ exists $_[0]->{_compiled_type_coercion} }


sub compile_type_constraint{
    my($self) = @_;

    # add parents first
    my @checks;
    for(my $parent = $self->{parent}; defined $parent; $parent = $parent->{parent}){
         if($parent->{hand_optimized_type_constraint}){
            unshift @checks, $parent->{hand_optimized_type_constraint};
            last; # a hand optimized constraint must include all the parents
        }
        elsif($parent->{constraint}){
            unshift @checks, $parent->{constraint};
        }
    }

    # then add child
    if($self->{constraint}){
        push @checks, $self->{constraint};
    }

    if($self->{type_constraints}){ # Union
        my @types = map{ $_->{compiled_type_constraint} } @{ $self->{type_constraints} };
        push @checks, sub{
            foreach my $c(@types){
                return 1 if $c->($_[0]);
            }
            return 0;
        };
    }

    if(@checks == 0){
        $self->{compiled_type_constraint} = \&Mouse::Util::TypeConstraints::Any;
    }
    else{
        $self->{compiled_type_constraint} =  sub{
            my(@args) = @_;
            local $_ = $args[0];
            foreach my $c(@checks){
                return undef if !$c->(@args);
            }
            return 1;
        };
    }
    return;
}

package
    Mouse::Object;


sub BUILDARGS {
    my $class = shift;

    if (scalar @_ == 1) {
        (ref($_[0]) eq 'HASH')
            || $class->meta->throw_error("Single parameters to new() must be a HASH ref");

        return {%{$_[0]}};
    }
    else {
        return {@_};
    }
}

1;
__END__

=head1 NAME

Mouse::PurePerl - A Mouse guts in pure Perl

=head1 VERSION

This document describes Mouse version 0.40_05

=head1 SEE ALSO

L<Mouse::XS>

=cut
