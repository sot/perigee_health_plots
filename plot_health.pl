#!/usr/bin/env /proj/sot/ska/bin/perlska

use strict; 
use warnings;
use PGPLOT;
use PGPLOT::Simple qw( pgs_plot );
use XML::Dumper;
use PDL;
use PDL::NiceSlice;
use Getopt::Long;
use YAML;


my %opt = ();

our %opt = ();
our $starttime;

GetOptions (\%opt,
            'help!',
            'dir=s',
            'missing!',
            'verbose|v!',
            'delete!',
	    'config=s',
	    'summary!',
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
    %config = YAML::LoadFile( "${SHARE}/plot_health.yaml" );
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
$config{working_dir} = $WORKING_DIR;


my $xml_data_file = $config{xml_data_file};
my $health_plot = "$config{health_plot}.ps";
my $health_plot_gif = "$config{health_plot}.gif";
my $legend = "$config{legend_plot}.ps";
my $legend_gif = "$config{legend_plot}.gif";


# Search for directories in $WORKING_DIR that have telemetry but don't have
# $xml_out_file

my @todo_directories;

# first get a list of directories.
my @telem_dirs = glob("${WORKING_DIR}/????:*");

# step backward through them until I find one that has an $xml_out_file
for my $dir ( reverse @telem_dirs ){
    if (( -e "${dir}/$health_plot" ) and (-e "${dir}/$legend")){
        last unless $opt{missing};
    }
    else{
        push @todo_directories, $dir;
    }
}

my @dir = @todo_directories[0 ... 7];
use Data::Dumper;
print Dumper @dir;

plot_health( \@dir, \%config );

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

#    my ($xml_file, $plotname, $legendname) = @_;
    my $dirlist = shift;
    my $config = shift;


    my $plotname = "$config->{health_plot}.ps";
    my $legendname = "$config->{legend_plot}.ps";

    if ( scalar(@{$dirlist}) == 1){
	$plotname = "$dirlist->[0]/$config->{health_plot}.ps";
	$legendname = "$dirlist->[0]/$config->{legend_plot}.ps";
    }




## infile and outfile
#my $xml_file = 'data.xml.gz';
#my $plotname = 'aca_health_pgplot.ps';
#my $legendname = 'legend.ps';

my %pg_colors = (black   => 1,
		 red     => 2,
		 green   => 3,
		 blue    => 4,
		 cyan    => 5,
		 yellow  => 7,
		 orange  => 8,
		 purple  => 12,
		 magenta => 6
		 );


# color choices for plot
my @colorlist = ( 'red', 'green', 'blue', 'magenta', 'cyan', 'orange', 'purple');
my @columns = ( 'time', 'obsid', 'aca_temp', 'ccd_temp', 'dac');

# polynomial coefficients for DAC vs TEMPDIFF plot
my @polyfit = @{$config->{polyfit}};

    my @data_array;

    for my $dir (@{$dirlist}){

	
	my $xml_file = "${dir}/$config->{xml_data_file}";

# read in data from XML file
	my $dump = new XML::Dumper;
	my $xml = $dump->xml2pl( $xml_file );
#    use Data::Dumper;
#    print Dumper $xml;
	my %data = %{$xml->{telem}};
	my %info = %{$xml->{info}};

# convert the handy text arrays to pdls
	my %datapdl;
	for my $column ( @columns ){
	    $datapdl{$column} = pdl( @{$data{$column}} );
#    print "column $column has ", $datapdl{$column}->nelem, " elements \n";
	}

#    print "keys ", keys(%datapdl), "\n";
#    print "ref ", ref($datapdl{obsid}), "\n";

#    use Data::Dumper;
#    print Dumper $info{bad_points};

# exclude marked bad points
	eval{
	    if( defined $info{bad_points} ){
		for my $column (keys %{$info{bad_points}}){
#	    use Data::Dumper;
#	    print Dumper $info{bad_points};
		    next unless defined $datapdl{$column};
		    my $not_ok = pdl( $info{bad_points}->{$column} );
		    my $dummy = ones($datapdl{$column});
		    $dummy->($not_ok) .= 0;
		    my $ok = which( $dummy == 1 );
#	    print "ok elements ", $ok->nelem, "\n";
		    for my $origcolumn (@columns){
			eval{
			    my $newpdl = $datapdl{$origcolumn}->($ok);
#		    print "newpdl is ", $newpdl->nelem, "\n";
			    delete $datapdl{$origcolumn};
			    $datapdl{$origcolumn} = $newpdl;
#		    print "$origcolumn has ", $newpdl->nelem, "\n";
			    
#		    print "new assign ", ref($datapdl{$origcolumn}), "\n";
			};
			if ($@){
			    use Carp;
			    croak("reducing column $origcolumn failed $@");
			}
		    }
		}
	    }
	};
	if ($@){
	    use Carp;
	    croak("$@");
	}
	


#    print Dumper $data{'obsid'};

#let's figure out how many obsids are present
	my $obsidpdl = $datapdl{obsid};
#    print "obsid pdl now has ", $obsidpdl->nelem, " elements\n";
	
	my $uniqpdl = $obsidpdl->uniq;
	my @uniqobsid = $uniqpdl->list;
	

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
			pdl => \%datapdl,
			ordered_obsid => \@ordered_obsid,
			obsid_idx => \%obsid_idx,
			colorlist => \@colorlist,
			);

	push @data_array, \%dir_data;
    }


    my @plotcolumns = ( 'dac', 'aca_temp', 'ccd_temp', 'dtime', 'dtemp', 'time');

    my %colranges;
    
    for my $column (@plotcolumns){

	my ($min, $max);
	my ($mindir, $maxdir);
	for my $dir_data (@data_array){
	    #print keys(%{$dir_data});
	    my $dir_max = $dir_data->{pdl}->{$column}->max;

	    my $dir_min = $dir_data->{pdl}->{$column}->min;

	    if (not defined $min){
		$min = $dir_min;
		
	    }
	    else{ 
		if ($dir_min < $min){
		    $min = $dir_min;
		}
	    }
	    if (not defined $max){
		$max = $dir_max;
	    }
	    else{ 
		if ($dir_max > $max){
		    $max = $dir_max;
		}
	    }
	}
	my %range = (
		     min => $min,
		     max => $max,
		     );
	    
	$colranges{$column} = \%range;
	    

    }

    use Data::Dumper;
    print Dumper %colranges;
	    
       

    
    my @plotarray;

# Page Setup


    my $plot_helper = PlotHelper->new({ config => $config,
					data_array => \@data_array,
					ranges => \%colranges,
				    });
    

    if ( $opt{summary}){


	push @plotarray, $plot_helper->plot_config_sum( 'plot11' );
	
	push @plotarray, $plot_helper->plot_config_sum( 'plot21' );
	
	push @plotarray, $plot_helper->plot_config_sum( 'plot12' );
	
	push @plotarray, $plot_helper->plot_config_reg( 'plot22' );

    }
    else{
	push @plotarray, $plot_helper->plot_config_reg( 'plot11' );
	
	push @plotarray, $plot_helper->plot_config_reg( 'plot21' );
	
	push @plotarray, $plot_helper->plot_config_reg( 'plot12' );
	
	push @plotarray, $plot_helper->plot_config_reg( 'plot22' );
    }

 
     my $npoints = 100;
 # 
 # # how much of the plot do I want with data in x
     my $dac_xscale = .8;
 
    my $minx = $colranges{dtemp}->{min};
    my $maxx = $colranges{dtemp}->{max};
    my $data_xrange = $maxx - $minx;
 #    print "data range is $data_xrange \n";
    my $plot_xrange = $data_xrange/$dac_xscale;
 # # left and right pad to get $dac_xscale of the plot to have data
    my $pad = ($plot_xrange-$data_xrange)/2;
    # 
 # # dummy x points for the fit line
    my $xvals = sequence($npoints+1)*(($plot_xrange)/($npoints))+(($minx)-($pad));
    #print $xvals->min, "\t", $xvals->max, "\n"; 
 # # predicted second order polynomial for aca-ccd vs dac
    my $yvals = $polyfit[0] + $xvals*$polyfit[1] + ($xvals*$xvals)*$polyfit[2];
 #    print $yvals->min, "\t", $yvals->max, "\n";



#    push @plotarray, plot_config( 'plot21' );
    
#    push @plotarray, plot_config( 'plot12' );
    
#    push @plotarray, plot_config( 'plot22' );


    push @plotarray, (
 		  # Prediction
		      'x' => [ $xvals->list ],
		      'y' => [ $yvals->list ],
		      color => { line => 'black' },
		      options => {linestyle => 'dashed' },
		      plot => 'line',
		      );
#
#    if ( ($datapdl{dac}->max > 511 )){
#	print "red line \n";
#	push @plotarray, (
#			  # 511 Line
#			  'x' => [ ($datapdl{dtemp}->min)-10, ($datapdl{dtemp}->max)+10],
#			  'y' => [ 511, 511],
#			  color => { line => 'red' },
#       		  plot => 'line',
#			  );
#    }
# 
# 

pgs_plot( @plotarray );


#    my $master_width = 6 + $sub_width;
my $master_width = 10;
my $aspect = .5;

#my $obsid = $self->{obsid};

#    print "sub width = $sub_width, sub height = $sub_height \n";
#   print "width = $master_width, aspect = $aspect \n";


#
## Setup pgplot
#my $dev = "$legendname/vcps"; # unless defined $dev;  # "?" will prompt for device
#pgbegin(0,$dev,2,1);  # Open plot device
#pgpap($master_width, $aspect );
#pgscf(1);             # Set character font
#pgscr(0, 1.0, 1.0, 1.0);
#pgscr(1, 0.0, 0.0, 0.0);
##    pgslw(2);
#
## Define data limits and plot axes
#pgpage();
#pgsch(2);
#pgvsiz (0.5, 4.5, 0.5, 4.5);
#pgswin (0,3000,0,3000);
##pgbox  ('BCNST', 0.0, 0, 'BCNST', 0.0, 0);
#
#
#for my $i (0 ... $#ordered_obsid){
#    my $obsid = $ordered_obsid[$i];
#    my $color = $colorlist[($i % scalar(@colorlist))];
##    print "obsid: $obsid is color: $color \n";
#    pgsci( $pg_colors{'black'} );
#    pgtext( 10, 2800-($i*200), "$obsid" );
#    pgsci( $pg_colors{$color} );
#    pgcirc( 800, 2850-($i*200), 50);
#}
#
#
#
#
#pgend;
#
#
}


package PlotHelper;

use strict;
use warnings;
use Class::MakeMethods::Standard::Hash(
                                        scalar => [ qw(
						       config
						       data_array
						       ranges
                                                       )
                                                    ],
				       );

sub new{

    my $class = shift;
    my $self = {};
    bless $self, $class;

    my $arg_in = shift;
    $self->config($arg_in->{config});
    $self->data_array($arg_in->{data_array});
    $self->ranges($arg_in->{ranges});

    return $self;

}



sub plot_summary{

    my $y = shift;
    my $x = shift;
    my $data_ref = shift;
    
    my @data_plot_array;

    if ($x eq 'time'){
	for my $datadir (@{$data_ref}){
	    my $xmin = $datadir->{pdl}->{$x}->min;
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

    for my $datadir (@{$data_ref}){

	my ($ymean,$yrms,$ymedian,$ymin,$ymax) = $datadir->{pdl}->{$y}->stats;

	my $xmin = $datadir->{pdl}->{$x}->min;
	my $xmax = $datadir->{pdl}->{$x}->max;

	if ($x eq 'time'){
	    $xmin = $xmin - $starttime;
	    $xmax = $xmax - $starttime;
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

	
	my @yvalue = [ $ymin, $ymin ];
	my @xvalue = [ $xmin, $xmax ];
	push @data_plot_array , (
				 'x' => [@xvalue],
				 'y' => [@yvalue],
				 color => { symbol => 'black' },
				 plot => 'line',
				 );
	
	@yvalue = [ $ymax, $ymax ];
	@xvalue = [ $xmin, $xmax ];
	push @data_plot_array , (
				 'x' => [@xvalue],
				 'y' => [@yvalue],
				 color => { symbol => 'black' },
				 plot => 'line',
				 );

	@yvalue = [ $ymean ];
	@xvalue = [ $xmid ];
	push @data_plot_array , (
				 'x' => [@xvalue],
				 'y' => [@yvalue],
				 color => { symbol => 'black' },
				 plot => 'points',
				 );


	@yvalue = [ $ymin, $ymax ];
	@xvalue = [ $xmid, $xmid ];
	push @data_plot_array , (
				 'x' => [@xvalue],
				 'y' => [@yvalue],
				 color => { symbol => 'black' },
				 plot => 'line',
				 );


    }
    
    
    
    return @data_plot_array;

}


sub plot_a_vs_b{

    my $a = shift;
    my $b = shift;
    my $data_ref = shift;

    my @data_plot_array;
    
    for my $datadir (@{$data_ref}){
	
        my @ordered_obsid = @{$datadir->{ordered_obsid}};
	my @colorlist = @{$datadir->{colorlist}};
	my %obsid_idx = %{$datadir->{obsid_idx}};
	my %datapdl = %{$datadir->{pdl}};
	
	for my $i (0 .. $#ordered_obsid){
	    my $obsid = $ordered_obsid[$i];
#	print "obsid is $obsid \n";
	    next unless ( $obsid_idx{$obsid}->nelem > 0);
	    my @xvalue = $datapdl{$b}->($obsid_idx{$obsid})->list;
	    my $color = $colorlist[($i % scalar(@colorlist))];
	    push @data_plot_array , (
				     'x' => [@xvalue],
				     'y' => $datapdl{$a}->($obsid_idx{$obsid}),
				     color => { symbol => $color },
				     plot => 'points',
				     );
	}
    
    }
    return @data_plot_array;

}



sub plot_config_reg{

    my $self = shift;
    my $plot = shift;

    my $config = $self->config();
    my $data_ref = $self->data_array();
    my $colrange = $self->ranges();

    my $curr_config = $config->{$plot};

    my @array;

    push @array, ( panel => $curr_config->{panel},
		   xtitle => $curr_config->{xtitle},
		   ytitle => $curr_config->{ytitle},
		   );

    my @lims = @{$curr_config->{lims}};
    my $x_type = $curr_config->{x};
    my $y_type = $curr_config->{y};

    if ((defined $lims[0]) 
	and (defined $lims[1])
	and (defined $lims[2])
	and (defined $lims[3])){
	push @array, ( lims => \@lims );
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
	
	push @array, ( lims => \@lims );
    }
    
    

    push @array, plot_a_vs_b( $y_type, $x_type, $data_ref );


    return @array;


}



sub plot_config_sum{

    my $self = shift;
    my $plot = shift;

    my $config = $self->config();
    my $data_ref = $self->data_array();
    my $colrange = $self->ranges();

    my $curr_config = $config->{$plot};

    my @array;

    push @array, ( panel => $curr_config->{panel},
		   xtitle => $curr_config->{xtitle},
		   ytitle => $curr_config->{ytitle},
		   );

    my @lims = @{$curr_config->{lims}};
    my $x_type = $curr_config->{x};
    my $y_type = $curr_config->{y};

    if ((defined $lims[0]) 
	and (defined $lims[1])
	and (defined $lims[2])
	and (defined $lims[3])){
	push @array, ( lims => \@lims );
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
	    if (($colrange->{$y_type}->{max} - $colrange->{$y_type}->{min}) < $curr_config->{min_x_size}){
		if (not defined $lims[2]){
		    $lims[2] = ( ( ( $colrange->{$y_type}->{max} + $colrange->{$y_type}->{min} ) / 2 ) 
				 - ( $curr_config->{min_x_size}/2 ));
		}
		if (not defined $lims[3]){
		    $lims[3] = ( ( ( $colrange->{$y_type}->{max} + $colrange->{$y_type}->{min} ) / 2 ) 
				 + ( $curr_config->{min_x_size}/2 ));
		}
	    }
	}

	push @array, ( lims => \@lims );
    }
    

    push @array, plot_summary( $y_type, $x_type, $data_ref );


    return @array;


}


1;
