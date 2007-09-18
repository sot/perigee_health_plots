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

require "./RetrievePerigeeTelem.pm";

if ($opt{help}){
    print "See perldoc for RetrievePerigeeTelem\n";
    exit;
}

my $status = RetrievePerigeeTelem::retrieve_telem(\%opt);

