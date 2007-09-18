package RetrievePerigeeTelem;

use strict;
use warnings;

use Time::CTime;
use IO::All;

use Data::ParseTable qw( parse_table );
use Carp;

use Getopt::Long;
use File::Glob;
use Ska::Convert qw(date2time);
use File::Copy;
use Data::Dumper;
use YAML;
use Hash::Merge qw( merge );

use vars qw($VERSION @ISA @EXPORT @EXPORT_OK %EXPORT_TAGS);

require Exporter;

our @ISA = qw(Exporter);
our @EXPORT = qw();
our @EXPORT_OK = qw( retrieve_telem );
%EXPORT_TAGS = ( all => \@EXPORT_OK );

our $VERSION = '1.0';


# I stuck these in an eval section later... we only need to load them if we
# have to grab data
#
# use File::Path;
# use Ska::Process qw/ get_archive_files /;
# use IO::All;


sub retrieve_telem{

    my $opt_ref = shift;

    check_options($opt_ref);

    my %opt = %{$opt_ref};

    my %status;

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
	%task_config = YAML::LoadFile( "${SHARE}/get_perigee_telem.yaml");
    }
    
# combine config
    Hash::Merge::set_behavior( 'RIGHT_PRECEDENT' );
    
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


    my $RADMON_DIR;
    if (defined $config{task}->{radmon_dir} ){
	$RADMON_DIR = $config{task}->{radmon_dir};
    }
    else{
	$RADMON_DIR = "${SKA}/data/arc/iFOT_events/radmon/";
    }
    
    my $pass_time_file = $config{general}->{pass_time_file};
    
    my @radmon_files = glob("$RADMON_DIR/*");
#
##my $ps_outfile = 'aca_health_perigee.ps';
##my $gif_outfile = 'aca_health.gif';



##-- Grab the current time and convert to Chandra time
    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst);
    ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = gmtime;
    my $now = sprintf ("%04d:%03d:%02d:%02d:%06.3f", $year+1900, $yday+1, $hour, $min, $sec);
    
    
    my %passes;

    for my $radmon_file (reverse(@radmon_files)){

    # skip the file unless it is readable
	next unless ( -r $radmon_file );
	
	# read it in reverse order if it is
	my @radmon_table = reverse(@{parse_table( $radmon_file )});
	
	for my $step (0 .. $#radmon_table-1){
	    my %radzone;
	    next unless ($radmon_table[$step]->{'Type Description'} eq 'Radmon Processing Enable');
	    next unless ($radmon_table[$step+1]->{'Type Description'} eq 'Radmon Processing Disable');
	    next unless (date2time($radmon_table[$step]->{'TStart (GMT)'}) < date2time($now));
	    $radzone{tstop} = $radmon_table[$step]->{'TStart (GMT)'};
	    $radzone{tstart} = $radmon_table[$step+1]->{'TStop (GMT)'};
	    $passes{date2time($radzone{tstart})} = \%radzone;
	}
	
    }
    
    if ($opt{verbose}){
	print "Getting Data for These Passes:\n";
	print Dumper %passes;
	print "Storing telemetry in : $WORKING_DIR \n";
    }

    
    for my $pass_start ( sort(keys %passes)){
	
	my %pass = %{$passes{$pass_start}};
	
	my $tstart = date2time($pass{tstart});
	my $tstop = date2time($pass{tstop});
	
	# skip retrieve if directory already exists
	if ( -e "${WORKING_DIR}/$pass{tstart}/$pass_time_file"){
	    if ($opt{verbose}){
		print "Skipping $pass{tstart}; already exists \n";
	    }
	    $status{last_pass} = $pass{tstart};
	    $status{updated} = 0;
	    next;
	}

	# Load the other packages required
	eval 'use File::Path qw/ mkpath rmtree /';
	if ($@){
	    croak(__PACKAGE__ .": !$@");
	}
	eval 'use Ska::Process ';
	if ($@){
	    croak(__PACKAGE__ . ": !$@");
	}
	eval 'use IO::All';
	if ($@){
	    croak(__PACKAGE__ . ": !$@");
	}
	
	if ($opt{verbose}){
	    print "mkdir ${WORKING_DIR}/$pass{tstart} \n";
	}
	mkpath("${WORKING_DIR}/$pass{tstart}");
	
	# Retrieve the telemetry needed to run the idl to make the plots
	
	my (@obsfiles1, @obsfiles2);
	eval{
	    @obsfiles1 = Ska::Process::get_archive_files(guestuser => 1,
							 tstart    => $tstart,
							 tstop     => $tstop, 
							 prod      => "aca0[*.fits]",
							 file_glob => "*.fits*",
							 dir       => $WORKING_DIR . "/$pass{tstart}/",
							 loud      => 0,
							 timeout => 1000,
							 );
	    
	    @obsfiles2 = Ska::Process::get_archive_files(guestuser => 1,
							 tstart    => $tstart,
							 tstop     => $tstop,
							 prod => "ccdm0[*_10_*]",
							 file_glob => "*_10_*",
							 dir       => $WORKING_DIR . "/$pass{tstart}/",
							 loud      => 0,
							 timeout => 1000,
							 );
	    
	};
	if ($@){
	    croak("$@");
	}
	
	
	my @filelist = glob( "${WORKING_DIR}/$pass{tstart}/*");
	
	if (scalar(@filelist) == 0 ){
	    rmtree("${WORKING_DIR}/$pass{tstart}");
	    next;
	}
	else{

	    $status{last_pass} = $pass{tstart};
	    $status{updated} = 1;
	    # put out a little text file with the tstart and stop time of the pass
	    my $notes = io("${WORKING_DIR}/$pass{tstart}/$pass_time_file");
	    $notes->print("TSTART\tTSTOP\n");
	    $notes->print("$pass{tstart}\t$pass{tstop}\n");
	    
	    # enforce file permissions
	chmod 0775, @obsfiles1;
	chmod 0775, @obsfiles2;
	chmod 0775,  $notes ;
	    
	}
	
    }

    return \%status;

}



sub check_options{

    my $opt_ref = shift;

    #possible options, help, config, shared_config, dir
    my @allowed_options = qw( help config shared_config dir verbose );

    for my $option (keys %{$opt_ref}){
	unless( grep( /^$option$/, @allowed_options)){
	    croak(__PACKAGE__ . "::retrieve_telem(), says undefined option \"$option\"" );
	}

    }
}

1;



=pod

=head1 NAME

RetrievePerigeeTelem.pm - Download aca0 image telemetry and ccdm telemetry from recent perigee passes 

=head1 SYNOPSIS

Common Usage

 use RetrievePerigeeTelem qw( retrieve_telem );

 retrieve_telem();

=head1 DESCRIPTION

RetrievePerigeeTelem yanks telemetry from recent perigee passes and
saves the telemetry files into the directories specified by its config
files.

=head1 EXPORT

None by default.
retrieve_telem is available by request.

=head1 METHODS

retrieve_telem is the only accessible method.  By default, it reads the config files:
 ${SKA}/share/${TASK}/shared.yaml
 ${SKA}/share/${TASK}/get_perigee_telem.yaml

See these files to modify the behavior of the retrieve.

$TASK is hard coded.  $SKA will default to the $SKA environment variable or /proj/sot/ska .

The method lso accepts options to override the location of those config files
and to override the output director explicitly.

 retrieve_telem( { shared_config => "${SKA}/share/${TASK}/shared.yaml",
                   config => "${SKA}/share/${TASK}/get_perigee_telem.yaml",
                   dir => "/proj/gads6/aca/perigee_health_plots/PASS_DATA/",
                   help => undef });


=head1 AUTHOR

Jean Connelly ( jconnelly@localdomain )

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2007 by Smithsonian Astrophysical Observatory

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.0 or,
at your option, any later version of Perl 5 you may have available.


=cut



