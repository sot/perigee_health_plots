#!/usr/bin/env /proj/sot/ska/bin/perlska

use warnings;
use strict;
use Getopt::Long;

use Telemetry;
use Carp;
use PDL;
use PDL::NiceSlice;
use YAML;
use Data::ParseTable qw( parse_table );
use Ska::Convert qw( date2time );
use IO::All;
use Hash::Merge qw( merge );
#use XML::Dumper;



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
    print "See perldoc for Ska::Perigee::Data::parse_pass_telem\n";
    exit;
}

use Ska::Perigee::Data;

my $status = Ska::Perigee::Data::parse_pass_telem(\%opt);



if ($opt{verbose}){
    if (defined $status->{prev_done}){
	print "Previous parsedly through pass with tstart: ";
	print $status->{prev_done}->[0], "\n";
    }

    if (defined $status->{just_parsed}){
	print "Just parsed passes: \n";
	for my $dir (@{$status->{just_parsed}}){
	    print "\t$dir\n";
	}
    }
}


