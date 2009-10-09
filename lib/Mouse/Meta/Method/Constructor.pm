package Mouse::Meta::Method::Constructor;
use Mouse::Util; # enables strict and warnings

sub _generate_constructor {
    my ($class, $metaclass, $args) = @_;

    my $associated_metaclass_name = $metaclass->name;

    my @attrs         = $metaclass->get_all_attributes;

    my $buildall      = $class->_generate_BUILDALL($metaclass);
    my $buildargs     = $class->_generate_BUILDARGS($metaclass);
    my $processattrs  = $class->_generate_processattrs($metaclass, \@attrs);

    my @checks = map { $_ && $_->_compiled_type_constraint }
                 map { $_->type_constraint } @attrs;

    my $source = sprintf("#line %d %s\n", __LINE__, __FILE__).<<"...";
        sub \{
            my \$class = shift;
            return \$class->Mouse::Object::new(\@_)
                if \$class ne q{$associated_metaclass_name};
            # BUILDARGS
            $buildargs;
            my \$instance = bless {}, \$class;
            # process attributes
            $processattrs;
            # BUILDALL
            $buildall;
            return \$instance;
        }
...
    #warn $source;
    my $code;
    my $e = do{
        local $@;
        $code = eval $source;
        $@;
    };
    die $e if $e;
    return $code;
}

sub _generate_processattrs {
    my ($class, $metaclass, $attrs) = @_;
    my @res;

    my $has_triggers;

    for my $index (0 .. @$attrs - 1) {
        my $code = '';

        my $attr = $attrs->[$index];
        my $key  = $attr->name;

        my $init_arg        = $attr->init_arg;
        my $type_constraint = $attr->type_constraint;
        my $need_coercion;

        my $instance_slot  = "\$instance->{q{$key}}";
        my $attr_var       = "\$attrs[$index]";
        my $constraint_var;

        if(defined $type_constraint){
             $constraint_var = "$attr_var\->{type_constraint}";
             $need_coercion  = ($attr->should_coerce && $type_constraint->has_coercion);
        }

        $code .= "# initialize $key\n";

        my $post_process = '';
        if(defined $type_constraint){
            $post_process .= "\$checks[$index]->($instance_slot)";
            $post_process .= "  or $attr_var->verify_type_constraint_error(q{$key}, $instance_slot, $constraint_var);\n";
        }
        if($attr->is_weak_ref){
            $post_process .= "Scalar::Util::weaken($instance_slot) if ref $instance_slot;\n";
        }

        if (defined $init_arg) {
            my $value = "\$args->{q{$init_arg}}";

            $code .= "if (exists $value) {\n";

            if($need_coercion){
                $value = "$constraint_var->coerce($value)";
            }

            $code .= "$instance_slot = $value;\n";
            $code .= $post_process;

            if ($attr->has_trigger) {
                $has_triggers++;
                $code .= "push \@triggers, [$attr_var\->{trigger}, $instance_slot];\n";
            }

            $code .= "\n} else {\n";
        }

        if ($attr->has_default || $attr->has_builder) {
            unless ($attr->is_lazy) {
                my $default = $attr->default;
                my $builder = $attr->builder;

                my $value;
                if (defined($builder)) {
                    $value = "\$instance->$builder()";
                }
                elsif (ref($default) eq 'CODE') {
                    $value = "$attr_var\->{default}->(\$instance)";
                }
                elsif (defined($default)) {
                    $value = "$attr_var\->{default}";
                }
                else {
                    $value = 'undef';
                }

                if($need_coercion){
                    $value = "$constraint_var->coerce($value)";
                }

                $code .= "$instance_slot = $value;\n";
            }
        }
        elsif ($attr->is_required) {
            $code .= "Carp::confess('Attribute ($key) is required');";
        }

        $code .= "}\n" if defined $init_arg;

        push @res, $code;
    }

    if($metaclass->is_anon_class){
        push @res, q{$instnace->{__METACLASS__} = $metaclass;};
    }

    if($has_triggers){
        unshift @res, q{my @triggers;};
        push    @res,  q{$_->[0]->($instance, $_->[1]) for @triggers;};
    }

    return join "\n", @res;
}

sub _generate_BUILDARGS {
    my(undef, $metaclass) = @_;

    my $class = $metaclass->name;
    if ( $class->can('BUILDARGS') && $class->can('BUILDARGS') != \&Mouse::Object::BUILDARGS ) {
        return 'my $args = $class->BUILDARGS(@_)';
    }

    return <<'...';
        my $args;
        if ( scalar @_ == 1 ) {
            ( ref( $_[0] ) eq 'HASH' )
                || Carp::confess "Single parameters to new() must be a HASH ref";
            $args = +{ %{ $_[0] } };
        }
        else {
            $args = +{@_};
        }
...
}

sub _generate_BUILDALL {
    my (undef, $metaclass) = @_;

    return '' unless $metaclass->name->can('BUILD');

    my @code;
    for my $class ($metaclass->linearized_isa) {
        no strict 'refs';
        no warnings 'once';

        if (*{ $class . '::BUILD' }{CODE}) {
            unshift  @code, qq{${class}::BUILD(\$instance, \$args);};
        }
    }
    return join "\n", @code;
}

1;
__END__
