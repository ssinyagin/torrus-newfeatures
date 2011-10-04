#!/usr/bin/perl

use warnings;
use strict;

use Test::More;

BEGIN {

unless ( $ENV{TEST_AUTHOR} ) {
    my $msg = 'Author test.  Set $ENV{TEST_AUTHOR} to a true value to run.';
    plan( skip_all => $msg );
}

eval 'use Test::Spelling; 1'
    or plan skip_all => 'Test::Spelling not available';

}

all_pod_files_spelling_ok();
