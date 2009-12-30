#!perl
#
use strict;
use warnings;
use Test::More tests => 8;
use Test::WWW::Mechanize::CGI;
use lib './t';
use Common;
use App::Blumenkraft;

my $datadir = './t/smoketest/data';
touch_files($datadir);

my $mech = Test::WWW::Mechanize::CGI->new;
$mech->cgi(sub {
    my $app = App::Blumenkraft->new(
        datadir       => $datadir,
        blog_encoding => 'ISO-8859-1',
    );
    $app->run_dynamic;
});

{
    $mech->get_ok('http://localhost/');
    is ($mech->content_type, 'text/html', 'HTML content type')
        || diag $mech->content_type;
    is ($mech->response->content_charset, 'ISO-8859-1', 'HTML encoding')
        || diag $mech->response->content_charset;
    my $expected = slurp('./t/smoketest/expected.html');
    $mech->content_is($expected, 'expected HTML') || diag $mech->content;
}

{
    $mech->get_ok('http://localhost/?flav=rss');
    is ($mech->content_type, 'text/xml', 'RSS content type')
        || diag $mech->content_type;
    is ($mech->response->content_charset, 'ISO-8859-1', 'RSS encoding')
        || diag $mech->response->content_charset;
    my $expected = slurp('./t/smoketest/expected.rss');
    $mech->content_is($expected, 'expected RSS') || diag $mech->content;
}
