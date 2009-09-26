package Mouse::Exporter;
use strict;
use warnings;

use Carp 'confess';
use Scalar::Util qw(looks_like_number);

use Mouse::Util qw(not_supported);

sub init_meta {
    shift;
    my %args = @_;

    my $class = $args{for_class}
                    or confess("Cannot call init_meta without specifying a for_class");
    my $base_class = $args{base_class} || 'Mouse::Object';
    my $metaclass  = $args{metaclass}  || 'Mouse::Meta::Class';

    confess("The Metaclass $metaclass must be a subclass of Mouse::Meta::Class.")
            unless $metaclass->isa('Mouse::Meta::Class');

    # make a subtype for each Mouse class
    Mouse::Util::TypeConstraints::class_type($class)
        unless Mouse::Util::TypeConstraints::find_type_constraint($class);

    my $meta = $metaclass->initialize($class);

    $meta->add_method(meta => sub{
        return $metaclass->initialize(ref($_[0]) || $_[0]);
    });

    $meta->superclasses($base_class)
        unless $meta->superclasses;

    return $meta;
}

sub do_import {
    my($class, $spec, @args) = @_;

    my $command;

    my @exports;
    foreach my $arg(@args){
        if(ref $arg){ # e.g. use Mouse { into => $package };
            $command = $arg;
        }
        elsif($arg =~ s/^[-:]//){
            my $group = $spec->{group}{$arg} or confess(qq{group "$arg" is not exported by the $class module});
            push @exports, @{$group};
        }
        else{
            push @exports, $arg;
        }
    }

    my $into = $command->{into} || caller(($command->{into_level} || 0) + 1);

    strict->import;
    warnings->import;

    if($into eq 'main' && !$spec->{_not_export_to_main}){
        warn qq{$class does not export its sugar to the 'main' package.\n};
        return;
    }

    $class->init_meta(
        for_class  => $into,
    );

    my $exports_ref = @exports ? \@exports : $spec->{default};

    foreach my $keyword(@{$exports_ref}){
        no strict 'refs';
        *{$caller.'::'.$keyword} = $spec->{exports}{$keyword}
            or confess(qq{"$keyword" is not exported by the $class module};
    }
    return;
}

sub do_unimport {
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
}

1;

__END__

=head1 NAME

Mouse - The Mouse Exporter

=head1 SYNOPSIS

    package MouseX::Foo;
    use Mouse::Exporter;

    Mouse::Exporter->setup_import_methods(

    );

=head1 DESCRIPTION


=head1 SEE ALSO

L<Moose::Exporter>

=head1 AUTHORS

Goro Fuji (gfx) C<< <gfuji at cpan.org> >>

=cut

