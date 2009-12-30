#!perl
#
use warnings;
use strict;
use Test::More tests => 1;

BEGIN {
    use_ok('App::Blumenkraft');
}

diag(
    "Testing App:Blumenkraft $App::Blumenkraft::VERSION, Perl $], $^X"
);
