#!/usr/bin/perl

use strict;
use warnings;

use Test::More;

BEGIN {

if ( not $ENV{TEST_AUTHOR} ) {

    my $msg = 'Author test.  Set $ENV{TEST_AUTHOR} to a true value to run.';
    plan( skip_all => $msg );

} else {

    eval 'use Test::Pod::Coverage 1.00; 1'
        or plan skip_all => 'Test::Pod::Coverage >= 1.00 not available';

}

}

my @modules = all_modules;
plan tests => scalar @modules;

my %override = (
	map(+($_ => { todo => 'Not documented yet' }), qw(
	)),

#	'Foo:Bar' => {
#		trustme => [ qr/^(_\w+)$/ ],
#	},

);

for (@modules) {
	my $override = $override{$_} || {};
	TODO: {
		local $TODO = $override->{todo} if $override->{todo};
		pod_coverage_ok($_, {
			coverage_class => 'Pod::Coverage::CountParents',
			trustme        => $override->{trustme} || [],
		});
	};
}
