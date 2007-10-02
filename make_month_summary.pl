#! /usr/bin/env /proj/sot/ska/bin/perlska

use strict;
use warnings;
use Getopt::Long;

my %opt = ();

#our %opt = ();

GetOptions (\%opt,
            'help!',
            'shared_config=s',
            'config=s',
            'dir=s',
            'missing!',
            'verbose|v!',
            'delete!'
            );

if ($opt{help}){
    print "See perldoc for Ska::Perigee::Data make_month_summary \n";
    exit;
}

use Ska::Perigee::Data;

my $status = Ska::Perigee::Data::month_stats_and_plots(\%opt);
