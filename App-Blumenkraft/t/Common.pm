#
package Common;
use strict;
use warnings;
use base qw/ Exporter /;
use File::Copy;
use File::DirCompare;
use File::Find;
use Time::Piece;

our @EXPORT = qw/ compare_trees slurp touch_files /;
our $VERSION = '0.1';

sub compare_trees {
    my ($old, $new, $different, $extra, $missing) = @_;

    File::DirCompare->compare($old, $new, sub {
        my ($expected, $got) = @_;

        if (!$expected) {
            push @{$extra}, $got;
        }
        elsif (!$got) {
            push @{$missing}, $expected;
        }
        else {
            push @{$different}, $got;
        }
    });
}

sub slurp {
    my ($file) = @_;
    local $/ = undef;
    open my $FILE, '<', $file or die "$file: $!\n";
    my $slurped = <$FILE>;
    close $FILE;
    
    return $slurped;
}

sub touch_files {
    find( sub {
        if (/^(.*)\.(\d+)$/) {
            copy($_, $1);
            my $t = Time::Piece->strptime($2, '%Y%m%d%H%M')->epoch;
            utime $t, $t, $1;
        }
    },
    shift );
}

1;
