#! /usr/bin/env /proj/sot/ska/bin/perlska

use strict;
use warnings;

use Getopt::Long;


our %opt = ();

GetOptions (\%opt,
	    'help!',
	    'shared_config=s',
	    'config=s',
	    'dir=s',
	    'verbose!',
	   );

#require "./Data.pm";
use Ska::Perigee::Data;

if ($opt{help}){
    print "See perldoc for Ska::Perigee::Data::retrieve_telem\n";
    exit;
}

my $status = Ska::Perigee::Data::retrieve_telem(\%opt);

