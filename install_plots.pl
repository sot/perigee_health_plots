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
#use Ska::Convert qw( date2time );

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
my $SUMMARY_DIR;

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
    %task_config = YAML::LoadFile( "${SHARE}/install_plots.yaml");
}

if (defined $task_config{task}->{loadconfig}){
    for my $file (@{$task_config{task}->{loadconfig}}){
        my %newconfig = YAML::LoadFile("$file");
        %task_config = %{merge( \%task_config, \%newconfig )};
    }
}

my %config = %{ merge( \%share_config, \%task_config )};
#use Data::Dumper;
#print Dumper %config;


if ( defined $config{general}->{pass_dir} ){
    $WORKING_DIR = $config{general}->{pass_dir};
}
if ( defined $config{general}->{web_dir}){
    $WEB_DIR = $config{general}->{web_dir};
}
if ( defined $config{general}->{summary_dir} ){
    $SUMMARY_DIR = $config{general}->{summary_dir};
}


#my $source_plot_ext = $config{general}->{source_plot_ext};

print "Installing pass plots to $WEB_DIR \n";


my $source_plot_ext = $config{task}->{source_plot_ext};
my @source_plots = @{$config{task}->{source_plots}};
my @dest_plots = @{$config{task}->{dest_plots}};

my $pass_time_file = $config{general}->{pass_time_file};
my $pass_dir_index = $config{task}->{pass_dir_index};

my %time_tree;

my @passes = glob("${WORKING_DIR}/????:*");

for my $pass_idx ( 0 ... $#passes ){

    my $pass = $passes[$pass_idx];

    my $curr_pass = "${pass}/$pass_time_file";
    my $pass_times = parse_table($curr_pass);

    my $tstart = $pass_times->[0]->{TSTART};
    my $tstop = $pass_times->[0]->{TSTOP};
    
    my $ct_tstart = Chandra::Time->new($tstart)->fits();
    $ct_tstart =~ /(\d{4})-(\d{2})-.*/;
    my $year = $1;
    my $month = $2;
    push @{$time_tree{$year}->{$month}}, $tstart;


    my @plots = glob("${pass}/*.${source_plot_ext}");
    if (scalar(@plots)){
	
	for my $expected_plot (@source_plots){
	    croak("${pass}/${expected_plot} missing ") 
		unless (-e "${pass}/${expected_plot}" );
	}

	unless( $opt{dryrun} ){
	    mkpath("$WEB_DIR/$tstart");
	}
	else{
	    print "Would have converted: \n";
	}

	for my $plot_idx (0 .. $#source_plots){
	    unless( $opt{dryrun} ){
		system(" convert ${pass}/$source_plots[$plot_idx] ${WEB_DIR}/${tstart}/$dest_plots[$plot_idx]"); 
	    }
	    else{
		 print "${pass}/$source_plots[$plot_idx] to ${WEB_DIR}/${tstart}/$dest_plots[$plot_idx] \n";
	    }
	}
	
	my $index = new CGI;
	my $out_string;

	$out_string .= sprintf( $index->start_html(-title=>'ACA Perigee Pass Health Indicators',
						   -style=>{'src'=> $config{task}->{stylesheet}},
							    ));

	my $base_url = $config{general}->{base_url};

	my $nav_links;

	$nav_links .= "<A HREF=\"${base_url}\">UP</A><br />\n";

	if ($pass_idx > 0){
	    my $prev = $passes[$pass_idx - 1];
	    my $prev_pass = "${prev}/$pass_time_file";
	    my $prev_pass_times = parse_table($prev_pass);
	    my $prev_tstart = $prev_pass_times->[0]->{TSTART};
	    $nav_links .= "<A HREF=\"${base_url}/${prev_tstart}\">PREV</A><br />\n";
	    
	}


	if ($pass_idx < $#passes){
	    my $next = $passes[$pass_idx + 1];
	    my $next_pass = "${next}/$pass_time_file";
	    my $next_pass_times = parse_table($next_pass);
	    my $next_tstart = $next_pass_times->[0]->{TSTART};
	    $nav_links .= "<A HREF=\"${base_url}/${next_tstart}\">NEXT</A><br />\n";
	}

	# the eval substitutes in $nav_links, base_url, tstart, tstop, and @dest_plots
	$out_string .= eval("<<EOF\n$config{task}->{pass_text}\nEOF\n" );

	$out_string .= sprintf( $index->end_html );
	
	my $index_file = io("${WEB_DIR}/${tstart}/$pass_dir_index");
	unless( $opt{dryrun} ){
	    $index_file->print($out_string);
	}
	else{
	    print "Would have made: ${WEB_DIR}/${tstart}/$pass_dir_index \n";
	}

	
    }


}


print "Installing summary plots to $WEB_DIR \n";

my @summaries = glob("${SUMMARY_DIR}/????-??");

for my $summ_month ( @summaries ){

    @source_plots = @source_plots[0,1,2,3];
    my @plots = glob("${summ_month}/*.${source_plot_ext}");
    if (scalar(@plots)){
	
	my $month_string;
	if ($summ_month =~ /${SUMMARY_DIR}\/(.*)/){
	    $month_string = $1;
	}
	    
	for my $expected_plot (@source_plots){
	    croak("${summ_month}/${expected_plot} missing ") 
		unless (-e "${summ_month}/${expected_plot}" );
	}

	unless( $opt{dryrun}){
	    mkpath("$WEB_DIR/$month_string");
	}
	else{
	    print "Would have mkdir $WEB_DIR/$month_string \n";
	    print " and converted files: \n";
	}

	for my $plot_idx (0 .. $#source_plots){
	    unless( $opt{dryrun}){
		system(" convert ${summ_month}/$source_plots[$plot_idx] ${WEB_DIR}/${month_string}/$dest_plots[$plot_idx]"); 
	    }
	    else{
		print "${summ_month}/$source_plots[$plot_idx] to ${WEB_DIR}/${month_string}/$dest_plots[$plot_idx] \n";
	    }
	}
	    

    }

}


my %month_map = %{$config{task}->{month_map}};

my @year_list = sort (keys %time_tree);
my @year_links = map { $_ . ".html" } @year_list;

#make_nav_page( 'index', \@year_links, $config{general}->{base_dir}, $WEB_DIR);

my $index = new CGI;

my $main_page .= sprintf( $index->start_html(-title=>'ACA Perigee Health Plots',
					   -style=>{'src'=> $config{task}->{stylesheet}},
					   ));

#$main_page .= "<H2>ACA Perigee Health Plots</H2>";



my $nav_table;

$nav_table .= "<TABLE BORDER=1><TR>";

for my $year (sort (keys %time_tree)){
    $nav_table .= "<TH>$year</TH>";
    my @month_list = sort keys %{$time_tree{$year}};
    my @month_links = map { $month_map{$_} . ".html" } @month_list;
#    make_nav_page( $year, \@month_links, $config{general}->{base_dir}, $WEB_DIR);
    for my $month_idx (0 .. $#month_list){
	my $month = $month_list[$month_idx];
	my ($prev_month, $next_month, $prev_string, $next_string);
	if ($month_idx > 0){
	    $prev_month = $month_list[$month_idx - 1];
	    $prev_string = $config{general}->{base_url} . sprintf( "%s-%02d.html", $year, $prev_month );
	}
	if ($month_idx < $#month_list){
	    $next_month = $month_list[$month_idx + 1];
	    $next_string = $config{general}->{base_url} . sprintf( "%s-%02d.html", $year, $next_month );
	}
	my $summ_string = sprintf( "%s-%02d", $year, $month);
#	print "going through month list $month \n";
	make_nav_page({
	    body => $config{task}->{month_text},
	    month_num => $month,
	    month_name => $month_map{$month}, 
	    prev_month => $prev_string,
	    next_month => $next_string,
	    year => $year,
	    passes => $time_tree{$year}->{$month}, 
	    base_url => $config{general}->{base_url}, 
	    web_dir => $WEB_DIR, 
	    plots => \@dest_plots});
	$nav_table .= "<TD><A HREF=\"${summ_string}.html\">$month_map{$month}</A></TD>";

#	print "for year $year and month $month :\n";
#	for my $pass (@{$time_tree{$year}->{$month}}){
#	    print "pass is $pass \n";
#	}
    }
    $nav_table .= "</TR>";
}
$nav_table .= "</TABLE></BODY></HTML>";
#print $main_page;

# eval substitues in nav_table

$main_page .= eval("<<EOF\n$config{task}->{main_text}\nEOF\n" );
#$main_page .= $config{task}->{main_text};

my $index_file = io("${WEB_DIR}/index.html");
unless( $opt{dryrun}){
    $index_file->print($main_page);
}
else{
    print "Would have made ${WEB_DIR}/index.html \n";
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



sub make_nav_page{
    my $arg_in = shift;
    my $body = $arg_in->{body};
    my $month_num = $arg_in->{month_num};
    my $month_name = $arg_in->{month_name};
    my $year = $arg_in->{year};
    my $passes = $arg_in->{passes};
    my $base_dir = $arg_in->{base_url};
    my $web_dir = $arg_in->{web_dir};
    my @dest_plots = @{$arg_in->{plots}};
    my $prev_month = $arg_in->{prev_month};
    my $next_month = $arg_in->{next_month};

    my $index = new CGI;

    
    my $summ_string = sprintf( "%s-%02d", $year, $month_num);

#    my $out_string = "<HTML><HEAD></HEAD><BODY><br />\n";
    my $out_string = sprintf( $index->start_html(-title=>'ACA health Summary Plots',
						 -style=>{'src'=> $config{task}->{stylesheet}},
						 ));

    my $nav_links;
    
    $nav_links .= "<A HREF=\"${base_dir}\">UP TO MAIN</A><br />\n";

    if (${prev_month}){
	$nav_links .= "<A HREF=\"${prev_month}\">PREVIOUS MONTH</A><br />\n";
    }
    if (${next_month}){
	$nav_links .= "<A HREF=\"${next_month}\">NEXT MONTH</A><br />\n";
    }

    my $pass_table;
    $pass_table .= "<TABLE BGCOLOR=\"white\">\n";

    for my $pass_idx (0 .. scalar(@{$passes})-1){
	my @colorlist = @{$config{task}->{allowed_colors}};
	my %colormap = %{$config{task}->{pg_to_html_colors}};
	my $entry = $passes->[$pass_idx];
	my $pg_color_idx = ($pass_idx) % scalar(@colorlist);
        my $pg_color = $colorlist[$pg_color_idx];
	my $color = $colormap{$pg_color};
	$pass_table .= "<TR>";
	$pass_table .= "<TD BGCOLOR=\"$color\" WIDTH=\"25\">&nbsp;</TD>\n";
	$pass_table .= "<TD><A HREF=\"${base_dir}/${entry}/index.html#plot\">${entry}</A></TD>\n";
	$pass_table .= "</TR>";
    }
    $pass_table .= "</TABLE>\n";
    
    # eval substitudes nav_links and pass_table
    $out_string .= eval("<<EOF\n$body\nEOF\n" );
    
    $out_string .= sprintf( $index->end_html );
    
    my $out_file = io("${WEB_DIR}/${summ_string}.html");
    unless( $opt{dryrun} ){
	$out_file->print($out_string);
    }
    else{
	print "Would have made: ${WEB_DIR}/${summ_string}.html \n";
    }
}


#sub make_nav_table{
#    my $name = shift;
#    my $link_ref = shift;
#    my $base_dir = shift;
#    
#    my $out_string = "<TABLE>";
#    $out_string .= "<TR><TH>$name</TH></TR>";
#    for my $entry (@{$link_ref}){
#	$out_string .= "<TR><TD><A HREF=\"${base_dir}/${entry}\">${entry}</A></TD></TR><br />\n";
#    }
#    $out_string .= "</TABlE>";
#    return $out_string;
#}
    

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



