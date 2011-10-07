#!/usr/bin/perl

use strict;
use warnings;

use Test::More;
use File::Spec;

unless ( $ENV{TEST_AUTHOR} ) {
    my $msg = 'Author test.  Set $ENV{TEST_AUTHOR} to a true value to run.';
    plan( skip_all => $msg );
}

eval { require Test::Perl::Critic; };
plan(skip_all=>'Test::Perl::Critic required to critique code') if $@;

my $rcfile = File::Spec->catfile( 't', '.perlcriticrc' );
Test::Perl::Critic->import(
    -profile    => $rcfile,
    -verbose    => 9,           # verbose 6 will hide rule name
);

all_critic_ok();
