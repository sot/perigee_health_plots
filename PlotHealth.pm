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

    if (defined $arg_href->{summary_object}){
	my $self = $arg_href->{summary_object}->hashify();
	return $self;
    }
    
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
	if (scalar(@todo_directories)){
	    print "Plotting health for:\n";
	    for my $dir (@todo_directories){
		print "\t${dir}\n";
	    }
	}
	else{
	    print "Health plots up to date\n";
	}
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
	
#    print $datapdl{dtime}->(10);
	$datapdl{dtemp} = $datapdl{aca_temp} - $datapdl{ccd_temp};
	
	my %dir_data = (
			dirname => $dir,
			pdl => \%datapdl,
			ordered_obsid => \@ordered_obsid,
			obsid_idx => \%obsid_idx,
			);


#	use PDL::Fit::Polynomial;
#	use PDL::NiceSlice;
## let's fit a polynomial to the pass
#	if (defined $config->{task}->{polyfit}){
#	    my $xdata = $datapdl{$config->{task}->{polyfit}->{x}};
#	    my $data = $datapdl{$config->{task}->{polyfit}->{y}};
#	    my ($xmean,$xrms,$xmedian,$xmin,$xmax) = $xdata->stats;
#	    my ($ymean,$yrms,$ymedian,$ymin,$ymax) = $data->stats;
#	    my $order = ($config->{task}->{polyfit}->{order});
#	    $order = $order + 1;
#	    my $min_dx = $config->{task}->{polyfit}->{min_dx};
#	    my ($yfit, $coeffs);
#	    if (($xmax - $xmin) < $min_dx){
#		my $diff = $xmax - $xmin;
#		print "diff is $diff \n";
#		$coeffs = pdl( $xmean, 0 );
#	    }
#	    else{
#		($yfit, $coeffs) = fitpoly1d($xdata, $data, $order);
#	    }
##	    
##print $yfit, "\n";
#	    print $coeffs, "\n";

	push @data_array, \%dir_data;
    }


# if I want 1 pass per plot, run in a loop and put the plots in the pass
# directory

    my $cumul_data;
    if (defined $config->{task}->{polyfit}){
	    
	$cumul_data = concat_data({ config => $config,
				    data_array => \@data_array });
    }


    if ($config->{task}->{dir_mode} eq 'single'){

	for my $dir (@data_array){
	    
	    my %colranges = find_pdl_ranges( [$dir]);
	    
	    my $plot_helper = PlotHelper->new({ config => $config,
						opt => $opt,
						data_array => [$dir],
						ranges => \%colranges,
						cumul_data => $cumul_data,
					    });
	    
	    $plot_helper->plot( 'aca_temp' );
           
	    $plot_helper->plot( 'ccd_temp' );
	    
	    $plot_helper->plot( 'dac' );
	    
	    $plot_helper->plot( 'dac_vs_dtemp' );

	    $plot_helper->legend();
	    
	    $plot_helper->report();

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
					 cumul_data => $cumul_data,
				     });
	
	
	$plot_helper->plot( 'aca_temp' );
	
	$plot_helper->plot( 'ccd_temp' );
	
	$plot_helper->plot( 'dac' );
	
	$plot_helper->plot( 'dac_vs_dtemp' );
	
#	$plot_helper->plot( 'dacfit' );

#	$plot_helper->plot( 'dtempfit' );

    }	
    

}

sub concat_data{

    my $arg_in = shift;
    my $data = $arg_in->{data_array};
    my $config = $arg_in->{config};

    my $polyfit = $config->{task}->{polyfit};

    my $x = null;
    my $y = null;

    for my $pass (@{$data}){
		
	my $x_pass = $pass->{pdl}->{$polyfit->{x}};
	my $y_pass = $pass->{pdl}->{$polyfit->{y}};
	$x = append( $x, $x_pass);
	$y = append( $y, $y_pass);
    }

    my %cumul_data = ( x => $x,
		       y => $y, 
		       name => $config->{task}->{polyfit}->{result},
		       );

    return \%cumul_data;
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
						       data_ranges
						       cumul_data
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

    if (defined $arg_in->{cumul_data}){
	$self->cumul_data($arg_in->{cumul_data});
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
	print "dir is $datadir \n";
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
	    push @data_plot_array , ('x' => [@xvalue] ,
				     'y' => $y_pdl->($obsid_idx{$obsid}),
				     color => { symbol => $color },
				     charsize => {symbol => $symbol_size, title => $axis_title_size, axis => $axis_num_size },
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

    push @pgs_array, ( lims => \@lims );

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
		cumul_data => $self->cumul_data(),
		config => $self->config(),
	    });
	}
    }


    unless ($opt->{dryrun}){
	eval{
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

sub make_polyfit{

    my $self = shift;
    my $arg_in = shift;
    my $config = $arg_in->{config};
    my $element = $arg_in->{element};
    my $cumul_data = $arg_in->{cumul_data};
    my $data = $arg_in->{data};

    print Dumper $data;
    my $polyname = $element->{polyname};

    eval 'use PDL::Fit::Polynomial';
    eval 'use PDL::NiceSlice';
## let's fit a polynomial to the pass
    my $xdata = $cumul_data->{x};
    my $ydata = $cumul_data->{y};
    my ($xmean,$xrms,$xmedian,$xmin,$xmax) = $xdata->stats;
    my ($ymean,$yrms,$ymedian,$ymin,$ymax) = $ydata->stats;
    my $order = ($config->{task}->{polyfit}->{order});
    $order = $order + 1; #fitpoly has a weird idea of order
    my $min_dx = $config->{task}->{polyfit}->{min_dx};
    my ($yfit, $coeffs);
#	    print "min: $xmin max: $xmax, dx: $min_dx \n";
    if (($xmax - $xmin) < $min_dx){
	my $diff = $xmax - $xmin;
	return undef;
    }
    else{
	my %fitpoint;
	($yfit, $coeffs) = fitpoly1d($xdata, $ydata, $order);
	my @poly = $coeffs->list;
	# if any points were requested, define them
		for my $fitset (keys %{$config->{task}->{polyfit}->{points}}){
		    my $fit_def = $config->{task}->{polyfit}->{points}->{$fitset};
		    if (defined $fit_def->{x}){
			my $plug = $fit_def->{x};
			my $yval = 0;
			for my $i (0 .. $#poly){
			    $yval += $poly[$i] * ($plug**$i);
			}
			$fitpoint{$fitset} =  { x => $plug,
						y => $yval,
					    }
		    }
		    if (defined $fit_def->{y}){
			my $solve_y = $fit_def->{y};
			my $solve_xmin = $fit_def->{xmin};
			my $solve_xmax = $fit_def->{xmax};
			my $npoints = 1000;
			my $xvals = sequence($npoints+1)*(($solve_xmax - $solve_xmin)/($npoints))+(($solve_xmin));
			my $yvals = 0;
			for my $i (0 .. $#poly){
			    $yvals += $poly[$i] * ($xvals**$i);
			}
			my $y_diff = abs($yvals - $solve_y);
			my $x_idx = which($y_diff eq min($y_diff));

			$fitpoint{$fitset} = { x => $xvals->($x_idx)->sclr,
					       y => $solve_y,
					   };
		    }
		}
	
	if ($self->{opt}->{verbose}){
	    print Dumper %fitpoint;
	}
	$self->polyfit( \%fitpoint );
	$self->coeffs( \@poly);

	return $coeffs->list();
    }
    
}

sub make_oplot{
    
    my $self = shift;
    my $arg_in = shift;
    my $data = $arg_in->{data};
    my @oplot = @{$arg_in->{oplot}};
    my $y_range = $arg_in->{y_range};
    my $x_range = $arg_in->{x_range};
    my $cumul_data = $arg_in->{cumul_data};
    my $config = $arg_in->{config};
    
    my @plot_array;

#    use Math::Polynomial;
    
    for my $element (@oplot){

	if ($element->{type} eq 'poly'){
	    my @poly = @{$element->{poly}};
	    my $npoints = $element->{npoints};
	    my $xvals = sequence($npoints+1)*(($x_range->{max} - $x_range->{min})/($npoints))+(($x_range->{min}));
#	    my $yvals = $poly[0] + $xvals*$poly[1] + ($xvals*$xvals)*$poly[2];
	    my $yvals = 0;
	    for my $i (0 .. $#poly){
		$yvals += $poly[$i] * ( $xvals**$i );
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

	    my @poly = $self->make_polyfit({ config => $config,
				     element => $element,
				      data => $data,
				     cumul_data => $cumul_data,
				     });

				     
	    if (scalar(@poly)){

		my $npoints = $element->{npoints};
		my $xvals = sequence($npoints+1)*(($x_range->{max} - $x_range->{min})/($npoints))+(($x_range->{min}));
		my $yvals = 0;
		for my $i (0 .. $#poly){
		    $yvals += $poly[$i] * ($xvals**$i);
		}
#		# Prediction
		push @plot_array, ('x' => [ $xvals->list ],
				   'y' => [ $yvals->list ],
				   color => $element->{color},
				   options => $element->{options},
				   plot => $element->{plot_type},
				   );
		
	    }
##	    
##print $yfit, "\n";
#	    print $coeffs, "\n";
#	    
#
##	    for my $dir_num ( 0 ... scalar(@{$data})-1 ){
##		my $datadir = $data->[$dir_num];
#		#my @ordered_obsid = @{$datadir->{ordered_obsid}};
#		#my %obsid_idx = %{$datadir->{obsid_idx}};
#		#my %datapdl = %{$datadir->{pdl}};
#		#my $y_pdl = zeroes($datapdl{$y_type});
#		my @poly = @{$datadir->{$polyname}};
#	    }
#
#	}

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

sub report{

    my $self = shift;
    my $report_config = $self->config()->{report};
    my $filename = $report_config->{file};

    my $report_text = "";

    $report_text .= "Perigee Health Report\n\n";

    $report_text .= "Report for these passes:\n\n";

    my $pass_dir = $self->config()->{general}->{pass_dir};

    my $full_path_dirname;
    if ($self->config()->{task}->{dir_mode} eq 'single'){
	my $pass = $self->data_array()->[0];
	$full_path_dirname = $pass->{dirname};
	my $dirname = $full_path_dirname;
	$dirname =~ s/$pass_dir\/?//;
	$report_text .= "\t $dirname \n";
    }


    $report_text .= "---------------------------------------------------\n";
    $report_text .= "Warnings\n";
    $report_text .= "---------------------------------------------------\n";
    $report_text .= "\n";
    
    my $warning = "";
    for my $plotcfg_name (keys %{$self->config()->{plot}}){
	my $plotcfg = $self->config()->{plot}->{$plotcfg_name};
	if (defined $plotcfg->{warn}){
	    for my $key (%{$plotcfg->{warn}}){
		if ($key eq 'max'){
		    my $datamax = $self->data_ranges()->{$plotcfg_name}->{max};
		    my $warnmax = $plotcfg->{warn}->{$key};
		    if ($datamax > $warnmax){
			$warning .= "Warning $plotcfg_name exceeded defined threshold\n";
			$warning .= "Threshold: $warnmax\n";
			$warning .= "$plotcfg_name high Value: $datamax\n";
		    }
		}
	    }
	}
    }
    if ($warning eq ""){
	$warning = "No warnings reported\n";
    }

    $report_text .= "$warning\n\n";


    $report_text .= "---------------------------------------------------\n";
    $report_text .= "Ranges\n";
    $report_text .= "---------------------------------------------------\n";

    my %ranges = %{$self->data_ranges()};


    $report_text .= "ACA Housing Temperature Range (deg C)\n";
    $report_text .= "\tmax:" . sprintf($ranges{aca_temp}->{max}) . "\n";
    $report_text .= "\tmin:" . sprintf($ranges{aca_temp}->{min}) . "\n\n";

    $report_text .= "CCD Temperature Range (deg C)\n";
    $report_text .= "\tmax:". sprintf($ranges{ccd_temp}->{max}) . "\n";
    $report_text .= "\tmin:". sprintf($ranges{ccd_temp}->{min}) . "\n\n";

    $report_text .= "TEC DAC Control Level Range\n";
    $report_text .= "\tmax:" . sprintf($ranges{dac}->{max}) . "\n";
    $report_text .= "\tmin:" . sprintf($ranges{dac}->{min}) . "\n\n";

    $report_text .= "\n";



    $report_text .= "---------------------------------------------------\n";
    $report_text .= "Fitpoints\n";
    $report_text .= "---------------------------------------------------\n\n";

    $report_text .= "With a linear fit of the available DAC vs Delta Temp data\n\n";

    $report_text .= "TEC DAC will reach " . $self->polyfit()->{dtempfit}->{y};
    $report_text .= ", when the ACA - CCD temp is " . $self->polyfit()->{dtempfit}->{x};
    $report_text .= "\n\n";

    $report_text .= "When the ACA - CCD temp is " . $self->polyfit()->{dacfit}->{x};
    $report_text .= ", the TEC DAC level should be " . $self->polyfit()->{dacfit}->{y};
    $report_text .= "\n\n";
    
    my $outfile = io("${full_path_dirname}/$filename");
    $outfile->print($report_text);
    


}

1;
