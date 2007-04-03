#! /usr/bin/env /proj/sot/ska/bin/perlska

use strict;
use warnings;

#use Time::Local 'timelocal_nocheck';
use Time::CTime;
use IO::All;
#use POSIX qw(tmpnam);
#use Getopt::Long;
use Data::ParseTable qw( parse_table );
#use Ska::Run;
use Carp;

use Getopt::Long;
use File::Glob;
use Ska::Convert qw(date2time);
use File::Copy;
use Data::Dumper;
use YAML;


# I stuck these in an eval section later... we only need to load them if we
# have to grab data
#
# use File::Path;
# use Ska::Process qw/ get_archive_files /;
# use IO::All;


our %opt = ();

GetOptions (\%opt,
	    'help!',
	    'config=s',
	    'dir=s',
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
    %config = YAML::LoadFile( "${SHARE}/get_perigee_telem.yaml" );
}

my $WORKING_DIR = $ENV{PWD};
if ( defined $opt{dir} or defined $config{working_dir} ){
 
    if (defined $opt{dir}){
	$WORKING_DIR = $opt{dir};
    }
    else{
	$WORKING_DIR = $config{working_dir};
    }

}


my $RADMON_DIR;
if (defined $config{radmon_dir} ){
    $RADMON_DIR = $config{radmon_dir};
}
else{
    $RADMON_DIR = "${SKA}/data/arc/iFOT_events/radmon/";
}

my $pass_time_file = $config{pass_time_file};

my @radmon_files = glob("$RADMON_DIR/*");

#my $ps_outfile = 'aca_health_perigee.ps';
#my $gif_outfile = 'aca_health.gif';



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
	$passes{$radzone{tstart}} = \%radzone;
    }

}

print "Getting Data for These Passes:\n";
print Dumper %passes;
print "Storing telemetry in : $WORKING_DIR \n";


for my $pass_start (keys %passes){

    my %pass = %{$passes{$pass_start}};

    my $tstart = date2time($pass{tstart});
    my $tstop = date2time($pass{tstop});

    # skip retrieve if directory already exists
    if ( -e "${WORKING_DIR}/$pass{tstart}/$pass_time_file"){
	print "Skipping $pass{tstart}; already exists \n";
	next;
    }

    # Load the other packages required
    eval 'use File::Path qw/ mkpath rmtree /';
    if ($@){
	croak(__PACKAGE__ .": !$@");
    }
    eval 'use Ska::Process qw/ get_archive_files /';
    if ($@){
	croak(__PACKAGE__ . ": !$@");
    }
    eval 'use IO::All';
    if ($@){
	croak(__PACKAGE__ . ": !$@");
    }

    print "mkdir ${WORKING_DIR}/$pass{tstart} \n";
    mkpath("${WORKING_DIR}/$pass{tstart}", 0, 775);

    # Retrieve the telemetry needed to run the idl to make the plots

    my (@obsfiles1, @obsfiles2);
    eval{
	@obsfiles1 = get_archive_files(guestuser => 1,
				       tstart    => $tstart,
				       tstop     => $tstop, 
				       prod      => "aca0[*.fits]",
				       file_glob => "*.fits*",
				       dir       => $WORKING_DIR . "/$pass{tstart}/",
				       loud      => 0,
				       );

	@obsfiles2 = get_archive_files(guestuser => 1,
				       tstart    => $tstart,
				       tstop     => $tstop,
				       prod => "ccdm0[*_10_*]",
                                      file_glob => "*_10_*",
				       dir       => $WORKING_DIR . "/$pass{tstart}/",
				       loud      => 0,
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
	# put out a little text file with the tstart and stop time of the pass
	my $notes = io("${WORKING_DIR}/$pass{tstart}/$pass_time_file");
	$notes->print("TSTART\tTSTOP\n");
	$notes->print("$pass{tstart}\t$pass{tstop}\n");
    }



}



##***************************************************************************
sub usage
##***************************************************************************
{
  my ( $exit ) = @_;

  local $^W = 0;
  eval 'use Pod::Text';
  if ($@){
      croak(__PACKAGE__ . ": !$@");
  }
  Pod::Text::pod2text( '-75', $0 );
  exit($exit) if ($exit);
}

=pod

=head1 NAME

get_perigee_telem.pl - Download aca0 image telemetry and ccdm telemetry from recent perigee passes 

=head1 SYNOPSIS

B<get_perigee_telem.pl>  [I<options>]

=head1 OPTIONS

=over 4

=item B<-help>

Print this help information.

=item B<-dir <dir>>

Save the telemetry in <dir>

=back

=head1 DESCRIPTION

B<get_perigee_telem.pl> reads the tables of recent perigee pass times from arc , and
then downloads aca level 0 and ccdm telemetry for those passes.  

=head1 AUTHOR

Jean Connelly ( jconnelly@localdomain )

=cut



