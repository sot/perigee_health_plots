#!/usr/bin/env /proj/sot/ska/bin/perlska

use strict; 
use warnings;
use PGPLOT::Simple qw( pgs_plot );
use XML::Dumper;
use PDL;
use PDL::NiceSlice;

# infile and outfile
my $xml_file = 'data.xml.gz';
my $pltname1 = 'aca_health_pgplot.ps';

# color choices for plot
my @colorlist = ( 'red', 'green', 'blue', 'hot pink', 'cyan', 'sienna', 'thistle');
my @columns = ( 'time', 'obsid', 'aca_temp', 'ccd_temp', 'dac');

# read in data from XML file
my $dump = new XML::Dumper;
my %data = %{$dump->xml2pl( $xml_file )};

# convert the handy text arrays to pdls
my %datapdl;
for my $column ( @columns ){
    $datapdl{$column} = pdl( @{$data{$column}} );
}

#let's figure out how many obsids are present
my @uniqobsid = ($datapdl{obsid}->uniq)->list;

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




my @plotarray;


# Page Setup
push @plotarray, ( nx => 2, ny => 2,
		   xsize => 9,
		   ysize => 6,
		   device => "$pltname1/vcps",
		   );

# ACA TEMP
push @plotarray, ( panel => [1,1],
		   xtitle=>'Seconds from Radmon disable',
		   ytitle=>'ACA temp (C)',
		   lims   => [0, undef, 17, 21],
		   );


#my @aca_temp_plot = plot_vs_time( 'aca_temp ')
push @plotarray, plot_vs_time( 'aca_temp' );

#my %obsidcolor;
#
#for my $i (0 .. $#uniqobsid){
#    my $obsid_match_idx = which( $obsidpdl == $uniqobsid[$i] );
#    my @match_time = $timepdl->($obsid_match_idx)->list;
#    my @time = map { $_ - $timepdl->min } @match_time;
#    my @aca_data = pdl( $data{aca_temp})->($obsid_match_idx)->list;
#    my $color = $colorlist[($i % scalar(@colorlist))];
#    $obsidcolor{$uniqobsid[$i]} = $color;
#    my @aca_plot_array = (
#			  'x' => [@time],
#			  'y' => [@aca_data],
#			  color => { symbol => $color },
#			  plot => 'points',
#			  );
#    push @plotarray, @aca_plot_array;
#}
#
## CCD TEMP
#push @plotarray, ( panel => [2,1],
#		   xtitle=>'Seconds from Radmon disable',
#		   ytitle=>'CCD temp (C)',
#		   lims   => [0, undef, -21, -17],
#		   );
#
#
#for my $i (0 .. $#uniqobsid){
#    my $obsid_match_idx = which( $obsidpdl == $uniqobsid[$i] );
#    my @match_time = $timepdl->($obsid_match_idx)->list;
#    my @time = map { $_ - $timepdl->min } @match_time;
#    my @plotdata = pdl( $data{ccd_temp})->($obsid_match_idx)->list;
#    my $color = $colorlist[($i % scalar(@colorlist))];
#    my @data_plot_array = (
#			  'x' => [@time],
#			  'y' => [@plotdata],
#			  color => { symbol => $color },
#			  plot => 'points',
#			  );
#    push @plotarray, @data_plot_array;
#}
#
#
#
#my $dtemp = pdl ( map { $data{aca_temp}->[$_] - $data{ccd_temp}->[$_] }	 (0 ... scalar(@{$data{time}})-1) );
#		  
#my $npoints = 100;
#
## how much of the plot do I want with data in x
#my $dac_xscale = .8;
#
#my $delta = ($dtemp->max)-($dtemp->min);
#my $plotdelta = $delta/$dac_xscale;
## left and right pad to get $dac_xscale of the plot to have data
#my $pad = ($plotdelta-$delta)/2;
#
#my $xvals = sequence($npoints+1)*(($plotdelta)/($npoints))+(($dtemp->min)-($pad));
#
## predicted second order polynomial for aca-ccd vs dac
#my @polyfit = ( 114.474, 0.403096, 0.236348 );
#my $yvals = $polyfit[0] + $xvals*$polyfit[1] + ($xvals*$xvals)*$polyfit[2];
#
#
#
## DAC
#push @plotarray, ( panel => [1,2],
#		   xtitle=>'Seconds from Radmon disable',
#		   ytitle=>'TEC DAC Control Level',
#		   lims   => [0, undef, ($yvals->min)-10, 520],
#		   );
#
#for my $i (0 .. $#uniqobsid){
#    my $obsid_match_idx = which( $obsidpdl == $uniqobsid[$i] );
#    my @match_time = $timepdl->($obsid_match_idx)->list;
#    my @time = map { $_ - $timepdl->min } @match_time;
#    my @plotdata =  pdl( $data{dac})->($obsid_match_idx)->list;
#    my $color = $colorlist[($i % scalar(@colorlist))];
#    my @data_plot_array = (
#			   'x' => [ @time ],
#			   'y' => [ @plotdata ],
#			   color => { symbol => $color },
#			   plot => 'points',
#			   );
#    push @plotarray, @data_plot_array;
#}
#
#push @plotarray, ( panel => [2,2],
#		   xtitle=>'ACA temp - CCD temp (C)',
#		   ytitle=>'TEC DAC Control Level',
#		   lims => [ ($dtemp->min)-($pad), ($dtemp->max)+($pad), ($yvals->min)-10, 520],
#		   );
#
#
#for my $i (0 .. $#uniqobsid){
#    my $obsid_match_idx = which( $obsidpdl == $uniqobsid[$i] );
#    my @match_dtemp = $dtemp->($obsid_match_idx)->list;
#    my @plotdata =  pdl( $data{dac})->($obsid_match_idx)->list;
#    my $color = $colorlist[($i % scalar(@colorlist))];
#    my @data_plot_array = (
#			   'x' => [ @match_dtemp ],
#			   'y' => [ @plotdata ],
#			   color => { symbol => $color },
#			   plot => 'points',
#			   );
#    push @plotarray, @data_plot_array;
#}
#
#push @plotarray, (
#		  # 511 Line
#		  'x' => [ ($dtemp->min)-10, ($dtemp->max)+10],
#		  'y' => [ 511, 511],
#		  color => { line => 'red' },
#		  plot => 'line',
#		  # Prediction
#		  'x' => [ $xvals->list ],
#		  'y' => [ $yvals->list ],
#		  color => { line => 'black' },
#		  options => {linestyle => 'dashed' },
#		  plot => 'line',
#		  );
#
#
#
#
#pgs_plot( @plotarray );

sub plot_vs_time{
    my $column = shift;
    my @data_plot_array;
    
    for my $i (0 .. $#ordered_obsid){
	my $obsid = $ordered_obsid[$i];
	my @time = map { $_ - $tzero } @{$datapdl{time}->($obsid_idx{$obsid})->list};
	my $color = $colorlist[($i % scalar(@colorlist))];
	push @data_plot_array = (
				 'x' => [@time],
				 'y' => $datapdl{$column}->($obsid_idx{$obsid}),
				 color => { symbol => $color },
				 plot => 'points',
				 );
    }
    
    return @data_plot_array;

}
