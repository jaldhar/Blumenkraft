
=head1 NAME

App::Blumenkraft - a simple weblog

=head1 SYNOPSIS

    use App::Blumenkraft;
    
    # run as a CGI script;
    my $app = App::Blumenkraft->new();
    $app->run_dynamic();

    # or perhaps create static pages from a cron job.
    use App::Blumenkraft;
    my $app = App::Blumenkraft->new();
    $app->run_static(password =>'1234', quiet => 0, all => 1);
    
        
=head1 ABSTRACT

Blumenkraft is a simple weblog application.  It is modular, extensible, and
does not require any other software than perl 5.10.

=cut

package App::Blumenkraft;

use 5.010;
use strict;
use warnings;
use Carp qw/ croak /;
use English qw/ -no_match_vars /;
use Fcntl qw/ SEEK_SET /;
use FileHandle;
use File::stat;
use Module::Load;
use Time::Piece;

=head1 VERSION

This document describes App::Blumenkraft Version 0.1

=cut

our $VERSION = '0.1';

=head1 DESCRIPTION

Blumenkraft is based on the popular Blosxom weblog script.  Like Blosxom, 
Blumenkraft can create static files or be run as a CGI script.  By default it 
creates HTML and RSS 2.0 but any number of new flavors can be added if you 
like.  It is very extensible via plugins.

Unlike Blosxom, Blumenkraft is an object-oriented  Perl module.  It is written
in a much more concise and clear dialect of perl and makes good use of the
features available in Perl 5.10.

=head1 METHODS

=head2 new($class, %opt)

Constructs a new App::Blumenkraft object. C<%opt> can contain the following
options:

=over 4

=item * C<blog_title>
   
What's this blog's title?

Default: 'My Weblog'

=item * C<blog_description>

What's this blog's description? (For outgoing RSS feed.)

Default: 'Yet another Blumenkraft weblog'

=item * C<blog_language>

What's this blog's primary language? (For outgoing RSS feed.)

Default: 'en'

=item * C<blog_encoding>

What's this blog's text encoding?

Default: 'UTF-8'

=item * C<datadir>

Where are this blog's entries kept?  (This is the one configuration option
you'll definitely want to change.)

Default: '/home/jaldhar/blumenkraft'

=item * C<url>

What's my preferred base URL for this blog? (leave blank for automatic.)

Default: <blank>

=item * C<depth>

Should Blumenkraft stick only to the datadir for items or travel down the
directory hierarchy looking for items?  If so, to what depth?
    0 = infinite depth (aka grab everything), 
    1 = datadir only,
    n = n levels down

Default: 0

=item * C<num_entries>

How many entries should Blumenkraft show on the home page?

Default: 40

=item * C<file_extention>

What file extension signifies a Blumenkraft entry?

Default: 'txt'

=item * C<default flavor>

What is the default flavor?

Default: 'html'

=item * C<show_future_entries>

Should Blumenkraft show entries from the future (i.e. dated after now)?
    1 = yes
    0 = no
    
Default: 0

=item * C<plugin_list>

A list of plugins Blumenkraft should load (if empty Blumenkraft will load 
all plugins in C<plugin_path> directories)

Default: <blank>

=item * C<plugin_path>

Additional plugin locations. A List of directories, separated by ';' on 
windows, ':' everywhere else

Default: <blank>

=item * C<plugin_state_dir>

Where should modules keep their state information?

Default: <blank>

=item * C<static_dir>

Where are this blog's static files to be created?

Default: '/home/jaldhar/blog',

=item * C<static_password>

What's the administrative password? (you must set this for static rendering)

Default: <blank>

=item * C<static_flavors>

What flavors should Blumenkraft generate statically?

Default: html rss

=item * C<static_entries>

Should Blumenkraft statically generate individual entries?
    0 = no
    1 = yes

Default: 0

=item * C<encode_xml_entities>

Should Blumenkraft encode entities for xml content-types? (plugins can turn 
this off if they do it themselves)
    0 = no
    1 = yes

Default: 1

=item * C<days>

day abbreviations

Default: Sun Mon Tue Wed Thu Fri Sat

=item * C<months>

month abbreviations

Default: Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec

=item * C<time_zone>

time zone

Default: The value of the TZ environment variable or UTC if TZ is not set.

=item * C<cgi_class>

CGI object class

Default: CGI

=back

=cut

sub new {
    my ( $class, %opt ) = @_;

    my %default = (
        blog_title          => 'My Weblog',
        blog_description    => 'Yet another Blumenkraft weblog.',
        blog_language       => 'en',
        blog_encoding       => 'UTF-8',
        datadir             => '/home/jaldhar/blumenkraft',
        url                 => q{},
        depth               => 0,
        num_entries         => 40,
        file_extension      => 'txt',
        default_flavor      => 'html',
        show_future_entries => 0,
        plugin_list         => [],
        plugin_path         => q{},
        plugin_state_dir    => q{},
        static_dir          => '/home/jaldhar/blog',
        static_password     => q{},
        static_flavors      => [qw/ html rss /],
        static_entries      => 0,
        encode_xml_entities => 1,
        days                => [qw/ Sun Mon Tue Wed Thu Fri Sat /],
        months    => [qw/ Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec /],
        tz        => $ENV{TZ} // 'UTC',
        cgi_class => 'CGI',
    );

    # initialize the class and bless it.
    my $self = {};
    map { $self->{$_} = $opt{$_} // $default{$_} } keys %default;

    # This is dealt with seperately because it depends on datadir
    $self->{plugin_state_dir} = $opt{plugin_state_dir} // join q{/},
      ( $self->{datadir}, '.state' );

    bless $self, $class;

    # Drop ending any / from dir settings
    foreach my $dir (qw/ datadir static_dir /) {
        if ( $self->{$dir} ) {
            $self->{$dir} =~ s{/$}{}msx;
        }
    }

    # Fix depth to take into account datadir's path
    if ( $self->{depth} ) {
        $self->{depth} += ( $self->{datadir} =~ tr[/][] - 1 );
    }

    # Bring in the default templates
    seek DATA, 0, SEEK_SET;
    while (<DATA>) {
        last if ( $_ eq '__END__' );
        if (/^(?<ct>\S+)\s(?<comp>\S+)(?:\s( ?<txt>.*))?$/mx)
        {    ## no critic 'RequireDotMatchAnything'
            $LAST_PAREN_MATCH{txt} =~ s/\\n/\n/mgsx;
            $self->{template}->{ $LAST_PAREN_MATCH{ct} }
              ->{ $LAST_PAREN_MATCH{comp} } .= "$LAST_PAREN_MATCH{txt}\n";
        }
    }

    $ENV{TZ} = $self->{tz};

    # Date fiddling
    my $mo_num = 1;
    foreach my $month ( @{ $self->{months} } ) {
        $self->{mon2num}->{$month} = sprintf '%02d', $mo_num++;
    }
    push @{ $self->{num2month} },
      sort { $self->{mon2num}->{$a} <=> $self->{mon2num}->{$b} }
      keys %{ $self->{mon2num} };

    # Plugins: Start
    my $path_sep = $OSNAME eq 'MSWin32' ? q{;} : q{:};
    my @plugin_path = split /$path_sep/msx, $self->{plugin_path};
    local @INC = @INC;
    unshift @INC, @plugin_path;

    my @plugin_list;
    foreach ( @{ $self->{plugin_list} } ) {
        my $plugin = "App::Blumenkraft::Plugin::$_";
        next if $plugin =~ /[ _ ~ ] \z/msx;
        if ( !eval { load $plugin } && $plugin->start ) {
            push @plugin_list, $plugin;
        }
    }
    $self->{plugin_list} = \@plugin_list;

    $self->_override_subs;

    return $self;
}

# Allow for the first encountered plugin::template subroutine to override
# the default built-in template subroutine

# Allow for the first encountered plugin::entries subroutine to override
# the default built-in entries subroutine

# Allow for the first encountered plugin::interpolate subroutine to
# override the default built-in interpolate subroutine

# Allow for the first encountered plugin::sort subroutine to override
# the default built-in sort subroutine

sub _override_subs {
    my ($self) = @_;

    foreach my $sub (qw/ template entries interpolate sort /) {
        foreach my $plugin ( @{ $self->{plugin_list} } ) {
            if ( $plugin->can($sub) ) {
                $self->$sub = $plugin->$sub;
                last;
            }
        }
    }

    return;
}

=head2 check_password($password)

Returns true if C<$password> matches C<static_password> from the configuration
or false if it does not.

=cut

sub check_password {
    my ( $self, $password ) = @_;

    if (   $password
        && $self->{static_password}
        && $password eq $self->{static_password} )
    {
        return 1;
    }
    return;
}

=head2 entries($base, $all)

Starting from C<$base> (which should be a directory) this routine recurses
through the filesystem, calling L<find> on each file.  Files beginning with
C<.> or C<..> are ignored.  The C<$all> flag is passed to L<find> if present.

=cut

sub entries {
    my ( $self, $base, $all ) = @_;

    my $DIR;

    if ( -d $base ) {
        my $file;
        if ( !opendir $DIR, $base ) {
            carp("Couldn't open directory $base: $OS_ERROR; skipping.\n");
            return;
        }

        while ( $file = readdir $DIR ) {
            next if $file eq q{.} || $file eq q{..};
            $self->entries( "$base/$file", $all );
        }
    }
    else {
        return $self->find( $base, $all );
    }

    return;
}

=head2 find($file, $all)

Examines C<$file> to see if it needs to be rendered.  The C<$all> argument is 
true if all static files need to be rendered.  (See L<run_static>.) if it is 
false, only static files which are out of date or do not already exist will be 
rendered.

=cut

sub find {
    my ( $self, $file, $all ) = @_;

    my $curr_depth = $file =~ tr[/][];
    return if $self->{depth} and $curr_depth > $self->{depth};

    # read modification time
    my $mtime = stat($file)->mtime || return;

    if (

        # a match
        $file =~ m{
            \A $self->{datadir} / 
            (?:(?<path>.*)/)? (?<filename>.+) 
            \.$self->{file_extension} \z }msx
      )
    {
        my $path     = $LAST_PAREN_MATCH{path}     || q{};
        my $filename = $LAST_PAREN_MATCH{filename} || q{};

        # not an index, .file, and is readable
        if ( $filename ne 'index' && $filename !~ /\A\./msx && -r $file ) {

            # to show or not to show future entries
            if ( $self->{show_future_entries} || $mtime < time ) {

                # add the file and its associated mtime to the list of files
                $self->{files}->{$file} = $mtime;
            }

            # static rendering bits
            my $static_file =
              "$self->{static_dir}/$path/index.$self->{static_flavors}->[0]";

            if (   $all
                || !-f $static_file
                || stat($static_file)->mtime < $mtime )
            {
                $self->{indexes}->{$path} = 1;
                my $date = Time::Piece->new($mtime)->ymd(q{/});
                $self->{indexes}->{$date} = $date;
                if ( $self->{static_entries} ) {
                    $self->{indexes}->{ ( $path ? "$path/" : q{} )
                          . "$filename.$self->{file_extension}" } = 1;
                }
            }
        }
    }

    # not an entries match
    elsif ( !-d -r $file ) {
        $self->{others}->{$file} = $mtime;
    }

    return;
}

=head2 generate(\%vars)

This method returns generated output to the L<run_dynamic> or L<run_static> 
methods.  The contents of C<%vars> are interpolated into templates during the
generation process via the L<interpolate> method.

=cut

sub generate {
    my ( $self, $vars ) = @_;

    my $output = q{};
    my %files  = %{ $self->{files} };
    my %others = ref $self->{others} ? %{ $self->{others} } : ();

    # Plugins: Filter
    foreach my $plugin ( @{ $self->{plugin_list} } ) {
        if ( $plugin->can('filter') ) {
            plugin->filter( \%files, \%others );
        }
    }

    # Plugins: Skip
    # Allow plugins to decide if we can cut short story generation
    my $skip;
    foreach my $plugin ( @{ $self->{plugin_list} } ) {
        if ( $plugin->can('skip') ) {
            $skip = plugin->skip;
            last;
        }
    }

    if ( !defined($skip) || !$skip ) {

        # Head
        $output .= $self->_generate_head($vars);

        # Stories + Dates
        if ( $vars->{currentdir} =~
            /(?<path>.*?)(?<filename>[^\/]+)\.(?<extension>.+)\z/msx
            && $LAST_PAREN_MATCH{filename} ne 'index' )
        {
            $vars->{currentdir} =
"$LAST_PAREN_MATCH{path}$LAST_PAREN_MATCH{filename}.$self->{file_extension}";
        }
        else {
            $vars->{currentdir} =~ s{/index\..+$}{}msx;
        }
        $output .= $self->_generate_body($vars);

        # Foot
        $output .= $self->_generate_foot($vars);

        # Plugins: Last
        foreach my $plugin ( @{ $self->{plugin_list} } ) {
            if ( $plugin->can('last') ) {
                my $entries = $plugin->last();
            }
        }
    }    # End skip

    return $output;
}

sub _generate_head {
    my ( $self, $vars ) = @_;

    my $head = $self->template( $vars->{currentdir}, 'head', $vars->{flavor} );

    # Plugins: Head
    foreach my $plugin ( @{ $self->{plugin_list} } ) {
        if ( $plugin->can('head') ) {
            my $entries = $plugin->head( $vars, $head );
        }
    }

    return $self->interpolate( $head, $vars );
}

sub _generate_body {
    my ( $self, $vars ) = @_;

    my $output  = q{};
    my $curdate = q{};
    my $ne      = $self->{num_entries};

    foreach my $path_file ( $self->sort( $self->{files}, $self->{others} ) ) {
        last
          if $ne <= 0
              && (
                  join q{/},
                  (
                      $vars->{path_info_yr}, $vars->{path_info_mo_num},
                      $vars->{path_info_da}
                  )
              ) !~ /\d/msx;

        my $tvars = {};
        %{$tvars} = ( %{$vars} );

        ( $tvars->{path}, $tvars->{fn} ) = $path_file =~ m{ \A$self->{datadir} /
                             (?:(.*)/)?(.*)\.$self->{file_extension} }msx;
        $tvars->{path_file} = $path_file;

        # Only stories in the right hierarchy
        next
          if ( $tvars->{path}
            && $tvars->{path} !~ /\A$tvars->{currentdir}/msx
            && $tvars->{path_file} ne "$self->{datadir}/$tvars->{currentdir}" );

        # Prepend a slash for use in templates only if a path exists
        $tvars->{path} &&= "/$tvars->{path}";

        # Date fiddling for by-{year,month,day} archive views
        %{$tvars} =
          ( %{$tvars}, %{ $self->nice_date( $self->{files}->{$path_file} ) } );

        # Only stories from the right date
        next
          if $tvars->{path_info_yr}
              && $tvars->{yr} != $tvars->{path_info_yr};
        last
          if $tvars->{path_info_yr}
              && $tvars->{yr} < $tvars->{path_info_yr};

        #
        next
          if $tvars->{path_info_mo_num}
              && $tvars->{mo} ne
              $self->{num2month}->[ $tvars->{path_info_mo_num} - 1 ];

        #
        next
          if $tvars->{path_info_da}
              && $tvars->{da} != $tvars->{path_info_da};
        last
          if $tvars->{path_info_da}
              && $tvars->{da} < $tvars->{path_info_da};

        # Date
        my $gendate =
          $self->_generate_date( $tvars,
            $self->{files}->{ $tvars->{path_file} } );

        if ( $gendate && $curdate ne $gendate ) {
            $curdate = $gendate;
            $output .= $gendate;
        }

        if ( -f $tvars->{path_file} ) {
            $output .= $self->_generate_story($tvars);
        }

        $ne--;
    }

    return $output;
}

sub _generate_date {
    my ( $self, $vars, $path_file ) = @_;

    my $date = $self->template( $vars->{path}, 'date', $vars->{flavor} );

    # Plugins: Date
    foreach my $plugin ( @{ $self->{plugin_list} } ) {
        if ( $plugin->can('date') ) {
            my $entries = plugin->date( $vars, \$date, $path_file );
        }
    }

    return $self->interpolate( $date, $vars );
}

sub _generate_story {
    my ( $self, $vars ) = @_;

    my $tvars = {};
    %{$tvars} = ( %{$vars} );

    my $fh = new FileHandle;
    if ( $fh->open("< $vars->{path_file}") ) {
        $tvars->{title} = <$fh>;
        $tvars->{body} = do { local $RS = undef; <$fh> };
        $fh->close;
        chomp +( $tvars->{title}, $tvars->{body} );
        $tvars->{raw} = join "\n", ( $tvars->{title}, $tvars->{body} );
    }

    my $story = $self->template( $tvars->{path}, 'story', $tvars->{flavor} );

    # Plugins: Story
    foreach my $plugin ( @{ $self->{plugin_list} } ) {
        if ( $plugin->can('story') ) {
            my $entries =
              $plugin->story( $tvars, \$story, \$tvars->{title},
                \$tvars->{body} );
        }
    }

    if (   $tvars->{content_type} =~ m{\bxml\b}msx
        && $tvars->{content_type} !~ m{\bxhtml\b}msx )
    {

        # Escape special characters inside the <link> container
        my $url_escape_re = qr{ [^-/a-zA-Z0-9:._] }msx;
        foreach (qw/ url path fn /) {
            if ( $tvars->{$_} ) {
                $tvars->{$_} =~ s{ $url_escape_re }
                                 { sprintf '%%%02X', ord $& }gemsx;
            }
        }

        # Escape HTML to produce valid RSS
        foreach (qw/ title body url path fn /) {
            if ( $tvars->{$_} ) {
                $self->html_escape( \$tvars->{$_} );
            }
        }
    }

    my $tmp = $self->interpolate( $story, $tvars );
    return $tmp;
}

sub _generate_foot {
    my ( $self, $vars ) = @_;

    my $foot = $self->template( $vars->{currentdir}, 'foot', $vars->{flavor} );

    # Plugins: Foot
    foreach my $plugin ( @{ $self->{plugin_list} } ) {
        if ( $plugin->can('foot') ) {
            my $entries = $plugin->foot( $vars, \$foot );
        }
    }

    return $self->interpolate( $foot, $vars );
}

=head2 html_escape(\$string)

Turns characters in a string that are unsafe for HTML/XML into entities.

=cut

sub html_escape {
    my ( $self, $string_ref ) = @_;

    my %escape = (
        q{<} => '&lt;',
        q{>} => '&gt;',
        q{&} => '&amp;',
        q{"} => '&quot;',
        q{'} => '&apos;',
    );
    my $escape_re = join q{|} => keys %escape;
    ${$string_ref} =~ s/($escape_re)/$escape{$1}/gmsx;

    return;
}

=head2 interpolate($template, \%vars)

This method will interpolate C<%vars> into C<$template> provided by the 
L<template> method and return it.

=cut

sub interpolate {
    my ( $self, $template, $vars ) = @_;

 #    $template =~ s{ (\$ \w+ (?:::\w+)* (?: (?:->)? { (['"]?) [-\w]+\2 } )? ) }
 #                  { "defined $1 ? $1 : ''" }geemx;

    $template =~ s{ \$ (\w+) }
#                  { defined($vars->{$1}) ? $vars->{$1} : '' }gemsx;
                  { $vars->{$1} // '' }gemsx;

    return $template;
}

=head2 nice_date($unixtime)

Expects a single parameter, namely a date in unix timestamp format.

Returns a hash reference containing the following date/time values:

=over 4

=item * C<dw>

 Three character abbreviation for the day of the week, e.g. 'Thu'

=item * C<mo>

 Three character month name abbreviation, e.g. 'Nov'

=item * C<mo_num>

 two digit number corrresponding to $mo, e.g. 11

=item * C<da>

 numerical day of the month, e.g. 24

=item * C<ti>

 24 hour formatted time of day including hours and minutes, e.g. 18:22

=item * C<yr>

 numerical 4 digit year, e.g. 2006

=item * C<hr>

 hour portion of current time of day in 24 hour format, e.g. 18

=item * C<min>

 minute portion of current time of day, eg 22

=item * C<sec>

 seconds portion of current time of day, eg 00

=item * C<hr12>

 hour portion of current time of day in 12 hour format, eg. 06

=item * C<ampm>

 The string 'am' or 'pm';

=item * C<utc_offset>

 The time-zone as hour offset from GMT eg. -0600 for Central Standard Time or
 +0530 for Asia/Calcutta

=back

=cut

sub nice_date {
    my ( $self, $unixtime ) = @_;

    my $t = Time::Piece->new($unixtime);
    $t->day_list( @{ $self->{days} } );
    $t->mon_list( @{ $self->{months} } );

    my $retval = {
        dw     => $t->day,
        mo     => $t->monname,
        mo_num => ( sprintf '%02d', $t->mon ),
        da     => ( sprintf '%02d', $t->day_of_month ),
        yr     => $t->year,
        hr     => ( sprintf '%02d', $t->hour ),
        min    => ( sprintf '%02d', $t->minute ),
        sec    => ( sprintf '%02d', $t->second ),
        ampm   => lc $t->strftime('%p'),
        utc_offset => $t->strftime('%z'),    # is %z portable?  Maybe not.

    };
    $retval->{hr12} = sprintf '%02d', $retval->{hr} % 12 || 12;
    $retval->{ti} = "$retval->{hr}:$retval->{min}";

    return $retval;
}

=head2 run_dynamic($cgi)

This method runs Blumenkraft as a CGI script.

The C<$cgi> parameter can be used to provide an existing object of the type 
C<cgi_class> as specified in the configuration.  If C<$cgi> is not defined, a 
new C<cgi_class> object wiil created.

If the environment variable C<BLUMENKRAFT_RETURN_ONLY> is set the output of
this method is returned as a scalar.  This could be useful for debugging.  If
it is not set, the output is printed to C<STDOUT> which is what you want in
normal CGI execution. 

=cut

sub run_dynamic {
    my ( $self, $cgi ) = @_;

    if ($cgi) {
        if ( !$cgi->isa( $self->{cgi_class} ) ) {
            croak "Wrong type of CGI object\n";
        }
        $self->{cgi} = $cgi;
    }
    else {

        # Create a CGI object
        load $self->{cgi_class};
        $self->{cgi} = $self->{cgi_class}->new
          || croak "Cannot load CGI object\n";
    }

    $self->entries( $self->{datadir} );

    my $vars = {};
    %{$vars} = ( %{$self}, %{ $self->_get_cgivars } );
    $vars->{version} = $VERSION;

    my $content_type =
      ( $self->template( $vars->{path_info}, 'content_type', $vars->{flavor} )
      );
    $content_type =~ s{\n.*}{}msx;
    $vars->{content_type} = $self->interpolate( $content_type, $vars );
    $vars->{currentdir} = $vars->{path_info};

    my $output =
        $self->{cgi}->header( -type => $vars->{content_type} )
      . $self->generate($vars);

    # Plugins: End
    foreach my $plugin ( @{ $self->{plugin_list} } ) {
        if ( $plugin->can('end') ) {
            my $entries = $plugin->end($vars);
        }
    }

    if ( $ENV{BLUMENKRAFT_RETURN_ONLY} ) {
        return $output;
    }
    else {
        print $output or croak "$OS_ERROR\n";
    }

    return;
}

sub _get_cgivars {
    my ($self) = @_;

    if ( !$self->{url} ) {
        $self->{url} = $self->{cgi}->url();

        # Unescape %XX hex codes (from URI::Escape::uri_unescape)
        $self->{url} =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/gemsx;

        # Support being called from inside a SSI document
        if ( $ENV{SERVER_PROTOCOL} && $ENV{SERVER_PROTOCOL} eq 'INCLUDED' ) {
            $self->{url} =~ s/^included:/http:/msx;
        }

        # Remove PATH_INFO if it is set but not removed by CGI.pm. This
        # seems to happen when used with Apache's Alias directive or if
        # called from inside a Server Side Include document. If that
        # doesn't help either, set $url manually in the configuration.
        if ( defined $ENV{PATH_INFO} ) {
            $self->{url} =~ s/\Q$ENV{PATH_INFO}\E$//msx;
        }

        # NOTE:
        #
        # There is one case where this code does more than necessary, too:
        # If the URL requested is e.g. http://example.org/blog/blog and
        # the base URL is correctly determined as http://example.org/blog
        # by CGI.pm, then this code will incorrectly normalize the base
        # URL down to http://example.org, because the same string as
        # PATH_INFO is part of the base URL, too. But this is such a
        # seldom case and can be fixed by setting $url in the config file,
        # too.
    }

    # The only modification done to a manually set base URL is to strip
    # a trailing slash if present.

    $self->{url} =~ s{/$}{}msx;

    # Path Info Magic
    # Take a gander at HTTP's PATH_INFO for optional blog name,
    # archive yr/mo/day
    my @path_info = split m{/}msx,
      $self->{cgi}->path_info() || $self->{cgi}->param('path') || q{};
    my $path_info_full = join q{/}, @path_info;
    shift @path_info;

    # Flavor specified by ?flav={flav} or index.{flav}
    my $flavor = q{};
    if ( !( $flavor = $self->{cgi}->param('flav') ) ) {
        if (   $path_info[-1]
            && $path_info[-1] =~ /(?<filename>.+)\.(?<flavor>.+)$/msx )
        {
            $flavor = $LAST_PAREN_MATCH{flavor};
            if ( $LAST_PAREN_MATCH{filename} eq 'index' ) {
                pop @path_info;
            }
        }
    }
    $flavor ||= $self->{default_flavor};

    # Fix XSS in flavor name
    $self->html_escape( \$flavor );

    # Global variable to be used in head/foot.{flavor} templates
    my $path_info = q{};

    # Add all @path_info elements to $path_info till we come to one that could
    # be a year
    while ( $path_info[0] && $path_info[0] !~ /\A(19|20)\d{2}\z/msx ) {
        $path_info .= q{/} . shift @path_info;
    }

    my ( $path_info_yr, $path_info_mo, $path_info_mo_num, $path_info_da ) = q{};

    # Pull date elements out of path
    if ( $path_info[0] && $path_info[0] =~ /\A(19|20)\d{2}\z/msx ) {
        $path_info_yr = shift @path_info;
        if (
            $path_info[0]
            && ( $path_info[0] =~ /\A(0\d|1[012])\z/msx
                || exists $self->{month2num}->{ ucfirst lc $path_info_mo } )
          )
        {
            $path_info_mo = shift @path_info;

            # Map path_info_mo to numeric $path_info_mo_num
            $path_info_mo_num =
                $path_info_mo =~ /\A \d{2} \z/msx
              ? $path_info_mo
              : $self->{month2num}->{ ucfirst lc $path_info_mo };
            if ( $path_info[0] && $path_info[0] =~ /\A[0123]\d\z/msx ) {
                $path_info_da = shift @path_info;
            }
        }
    }

    # Add remaining path elements to $path_info
    $path_info .= q{/} . join q{/}, @path_info;

    # Strip spurious slashes
    $path_info =~ s{(^/*)|(/*$)}{}gmsx;

    return {
        url              => $self->{url},
        flavor           => $flavor,
        path_info        => $path_info,
        path_info_yr     => $path_info_yr,
        path_info_mo     => $path_info_mo,
        path_info_mo_num => $path_info_mo_num,
        path_info_da     => $path_info_da
    };
}

=head2 run_static(%options)

This method is used to make Blumenkraft generate static files.  C<%options> 
can contain the following:

=over 4

=item * C<all>

If this option is set to 1, all files will be statically generated whether 
they need to be or not.  If it is set to 0 (the default) only files which
are out of date will be generated.

=item * C<password>

This option is required.  The value of the option is checked against the 
static_password set in the configuration.  Static generation only proceeds if
the two match.

=item * C<quiet>

If this option is set to 0 (the default), status messages will be displayed
during the generation process.  If it is set to 1 they will not.

=back

=cut

sub run_static {
    my ( $self, %options ) = @_;

    if ( !$self->check_password( $options{password} ) ) {
        if ( !$options{quiet} ) {
            say 'Access denied.';
        }
        return 1;
    }

    $self->entries( $self->{datadir}, $options{all} );
    if ( !$options{quiet} ) {
        say 'Blumenkraft is generating static index pages...';
    }

    my $vars = {};
    %{$vars} = ( %{$self} );
    $vars->{version} = $VERSION;

    # Unescape %XX hex codes (from URI::Escape::uri_unescape)
    $vars->{url} =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/gemsx;

    # Remove trailing slash if any.
    $vars->{url} =~ s{/$}{}msx;

    # Home Page and Directory Indexes
    my %done;
    foreach my $path ( sort keys %{ $self->{indexes} } ) {
        my $p = q{};
        foreach ( ( q{}, ( split m{/}msx, $path ) ) ) {
            $p .= "/$_";
            $p =~ s{\A/}{}msx;
            if ( $done{$p} ) {
                next;
            }
            else {
                $done{$p} = 1;
            }
            if ( !-d "$self->{static_dir}/$p"
                && $p !~ /\.$self->{file_extension}$/msx )
            {
                mkdir "$self->{static_dir}/$p", oct 755
                  or croak
                  "Couldn't make directory $self->{static_dir}/$p: $OS_ERROR\n";
            }
            foreach my $flavor ( @{ $self->{static_flavors} } ) {
                my $tvars = {};
                %{$tvars} = ( %{$vars} );

                $tvars->{flavor} = $flavor;
                my $content_type =
                  $self->template( $p, 'content_type', $tvars->{flavor} );
                $content_type =~ s{\n.*}{}msx;
                $tvars->{content_type} =
                  $self->interpolate( $content_type, $tvars );
                $tvars->{fn} =
                    $p =~ m{\A(.+)\.$self->{file_extension}$}msx
                  ? $1
                  : "$p/index";

                if ( !$options{quiet} ) {
                    say "$tvars->{fn}.$tvars->{flavor}";
                }
                my $fh_w =
                  new FileHandle
                  "> $self->{static_dir}/$tvars->{fn}.$tvars->{flavor}"
                  or croak
"Couldn't open $self->{static_dir}/$tvars->{fn}.$tvars->{flavor} for writing: $OS_ERROR";

                (
                    $tvars->{path_info_yr},     $tvars->{path_info_mo},
                    $tvars->{path_info_mo_num}, $tvars->{path_info_da}
                ) = q{};
                if ( $self->{indexes}->{$path} eq '1' ) {

                    # category
                    $tvars->{path_info} = $p;

                    # individual story
                    $tvars->{path_info} =~
                      s{\.$self->file_extension$}{\.$tvars->{flavor}}msx;
                    $tvars->{currentdir} = $tvars->{path_info};

                    print {$fh_w} $self->generate($tvars)
                      or croak "$OS_ERROR\n";
                }
                else {

                    # date
                    (
                        $tvars->{path_info_yr}, $tvars->{path_info_mo},
                        $tvars->{path_info_da}, $tvars->{path_info}
                    ) = split m{ / }msx, $p, 4;

                    # Map $path_info_mo to numeric $path_info_mo_num
                    if ( defined $tvars->{path_info_mo} ) {
                        $tvars->{path_info_mo_num} =
                            $tvars->{path_info_mo} =~ /\A \d{2} \z/msx
                          ? $tvars->{path_info_mo}
                          : $self->{month2num}
                          ->{ ucfirst lc $tvars->{path_info_mo} };
                    }
                    $tvars->{currentdir} = q{};

                    print {$fh_w} $self->generate($tvars)
                      or croak "$OS_ERROR\n";
                }
                $fh_w->close;
            }
        }
    }

    # Plugins: End
    foreach my $plugin ( @{ $self->{plugin_list} } ) {
        if ( $plugin->can('end') ) {
            my $entries = $plugin->end($vars);
        }
    }

    return;
}

=head2 sort(\%files)

Returns an array of the names of the files in C<%files> sorted in order of 
their modification times, newest first.

=cut

sub sort {    ## no critic (ProhibitBuiltinHomonyms)
    my ( $self, $files_ref ) = @_;
    return reverse sort { $files_ref->{$a} <=> $files_ref->{$b} }
      keys %{$files_ref};
}

=head2 template($path, $chunk, $flavor)

This routine returns the template file found at C<$path> called 
C<$chunk>.C<$flavor>.  If it is not found, a default template is returned.
If the default template cannot be found, an error template for that C<$chunk>
is returned.

=cut

sub template {
    my ( $self, $path, $chunk, $flavor ) = @_;

    $path   //= q{};    # $path may not be defined.
    $flavor //= q{};    # $flavor may not be defined;
    my $fh = new FileHandle;

    while ( $path =~ m{ /*[^/]* $ }msx ) {
        if ( $fh->open("< $self->{datadir}/$path/$chunk.$flavor") ) {
            return scalar do { local $RS = undef; <$fh> };
        }
        $path =~ s{ (?<path>/*[^/]*) $ }{}msx;
        last if !$LAST_PAREN_MATCH{path};
    }

    # Check for definedness, since flavor can be the empty string
    if ( defined $self->{template}->{$flavor}->{$chunk} ) {
        return $self->{template}->{$flavor}->{$chunk};
    }
    elsif ( defined $self->{template}->{error}->{$chunk} ) {
        return $self->{template}->{error}->{$chunk};
    }
    else {
        return q{};
    }

    return;
}

=head1 BUGS AND LIMITATIONS

There are no known problems with this module.

Please report any bugs or feature requests to
C<bug-app-blumenkraft at rt.cpan.org>, or through the web interface at
L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=App-Blumenkraft>.
I will be notified, and then you'll automatically be notified of progress on
your bug as I make changes.

=head1 AUTHOR

Jaldhar H. Vyas, C<< <jaldhar at braincells.com> >>

=head1 LICENSE AND COPYRIGHT

Copyright (C) 2009 Consolidated Braincells Inc., all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

1;    # End of Blumenkraft

# Default templates
__DATA__
html content_type text/html; charset=$blog_encoding

html head <!DOCTYPE html PUBLIC "-//W3C//DTD HTML 4.01 Transitional//EN" "http://www.w3.org/TR/html4/loose.dtd">
html head <html>
html head     <head>
html head         <meta http-equiv="content-type" content="$content_type" >
html head         <link rel="alternate" type="type="application/rss+xml" title="RSS" href="$url/index.rss" />
html head         <title>$blog_title $path_info_da $path_info_mo $path_info_yr</title>
html head     </head>
html head     <body>
html head         <div align="center">
html head             <h1>$blog_title</h1>
html head             <p>$path_info_da $path_info_mo $path_info_yr</p>
html head         </div>

html story         <div>
html story             <h3><a name="$fn">$title</a></h3>
html story             <div>$body</div>
html story             <p>posted at: $ti | path: <a href="$url$path">$path</a> | <a href="$url/$yr/$mo_num/$da#$fn">permanent link to this entry</a></p>
html story         </div>

html date         <h2>$dw, $da $mo $yr</h2>

html foot
html foot         <div align="center">
html foot             <a href="http://blosxom.sourceforge.net/"><img src="http://blosxom.sourceforge.net/images/pb_blosxom.gif" alt="powered by blosxom" border="0" width="90" height="33" ></a>
html foot         </div>
html foot     </body>
html foot </html>

rss content_type text/xml; charset=$blog_encoding

rss head <?xml version="1.0" encoding="$blog_encoding"?>
rss head <rss version="2.0">
rss head   <channel>
rss head     <title>$blog_title</title>
rss head     <link>$url/$path_info</link>
rss head     <description>$blog_description</description>
rss head     <language>$blog_language</language>
rss head     <docs>http://blogs.law.harvard.edu/tech/rss</docs>
rss head     <generator>Blumenkraft/$version</generator>

rss story   <item>
rss story     <title>$title</title>
rss story     <pubDate>$dw, $da $mo $yr $ti:$sec $utc_offset</pubDate>
rss story     <link>$url/$yr/$mo_num/$da#$fn</link>
rss story     <category>$path</category>
rss story     <guid isPermaLink="false">$url$path/$fn</guid>
rss story     <description>$body</description>
rss story   </item>

rss date

rss foot   </channel>
rss foot </rss>

error content_type text/html

error head <!DOCTYPE html PUBLIC "-//W3C//DTD HTML 4.01 Transitional//EN" "http://www.w3.org/TR/html4/loose.dtd">
error head <html>
error head <head><title>Error: unknown Blumenkraft flavor "$flavor"</title></head>
error head     <body>
error head         <h1><font color="red">Error: unknown Blumenkraft flavor "$flavor"</font></h1>
error head         <p>I'm afraid this is the first I've heard of a "$flavor" flavored Blumenkraft.  Try dropping the "/+$flavor" bit from the end of the URL.</p>

error story        <h3>$title</h3>
error story        <div>$body</div> <p><a href="$url/$yr/$mo_num/$da#fn.$default_flavor">#</a></p>

error date         <h2>$dw, $da $mo $yr</h2>

error foot     </body>
error foot </html>

__END__
