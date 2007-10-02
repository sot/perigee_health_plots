package Ska::Perigee::Data;


=pod

=head1 NAME

Ska::Perigee::Data - Work with perigee pass aca0 image telemetry 

=head1 SYNOPSIS

Common Usage

 use Ska::Perigee::Data qw( retrieve_telem parse_telem make_plots );

 retrieve_telem();
 parse_telem();
 make_plots();

=head1 DESCRIPTION

=head1 EXPORT

None by default.
retrieve_telem, parse_telem, and make_plots are available by request.

=head1 METHODS

=cut


use strict;
use warnings;

use IO::All;
use Carp;
use YAML;

use Data::ParseTable qw( parse_table );

use File::Copy;
use File::Glob;
use Ska::Convert qw(date2time);

use Hash::Merge qw( merge );

use Time::CTime;
use Chandra::Time;

use Data::Dumper;

use PDL;
use PDL::NiceSlice;


use vars qw($VERSION @ISA @EXPORT @EXPORT_OK %EXPORT_TAGS);

require Exporter;




our @ISA = qw(Exporter);
our @EXPORT = qw();
our @EXPORT_OK = qw( retrieve_telem 
		     parse_pass_telem 
		     pass_stats_and_plots 
		     month_stats_and_plots 
		     range_stats_and_plots
		     );
%EXPORT_TAGS = ( all => \@EXPORT_OK );

our $VERSION = '1.0';

# Set some global vars with directory locations
my $SKA = $ENV{SKA} || '/proj/sot/ska';
my $TASK = 'perigee_health_plots';
my $SHARE = "$ENV{SKA}/share/${TASK}";



# This file first has the the main processing routines that are intended
# to be called by external scripts and are ok to export

#sub retrieve_telem{
#sub parse_pass_telem{
#sub pass_stats_and_plots{
#sub month_stats_and_plots{
#sub range_stats_and_plots{



=pod

 * retrieve_telem().  

Retrieves aca0 and ccdm telemetry from perigee passes and stores the
data in the specified directory.

By default, it reads the config files:
   ${SKA}/share/${TASK}/shared.yaml
   ${SKA}/share/${TASK}/get_perigee_telem.yaml

See these files to modify the behavior of the retrieve.

$TASK is hard coded.  $SKA will default to the $SKA environment
variable or /proj/sot/ska .

The method also accepts options to override the location of those config files
and to override the output directory explicitly.

 retrieve_telem( { shared_config => "${SKA}/share/${TASK}/shared.yaml",
                   config => "${SKA}/share/${TASK}/get_perigee_telem.yaml",
                   dir => "/proj/gads6/aca/perigee_health_plots/PASS_DATA/",
                   help => undef,
                   verbose => undef });


=cut

sub retrieve_telem{
    
    my $opt_ref = shift;

    my @allowed_options =  qw( help config shared_config dir verbose );
    check_options({ allowed => \@allowed_options,
		    opt => $opt_ref});

    my %opt = %{$opt_ref};

    my %status;

    my %config = get_configs({ opt => \%opt,
			       shared_config => 'shared.yaml',
			       config => 'get_perigee_telem.yaml',
			       });

    
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
	    chmod 0775, $notes ;
	    
	}
	
    }

    return \%status;

}



=pod

 * parse_pass_telem().  

Reads the aca0 and ccdm telemetry for a perigee pass or passes and
stores, by default, a data.yaml file within the pass directory
containing the relevant telemetry information for most processing.

By default, it reads the config files:
   ${SKA}/share/${TASK}/shared.yaml
   ${SKA}/share/${TASK}/perigee_telem_parse.yaml

The method also accepts options to override the location of those config files
and to override the pass data directory explicitly.

 parse_telem( { shared_config => "${SKA}/share/${TASK}/shared.yaml",
                config => "${SKA}/share/${TASK}/perigee_telem_parse.yaml",
                dir => "/proj/gads6/aca/perigee_health_plots/PASS_DATA/",
                help => undef,
                missing => undef,
                verbose => undef });

If the "missing" flag is unset (or set to 0) the routine searches back
through perigee pass telemetry until it finds the first previously
analyzed directory.  All of the directories up until that directory
are added to a "todo" list that is then parsed.  If the "missing" flag
is set, the routine checks each directory in $opt{dir} to confirm that
it has been parsed.

=cut

sub parse_pass_telem{

    my $opt_ref = shift;

    eval 'use PDL';
    if ($@){
	croak(__PACKAGE__ . ": !$@");
    }
    eval 'use PDL::NiceSlice';
    if ($@){
	croak(__PACKAGE__ . ": !$@");
    }



    my %status;

    my @allowed_options =  qw( help config shared_config dir verbose missing delete v);
    check_options({ allowed => \@allowed_options,
		    opt => $opt_ref});

    my %opt = %{$opt_ref};

    my %config = get_configs({ opt => \%opt,
			       shared_config => 'shared.yaml',
			       config => 'perigee_telem_parse.yaml',
			       });


    
    my $WORKING_DIR = $ENV{PWD};
    if ( defined $opt{dir} or defined $config{general}->{pass_dir} ){
 
	if (defined $opt{dir}){
	    $WORKING_DIR = $opt{dir};
	}
	else{
	    $WORKING_DIR = $config{general}->{pass_dir};
	}
	
    }


    my $out_file = $config{general}->{data_file};


    my $dir_status = find_todo_dir({ dir => $WORKING_DIR,
				     check_files => [ "$out_file" ],
				     opt => \%opt,
				 });



    for my $dir (@{$dir_status->{todo}}){
	if ($opt{verbose}){
	    print "parsing telemetry for $dir \n";
	}
	my $result;
	eval{
	    $result = perigee_parse({ dir => $dir,
				      ska => $SKA,
				      time_interval => $config{task}->{time_interval},
				      min_samples => $config{task}->{min_samples},
				      column_config  => $config{general}->{column_config},
				      pass_time_file => $config{general}->{pass_time_file},
				  });
	};
	if ($@){
	    print "Could not parse telem in $dir \n";
	    print "$@ \n";
	    next;
	}
	
	my $dir_tstart = $dir;
	$dir_tstart =~ s/${WORKING_DIR}\///;
	push @{$status{just_parsed}}, $dir_tstart;

    # let's find points outside the expected ranges from the median
	my %threshold;
	if (defined $config{task}->{threshold}){
	    %threshold = %{$config{task}->{threshold}};
	}
	for my $column (keys %threshold){
	    
	    my $column_pdl = pdl( @{$result->{telem}->{$column}} );
	    
	    my $limit = $threshold{$column};
	    
	    my $not_ok = which( ($column_pdl < ( medover( $column_pdl ) - $limit ))
				| ( $column_pdl > ( medover( $column_pdl ) + $limit )));
	    
	    if ( $not_ok->nelem > 0 ){
		$result->{info}->{bad_points}->{$column} = [ $not_ok->list ];
	    }
	}
	
	my $yaml_out = io("${dir}/$out_file");

	my $comments = io("${SHARE}/$config{task}->{data_file_comments}")->slurp;

	$yaml_out->print("$comments");
	$yaml_out->print(Dump($result));
	
	chmod 0775, "${dir}/$out_file";
	
	if ( -e "${dir}/$out_file" ){
	    if ($opt{delete}){
		unlink("${dir}/acaf*fits.gz");
		unlink("${dir}/ccdm*fits.gz");
	    }
	}
    }

    push @{$status{prev_done}}, @{$dir_status->{done}};

    return \%status;
    
}


=pod 
  
 * pass_stats_and_plots()

Creates statistics yaml files and reports and postscript plots of the perigee pass data.  
The plot configuration is stored in the plot-specific yaml configuration file.
The routine is designed to assist with single pass plots.

See the config file for complete options.

By default, it reads the config files:
   ${SKA}/share/${TASK}/shared.yaml
   ${SKA}/share/${TASK}/plot_health.yaml

The method also accepts options to override the location of those config files
and to override the pass data directory explicitly.

    pass_stats_and_plots( { shared_config => "${SKA}/share/${TASK}/shared.yaml",
                            config => "${SKA}/share/${TASK}/plot_health.yaml",
                            dir => "/proj/gads6/aca/perigee_health_plots/PASS_DATA/",
                            help => undef,
                            dryrun => undef,
                            missing => undef,
                            verbose => undef,
                            tstart => undef,
                            tstop => undef });

The "dryrun" option, if set, causes the routine to print to screen a
list of the plots it would have created if it had been run in truth.


=cut


sub pass_stats_and_plots{

    my $opt_ref = shift;

    eval 'use Ska::Perigee::Pass';
    if ($@){
	croak(__PACKAGE__ . ": !$@");
    }
    

    my @allowed_options =  qw( help config shared_config dir verbose missing delete dryrun );
    check_options({ allowed => \@allowed_options,
		    opt => $opt_ref});
    
    my %opt = %{$opt_ref};
    
    my %status;

    my %config = get_configs({ opt => \%opt,
			       shared_config => 'shared.yaml',
			       config => 'plot_health.yaml',
			   });
    


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

    my @check_files = @{$config{task}->{plots}};
    push @check_files, $config{task}->{stats_file};
    

    my $dir_status = find_todo_dir({ dir => $WORKING_DIR,
				     check_files => \@check_files,
				     opt => \%opt,
				 });


    if (defined $dir_status->{todo}){
	my @todo_directories = @{$dir_status->{todo}};
    
	
	for my $dir (@todo_directories){
	    

	    my $pass_data = Ska::Perigee::Pass->new({ passlist => [ $dir ],
						      config => \%config,
						      opt => \%opt,
						  })->process();
	    
	    $pass_data->save_stats();
	    
	    $pass_data->report();

	    $pass_data->plot();
	    
	}
		
	
    }


}


=pod 
  
 * month_stats_and_plots()

Creates statistics yaml files and reports and postscript plots of the perigee pass data.  
The plot configuration is stored in the plot-specific yaml configuration file.
The routine is designed to assist with summarizing the data for all of the passes in a month.
As such, it figures out which passes are for which months, creates a summary folder for
that month and places the output (statistics yaml and report, plots) in that folder.

See the config file for complete options.

By default, it reads the config files:
   ${SKA}/share/${TASK}/shared.yaml
   ${SKA}/share/${TASK}/make_month_summary.yaml

The method also accepts options to override the location of those config files
and to override the pass data directory explicitly.

    month_stats_and_plots( { shared_config => "${SKA}/share/${TASK}/shared.yaml",
                            config => "${SKA}/share/${TASK}/make_month_summary.yaml",
                            dir => "/proj/gads6/aca/perigee_health_plots/PASS_DATA/",
                            help => undef,
                            dryrun => undef,
                            missing => undef,
                            verbose => undef});

The "dryrun" option, if set, causes the routine to print to screen a
list of the plots it would have created if it had been run in truth.


=cut


sub month_stats_and_plots{

    my $opt_ref = shift;


    eval 'use Ska::Perigee::Range';
    if ($@){
	croak(__PACKAGE__ . ": !$@");
    }


    
    my @allowed_options =  qw( help config shared_config 'redo' verbose dryrun );
    check_options({ allowed => \@allowed_options,
                    opt => $opt_ref});
    
    my %opt = %{$opt_ref};
    
    my %status;
    
    my %config = get_configs({ opt => \%opt,
                               shared_config => 'shared.yaml',
                               config => 'make_month_summary.yaml',
                           });
    

    eval 'use File::Path qw/ mkpath rmtree /';
    if ($@){
	croak(__PACKAGE__ . ": !$@");
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
	
	my @passlist = @{$time_tree{$month}};
	
	unless( $opt{dryrun}){
	    mkpath( "${summary_dir}/${month}", 1);
	    my $pass_list_file = "${summary_dir}/${month}/$config{task}->{pass_file}";
	    print "file is $pass_list_file \n";
	    io($pass_list_file)->print(join("\n", @passlist));
	    
	}
	
	
#    # override plot destination
	$config{task}->{plot_dir} = "${summary_dir}/${month}";
#    # directories to summarize
	
	
	my $month_data = Ska::Perigee::Range->new({ config => \%config,
						    opt => \%opt,
						    passlist => \@passlist,
						})->process;
	

    
	my $summary_file = "${summary_dir}/${month}/$config{task}->{stats_file}";
	

	$month_data->save_stats($summary_file);
    
	my $report_file = "${summary_dir}/${month}/$config{report}->{file}";

	$month_data->report($report_file);

	$month_data->plot();



    }
}



=pod 
  
 * range_stats_and_plots()

Much the same as month_stats_and_plots except it accepts an arbitrary time range and puts the 
reports and plot out to the current directory.

See the config file for complete options.

By default, it reads the config files:
   ${SKA}/share/${TASK}/shared.yaml
   ${SKA}/share/${TASK}/make_month_summary.yaml

The method also accepts options to override the location of those config files
and to override the pass data directory explicitly.

    range_stats_and_plots( { shared_config => "${SKA}/share/${TASK}/shared.yaml",
                            config => "${SKA}/share/${TASK}/make_month_summary.yaml",
                            dir => "/proj/gads6/aca/perigee_health_plots/PASS_DATA/",
                            help => undef,
                            dryrun => undef,
                            missing => undef,
                            verbose => undef,
                            tstart => undef,
                            tstop => undef });

The "dryrun" option, if set, causes the routine to print to screen a
list of the plots it would have created if it had been run in truth.


=cut


sub range_stats_and_plots{

    my $opt_ref = shift;


    eval 'use Ska::Perigee::Range';
    if ($@){
	croak(__PACKAGE__ . ": !$@");
    }



    my @allowed_options =  qw( help config shared_config 'redo' verbose dryrun tstop tstart);
    check_options({ allowed => \@allowed_options,
                    opt => $opt_ref});
    
    my %opt = %{$opt_ref};

    my %status;

    my %config = get_configs({ opt => \%opt,
                               shared_config => 'shared.yaml',
                               config => 'make_month_summary.yaml',
                           });

 
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

    my $dir_status = find_range_dir({ WORKING_DIR => $WORKING_DIR,
				      tstart => $opt{tstart},
				      tstop => $opt{tstop} });

    my @passlist;
    if (defined $dir_status->{todo}){
	
	@passlist = @{$dir_status->{todo}};	

	my $range_data = Ska::Perigee::Range->new({ config => \%config,
						    opt => \%opt,
						    passlist => \@passlist,
						})->process;
	
	
	
	
	my $summary_file = "$config{task}->{stats_file}";
	
	$range_data->save_stats($summary_file);
	
	my $report_file = "$config{report}->{report_file}";
	
	$range_data->report($report_file);
	
	$range_data->plot("$ENV{PWD}");
	
    }
    
}


    
    



sub find_todo_dir{

# returns a reference to a hash of arrays 
# the {todo} array is a list of perigee pass directories that 
#      don't have the files in @check_files
# the {done} array is a list of completed pass directories or
#      just the most recently completed directory
# 
# the routine just steps backward through the pass directories to find
# directories that have yet to be completed



    my $arg_in = shift;
    my $WORKING_DIR = $arg_in->{dir};
    my @check_files = @{$arg_in->{check_files}};
    my %opt = %{$arg_in->{opt}};

    my %dir_status;

# first get a list of directories.
    my @telem_dirs = glob("${WORKING_DIR}/????:*");

# step backward through them until I find one that has an $xml_out_file
    for my $dir ( reverse @telem_dirs ){
	if ( all_files_present($dir, @check_files)){
	    my $dir_tstart = $dir;
	    $dir_tstart =~ s/${WORKING_DIR}\///;
	    push @{$dir_status{done}}, $dir_tstart;
	    last unless $opt{missing};
	}
	else{
	    push @{$dir_status{todo}}, $dir;
	}
	
    }


    return \%dir_status;

}



sub find_range_dir{

# much the same as find_todo_dir, except this looks for directories within
# a specified time range.

# returns a reference to a hash of arrays 
# the {todo} array is a list of perigee pass directories that 
#      don't have the files in @check_files




    my $arg_in = shift;
    my $WORKING_DIR = $arg_in->{dir};
    my $tstart = $arg_in->{tstart};
    my $tstop = $arg_in->{tstop};
    my @check_files = @{$arg_in->{check_files}};

# first get a list of directories.
    my @telem_dirs = glob("${WORKING_DIR}/????:*");

    my @todo_directories;

  DIRECTORY:
    for my $dir (@telem_dirs){
	my $dir_start;
	if ($dir =~ /${WORKING_DIR}\/(.*)/){
	    $dir_start = $1;
	}
	else{
	    next DIRECTORY;
	}
	my $dir_start_secs = Chandra::Time->new($dir_start)->secs();
	
	if (defined $tstart and defined $tstop){
	    next DIRECTORY if ( $dir_start_secs < $tstart );
	    next DIRECTORY if ( $dir_start_secs > $tstop );
	    if ( all_files_present($dir, @check_files)){
		push @todo_directories, $dir;
	    }
	    next DIRECTORY;
	}
	
	if (defined $tstart and not defined $tstop){
	    next DIRECTORY if ($dir_start_secs < $tstart);
	    if ( all_files_present($dir, @check_files)){
		push @todo_directories, $dir;
	    }
	    next DIRECTORY;
	}
	
	if (defined $tstop and not defined $tstart){
	    next DIRECTORY if ($dir_start_secs > $tstop);
	    if ( all_files_present($dir, @check_files)){
		push @todo_directories, $dir;
	    }
	    next DIRECTORY;
	}
	
    }

    my %dir_status;
    $dir_status{todo} = \@todo_directories;
    return \%dir_status;

}




sub all_files_present{

# simple routine that checks to see if all of the files submitted in the
# @check_files list are present in a directory
# if they are not, a 0 status is returned


    my $dir = shift;
    my @check_files = @_;
    my $present = 1;

    if (scalar(@check_files)){
        for my $file (@check_files){
	    if ( -e "${dir}/$file"){
		next;
	    }
	    else{
		$present = 0;
		last;
	    }
	}
    }
    else{
	$present = 0;
    }
    return $present;
}
    


sub check_options{

# simple routine that confirms that there are no keys in the {opt} hashref that 
# are not specified in the {allowed} arrayref

    my $arg_in = shift;
    my $opt_ref = $arg_in->{opt};
    my @allowed_options = @{$arg_in->{allowed}};

    #possible options, help, config, shared_config, dir

    for my $option (keys %{$opt_ref}){
	unless( grep( /^$option$/, @allowed_options)){
	    croak(__PACKAGE__ . "::retrieve_telem(), says undefined option \"$option\"" );
	}

    }
}


sub get_configs{

# Loads specified config files and merges (giving preference to {config} over {shared_config}
# using RIGHT_PRECEDENT hash merge



    my $arg_in = shift;
    my %opt = %{$arg_in->{opt}};
    my $default_shared_config = $arg_in->{shared_config};
    my $default_config = $arg_in->{config};

    my %share_config;
    if ( defined $opt{shared_config}){
	%share_config = YAML::LoadFile( $opt{shared_config} );
    }
    else{
	%share_config = YAML::LoadFile( "${SHARE}/${default_shared_config}" );
    }

    my %task_config;
    if ( defined $opt{config} ){
	%task_config = YAML::LoadFile( $opt{config} );
    }
    else{
	%task_config = YAML::LoadFile( "${SHARE}/${default_config}");
    }

    Hash::Merge::set_behavior( 'RIGHT_PRECEDENT' );

# Also loads additional configs if present in the {task}->{loadconfig} section of either file

    if (defined $task_config{task}->{loadconfig}){
	for my $file (@{$task_config{task}->{loadconfig}}){
	    my %newconfig = YAML::LoadFile("$file");
	    %task_config = %{merge( \%task_config, \%newconfig )};
	}
    }


    my %config = %{ merge( \%share_config, \%task_config )};

    return %config;

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


##***************************************************************************
sub perigee_parse{
##***************************************************************************

# the meat of the perigee pass parsing
# reads the aca level 0 files
# concatenates them along their time dimension
# returns a hash of the columns that were requested

    eval 'use Ska::Telemetry';
    if ($@){
	croak(__PACKAGE__ . ": !$@");
    }
    
    my $args = shift;
    
    my %status;

    my $DIR = $args->{dir};
    my $time_interval = $args->{time_interval};
    my $min_samples = $args->{min_samples};

    
    
# Let's use a config file to define how to "build" our columns from the header 3 telemetry
# see the config file for an explanation of its format
    my $SKA = $args->{SKA};
#    my $SKA = $ENV{SKA} || '/proj/sot/ska';
#    my $column_config_file = "${SKA}/data/perigee_health_plots/column_conversion.yaml";
    my $column_config_file = $args->{column_config};
   
# other files
    my $pass_time_file = "${DIR}/$args->{pass_time_file}";

    
#    print "column config file is $column_config_file \n";
    my %column_conversion = YAML::LoadFile($column_config_file);

    
    my $pass_times = parse_table($pass_time_file);
    my %pass_time_cs = (
			tstart => date2time($pass_times->[0]->{TSTART}),
			tstop => date2time($pass_times->[0]->{TSTOP}),
			);
    
    
# Create a ccdm telemetry object and a hash of aca objects (one for each slot)
    my @ccdmcols = ('time', 'quality', 'cobsrqid' );
    my @ccdm_file_list = glob("${DIR}/ccdm*gz");
    unless (scalar(@ccdm_file_list)){
	croak "No ccdm files found.  Could not parse obsids.\n";
    }
    my $ccdm = Ska::Telemetry::Interval->new({ file_list => \@ccdm_file_list, columns => \@ccdmcols})->combine_telem();
    
    
    my %aca0;
    for my $slot ( 0, 1, 2, 6, 7 ){
	my @file_list = glob("${DIR}/aca*_${slot}_*gz");
	my $aca_telem = Ska::Telemetry::Interval::ACA0->new({ file_list => \@file_list })->combine_telem();
	$aca0{$slot} =  $aca_telem;
    }

    
    
# Use pdl to figure out the time range shared by all the slots and within the time range
    my $maxtimepdl = pdl( $pass_time_cs{tstop} );
    my $mintimepdl = pdl( $pass_time_cs{tstart} );
    for my $slot ( 0, 1, 2, 6, 7 ){
	$maxtimepdl = $maxtimepdl->append( $aca0{$slot}->telem->{time}->max );
	$mintimepdl = $mintimepdl->append( $aca0{$slot}->telem->{time}->min );
    }
    my $maxtime =  $maxtimepdl->min ;
    my $mintime =  $mintimepdl->max ;
    
# calculate the number of intervals for the time range
    my $n_intervals = ($maxtime - $mintime)/($time_interval);
    
# create a hash to store our processed data
    my %result;
    
# throw some stuff into a hash to have it handy later if needed
    %{$result{info}} = (
			sample_interval_in_secs => $time_interval,
			tstart => $mintime,
			tstop => $maxtime,
			min_required_samples => $min_samples,
			number_of_intervals => $n_intervals,
			);
    

    my %temp_result;
    
    for my $i ( 0 ... floor($n_intervals) ){
	
	my $range_start = $mintime + ($i * $time_interval);
	my $range_end = $range_start + $time_interval;
	
	my %ok;
	
	for my $slot (0, 1, 2, 6, 7){
	    # ok if in time range, 8x8 telem, and ok quality
	    $ok{$slot} = which( ( $aca0{$slot}->telem->{time} >= $range_start )
				& ( $aca0{$slot}->telem->{time} < $range_end )
				& ( $aca0{$slot}->telem->{imgdim} == 8 )
				& ( $aca0{$slot}->telem->{quality} == 0 )
				);
	    
	    
	}
	
	my $samples = pdl( map $ok{$_}->nelem(), (0,1,2,6,7) );
	
	if ( $samples->min() == $min_samples ){
	    

	    my $ok_ccdm = which( ($ccdm->telem()->{time} >= $range_start )
				 & ( $ccdm->telem()->{time} < $range_end ));

	    
	    # I just want the ccdm for the obsid
	    my $obsid_pdl = $ccdm->telem->{cobsrqid}->($ok_ccdm);
	    
	    if ( $obsid_pdl->nelem == $min_samples ){
		push @{$temp_result{obsid}}, $obsid_pdl->list;
	    }
	    else{
		my $obsid = $obsid_pdl->at(0);
		my $newpdl = ones($min_samples)*$obsid;
		push @{$temp_result{obsid}}, $newpdl->list;
	    }
	    
	    my @products = keys %column_conversion;
	    
	    # this just performs the simple math to convert the telemetry columns
	    # into spacecraft data in the case there the columns are bitwise
	    for my $name (@products){
		my $product_name = $column_conversion{$name};
		my $product_string = '';
		for my $col_i ( 1, 2 ){
		    my $temp_string = '';
		    if (defined $product_name->{"column${col_i}"}){
			if (defined $product_name->{"joinpre${col_i}"}){
			    $temp_string = $product_name->{"joinpre${col_i}"};
			}
			if (defined $product_name->{"op${col_i}"}){
			    $temp_string .= '( ' 
				. '( $aca0{' . $product_name->{"source"} .'}->telem()->{' 
				. $product_name->{"column${col_i}"} .'}->($ok{'
				. $product_name->{"source"} .'})' . ' )' 
			    . $product_name->{"op${col_i}"} 
			    . ' )';
			}
			else{
			    $temp_string .= 
				'( $aca0{' . $product_name->{"source"} .'}->telem()->{' 
				. $product_name->{"column${col_i}"} .'}->($ok{'
				. $product_name->{"source"} .'})' . ' )' ;
			}
		    }
		    $product_string .= $temp_string;
		}
		if (defined $product_name->{"global"}){
		    $product_string = ' ( ' . $product_string . ' ) ' . $product_name->{"global"};
		}
		
	    push @{$temp_result{$name}}, list( eval( $product_string ));
		
		
	    }
	    
	    

	    
	}
    }
    
# let's convert the hash of arrays to an array of hashes
    
    $result{telem} = \%temp_result;

    
    return \%result;
    
}








1;




=head1 AUTHOR

Jean Connelly ( jconnelly@localdomain )

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2007 by Smithsonian Astrophysical Observatory

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.0 or,
at your option, any later version of Perl 5 you may have available.


=cut


1;
