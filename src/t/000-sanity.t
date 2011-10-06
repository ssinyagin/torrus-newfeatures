#!/usr/bin/perl

use strict;
use strict;

eval 'require Test::More' or do {
	print "Bail out! Test::More not available\n";
	exit 1;
};

import Test::More qw( no_plan );

$::{can_ok} or
	die "Bail out! Test::More did not export can_ok\n";

can_ok('main', qw(
	ok use_ok require_ok
	is isnt like unlike is_deeply
	skip
	pass fail
	plan
	can_ok isa_ok
)) or die("Bail out! Test::More did not export all necessary functions\n");

my %requires = (

#Apache2::ServerUtil
#BerkeleyDB
#CGI
#CGI::Fast
#Data::Dumper
#Date::Format
#Date::Parse
#DBI
#DBIx::Abstract

	'Digest::MD5'     => { can => [ qw( new md5_hex ) ] }, # FIXME: need to check which other functions we need

#Fcntl
#File::Copy
#File::Find
#Getopt::Long
#IO::Dir
#JSON
#Math::BigFloat
#Math::BigInt
#mod_perl2
#Net::hostent
#Net::SNMP  Net::SNMP qw(:snmp :asn1);

	'POSIX'           => { can => [ qw( abs log floor pow strftime ) ] },

#Proc::Daemon
#RRDs

	'Socket'          => { exports => [ qw( inet_ntoa ) ] },
        'Sys::Hostname'   => { exports => [ qw( hostname ) ] },

#Template
#Text::Tabs
#threads
#URI::Escape
#XML::LibXML

);

my $bail;
for my $module (sort keys %requires) {
	my $spec = $requires{$module};
	SKIP: {
		ok(scalar eval "require $module", "$module could be required")
			or do { warn "# $@"; $bail++; skip("$module not available", 3) };

		if (my $can = $spec->{can}) {
			can_ok($module, @$can)
				or $bail++;
		}

		my $import = $spec->{import} || [];
		ok(scalar eval { $module->import(@$import); 1 }, "$module could be imported")
			or do { warn "# $@"; $bail++ };

		my (@subs, %vars);
		if (my $exports = $spec->{exports}) {
			foreach (@$exports) {
				/^\$(.*)/ and do { $vars{$1} = 'SCALAR'; next };
				/^\@(.*)/ and do { $vars{$1} = 'ARRAY'; next };
				/^%(.*)/  and do { $vars{$1} = 'HASH'; next };
				/^&?(.*)/ and do { push @subs, $1; next };
				die "# Weird export for $module: $exports\n";
			}
		}
		if (@subs) {
			can_ok('main', @subs)
				or $bail++;
		}
		if (%vars) {
			my @missing;
			while (my ($k, $v) = each %vars) {
				push @missing, "$v $k" unless eval "*${k}" . "{$v}";
			}
			if (@missing) {
				fail("$module did not export: @missing");
				$bail++;
			} else {
				pass("$module exported all expected variables");
			}
		}
	}
}

not $bail
	or die "Bail out! Not all test facilities are available\n";
