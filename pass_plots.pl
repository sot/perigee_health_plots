#! /usr/bin/env /proj/sot/ska/bin/perlska

use strict;
use warnings;

use Time::Local 'timelocal_nocheck';
use Time::CTime;
use IO::All;
#use POSIX qw(tmpnam);
use Getopt::Long;
use Data::ParseTable qw( parse_table );
#use Ska::Run;
use Carp;

use Getopt::Long;
use File::Glob;
use Ska::Convert qw(date2time);
use File::Copy;
use Data::Dumper;

# I stuck these in an eval section later... we only need to load them if we
# have to grab data
#
# use File::Path;
# use Ska::Process qw/ get_archive_files /;
# use Expect::Simple;
# use IO::All;


#our $VERSION = '$Id: pass_plots.pl,v 1.1.1.1 2007-02-09 20:09:41 jeanconn Exp $'; # '
our %opt = ();

GetOptions (\%opt,
	    'help!',
	    'dir=s',
	    'web_dir=s',
	   );

help() if $opt{help};


sub help
{
  my $verbose = @_ ? shift : 2;
  require Pod::Usage;
  Pod::Usage::pod2usage ( { -exitval => 0, -verbose => $verbose } );
}

print Dumper %opt;

# Set some global vars with directory locations
my $SKA = $ENV{SKA} || '/proj/sot/ska';
my $TASK = 'perigee_plots';
my $SHARE = "$ENV{SKA}/share/${TASK}";

my $WEB_DIR = "${SKA}/www/ASPECT/perigee_health_plots/";
my $WORKING_DIR = $ENV{PWD};


if ( defined $opt{dir}){
    $WORKING_DIR = $opt{dir};
    
}
if ( defined $opt{web_dir}){
    $WEB_DIR = $opt{web_dir};
}


my $RADMON_DIR = "${SKA}/data/arc/iFOT_events/radmon/";
my @radmon_files = glob("$RADMON_DIR/*");

my $ps_outfile = 'aca_health_perigee.ps';
my $gif_outfile = 'aca_health.gif';



##-- Grab the current time and convert to Chandra time
my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst);
($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = gmtime;
my $now = sprintf ("%04d:%03d:%02d:%02d:%06.3f", $year+1900, $yday+1, $hour, $min, $sec);


my %passes;
 
#@radmon_files = @radmon_files[0 ... 10];

#print Dumper @radmon_files;

for my $radmon_file (reverse(@radmon_files)){


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

#!/usr/bin/env /proj/sot/ska/bin/perlska


for my $pass_start (keys %passes){

    my %pass = %{$passes{$pass_start}};

    my $tstart = date2time($pass{tstart});
    my $tstop = date2time($pass{tstop});

    # skip retrieve if directory already exists
    if ( -e "${WORKING_DIR}/$pass{tstart}/$ps_outfile"){
	print "Skipping $pass{tstart}; already exists \n";
	next;
    }

    eval 'use File::Path qw/ mkpath rmtree /';
    if ($@){
	croak(__PACKAGE__ .": !$@");
    }
    eval 'use Ska::Process qw/ get_archive_files /';
    if ($@){
	croak(__PACKAGE__ . ": !$@");
    }
    eval 'use Expect::Simple ';
    if ($@){
	croak(__PACKAGE__ . ": !$@");
    }
    eval 'use IO::All';
    if ($@){
	croak(__PACKAGE__ . ": !$@");
    }

    print "mkdir ${WORKING_DIR}/$pass{tstart} \n";
    mkpath("${WORKING_DIR}/$pass{tstart}");

    my (@obsfiles1, @obsfiles2, @obsfiles3);
    eval{
	@obsfiles1 = get_archive_files(guestuser => 1,
				       tstart    => $tstart,
				       tstop     => $tstop, 
				       prod      => "aca0[*.fits]",
				       file_glob => "*.fits*",
				       dir       => $WORKING_DIR . "/$pass{tstart}/",
				       loud      => 0,
				       );

#	@obsfiles2 = get_archive_files(guestuser => 1,
#				       tstart    => $tstart,
#				       tstop     => $tstop,
#				       prod      => "eps_eng_0[*_9_*.fits]",
#				       file_glob => "*_9_*.fits*",
#				       dir       => $ENV{PWD} . "/$pass{tstart}/",
#				       loud      => 0,
#				       );
#
	@obsfiles3 = get_archive_files(guestuser => 1,
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
	my $notes = io("${WORKING_DIR}/$pass{tstart}/pass_times.txt");
	$notes->print("TSTART\tTSTOP\n");
	$notes->print("$pass{tstart}\t$pass{tstop}\n");
    }



    
    my $idl = new Expect::Simple  { Cmd => "idl",
				    Prompt => 'IDL>',
				    DisconnectCmd => 'exit',
				    Verbose => 1,
				    Debug => 0,
				    Timeout => 2000
				    };
    

    print "Calling IDL with command\n";

    $idl->send(".run $SHARE/startup.pro" );
#    print ".run $SHARE/startup.pro \n\n";

    $idl->send(".compile $SHARE/aca_health.pro");
#    print ".compile $SHARE/aca_health.pro\n\n";
    
    $idl->send("aca_health, \'${WORKING_DIR}/$pass{tstart}\', \'$ps_outfile\'");
#    print "aca_health, \'${WORKING_DIR}/$pass{tstart}\', \'$ps_outfile\' \n\n";

#    use Image::Magick;
#    my $image = new Image::Magick;
#    $image->Read("$pass{tstart}/$ps_outfile");
#    $image->Write("$WEB_DIR/$pass{tstart}/$gif_outfile")

    system(" convert -rotate -90 -density 100x100 ${WORKING_DIR}/$pass{tstart}/$ps_outfile ${WORKING_DIR}/$pass{tstart}/$gif_outfile");
    print(" convert -rotate -90 -density 100x100 ${WORKING_DIR}/$pass{tstart}/$ps_outfile ${WORKING_DIR}/$pass{tstart}/$gif_outfile\n");

#    if ( -e "${WORKING_DIR}/$pass{tstart}/$gif_outfile" ){
	
#	mkpath("$WEB_DIR/$pass{tstart}");
#	system("mkdir -p $WEB_DIR/$pass{tstart} ");


#	copy( "${WORKING_DIR}/$pass{tstart}/$gif_outfile", "$WEB_DIR/$pass{tstart}/$gif_outfile");
#	system("cp -uva $pass{tstart}/$gif_outfile $WEB_DIR/$pass{tstart} ");
#	copy( "$SHARE/index.html", "$WEB_DIR/$pass{tstart}/index.html");
#	system("cp -uva $SHARE/index.html $WEB_DIR/$pass{tstart} ");
#    }

}



#
#print Dumper @passes;    
#
# Run the data preparation and extraction IDL routines
# All output from the IDL goes into $acadir/Result

