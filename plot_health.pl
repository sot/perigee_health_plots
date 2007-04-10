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

GetOptions (\%opt,
            'help!',
            'dir=s',
            'missing!',
            'verbose|v!',
            'delete!',
	    'config=s',
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

for my $dir (@todo_directories[0]){
    if ($opt{verbose}){
	print "making plots for $dir \n";
    }
    plot_health( $dir, \%config );
    convert_to_gif( "${dir}/$health_plot", "${dir}/$health_plot_gif");
    convert_to_gif( "${dir}/$legend", "${dir}/$legend_gif");
    if (( -e "${dir}/$health_plot_gif" ) and (-e "${dir}/$legend_gif" )){
        if ($opt{delete}){
            unlink("${dir}/$health_plot");
            unlink("${dir}/$legend");
        }
    }
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
    my $dir = shift;
    my $config = shift;

    
    my $xml_file = "${dir}/$config->{xml_data_file}";
    my $plotname = "${dir}/$config->{health_plot}.ps";
    my $legendname = "${dir}/$config->{legend_plot}.ps";

## infile and outfile
#my $xml_file = 'data.xml.gz';
#my $plotname = 'aca_health_pgplot.ps';
#my $legendname = 'legend.ps';
#

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

    my $plot_helper = PlotHelper->new({ ordered_obsid => \@ordered_obsid,
					colorlist => \@colorlist,
					obsid_idx => \%obsid_idx,
					datapdl => \%datapdl});
    


my @plotarray;

# Page Setup
push @plotarray, ( nx => 2, ny => 2,
		   xsize => 9,
		   ysize => 6,
		   device => "$plotname/vcps",
		   );

# ACA TEMP
    push @plotarray, ( panel => [1,1]);
    
    # set reasonable defaults
    my %plot11 = ( xtitle=>'Seconds from Radmon disable',
		   ytitle=>'ACA temp (C)',
		   lims   => [0, undef, 17, 21],
		   );

    # allow them to be overridden with config file
    for my $key (keys %plot11){
	if (defined $config->{plot11}->{$key}){
	    $plot11{$key} = $config->{plot11}->{$key};
	}
    }

    push @plotarray, %plot11;

#my @aca_temp_plot = $plot_helper->plot_a_vs_b( 'aca_temp ')

    push @plotarray, $plot_helper->plot_a_vs_b( 'aca_temp', 'dtime' );

 
 # CCD TEMP
    push @plotarray, ( panel => [2,1]);

    # set reasonable defaults
    my %plot21 = ( xtitle=>'Seconds from Radmon disable',
 		   ytitle=>'CCD temp (C)',
 		   lims   => [0, undef, -21, -17],
 		   );
 
    # allow them to be overridden with config file
    for my $key (keys %plot21){
	if (defined $config->{plot21}->{$key}){
	    $plot21{$key} = $config->{plot21}->{$key};
	}
    }

    push @plotarray, %plot21;
    
    push @plotarray, $plot_helper->plot_a_vs_b( 'ccd_temp', 'dtime' );
 
 
 # I want both DAC plots to have the same scale by default, so I'll need to figure out the range and such
 
 $datapdl{dtemp} = $datapdl{aca_temp} - $datapdl{ccd_temp};

    for my $i ( 0 .. ($datapdl{dtemp}->nelem)-1 ){
	if ( $datapdl{dtemp}->at($i) < 35 ){
	    print "at $i ", $datapdl{dtemp}->at($i), " aca ", $datapdl{aca_temp}->at($i), " ccd ", $datapdl{ccd_temp}->at($i), " time ", $datapdl{time}->at($i), "\n";
	}	
    }
    print "\n";
 		  
 my $npoints = 100;
 
 # how much of the plot do I want with data in x
 my $dac_xscale = .8;
 

 my $data_xrange = ($datapdl{dtemp}->max)-($datapdl{dtemp}->min);
    print "data range is $data_xrange \n";
 my $plot_xrange = $data_xrange/$dac_xscale;
 # left and right pad to get $dac_xscale of the plot to have data
 my $pad = ($plot_xrange-$data_xrange)/2;
 
 # dummy x points for the fit line
 my $xvals = sequence($npoints+1)*(($plot_xrange)/($npoints))+(($datapdl{dtemp}->min)-($pad));
print $xvals->min, "\t", $xvals->max, "\n"; 
 # predicted second order polynomial for aca-ccd vs dac
    my $yvals = $polyfit[0] + $xvals*$polyfit[1] + ($xvals*$xvals)*$polyfit[2];
    print $yvals->min, "\t", $yvals->max, "\n";

 # make an object to store
 
 
 # DAC
 push @plotarray, ( panel => [1,2]);

    my %plot12 = ( xtitle=>'Seconds from Radmon disable',
 		   ytitle=>'TEC DAC Control Level',
 		   lims   => [0, undef, ($yvals->min)-2, ($yvals->max)+2],
 		   );
    
    # allow them to be overridden with config file
    for my $key (keys %plot12){
	if (defined $config->{plot12}->{$key}){
	    $plot12{$key} = $config->{plot12}->{$key};
	    if ( $key eq 'lims'){
		if (not defined $config->{plot12}->{lims}->[2]){
		    $plot12{lims}->[2] = ($yvals->min)-2;
		}
		if (not defined $config->{plot12}->{lims}->[3]){
		    $plot12{lims}->[3] = ($yvals->max)+2;
		}
	    }

	}
    }

    push @plotarray, %plot12;

    push @plotarray, $plot_helper->plot_a_vs_b( 'dac', 'dtime' );
#    use Data::Dumper;
#    print Dumper $plot_helper->plot_a_vs_b( 'dac', 'dtime' );

# 
# 
 # DAC vs Delta Temp
    push @plotarray, ( panel => [2,2]);

    my %plot22 = ( xtitle=>'ACA temp - CCD temp (C)',
 		   ytitle=>'TEC DAC Control Level',
 		   lims => [ ($datapdl{dtemp}->min)-($pad), ($datapdl{dtemp}->max)+($pad), ($yvals->min)-2, ($yvals->max)+2],
 		   );

    for my $key (keys %plot22){
	if (defined $config->{plot22}->{$key}){
	    $plot22{$key} = $config->{plot22}->{$key};
	    if ( $key eq 'lims'){
		if (not defined $config->{plot22}->{lims}->[2]){
		    $plot22{lims}->[2] = ($yvals->min)-2;
		}
		if (not defined $config->{plot22}->{lims}->[3]){
		    $plot22{lims}->[3] = ($yvals->max)+2;
		}
	    }

	}
    }

    push @plotarray, %plot22;

    push @plotarray, $plot_helper->plot_a_vs_b( 'dac', 'dtemp' );
 
    push @plotarray, (
 		  # Prediction
		      'x' => [ $xvals->list ],
		      'y' => [ $yvals->list ],
		      color => { line => 'black' },
		      options => {linestyle => 'dashed' },
		      plot => 'line',
		      );

    if ( ($datapdl{dac}->max > 511 )){
	print "red line \n";
	push @plotarray, (
			  # 511 Line
			  'x' => [ ($datapdl{dtemp}->min)-10, ($datapdl{dtemp}->max)+10],
			  'y' => [ 511, 511],
			  color => { line => 'red' },
       		  plot => 'line',
			  );
    }
 
 

pgs_plot( @plotarray );


#    my $master_width = 6 + $sub_width;
my $master_width = 10;
my $aspect = .5;

#my $obsid = $self->{obsid};

#    print "sub width = $sub_width, sub height = $sub_height \n";
#   print "width = $master_width, aspect = $aspect \n";

# Setup pgplot
my $dev = "$legendname/vcps"; # unless defined $dev;  # "?" will prompt for device
pgbegin(0,$dev,2,1);  # Open plot device
pgpap($master_width, $aspect );
pgscf(1);             # Set character font
pgscr(0, 1.0, 1.0, 1.0);
pgscr(1, 0.0, 0.0, 0.0);
#    pgslw(2);

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




pgend;

}


package PlotHelper;

use strict;
use warnings;
use Class::MakeMethods::Standard::Hash(
                                        scalar => [ qw(
						       ordered_obsid
						       colorlist
						       obsid_idx
						       datapdl
                                                       )
                                                    ],
				       );
use CFITSIO::Simple;


sub new{

    my $class = shift;
    my $self = {};
    bless $self, $class;

    my $arg_in = shift;
    $self->ordered_obsid($arg_in->{ordered_obsid});
    $self->colorlist($arg_in->{colorlist});
    $self->obsid_idx($arg_in->{obsid_idx});
    $self->datapdl($arg_in->{datapdl});

    return $self;

}


sub plot_a_vs_b{
    my $self = shift;
    my $a = shift;
    my $b = shift;

    
    my @ordered_obsid = @{$self->ordered_obsid()};
    my @colorlist = @{$self->colorlist()};
    my %obsid_idx = %{$self->obsid_idx()};
    my %datapdl = %{$self->datapdl()};

    my @data_plot_array;
    
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
    
    return @data_plot_array;

}

1;
