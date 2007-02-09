#! /usr/bin/env /proj/sot/ska/bin/perlska

use strict;
use warnings;

use IO::All;
#use POSIX qw(tmpnam);
use Getopt::Long;
#use Ska::Run;
use Carp;

use Getopt::Long;
use File::Glob;

use File::Copy;
use Data::Dumper;


use File::Path;
# use Ska::Process qw/ get_archive_files /;
# use Expect::Simple;
# use IO::All;


#our $VERSION = '$Id: install_plots.pl,v 1.1.1.1 2007-02-09 20:09:41 jeanconn Exp $'; # '
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



# Set some global vars with directory locations
my $SKA = $ENV{SKA} || '/proj/sot/ska';
my $TASK = 'perigee_plots';
my $SHARE = "$ENV{SKA}/share/${TASK}";

my $WEB_DIR = "${SKA}/www/ASPECT/perigee_health_plots/";
my $WORKING_DIR = $ENV{PWD};

my $gif_outfile = 'aca_health.gif';


if ( defined $opt{dir}){
    $WORKING_DIR = $opt{dir};
    
}
if ( defined $opt{web_dir}){
    $WEB_DIR = $opt{web_dir};
}


print "Installing plots to $WEB_DIR \n";

my @passes = glob("${WORKING_DIR}/????:*");

my @pass_tstart;

for my $pass ( @passes ){

    $pass =~ /^${WORKING_DIR}\/+(\d{4}:\d{3}:\d{2}:\d{2}:\d{2}\.\d{3})$/;
    my $tstart = $1;
    push @pass_tstart, $tstart;

    if ( -e "${WORKING_DIR}/$tstart/$gif_outfile" ){
	
	mkpath("$WEB_DIR/$tstart");

	copy( "${WORKING_DIR}/$tstart/$gif_outfile", "$WEB_DIR/$tstart/$gif_outfile");

	copy( "$SHARE/index.html", "$WEB_DIR/$tstart/index.html");

    }

}

use CGI qw/ :standard /;
my $index = new CGI;

my $out_string;

$out_string .= sprintf( $index->start_html('Perigee Plots'));
$out_string .= sprintf( "<br>\n" );
$out_string .= sprintf( $index->h1('Perigee Pass Health Plots'));
$out_string .= sprintf( "<br>\n" );

for my $pass_dir (@pass_tstart){

    $out_string .= sprintf($index->a({href => "$pass_dir"}, "$pass_dir"));
    $out_string .= sprintf( "<br>\n");
}

$out_string .= sprintf( $index->end_html );

my $index_file = io("${WEB_DIR}/index.html");
$index_file->print($out_string);
