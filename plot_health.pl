#!/usr/bin/env /proj/sot/ska/bin/perlska

use strict; 
use warnings;
#use PGPLOT;

use XML::Dumper;
use PDL;
use PDL::NiceSlice;
use Getopt::Long;
use YAML;
use Carp;

use Data::Dumper;

use Chandra::Time;

my %opt = ();

#our %opt = ();
#our $starttime;

GetOptions (\%opt,
            'help!',
            'dir=s',
            'missing!',
            'verbose|v!',
            'delete!',
	    'config=s',
	    'tstart=s',
	    'tstop=s',
            );



usage( 1 )
    if $opt{help};


# Set some global vars with directory locations
my $SKA = $ENV{SKA} || '/proj/sot/ska';
my $TASK = 'perigee_health_plots';
my $SHARE = "$ENV{SKA}/share/${TASK}";


my %config;
if ( defined $opt{config}){
    %config = YAML::LoadFile( $opt{config} );
}
else{
    %config = YAML::LoadFile( "${SHARE}/plot_health.yaml" );
}

my ($tstart, $tstop);
if (defined $opt{tstart}){
    $tstart = Chandra::Time->new($opt{tstart})->secs();
}
if (defined $opt{tstop}){
    $tstop = Chandra::Time->new($opt{tstop})->secs();
}


my $WORKING_DIR = $ENV{PWD};
if ( defined $opt{dir} or defined $config{general}->{working_dir} ){

    if (defined $opt{dir}){
        $WORKING_DIR = $opt{dir};
    }
    else{
        $WORKING_DIR = $config{general}->{working_dir};
    }

}
$config{general}->{working_dir} = $WORKING_DIR;

require "${SHARE}/PlotHealth.pm";

my $plothealth = PlotHealth->new({ tstart => $tstart,
				   tstop => $tstop,
				   config => \%config,
				   opt => \%opt,
			       });

$plothealth->make_plots();
