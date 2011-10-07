#!/usr/bin/perl

use strict;
use warnings;

use Test::More;
BEGIN {
    eval 'use Test::HasVersion 0.012; 1'
        or plan skip_all => 'Test::HasVersion >= 0.012 not available';
}

all_pm_version_ok;


