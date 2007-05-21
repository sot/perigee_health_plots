#! /usr/bin/env /proj/sot/ska/bin/perlska

use strict;
use warnings;

use IO::All;
use Getopt::Long;
use Carp;

use File::Glob;
use File::Copy;
#use File::Path;

use YAML;

use Data::ParseTable qw( parse_table );

use CGI qw/ :standard /;
use File::Path qw/ mkpath rmtree /;

use Chandra::Time;

use Hash::Merge qw( merge );
# combine config
Hash::Merge::set_behavior( 'RIGHT_PRECEDENT' );


my %opt = ();

GetOptions (\%opt,
	    'help!',
	    'shared_config=s',
	    'config=s',
	    'redo!',
	    'verbose!',
	    'dryrun!',
	   );

usage( 1 ) if $opt{help};


# Set some global vars with directory locations
my $SKA = $ENV{SKA} || '/proj/sot/ska';
my $TASK = 'perigee_health_plots';
my $SHARE = "$ENV{SKA}/share/${TASK}";

#require "${SHARE}/PlotHealth.pm";
require "/proj/gads6/jeanproj/perigee_health_plots/PlotHealth.pm";

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
    %task_config = YAML::LoadFile( "${SHARE}/make_month_summary.yaml");
}



if (defined $task_config{task}->{loadconfig}){
    for my $file (@{$task_config{task}->{loadconfig}}){
	my %newconfig = YAML::LoadFile("$file");
	%task_config = %{merge( \%task_config, \%newconfig )};
    }
}

my %config = %{ merge( \%share_config, \%task_config )};



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



my @passes = glob("${WORKING_DIR}/????:*");


my $pass_time_file = $config{general}->{pass_time_file};

my %time_tree;

for my $pass ( @passes ){

    my $curr_pass = "${pass}/$pass_time_file";
    my $pass_times = parse_table($curr_pass);
    my $tstart = $pass_times->[0]->{TSTART};
    my $tstop = $pass_times->[0]->{TSTOP};
    

    my $ct_tstart = Chandra::Time->new($tstart)->fits;
    if ($ct_tstart =~ /(\d{4}-\d{2}).*/){
	my $month_string = $1;
	push @{$time_tree{$month_string}}, $pass;
	
    }

}


my $summary_dir = $config{general}->{summary_dir};

my @month_list;
if ($opt{redo}){
    @month_list = sort(keys %time_tree);
}
else{
    my @full_list = reverse(sort(keys %time_tree));
    @month_list = @full_list[0,1];
}

if ($opt{verbose}){
    for my $month (@month_list){
	print "Making summary plots for $month \n";
    }
}

for my $month (@month_list){

    unless( $opt{dryrun}){
	mkpath( "${summary_dir}/${month}", 1);
    }

#    my %config = YAML::LoadFile( "plot_summary.yaml" );
#    # override plot destination
    $config{task}->{plot_dir} = "${summary_dir}/${month}";
#    # directories to summarize
    my @passlist = @{$time_tree{$month}};

    my $plothealth = PlotHealth->new({ config => \%config,
				       opt => \%opt,
				       passlist => \@passlist,
				  });

    $plothealth->make_plots();
}



