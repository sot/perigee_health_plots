#! /usr/bin/env /proj/sot/ska/bin/perlska

use strict;
use warnings;

use IO::All;
use Getopt::Long;
use Carp;

use File::Glob;
use File::Copy;
use File::Path;

use YAML;

use Data::ParseTable qw( parse_table );

use CGI qw/ :standard /;
use Ska::Convert qw( date2time );

my %opt = ();

GetOptions (\%opt,
	    'help!',
	    'config=s',
#	    'dir=s',
#	    'web_dir=s',
	   );

usage( 1 ) if $opt{help};


# Set some global vars with directory locations
my $SKA = $ENV{SKA} || '/proj/sot/ska';
my $TASK = 'perigee_health_plots';
my $SHARE = "$ENV{SKA}/share/${TASK}";


my $WEB_DIR = "${SKA}/www/ASPECT/${TASK}/";
my $WORKING_DIR = $ENV{PWD};

my %config;
if ( defined $opt{config}){
    %config = YAML::LoadFile( $opt{config} );
}
else{
    %config = YAML::LoadFile( "${SHARE}/install_plots.yaml" );
}

use Data::Dumper;
print Dumper %config;

if ( defined $config{general}->{working_dir} ){
    $WORKING_DIR = $config{general}->{working_dir};
}
if ( defined $config{general}->{web_dir}){
    $WEB_DIR = $config{general}->{web_dir};
}


my $source_plot_ext = $config{general}->{source_plot_ext};

print "Installing plots to $WEB_DIR \n";

my @passes = glob("${WORKING_DIR}/????:*");
my @pass_times;

my @source_plots = @{$config{general}->{source_plots}};
my @dest_plots = @{$config{general}->{dest_plots}};

my $pass_time_file = $config{general}->{pass_time_file};
my $pass_dir_index = $config{general}->{pass_dir_index};

my %time_tree;

for my $pass ( @passes ){

    my $curr_pass = "${pass}/$pass_time_file";
    my $pass_times = parse_table($curr_pass);
    my %pass_time_cs = (
                        tstart => $pass_times->[0]->{TSTART},
                        tstop => $pass_times->[0]->{TSTOP},
                        );

    my $tstart = $pass_times->[0]->{TSTART};
    my $tstop = $pass_times->[0]->{TSTOP};
    
    use Chandra::Time;
    my $parsed_tstart = Chandra::Time->new($tstart)->parse();
    push @{$time_tree{$parsed_tstart->{year}}->{$parsed_tstart->{month}}}, $tstart;

    push @pass_times, \%pass_time_cs;
    
# save that for later

    my @plots = glob("${pass}/*.${source_plot_ext}");
#    if (scalar(@plots)){
#	
#	for my $expected_plot (@source_plots){
#	    croak("${pass}/${expected_plot} missing ") 
#		unless (-e "${pass}/${expected_plot}" );
#	}
#
#	mkpath("$WEB_DIR/$tstart");
#	
#	for my $plot_idx (0 .. $#source_plots){
#	    system(" convert ${pass}/$source_plots[$plot_idx] ${WEB_DIR}/${tstart}/$dest_plots[$plot_idx]"); 
#	}
#
## Use CGI to have the handiest html-making routines
#	
#	my $index = new CGI;
#	my $out_string;
#
#	$out_string .= sprintf( $index->start_html('ACA Perigee Pass Health Indicators'));
#	$out_string .= sprintf( "<br>\n" );
#	$out_string .= sprintf( $index->h1('ACA Perigee Pass Health Indicators'));
#	$out_string .= sprintf( "<br>\n" );
#	$out_string .= sprintf( "<TABLE>\n");
#	$out_string .= sprintf( "<TR><TH>TSTART</TH><TH>TSTOP</TH></TR>\n");
#	$out_string .= sprintf( "<TR><TD>$tstart</TD><TD>$tstop</TD></TR>\n");
#	$out_string .= sprintf( "</TABLE>\n");
#	$out_string .= sprintf( "<TABLE>\n");
#	$out_string .= sprintf( "<TR><TD><IMG SRC=\"$dest_plots[0]\"></TD><TD><IMG SRC=\"$dest_plots[1]\"></TD></TR>");
#	$out_string .= sprintf( "<TR><TD><IMG SRC=\"$dest_plots[2]\"></TD><TD><IMG SRC=\"$dest_plots[3]\"></TD></TR>");
#	$out_string .= sprintf( "</TABLE>");
#	$out_string .= sprintf( "<IMG SRC=\"$dest_plots[4]\">");
#
#	$out_string .= sprintf( $index->end_html );
#	
## Make an index file for the perigee pass directories
#	my $index_file = io("${WEB_DIR}/${tstart}/$pass_dir_index");
#	$index_file->print($out_string);
#	
#
#	
#    }


    
}

my %month_map = %{$config{general}->{month_map}};

my @year_list = sort (keys %time_tree);
my @year_links = map { $_ . ".html" } @year_list;

#make_nav_page( 'index', \@year_links, $config{general}->{base_dir}, $WEB_DIR);
my $main_page = "<HTML><HEAD></HEAD><BODY><br />";
$main_page .= "<H2>ACA Perigee Health Plots</H2><br />";
$main_page .= "<TABLE BORDER=1><TR>";

for my $year (sort (keys %time_tree)){
    $main_page .= "<TH>$year</TH>";
    my @month_list = sort keys %{$time_tree{$year}};
    my @month_links = map { $month_map{$_} . ".html" } @month_list;
#    make_nav_page( $year, \@month_links, $config{general}->{base_dir}, $WEB_DIR);
    for my $month (@month_list){
	make_nav_page( $month_map{$month}, $time_tree{$year}->{$month}, $config{general}->{base_dir}, $WEB_DIR);
	$main_page .= "<TD><A HREF=\"$month_map{$month}.html\">$month_map{$month}</A></TD>";

#	print "for year $year and month $month :\n";
#	for my $pass (@{$time_tree{$year}->{$month}}){
#	    print "pass is $pass \n";
#	}
    }
    $main_page .= "</TR>";
}
$main_page .= "</TABLE></BODY></HTML>";
print $main_page;
my $index = io("${WEB_DIR}/index.html");
$index->print($main_page);


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



sub make_nav_page{
    my $name = shift;
    my $link_ref = shift;
    my $base_dir = shift;
    my $WEB_DIR = shift;

    my $out_string = "<HTML><HEAD></HEAD><BODY><br />\n";
     $out_string = "<H2>Data for $name</H2><br />\n"; 
#    print "make ${name}.html with contents \n";
    for my $entry (@{$link_ref}){
#	print "${base_dir}/${entry} \n";
	$out_string .= "<A HREF=\"${base_dir}/${entry}\">${entry}</A><br />\n";
    }
    $out_string .= "</BODY></HTML>\n";
    
    my $out_file = io("${WEB_DIR}/${name}.html");
    $out_file->print($out_string);
}

sub make_nav_table{
    my $name = shift;
    my $link_ref = shift;
    my $base_dir = shift;
    
    my $out_string = "<TABLE>";
    $out_string .= "<TR><TH>$name</TH></TR>";
    for my $entry (@{$link_ref}){
	$out_string .= "<TR><TD><A HREF=\"${base_dir}/${entry}\">${entry}</A></TD></TR><br />\n";
    }
    $out_string .= "</TABlE>";
    return $out_string;
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



