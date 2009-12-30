#!perl
#
# Testing plugin loading
#
use strict;
use warnings;
use Test::More tests => 1;
use Test::WWW::Mechanize::CGI;
use lib './t';
use Common;
use App::Blumenkraft;

my $datadir = './t/plugins/data';
touch_files($datadir);

my $plugin_list = [
# Bare
'plugin1',

'plugin3_',

'plugin2',

# 'plugin4',

'plugin5', # doesn't start

# Real plugin - dump the list of plugins
'dump_plugins',

];

my $mech = Test::WWW::Mechanize::CGI->new;
$mech->cgi(sub {
    my $app = App::Blumenkraft->new(
        blog_title    => 'plugin_list test',
        datadir       => $datadir,
        blog_encoding => 'ISO-8859-1',
        plugin_list   => $plugin_list,
        plugin_path   => 't/plugins/plugins1:t/plugins/plugins2',
    );
    $app->run_dynamic;
});


{
    $mech->get('http://localhost/');
    my $expected = slurp('./t/plugins/expected.html');
    $mech->content_is($expected, 'expected HTML') || diag $mech->content;
}

