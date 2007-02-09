#! /usr/bin/env /proj/sot/ska/bin/perlska

use strict;
use warnings;

use IO::All;
use Getopt::Long;
use Carp;

use File::Glob;
use File::Copy;
use File::Path;



our %opt = ();

GetOptions (\%opt,
	    'help!',
	    'dir=s',
	    'web_dir=s',
	   );

usage( 1 ) if $opt{help};


# Set some global vars with directory locations
my $SKA = $ENV{SKA} || '/proj/sot/ska';
my $TASK = 'perigee_health_plots';
my $SHARE = "$ENV{SKA}/share/${TASK}";

my $WEB_DIR = "${SKA}/www/ASPECT/${TASK}/";
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

    # regrab the actual start time by parsing the string
    $pass =~ /^${WORKING_DIR}\/+(\d{4}:\d{3}:\d{2}:\d{2}:\d{2}\.\d{3})$/;
    my $tstart = $1;
    
    # save that for later
    push @pass_tstart, $tstart;

    # Copy the files to the web area
    if ( -e "${WORKING_DIR}/$tstart/$gif_outfile" ){
	
	mkpath("$WEB_DIR/$tstart");

	copy( "${WORKING_DIR}/$tstart/$gif_outfile", "$WEB_DIR/$tstart/$gif_outfile");

	copy( "$SHARE/index.html", "$WEB_DIR/$tstart/index.html");

    }

}

# Use CGI to have the handiest html-making routines
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

# Make an index file for the perigee pass directories
my $index_file = io("${WEB_DIR}/index.html");
$index_file->print($out_string);



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

install_plots.pl - Copy plots and directories made by pass_plots.pl to a web-accessible area

=head1 SYNOPSIS

B<pass_plots.pl>  [I<options>]

=head1 OPTIONS

=over 4

=item B<-help>

Print this help information.

=item B<-dir <dir>>

Specify the perigee_health_plots data directory, defaults to PWD .

=item B<-web_dir <web_dir>>

Specify the destination web directory . Defaults to ${SKA}/www/ASPECT/perigee_health_plots/

=back

=head1 DESCRIPTION

B<install_plots.pl> just copies over the plots made by pass_plots.pl and then generates a new index file for the lot.

=head1 AUTHOR

Jean Connelly ( jconnelly@localdomain )

=cut



