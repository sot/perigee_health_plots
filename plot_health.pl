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
use Hash::Merge qw( merge );

my %opt = ();

#our %opt = ();
#our $starttime;

GetOptions (\%opt,
            'help!',
            'dir=s',
            'missing!',
            'verbose|v!',
            'delete!',
	    'dryrun!',
	    'shared_config=s',
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

my %share_config;
if ( defined $opt{shared_config}){
    %share_config = YAML::LoadFile( $opt{shared_config} );
}
else{
    %share_config = YAML::LoadFile( "${SHARE}/shared.yaml" );
}

my %task_config;
if ( defined $opt{config} ){
    %task_config = YAML::LoadFile( $opt{config} );
}
else{
    %task_config = YAML::LoadFile( "${SHARE}/plot_health.yaml");
}

# combine config
Hash::Merge::set_behavior( 'RIGHT_PRECEDENT' );

my %config = %{ merge( \%share_config, \%task_config )};


my ($tstart, $tstop);
if (defined $opt{tstart}){
    $tstart = Chandra::Time->new($opt{tstart})->secs();
}
if (defined $opt{tstop}){
    $tstop = Chandra::Time->new($opt{tstop})->secs();
}


my $WORKING_DIR = $ENV{PWD};
if ( defined $opt{dir} or defined $config{general}->{pass_dir} ){

    if (defined $opt{dir}){
        $WORKING_DIR = $opt{dir};
    }
    else{
        $WORKING_DIR = $config{general}->{pass_dir};
    }

}
$config{general}->{pass_dir} = $WORKING_DIR;

require "${SHARE}/PlotHealth.pm";
#require "PlotHealth.pm";

my $plothealth = PlotHealth->new({ tstart => $tstart,
				   tstop => $tstop,
				   config => \%config,
				   opt => \%opt,
			       });

$plothealth->make_plots();
