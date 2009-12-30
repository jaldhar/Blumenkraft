use strict;
use warnings;
use Module::Build;

my $builder = Module::Build->new(
    module_name         => 'App::Blumenkraft',
    license             => 'perl',
    dist_author         => 'Jaldhar H. Vyas <jaldhar@braincells.com>',
    dist_version_from   => 'lib/App/Blumenkraft.pm',
    build_requires => {
        'CGI'                           => 3.12,
        'Test::LongString'              => 0,
        'Test::More'                    => 0,
        'Test::WWW::Mechanize::CGI'     => 0,
        'Time::Piece'                   => 0,
    },
    requires => {
        'perl'                          => 5.010,
        'CGI'                           => 3.12,
        'Time::Piece'                   => 0,
    },
    add_to_cleanup      => [ 'App-Blumenkraft-*' ],
    create_makefile_pl  => 'traditional',
    sign                => 1,
);

$builder->create_build_script();

