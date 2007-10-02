#! /usr/bin/env /proj/sot/ska/bin/perlska

use strict;
use warnings;

use Getopt::Long;


my %opt = ();

GetOptions (\%opt,
	    'help!',
	    'shared_config=s',
	    'config=s',
	    'redo!',
	    'verbose!',
	    'dryrun!',
#	    'dir=s',
#	    'web_dir=s',
	   );

use Ska::Perigee::Data;

my $status = Ska::Perigee::Data::install_plots(\%opt);

