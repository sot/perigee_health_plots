package PlotHealth;

use strict; 
use warnings;
#use PGPLOT;
#use XML::Dumper;
use PDL;
use PDL::NiceSlice;
use Getopt::Long;
use YAML;
use Carp;
use Data::Dumper;
use Chandra::Time;


use Class::MakeMethods::Standard::Hash(
				       scalar => [ qw(
						      tstart
						      tstop
						      config
						      opt
						      passlist
						      )
						   ],
				       );


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


sub make_plots{
    my $self = shift;
    my %config = %{$self->config()};
    my $WORKING_DIR = $config{general}->{pass_dir};
    my $tstart = $self->tstart();
    my $tstop = $self->tstop();
    my %opt = %{$self->opt()};

    my $yaml_data_file = $config{general}->{data_file};

    my @todo_directories;

# first get a list of directories.
    my @telem_dirs = glob("${WORKING_DIR}/????:*");


# first, if time range specified for multi or summary plots,
# just get all the dirs in that time range
    if (defined $self->passlist()){
	@todo_directories = @{$self->passlist()};
    }
    else{
	if ((defined $tstart) or (defined $tstop)){
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
# if no range specified, try to just get recent directories with
# missing plots
	else{
	    
	    my @plotlist;
	    for my $plot ( values %{$config{plot}} ){
		my $device = "$plot->{device}";
		if ($device =~ /(.*)\/vcps/ ){
		    push @plotlist, $1;
		}
	    }
	    
# step backward through them until I find one (or more) without pictures
	    
	  DIRECTORY:
	    for my $dir ( reverse @telem_dirs ){
	      PICTURE:
		for my $picture (@plotlist){
		    next PICTURE if (-e "${dir}/${picture}");
		    push @todo_directories, $dir;
		    next DIRECTORY;
		}
		# if missing flag specified, continue even if I hit a directory with pictures
		last DIRECTORY unless ($opt{missing});
	    }
	}
    }

    if ($opt{verbose}){
	print Dumper @todo_directories;
    }
    
    plot_health( \@todo_directories, \%config, \%opt );
}
#for my $dir (@todo_directories[0]){
#    if ($opt{verbose}){
#	print "making plots for $dir \n";
#    }
#    plot_health( $dir, \%config );
#    convert_to_gif( "${dir}/$health_plot", "${dir}/$health_plot_gif");
#    convert_to_gif( "${dir}/$legend", "${dir}/$legend_gif");
#    if (( -e "${dir}/$health_plot_gif" ) and (-e "${dir}/$legend_gif" )){
#        if ($opt{delete}){
#            unlink("${dir}/$health_plot");
#            unlink("${dir}/$legend");
#        }
#    }
#}
#



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
sub convert_to_gif{
##***************************************************************************
    my ( $in_ps, $out_gif) = @_;
#    print( "convert -density 100x100 $in_ps $out_gif\n");
#    system( "convert -density 100x100 $in_ps $out_gif");

    print "in_ps is $in_ps \n";
    print "out_gif is $out_gif \n";
#    system("/proj/gads6/jeanproj/perigee_health_plots/ps2any -density 100 -verbose $in_ps $out_gif ");
    system("convert -density 100x100 $in_ps $out_gif ");
    if ($? == -1) {
	print "failed to execute: $!\n";
    }
    elsif ($? & 127) {
                     printf "child died with signal %d, %s coredump\n",
		     ($? & 127),  ($? & 128) ? 'with' : 'without';
                 }
    else {
	printf "child exited with value %d\n", $? >> 8;
    }


}




##***************************************************************************
sub plot_health{
##***************************************************************************

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
	my $yaml = YAML::LoadFile($yaml_file);

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
	
# let's define a new delta time
	$datapdl{dtime} = $datapdl{time} - $tzero;
	
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
	    
	    my $plot_helper = PlotHelper->new({ config => $config,
						opt => $opt,
						data_array => [$dir],
						ranges => \%colranges,
					    });
	    
	    $plot_helper->plot( 'aca_temp' );
	    
	    $plot_helper->plot( 'ccd_temp' );
	    
	    $plot_helper->plot( 'dac' );
	    
	    $plot_helper->plot( 'dac_vs_dtemp' );

	    $plot_helper->legend();
	}
	
    }

# else, gather all of the pass data and make multi or summary plots

    else{
	
	my %colranges = find_pdl_ranges( \@data_array );
	
	my $plot_helper = PlotHelper->new({ config => $config,
					    opt => $opt,
					    data_array => \@data_array,
					    ranges => \%colranges,
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
#	my ($mindir, $maxdir);
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
	


sub clean_bad_points{
    
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

1;    




package PlotHelper;

use strict;
use warnings;
use Class::MakeMethods::Standard::Hash(
                                        scalar => [ qw(
						       config
						       opt
						       data_array
						       ranges
						       )
                                                    ],
				       );

use PGPLOT::Simple qw( pgs_plot );
use PDL::NiceSlice;
use PDL;
use PGPLOT;

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
    $self->ranges($arg_in->{ranges});
    $self->opt($arg_in->{opt});

    return $self;

}



sub make_plot_summary{

    my $arg_in = shift;
    my $y_type = $arg_in->{y_type};
    my $x_type = $arg_in->{x_type};
    my $data_ref = $arg_in->{data_array};
    my @colorlist = @{$arg_in->{color_array}};
    my $axis_label_size = $arg_in->{axis_label_size};
      
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

	my ($ymean,$yrms,$ymedian,$ymin,$ymax) = $datadir->{pdl}->{$y_type}->stats;

	my $xmin = $datadir->{pdl}->{$x_type}->min;
	my $xmax = $datadir->{pdl}->{$x_type}->max;

	if ($x_type eq 'time'){
	    $xmin = ($xmin - $starttime)/86400; # find time difference and convert to days
	    $xmax = ($xmax - $starttime)/86400; 
	}

	my $xmid = ($xmin+$xmax)/2;
	
	
#	if ($b eq 'time'){
#	    use Chandra::Time;
#	    my $ctime_min = Chandra::Time->new( $xmin );
#	    my $ctime_max = Chandra::Time->new( $xmax );
#	    my $date_min = $ctime_min->date();
#	    my $date_max = $ctime_max->date();
#	    print "date $date_min $date_max \n";
#	    my $dy_min, $dy_max;
#	    if ( $date_min ~= /(\d{4}):(\d{3}):.*)
#	}


	push @data_plot_array, ( charsize => { axis => $axis_label_size } );
	
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

    
    
    return @data_plot_array;

}


sub make_plot_a_vs_b{

    my $arg_in = shift;
    my $a = $arg_in->{y_type};
    my $b = $arg_in->{x_type};
    my $data_ref = $arg_in->{data_array};
    my @colorlist = @{$arg_in->{color_array}};
    my $symbol_size = $arg_in->{symbol_size};
    my $axis_label_size = $arg_in->{axis_label_size};

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
	    push @data_plot_array , (
				     'x' => [@xvalue],
				     'y' => $datapdl{$a}->($obsid_idx{$obsid}),
				     color => { symbol => $color },
				     charsize => {symbol => 1, title => 1},
				     plot => 'points',
				     );

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
    my $colrange = $self->ranges();

    my $curr_config = $config->{plot}->{$plot};

    my @pgs_array;

    my $device;
    if ($config->{task}->{dir_mode} eq 'single'){
	$device = $data_ref->[0]->{dirname} . "/" . $curr_config->{device};
    }	
    else{
	if (defined $config->{task}->{plot_dir}){
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

    push @pgs_array, ( lims => \@lims );

    my $x_type = $curr_config->{x};
    my $y_type = $curr_config->{y};

    if (defined $curr_config->{randomize_unit}){
	my $random_unit = $curr_config->{randomize_unit};
#	print "random unit is $random_unit \n";
	for my $data_dir (@{$data_ref}){
	    my $y_pdl = $data_dir->{pdl}->{$y_type};
	    my $random = random($y_pdl);
	    my $rpdl = ($y_pdl - ($random_unit/2)) + ($random * $random_unit);
	    $data_dir->{pdl}->{$y_type} = $rpdl;
	}
    }
    
    # adjust undefined limits if minimum x or y defined 

    if ( $curr_config->{mode} eq 'summary'){
	push @pgs_array, make_plot_summary({ y_type => $y_type,
					     x_type => $x_type,
					     data_array => $data_ref,
					     color_array => $self->config()->{task}->{allowed_colors},
					     axis_label_size => $curr_config->{axis_label_size},
					 });

    }
    else{

	push @pgs_array, make_plot_a_vs_b({ y_type => $y_type, 
					    x_type => $x_type, 
					    data_array => $data_ref, 
					    symbol_size => $curr_config->{symbol_size},
					    axis_label_size => $curr_config->{axis_label_size},
					    color_array => $self->config()->{task}->{allowed_colors} 					
					});
	
	if (defined $curr_config->{oplot}){
	    push @pgs_array, make_oplot({ 
		y_range => $colrange->{$y_type},
		x_range => $colrange->{$x_type},
		oplot => $curr_config->{oplot},
	    });
	}
    }
#    use Data::Dumper;
#    print Dumper @pgs_array;
    
#    print "plot is $plot \n";
    use Data::Dumper;
    unless ($opt->{dryrun}){
	eval{
#	print Dumper @pgs_array;
	    pgs_plot( @pgs_array );
	};
	if ($@){
	    print $@, "\n";
	    print Dumper @pgs_array;
	}
    }
    else{
	print "would have plotted $plot to $device \n";
    }

}

sub make_oplot{
    my $arg_in = shift;
    my @oplot = @{$arg_in->{oplot}};
    my $y_range = $arg_in->{y_range};
    my $x_range = $arg_in->{x_range};
    
    my @plot_array;
    
    for my $element (@oplot){
	if ($element->{type} eq 'poly'){
	    my @poly = @{$element->{poly}};
	    my $npoints = $element->{npoints};
	    my $xvals = sequence($npoints+1)*(($x_range->{max} - $x_range->{min})/($npoints))+(($x_range->{min}));
	    my $yvals = $poly[0] + $xvals*$poly[1] + ($xvals*$xvals)*$poly[2];
	    # Prediction
	    push @plot_array, ('x' => [ $xvals->list ],
			   'y' => [ $yvals->list ],
			       color => $element->{color},
			       options => $element->{options},
			       plot => $element->{plot_type},
			       );
	    
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
}


1;
