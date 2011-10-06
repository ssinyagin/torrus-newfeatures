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
	'Digest::MD5'     => { can => [ qw( new md5_hex ) ] },
	'Digest::SHA1'    => { can => [ qw( sha1 ) ] },
	'Errno'           => { import => [ qw(
		EAGAIN
	) ] },
	'File::Spec'      => { can => [ qw( catfile catdir ) ] },
	'File::Temp'      => { can => [ qw( tempdir ) ] },
	'IO::Handle'      => { can => [ qw( new ) ] },
	'IO::File'        => { can => [ qw( new ) ] },
	'IO::Socket'      => {},
	'MIME::Base64'    => { can => [ qw( encode_base64 decode_base64 ) ] },
	'POSIX'           => { import => [ qw(
		:sys_wait_h SIGALRM SIGTERM SIGKILL _exit
	) ] },
	'Socket'          => { exports => [ qw( PF_UNIX SOCK_STREAM ) ] },
	'Symbol'          => { import => [ qw( delete_package ) ] },
	'Test::File'      => { exports => [ qw(
		file_empty_ok file_exists_ok file_not_exists_ok
		file_mode_is
		symlink_target_dangles_ok symlink_target_exists_ok
		owner_is
	) ] },
	'Test::Files'     => { exports => [ qw(
		file_ok compare_ok dir_contains_ok dir_only_contains_ok
	) ] },
	'Test::Trap'      => { exports => [ qw( trap $trap ) ] },
	'Time::ParseDate' => { exports => [ qw( parsedate ) ] },
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
