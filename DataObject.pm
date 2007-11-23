package Ska::Perigee::DataObject;

use strict;
use warnings;

use Time::CTime;
use IO::All;

#use Data::ParseTable qw( parse_table );
use Carp;

#use Getopt::Long;
#use File::Glob;
use Ska::Convert qw(date2time);
#use File::Copy;
use Data::Dumper;
use YAML;

#use Hash::Merge qw( merge );

use vars qw($VERSION @ISA @EXPORT @EXPORT_OK %EXPORT_TAGS);

require Exporter;

our @ISA = qw(Exporter);
our @EXPORT = qw();
our @EXPORT_OK = qw( );
%EXPORT_TAGS = ( all => \@EXPORT_OK );

our $VERSION = '1.0';



# Set some global vars with directory locations
my $SKA = $ENV{SKA} || '/proj/sot/ska';
my $TASK = 'perigee_health_plots';
my $SHARE = "$ENV{SKA}/share/${TASK}";



# I stuck these in an eval section later... we only need to load them if we
# have to grab data
#
# use File::Path;
# use Ska::Process qw/ get_archive_files /;
# use IO::All;

use PDL;
use PDL::NiceSlice;
use YAML;

use Data::Dumper;
use Chandra::Time;

use Class::MakeMethods::Standard::Hash(
				       scalar => [ qw(
						      tstart
						      tstop
						      config
						      opt
						      passlist
						      todo_directories
						      pass_data
						      aggregate_pdl
						      fit_result
						      )
						   ],
				       );


use Data::Dumper;

sub new{
    my $class = shift;
    my $arg_href = shift;
    my $self = {};
    bless $self, $class;
    
    if (defined $arg_href->{tstart}){
	$self->tstart($arg_href->{tstart});
    }
    if (defined $arg_href->{tstop}){
	$self->tstop($arg_href->{tstop});
    }
    if (defined $arg_href->{config}){
	$self->config($arg_href->{config});
    }
    if (defined $arg_href->{opt}){
	$self->opt($arg_href->{opt});
    }
    else{
	my %dummyopt = ();
	$self->opt(\%dummyopt);
    }
    if (defined $arg_href->{passlist}){
	$self->passlist($arg_href->{passlist});
    }

    return $self;
}



sub process{
# perform the actions to 
#    1) find the relevant data directories,
#    2) read in the data 
#    3) calculate rough statistics over the interval requested
#    4) fit polynomials as requested 
    my $self = shift;
    $self->select_analyzed_dir();
    $self->prepare_data();
    $self->pdl_stats();
    $self->polyfit();
    return $self;
}





sub select_analyzed_dir{
    # find all directories within the specified time range that have
    # the yaml data file

    my $self = shift;
    my %config = %{$self->config()};
    my $WORKING_DIR = $config{general}->{pass_dir};
    my $tstart = $self->tstart();
    my $tstop = $self->tstop();
    my %opt = %{$self->opt()};

    my $yaml_data_file = $config{general}->{data_file};

    my @todo_directories;

# first get a list of directories.
    my @telem_dirs = glob("${WORKING_DIR}/????/????:*");


# first, if time range specified for multi or summary plots,
# just get all the dirs in that time range
    if (defined $self->passlist()){
	@todo_directories = @{$self->passlist()};
    }
    else{
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
		if ( -e "${dir}/${yaml_data_file}"){
		    push @todo_directories, $dir;
		}
		next DIRECTORY;
	    }
	    
	    if (defined $tstart and not defined $tstop){
		next DIRECTORY if ($dir_start_secs < $tstart);
		if ( -e "${dir}/${yaml_data_file}"){
		    push @todo_directories, $dir;
		}
		next DIRECTORY;
	    }
	    
	    if (defined $tstop and not defined $tstart){
		next DIRECTORY if ($dir_start_secs > $tstop);
		if ( -e "${dir}/${yaml_data_file}"){
		    push @todo_directories, $dir;
		}
		next DIRECTORY;
	    }
	    
	}
    }
    
    
    $self->todo_directories(\@todo_directories);

    return $self;
    
}



sub prepare_data{
    # read in the yaml data files from a directory or a list of directories
    # store the pdls in a hash by pass and in aggregate

    my $self = shift;

    my $dirlist = $self->todo_directories();
    my $config = $self->config();
    my $opt = $self->opt();
    
    my @columns = @{$config->{task}->{data_columns}};

    my @data_array;
    my %agg_data_pdl;

    for my $dir (@{$dirlist}){
#	print "dir is $dir \n";
	
	my $yaml_file = "${dir}/$config->{general}->{data_file}";

	my $yaml;
	eval{
	    $yaml = YAML::LoadFile($yaml_file);
	};
	if ($@){
	    print "Problem loading $yaml_file \n $@ \n";
	    print "Skipping $dir \n";
	    next;
	}

	my %data = %{$yaml->{telem}};
	my %info = %{$yaml->{info}};

# convert the handy text arrays to pdls
	my %datapdl;
	for my $column ( @columns ){
	    $datapdl{$column} = pdl( @{$data{$column}} );
	}

# exclude marked bad points
	eval{
	    if( defined $info{bad_points} ){
		%datapdl = clean_bad_points( $info{bad_points}, \%datapdl);
	    }
	};
	if ($@){
	    croak("$@");
	}

#let's figure out how many obsids are present
	my @uniqobsid = $datapdl{obsid}->uniq->list;

	# and let's store the index slices for each obsid
# and store the number of the slice of the first instance of the obsid (for sorting)
	my %obsid_idx;
	my %obsid_first_idx;
	for my $i (0 ... $#uniqobsid){
	    my $obsid = $uniqobsid[$i];
	    my $obsid_match_idx = which( $datapdl{obsid} == $obsid );
	    $obsid_idx{$obsid} = $obsid_match_idx;
	    $obsid_first_idx{$obsid} = $obsid_match_idx->min;
	    
	}
	
# and let's create an ordered list of the obsids
	my @ordered_obsid = sort {$obsid_first_idx{$a} <=> $obsid_first_idx{$b}}  keys %obsid_first_idx;
	
# and let's defined time t0
	my $tzero = $datapdl{time}->min;
	
# let's define a new delta time, dtime in hours
	$datapdl{dtime} = ($datapdl{time} - $tzero)/(60*60);
	

	$datapdl{dtemp} = $datapdl{aca_temp} - $datapdl{ccd_temp};

	    
# concatenate any needed data for aggregate analysis


	if (defined $config->{task}->{stats_columns}){


	    my @columns = @{$config->{task}->{stats_columns}};
	    for my $col (@columns){
		if (not defined $agg_data_pdl{$col}){
		    $agg_data_pdl{$col} = $datapdl{$col};
		}
		else{
		    $agg_data_pdl{$col} = append( $agg_data_pdl{$col}, $datapdl{$col});
		}
	    }

	}

	my %dir_data = (
			dirname => $dir,
			pdl => \%datapdl,
			ordered_obsid => \@ordered_obsid,
			obsid_idx => \%obsid_idx,
			);

	push @data_array, \%dir_data;
    }

    $self->pass_data(\@data_array);
#    return @data_array;


    $self->aggregate_pdl(\%agg_data_pdl);
    
    return $self;

}



sub pdl_stats{
    # return the standard stats for all of the telemetry pdls

    my $self = shift;

    if (defined $self->{pdl_stats}){
	return $self->{pdl_stats};
    }
    else{

	my %agg_pdl = %{$self->aggregate_pdl};

	my @columnlist = keys %agg_pdl;
	
	my %stats;

	for my $column (@columnlist){
	    
	    if (not defined $agg_pdl{$column}){
		print "column  $column not defined \n";
	    }
	    
	    my %pdl_stat;
	    ($pdl_stat{mean},$pdl_stat{rms},$pdl_stat{median},$pdl_stat{min},$pdl_stat{max}) = $agg_pdl{$column}->stats;
	    
	    $stats{$column} = \%pdl_stat;
	}

	$self->{pdl_stats} = \%stats;
	return $self->{pdl_stats};
    }

}



sub clean_bad_points{
    # delete time slices for pdls that are outside of the specified thresholds

    my $bad_points = shift;
    my $datapdl = shift;

    my %newdatapdl;

    for my $column (keys %{$bad_points}){
        next unless defined $datapdl->{$column};
        my $not_ok = pdl( $bad_points->{$column} );
        my $dummy = ones($datapdl->{$column});
        $dummy->($not_ok) .= 0;
        my $ok = which( $dummy == 1 );
        for my $origcolumn (keys %{$datapdl}){
            eval{
                my $newpdl = $datapdl->{$origcolumn}->($ok);
                delete $datapdl->{$origcolumn};
                $newdatapdl{$origcolumn} = $newpdl;
            };
            if ($@){
                croak("clean_bad_points $origcolumn failed $@");
            }
        }
    }

    return %newdatapdl;
}



sub polyfit{
    # fit polynomials as requested (in the config files) to the aggregate pdls 
    
    my $self = shift;

    if ( defined $self->fit_result() ){
	return  $self->fit_result();
    }
    else{

	my $agg_pdl = $self->aggregate_pdl();

	my $stats = $self->pdl_stats();
	my $config = $self->config();
	
	if (defined $config->{task}->{polyfit}){
	
	    my %fit_result;
	
	    for my $fit (@{$config->{task}->{polyfit}}){
		
		my $xname = $fit->{x};
		my $yname = $fit->{y};
		my $name = $fit->{result};
		my $min_dx = $fit->{min_dx};
		
		
#	my $x_name = $fit->{x};
#	my $y_name = $fit->{y};
		eval 'use PDL::Fit::Polynomial';
		eval 'use PDL::NiceSlice';
## let's fit a polynomial to the chunk
		my $xdata = $agg_pdl->{$xname};
		my $ydata = $agg_pdl->{$yname};
		my $xstats = $stats->{$xname};

		my $order = ($fit->{order});
		$order = $order + 1;
		
		my ($yfit, $coeffs);
		if (($xstats->{max} - $xstats->{min}) < $min_dx){
#		    my $diff = $xstats->{max} - $xstats->{min};
		    $fit_result{$name}->{fitsuccess} = 0;
#		print "diff is $diff \n";
		    $coeffs = pdl( $xstats->{mean}, 0 );
		    $fit_result{$name}->{coeffs} = [$coeffs->list];
		}
		else{
		    ($yfit, $coeffs) = fitpoly1d($xdata, $ydata, $order);
		    $fit_result{$name}->{fitsuccess} = 1;
		    $fit_result{$name}->{coeffs} = [$coeffs->list];
		}	    
		
		if ( defined $fit->{points} ){
		    
		    my @poly = @{$fit_result{$name}->{coeffs}};
		    my @points;
		    
		    for my $fit_point ( @{ $fit->{points} } ){
			my $type = $fit_point->{type};

			if ( $type eq 'fit_y' ){

			    my $plug = $fit_point->{plug_x};
			    my $yval = 0;
			    for my $i (0 .. $#poly){
				$yval += $poly[$i] * ($plug**$i);
			    }
			    my %point = ( x => $plug,
					  y => $yval,
				      );
			    push @points, \%point;
			}
			if ( $type eq 'fit_x' ){
			    my $y = $fit_point->{solve_y};
			    my $solve_xmin = $fit_point->{xmin};
			    my $solve_xmax = $fit_point->{xmax};
			    my $npoints = 1000;
			    my $xvals = sequence($npoints+1)*(($solve_xmax - $solve_xmin)/($npoints))+(($solve_xmin));
			    my $yvals = 0;
			    for my $i (0 .. $#poly){
				$yvals += $poly[$i] * ($xvals**$i);
			    }
			    my $y_diff = abs($yvals - $y);
			    my $x_idx = which($y_diff eq min($y_diff));

			    my %point = ( x => $xvals->($x_idx)->sclr,
					  y => $y,
				      );
			    push @points, \%point;
			}
			
		    }

		    $fit_result{points} = \@points;

		}
		
	    }


	    
	$self->fit_result(\%fit_result);	
	}	
	
	    return $self;
    }

}

##***************************************************************************
sub plot_health{
##***************************************************************************
    # gathers a bunch of information, creates PlotHelper objects, and plots
    # the pass or passes as requested


    my $self = shift;
    my $dirlist = shift;
    my $config = shift;
    my $opt = shift;


    my @columns = @{$config->{task}->{data_columns}};
    my @data_array;


    for my $dir (@{$dirlist}){
#	print "dir is $dir \n";
	
	my $yaml_file = "${dir}/$config->{general}->{data_file}";

# read in data from YAML file
#	my $dump = new XML::Dumper;
#	my $xml = $dump->xml2pl( $xml_file );
	my $yaml;
	eval{
	    $yaml = YAML::LoadFile($yaml_file);
	};
	if ($@){
	    print "Problem loading $yaml_file \n $@ \n";
	    print "Skipping $dir \n";
	    next;
	}

	my %data = %{$yaml->{telem}};
	my %info;
	if (defined $yaml->{info}){
	    %info = %{$yaml->{info}};
	}

# convert the handy text arrays to pdls
	my %datapdl;
	for my $column ( @columns ){
	    $datapdl{$column} = pdl( @{$data{$column}} );
	}


# exclude marked bad points
	eval{
	    if( defined $info{bad_points} ){
		%datapdl = clean_bad_points( $info{bad_points}, \%datapdl);
	    }
	};
	if ($@){
	    croak("$@");
	}
	 
#	print $datapdl{obsid};
	
    
#let's figure out how many obsids are present
	my @uniqobsid = $datapdl{obsid}->uniq->list;

	# and let's store the index slices for each obsid
# and store the number of the slice of the first instance of the obsid (for sorting)
	my %obsid_idx;
	my %obsid_first_idx;
	for my $i (0 ... $#uniqobsid){
	    my $obsid = $uniqobsid[$i];
	    my $obsid_match_idx = which( $datapdl{obsid} == $obsid );
	    $obsid_idx{$obsid} = $obsid_match_idx;
	    $obsid_first_idx{$obsid} = $obsid_match_idx->min;
	    
	}
	
# and let's create an ordered list of the obsids
	my @ordered_obsid = sort {$obsid_first_idx{$a} <=> $obsid_first_idx{$b}}  keys %obsid_first_idx;

#	use Data::Dumper;
#	print Dumper @ordered_obsid;
	
# and let's defined time t0
	my $tzero = $datapdl{time}->min;
	
# let's define a new delta time, dtime in hours
	$datapdl{dtime} = ($datapdl{time} - $tzero)/(60*60);
	
#    print $datapdl{dtime}->(10);
	$datapdl{dtemp} = $datapdl{aca_temp} - $datapdl{ccd_temp};
	
	my %dir_data = (
			dirname => $dir,
			pdl => \%datapdl,
			ordered_obsid => \@ordered_obsid,
			obsid_idx => \%obsid_idx,
			);



	push @data_array, \%dir_data;
    }


# if I want 1 pass per plot, run in a loop and put the plots in the pass
# directory


    if ($config->{task}->{dir_mode} eq 'single'){

	for my $dir (@data_array){
	    
	    my %colranges = find_pdl_ranges( [$dir]);

#	    print Dumper %colranges;
	    
	    my $plot_helper = PlotHelper->new({ config => $config,
						opt => $opt,
						data_array => [$dir],
						ranges => \%colranges,
						polyfit => $self->fit_result(),
					    });
	    
#	    $plot_helper->plot( 'aca_temp' );
           
#	    $plot_helper->plot( 'ccd_temp' );
	    
#	    $plot_helper->plot( 'dac' );
	    
	    $plot_helper->plot( 'dac_vs_dtemp' );

	    $plot_helper->legend();
	    

	}
	
    }

# else, gather all of the pass data and make multi or summary plots

    else{
	
	my %colranges = find_pdl_ranges( \@data_array );

	my $plot_helper;
	    
	$plot_helper = PlotHelper->new({ config => $config,
					 opt => $opt,
					 data_array => \@data_array,
					 ranges => \%colranges,
					 polyfit => $self->fit_result(),
				     });
	
	
	$plot_helper->plot( 'aca_temp' );
	
	$plot_helper->plot( 'ccd_temp' );
	
	$plot_helper->plot( 'dac' );
	
	$plot_helper->plot( 'dac_vs_dtemp' );
	


    }	
    

}


sub find_pdl_ranges{

    my $data_ref = shift;

    # they should all have the same columns
    my @columnlist = keys %{$data_ref->[0]->{pdl}};

    my %colranges;

    for my $column (@columnlist){

	my ($overall_min, $overall_max);
#      my ($mindir, $maxdir);
	for my $dir_data (@{$data_ref}){


	    if (not defined $dir_data->{pdl}->{$column}){
		print "column  $column not defined \n";
	    }
	    my ($mean,$rms,$median,$min,$max) = $dir_data->{pdl}->{$column}->stats;

	    if (not defined $overall_min){
		$overall_min = $min;

	    }
	    else{
		if ($min < $overall_min){
		    $overall_min = $min;
		}
	    }
	    if (not defined $overall_max){
		$overall_max = $max;
	    }
	    else{
		if ($max > $overall_max){
		    $overall_max = $max;
		}
	    }
	}

       my %range = (
                    min => $overall_min,
                    max => $overall_max,
                    );

	$colranges{$column} = \%range;


    }

    return %colranges;
}




sub save_stats{

    my $self = shift;
    my $file = shift;
    my %opt = %{$self->opt()};
    

    my %summary;
    if (defined $self->fit_result()){
        $summary{fit_result} = $self->fit_result();
    }
    $summary{stats} = $self->pdl_stats();
    my $summary_yaml = YAML::Dump(%summary);

#    if ($opt{verbose}){
#        print $summary_yaml, "\n";
#    }

    my $destfile = $file;

    if( $self->config()->{task}->{dir_mode} eq 'single'){
	my $destdir = $self->{passlist}->[0];
	$destfile = "$destdir" . "/" . $self->config()->{task}->{stats_file};
    }
    
    if (defined $destfile){
	unless ($opt{dryrun}){
	    io($destfile)->print($summary_yaml);
	}
    }
}

sub report{

    my $self = shift;
    my $savefile = shift;
    my %opt = %{$self->opt()};

    my $report_config = $self->config()->{report};

    my $template_file = "${SHARE}/" . $report_config->{report_text};
    my $report_text = io($template_file)->slurp;

    my %report;

    my $pass_dir = $self->config()->{general}->{pass_dir};

    my $full_path_dirname;
    if ($self->config()->{task}->{dir_mode} eq 'single'){
	my $pass = $self->passlist->[0];
	$full_path_dirname = $pass;
	my $dirname = $full_path_dirname;
	$dirname =~ s/$pass_dir\/?//;
	push @{$report{pass_list}}, $dirname;
    }

    
    for my $plotcfg_name (keys %{$self->config()->{plot}}){
	my $plotcfg = $self->config()->{plot}->{$plotcfg_name};
	if (defined $plotcfg->{warn}){
	    for my $key (%{$plotcfg->{warn}}){
		if ($key eq 'max'){
		    my $datamax = $self->pdl_stats->{$plotcfg_name}->{max};
		    my $warnmax = $plotcfg->{warn}->{$key};
		    if ($datamax > $warnmax){
			if (scalar(@{$report{pass_list}}) == 1){
			    push @{$report{warnings}}, sprintf("For pass: " . $report{pass_list}->[0] );
			}
			push @{$report{warnings}}, "Warning $plotcfg_name exceeded defined threshold";
			push @{$report{warnings}}, "Threshold: $warnmax";
			push @{$report{warnings}}, "$plotcfg_name high Value: $datamax";
		    }
		}
	    }
	}
    }
    if ( not defined $report{warnings}){
	push @{$report{warnings}}, "No warnings reported";
    }
    else{
	if (scalar(@{$report{pass_list}}) == 1){
	    use Mail::Send;
	    my $msg = new Mail::Send;
	    $msg->to($self->config()->{general}->{notify});
	    $msg->subject("Perigee Health Notification");
	    my $fh = $msg->open;
	    my $message = join( "\n", @{$report{warnings}} );
	    print $fh $message;
	    $fh->close;
    	}
    }
	
    
    my %ranges = %{$self->pdl_stats()};
    $report{aca_temp_max} = sprintf( "%6.1f", $ranges{aca_temp}->{max});
    $report{aca_temp_min} = sprintf( "%6.1f", $ranges{aca_temp}->{min});
    $report{aca_temp_mean} = sprintf( "%6.1f", $ranges{aca_temp}->{mean});
    $report{ccd_temp_max} = sprintf( "%6.1f", $ranges{ccd_temp}->{max});
    $report{ccd_temp_min} = sprintf( "%6.1f", $ranges{ccd_temp}->{min});
    $report{ccd_temp_mean} = sprintf( "%6.1f", $ranges{ccd_temp}->{mean});
    $report{dac_max} = sprintf( "%6.1f", $ranges{dac}->{max});
    $report{dac_min} = sprintf( "%6.1f", $ranges{dac}->{min});
    $report{dac_mean} = sprintf( "%6.1f", $ranges{dac}->{mean});	


    for my $keyword (keys %report){
	my $file_keyword = uc($keyword);
	if (ref($report{$keyword}) eq 'ARRAY'){
	    my $text = '';
	    for my $line (@{$report{$keyword}}){
		$text .= "$line \n";
	    }
	    $report_text =~ s/%${file_keyword}%/$text/g;
	}
	else{
	    $report_text =~ s/%${file_keyword}%/$report{$keyword}/g;
	}
    }



    my $destfile = $savefile;
    if( $self->config()->{task}->{dir_mode} eq 'single'){
        my $destdir = $self->{passlist}->[0];
        $destfile = "$destdir" . "/" . $report_config->{file};
    }

    if (defined $destfile){
        unless ($opt{dryrun}){
            io($destfile)->print($report_text);
        }
    }



}



1;    




package PlotHelper;

use strict;
use warnings;
use Class::MakeMethods::Standard::Hash(
                                        scalar => [ qw(
						       config
						       opt
						       data_array
						       data_ranges
						       coeffs
						       polyfit
						       )
                                                    ],
				       );

use PGPLOT::Simple qw( pgs_plot );
use PDL::NiceSlice;
use PDL;
use PGPLOT;
use Data::Dumper;
use IO::All;

#my $obsid_count = 0;
#my $pass_count = 0;

sub new{

    my $class = shift;
    my $self = {};
    bless $self, $class;

    my $arg_in = shift;
#    $obsid_count = 0;
#    $pass_count = 0;
    $self->config($arg_in->{config});
    $self->data_array($arg_in->{data_array});
    $self->data_ranges($arg_in->{ranges});
    $self->opt($arg_in->{opt});

    if (defined $arg_in->{polyfit}){
	$self->polyfit($arg_in->{polyfit});
    }



    return $self;

}



sub make_plot_summary{

    my $arg_in = shift;
    my $y_type = $arg_in->{plot_config}->{y};
    my $x_type = $arg_in->{plot_config}->{x};
    my $data_ref = $arg_in->{data_array};
    my @colorlist = @{$arg_in->{color_array}};
    my $axis_num_size = $arg_in->{plot_config}->{axis_num_size};
    my $axis_title_size = $arg_in->{plot_config}->{axis_title_size};

    my @data_plot_array;

    my $starttime;

    if ($x_type eq 'time'){
	for my $datadir (@{$data_ref}){
	    my $xmin = $datadir->{pdl}->{$x_type}->min;
	    if (not defined $starttime){
		$starttime = $xmin;
	    }
	    else{
		if ($xmin < $starttime){
		    $starttime = $xmin;
		}
	    }
	}
    }


    for my $dir_num ( 0 ... scalar(@{$data_ref})-1 ){
	
	my $datadir = $data_ref->[$dir_num];
	my $coloridx = ($dir_num) % scalar(@colorlist);
	my $color = $colorlist[$coloridx];

	my $xmin = $datadir->{pdl}->{$x_type}->min;
	my $xmax = $datadir->{pdl}->{$x_type}->max;

	if ($x_type eq 'time'){
	    $xmin = ($xmin - $starttime)/86400; # find time difference and convert to days
	    $xmax = ($xmax - $starttime)/86400; 
	}

	my $xmid = ($xmin+$xmax)/2;

	push @data_plot_array, ( charsize => { axis => $axis_num_size, title => $axis_title_size } );

	# if it is a poly fit stored at the top level of the hash:
	if (defined $datadir->{$y_type}){
	    my $y = $datadir->{$y_type};
	    my @yvalue = [ $y ];
	    my @xvalue = [ $xmid ];
	    push @data_plot_array, (
				    'x' => [ @xvalue],
				    'y' => [ @yvalue],
				    color => { symbol => $color },
				    plot => 'points',
				    );

	}
	# if we really want poly fit.
	else{

	    my ($ymean,$yrms,$ymedian,$ymin,$ymax) = $datadir->{pdl}->{$y_type}->stats;	
	
	    my @yvalue = [ $ymin, $ymin ];
	    my @xvalue = [ $xmin, $xmax ];
	    push @data_plot_array , (
				     'x' => [@xvalue],
				     'y' => [@yvalue],
				     color => { line => 'black' },
				     plot => 'line',
				     );
	
	    @yvalue = [ $ymax, $ymax ];
	    @xvalue = [ $xmin, $xmax ];
	    push @data_plot_array , (
				     'x' => [@xvalue],
				     'y' => [@yvalue],
				     color => { line => 'black' },
				     plot => 'line',
				     );
	    
	    @yvalue = [ $ymean ];
	    @xvalue = [ $xmid ];
	    push @data_plot_array , (
				     'x' => [@xvalue],
				     'y' => [@yvalue],
				     color => { symbol => $color },
				     plot => 'points',
				     );
	    
	    
	    @yvalue = [ $ymin, $ymax ];
	    @xvalue = [ $xmid, $xmid ];
	    push @data_plot_array , (
				     'x' => [@xvalue],
				     'y' => [@yvalue],
				     color => { line => $color },
				     plot => 'line',
				     );
	    
	    
	    
	}
	
    }
    
    return @data_plot_array;

}


sub make_plot_a_vs_b{

    my $arg_in = shift;
    my $curr_config = $arg_in->{plot_config};
    my $a = $arg_in->{plot_config}->{y};
    my $y_type = $a;
    my $b = $arg_in->{plot_config}->{x};
    my $x_type = $b;
    my $data_ref = $arg_in->{data_array};
    my @colorlist = @{$arg_in->{color_array}};
    my $symbol_size = $arg_in->{plot_config}->{symbol_size};
    my $axis_num_size = $arg_in->{plot_config}->{axis_num_size};
    my $axis_title_size = $arg_in->{plot_config}->{axis_title_size};

    my @data_plot_array;

    # use different obsid colors for the single pass case

    # use different pass colors for the multi-pass case

    my $colormode = 'obsid';

    if (scalar(@{$data_ref}) > 1){
	$colormode = 'pass';
    }

#    my $pass_count = 0; # reset for each plot
#    my $obsid_count = 0; # reset for each plot
    for my $dir_num ( 0 ... scalar(@{$data_ref})-1 ){
	
	my $datadir = $data_ref->[$dir_num];

        my @ordered_obsid = @{$datadir->{ordered_obsid}};
	my %obsid_idx = %{$datadir->{obsid_idx}};
	my %datapdl = %{$datadir->{pdl}};
	my $y_pdl = zeroes($datapdl{$y_type});
	if (defined $curr_config->{randomize_unit}){
	    my $random_unit = $curr_config->{randomize_unit};
	    my $random = random($datapdl{$y_type});
	    my $rpdl = ($datapdl{$y_type} - ($random_unit/2)) + ($random * $random_unit);
	    $y_pdl = $rpdl;
	}
	else{
	    $y_pdl = $datapdl{$y_type};
	}	     

	for my $obs_num ( 0 ... $#ordered_obsid ){
	    my $obsid = $ordered_obsid[$obs_num];
	    next unless ( $obsid_idx{$obsid}->nelem > 0);
	    my @xvalue = $datapdl{$b}->($obsid_idx{$obsid})->list;
	    my $coloridx;
	    if ($colormode eq 'obsid'){
		$coloridx = ($obs_num) % scalar(@colorlist);
	    }
	    else{
		$coloridx = ($dir_num) % scalar(@colorlist);
	    }
	    my $color = $colorlist[$coloridx];
	    if ( scalar(@xvalue) == $y_pdl->($obsid_idx{$obsid})->nelem() ){ 
		push @data_plot_array , ('x' => [@xvalue] ,
					 'y' => $y_pdl->($obsid_idx{$obsid}),
					 color => { symbol => $color },
					 charsize => {symbol => $symbol_size, title => $axis_title_size, axis => $axis_num_size },
					 plot => 'points',
					 );
	    
	    }
	    else{
		print "$obsid has ", scalar(@xvalue), ":xval and", $y_pdl->($obsid_idx{$obsid})->nelem(), ":yval \n";
	    }
	      
	}

#	$obsid_count += scalar(@ordered_obsid);
#	$pass_count++;
    
    }

    
    return @data_plot_array;

}



sub plot{

    my $self = shift;
    my $plot = shift;

    my $config = $self->config();
    my $opt = $self->opt();
    my $data_ref = $self->data_array();
    my $colrange = $self->data_ranges();

    my $curr_config = $config->{plot}->{$plot};

    my @pgs_array;

    my $device;
    if ($config->{task}->{dir_mode} eq 'single'){
	$device = $data_ref->[0]->{dirname} . "/" . $curr_config->{device};
    }	
    else{
	if (defined $config->{task}->{plot_dir}){
	    print $config->{task}->{plot_dir}, " ", $curr_config->{device}, "\n";
	    $device = $config->{task}->{plot_dir} . "/" . $curr_config->{device};

	}
	else{
	    $device = $curr_config->{device};
	}
    }

    
    push @pgs_array, ( nx => 1, ny => 1,
		       xsize => 5, ysize => 5,
		       device => $device,
		       );

    push @pgs_array, ( xtitle => $curr_config->{xtitle},
		       ytitle => $curr_config->{ytitle},
		       );

    
    my @lims = tweak_limits( $curr_config, $colrange);
#    print Dumper @lims;

    push @pgs_array, ( lims => \@lims );
#    use Data::Dumper;
#    print Dumper @lims;

    my $x_type = $curr_config->{x};
    my $y_type = $curr_config->{y};

    
    # adjust undefined limits if minimum x or y defined 

    if ( $curr_config->{mode} eq 'summary'){
	push @pgs_array, make_plot_summary({ 
	    plot_config => $curr_config,
	    data_array => $data_ref,
	    color_array => $self->config()->{task}->{allowed_colors},
	});

    }
    else{
	
	push @pgs_array, make_plot_a_vs_b({ 
	                                    plot_config => $curr_config,
					    data_array => $data_ref, 
					    color_array => $self->config()->{task}->{allowed_colors} 					
					});
	

	if (defined $curr_config->{oplot}){
	    push @pgs_array, $self->make_oplot({ 
		y_range => $colrange->{$y_type},
		x_range => $colrange->{$x_type},
		oplot => $curr_config->{oplot},
		data => $data_ref,
		plot => $plot,
		lims => \@lims,
		config => $self->config(),
	    });
	}
    }


    unless ($opt->{dryrun}){
	eval{
	    pgs_plot( @pgs_array );
	};
	if ($@){
	    print "Could not plot data\n";
	    print $@, "\n";
#	    print Dumper @pgs_array;
	}
    }
    else{
	print "would have plotted $plot to $device \n";
    }

}

sub make_oplot{
    
    my $self = shift;
    my $arg_in = shift;
    my $data = $arg_in->{data};
    my @oplot = @{$arg_in->{oplot}};
    my $y_range = $arg_in->{y_range};
    my $x_range = $arg_in->{x_range};
    my $config = $arg_in->{config};
    my $plot_name = $arg_in->{plot};

    my $lims = $arg_in->{lims};
    my $curr_config = $config->{$plot_name};

    my @plot_array;

#    use Math::Polynomial;
    
    for my $element (@oplot){

	if ($element->{type} eq 'poly'){
	    my @poly = @{$element->{poly}};
	    my $npoints = $element->{npoints};
	    my $xvals;

	    $xvals = sequence($npoints+1)*(($lims->[1] - $lims->[0])/($npoints))+(($lims->[0]));

	    my $yvals = 0;
	    for my $i (0 .. $#poly){
		$yvals += $poly[$i] * ( $xvals**$i );
	    }

	    # Exclude any points outside our desired yrange;
	    # one method for regular plots, one method for those that need to be padded due to min_x or min_y

	    if (defined $curr_config->{min_y_size}){
		if (($y_range->{max} - $y_range->{min}) > $curr_config->{min_y_size}){
		    my $ok_yval = which((  $yvals <= $y_range->{max}) & ( $yvals >= $y_range->{min} ));
		    my $new_yval = $yvals->($ok_yval);
		    $yvals = $new_yval;
		    # reduce the xvals to the same list
		    my $new_xval = $xvals->($ok_yval);
		    $xvals = $new_xval;
		}
	    }

	    # Prediction
	    push @plot_array, ('x' => [ $xvals->list ],
			       'y' => [ $yvals->list ],
			       color => $element->{color},
			       options => $element->{options},
			       plot => $element->{plot_type},
			       );

	}

	if ($element->{type} eq 'polyfit'){
	    
	    my $fit = $self->polyfit();

	    my $name = $element->{polyname};

	    if ( defined $fit->{$name} ){

		my @poly = @{$fit->{$name}->{coeffs}};
		
		if (scalar(@poly)){
		    
		    my $npoints = $element->{npoints};
		    my $xvals = sequence($npoints+1)*(($x_range->{max} - $x_range->{min})/($npoints))+(($x_range->{min}));
		    my $yvals = 0;
		    for my $i (0 .. $#poly){
			$yvals += $poly[$i] * ($xvals**$i);
		    }

		    # Exclude any points outside our desired yrange
		    my $ok_yval = which((  $yvals <= $y_range->{max}) & ( $yvals >= $y_range->{min} ));
		    my $new_yval = $yvals->($ok_yval);
		    $yvals = $new_yval;
		    # reduce the xvals to the same list
		    my $new_xval = $xvals->($ok_yval);
		    $xvals = $new_xval;
		    
#		# Prediction
		    push @plot_array, ('x' => [ $xvals->list ],
				       'y' => [ $yvals->list ],
				       color => $element->{color},
				       options => $element->{options},
				       plot => $element->{plot_type},
				       );
		    
		}
	    }

	}
    }
    
    return  @plot_array;
}



sub tweak_limits{

    my $curr_config = shift;
    my $colrange = shift;

    my $x_type = $curr_config->{x};
    my $y_type = $curr_config->{y};

    my @lims = @{$curr_config->{lims}};
    
    if ((defined $lims[0]) 
	and (defined $lims[1])
	and (defined $lims[2])
	and (defined $lims[3])){
	return @lims;
    }
    else{
	if (defined $curr_config->{min_x_size}){
	    if (($colrange->{$x_type}->{max} - $colrange->{$x_type}->{min}) < $curr_config->{min_x_size}){
		if (not defined $lims[0]){
		    $lims[0] = ( ( ( $colrange->{$x_type}->{max} + $colrange->{$x_type}->{min} ) / 2 ) 
				 - ( $curr_config->{min_x_size}/2 ));
		}
		if (not defined $lims[1]){
		    $lims[1] = ( ( ( $colrange->{$x_type}->{max} + $colrange->{$x_type}->{min} ) / 2 ) 
				 + ( $curr_config->{min_x_size}/2 ));
		}
	    }
	    
	}
	if (defined $curr_config->{min_y_size}){
	    if (($colrange->{$y_type}->{max} - $colrange->{$y_type}->{min}) < $curr_config->{min_y_size}){
		if (not defined $lims[2]){
		    $lims[2] = ( ( ( $colrange->{$y_type}->{max} + $colrange->{$y_type}->{min} ) / 2 ) 
				 - ( $curr_config->{min_y_size}/2 ));
		}
		if (not defined $lims[3]){
		    $lims[3] = ( ( ( $colrange->{$y_type}->{max} + $colrange->{$y_type}->{min} ) / 2 ) 
				 + ( $curr_config->{min_y_size}/2 ));
		}
	    }
	}
	
	return @lims;
    }

}

sub legend{
    my $self = shift;
    my $data_ref = $self->data_array();
    my $config = $self->config();
    my $opt = $self->config();

    my @ordered_obsid = @{$data_ref->[0]->{ordered_obsid}};
    my @colorlist = @{$config->{task}->{allowed_colors}};
    my %pg_colors = %{$config->{task}->{pg_colors}};
    

##    my $master_width = 6 + $sub_width;
my $master_width = 10;
my $aspect = .5;

#
##my $obsid = $self->{obsid};
#
##    print "sub width = $sub_width, sub height = $sub_height \n";
##   print "width = $master_width, aspect = $aspect \n";
#
#
##
## Setup pgplot

    my $dirname = $data_ref->[0]->{dirname};
    my $legend_device = $config->{task}->{legend_device};

    my $dev = "${dirname}/${legend_device}"; # unless defined $dev;  # "?" will prompt for device
    
    unless ($opt->{dryrun}){
	
	pgbegin(0,$dev,2,1);  # Open plot device
	pgpap($master_width, $aspect );
	pgscf(1);             # Set character font
	pgscr(0, 1.0, 1.0, 1.0);
	pgscr(1, 0.0, 0.0, 0.0);
###    pgslw(2);
	
# Define data limits and plot axes
	pgpage();
	pgsch(2);
	pgvsiz (0.5, 4.5, 0.5, 4.5);
	pgswin (0,3000,0,3000);
#pgbox  ('BCNST', 0.0, 0, 'BCNST', 0.0, 0);
	
	for my $i (0 ... $#ordered_obsid){
	    my $obsid = $ordered_obsid[$i];
	    my $color = $colorlist[($i % scalar(@colorlist))];
#    print "obsid: $obsid is color: $color \n";
	    pgsci( $pg_colors{'black'} );
	    pgtext( 10, 2800-($i*200), "$obsid" );
	    pgsci( $pg_colors{$color} );
	    pgcirc( 800, 2850-($i*200), 50);
	}
	pgend();
    }
    else{
	print "would have made $dev\n";
    }
}#




1;



1;

=pod

=head1 NAME

Ska::Perigee::DataObject - Perigee pass data object construction and manipulation

=head1 SYNOPSIS

=head1 DESCRIPTION

Object to store all of the perigee pass data for a pass or passes to
aid with plotting and generation of statistics.

=cut
