#!perl
#
use strict;
use warnings;
use English qw( -no_match_vars );
use File::Path qw( rmtree );
use Test::More tests => 3;
use lib './t';
use Common;
use App::Blumenkraft;

my $testdir = './t/static_basic';
touch_files("$testdir/data");

my $app = App::Blumenkraft->new(
    datadir         => "$testdir/data",
    url             => "http://localhost/",
    static_dir      => "$testdir/static",
    static_password => 'static',
    static_flavours => [qw/ html rss /],
);
$app->run_static(password => 'static', quiet => 0, all => 1,);

my (@different, @extra, @missing);

compare_trees(
    "$testdir/expected", "$testdir/static", \@different, \@extra, \@missing
);
is(scalar @different, 0, 'different files') || diag join "\n", @different;
is(scalar @extra, 0, 'extra files') || diag join "\n", @extra;
is(scalar @missing, 0, 'missing files') || diag join "\n", @missing;


END {
    if ( -d "$testdir/static" ) {
        rmtree "$testdir/static" || die "$OS_ERROR\n";
    }
}
