#!/usr/bin/perl

# Check distribution for Kwalitee
use strict;
BEGIN {
	$|  = 1;
	$^W = 1;
}

my @MODULES = (
	'Test::Kwalitee tests => [ qw( -has_test_pod -has_test_pod_coverage ) ]',
);

# Don't run tests during end-user installs
use Test::More;
unless ( $ENV{AUTOMATED_TESTING} or $ENV{RELEASE_TESTING} ) {
	plan( skip_all => "Author tests not required for installation" );
}

# Load the testing modules
foreach my $MODULE ( @MODULES ) {
	eval "use $MODULE";
	if ( $@ ) {
		$ENV{RELEASE_TESTING}
		? die( "Failed to load required release-testing module $MODULE" )
		: plan( skip_all => "$MODULE not available for testing" );
	}
}

END {
    if ( -f 'Debian_CPANTS.txt') {
        unlink 'Debian_CPANTS.txt' or die "$!\n";
    }
}

1;

