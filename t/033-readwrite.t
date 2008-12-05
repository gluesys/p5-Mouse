#!/usr/bin/env perl
use strict;
use warnings;
use Test::More tests => 4;
use Mouse::Util ':test';

do {
    package Class;
    use Mouse;

    # We want this attr to have a reader and writer with unconventional names,
    # and not the default rw_attr method. -- rjbs, 2008-12-04
    has 'rw_attr' => (
        reader => 'read_attr',
        writer => 'write_attr',
    );;
};

my $object = Class->new;

ok(!$object->can('rw_attr'), "no rw_attr method because wasn't 'is' ro or rw");
ok($object->can('read_attr'),  "did get a reader");
ok($object->can('write_attr'), "did get a writer");

$object->write_attr(2);

is($object->read_attr, 2, "writing to the object worked");

