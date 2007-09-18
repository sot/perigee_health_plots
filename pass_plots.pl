#! /usr/bin/env /proj/sot/ska/bin/perlska

use strict;
use warnings;

use Time::Local 'timelocal_nocheck';
use Time::CTime;
use IO::All;
#use POSIX qw(tmpnam);
use Getopt::Long;

#use Data::ParseTable qw( parse_table );
#use Ska::Run;
#use Carp;

#use Getopt::Long;
#use File::Glob;
#use Ska::Convert qw(date2time);
#use File::Copy;
use Data::Dumper;

# I stuck these in an eval section later... we only need to load them if we
# have to grab data
#
# use File::Path;
# use Ska::Process qw/ get_archive_files /;
# use Expect::Simple;
# use IO::All;


our %opt = ();

GetOptions (\%opt,
	    'help!',
	    'verbose!',
	   );

usage( 1 )
    if $opt{help};


##-- Grab the current time and convert to Chandra time
my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = gmtime;
my $now = sprintf ("%04d:%03d:%02d:%02d:%06.3f", $year+1900, $yday+1, $hour, $min, $sec);

require "./RetrievePerigeeTelem.pm";

my $retrieve_status = RetrievePerigeeTelem::retrieve_telem(\%opt);



