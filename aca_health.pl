#!/usr/bin/env /proj/sot/ska/bin/perlska


use warnings;
use strict;
use Telemetry;
#require "/proj/gads6/jeanproj/perigee_health_plots/Telemetry.pm";
use Carp;
use PDL;
use PDL::NiceSlice;
use YAML;
use IO::All;
use Data::ParseTable qw( parse_table );
use Ska::Convert qw( date2time );

my $time_interval = 20;
my $min_samples = 4;


# Let's use a config file to define how to "build" our columns from the header 3 telemetry
# see the config file for an explanation of its format
#use GrabEnv qw( grabenv );
my $SKA = $ENV{SKA} || '/proj/sot/ska';
my $column_config_file = "${SKA}/data/perigee_health_plots/column_conversion.yaml";


# other files
my $pass_time_file = 'pass_times.txt';
my $xml_out_file = 'data.xml.gz';


my %column_conversion = YAML::LoadFile($column_config_file);


my @captimes = io($pass_time_file)->slurp;
my $pass_times = parse_table(\@captimes);
my %pass_time_cs = (
		    tstart => date2time($pass_times->[0]->{TSTART}),
		    tstop => date2time($pass_times->[0]->{TSTOP}),
		    );


my @ccdmcols = ('time', 'quality', 'cobsrqid' );
my @ccdm_file_list = glob("ccdm*gz");
my $ccdm = Telemetry::Interval->new({ file_list => \@ccdm_file_list, columns => \@ccdmcols});
$ccdm->combine_telem();



my %aca0;
for my $slot ( 0, 1, 2, 6, 7 ){
    my @file_list = glob("aca*_${slot}_*gz");
    my $aca_telem = Telemetry::Interval::ACA0->new({ file_list => \@file_list })->combine_telem();
    $aca0{$slot} =  $aca_telem;
}


my $maxtimepdl = pdl( $pass_time_cs{tstop} );
my $mintimepdl = pdl( $pass_time_cs{tstart} );
for my $slot ( 0, 1, 2, 6, 7 ){
    $maxtimepdl = $maxtimepdl->append( $aca0{$slot}->telem->{time}->max );
    $mintimepdl = $mintimepdl->append( $aca0{$slot}->telem->{time}->min );
}


my $maxtime =  $maxtimepdl->min ;
my $mintime =  $mintimepdl->max ;
my $n_intervals = ($maxtime - $mintime)/($time_interval);




my %result;

%{$result{info}} = (
		 sample_interval_in_secs => $time_interval,
		 tstart => $mintime,
		 tstop => $maxtime,
		 min_required_samples => $min_samples,
		 number_of_intervals => $n_intervals,
		 );



for my $i ( 0 ... floor($n_intervals) ){

    my $range_start = $mintime + ($i * $time_interval);
    my $range_end = $range_start + $time_interval;

    my $ok_ccdm = which( ($ccdm->telem()->{time} >= $range_start )
			 & ( $ccdm->telem()->{time} < $range_end ));
    my $obsid_pdl = $ccdm->telem->{cobsrqid}->($ok_ccdm);

    my %ok;

    for my $slot (0, 1, 2, 6, 7){
	$ok{$slot} = which( ( $aca0{$slot}->telem->{time} >= $range_start )
			    & ( $aca0{$slot}->telem->{time} < $range_end )
			    & ( $aca0{$slot}->telem->{imgdim} == 8 )
			    );
	
    }

    my $samples = pdl( map $ok{$_}->nelem(), (0,1,2,6,7) );

    if ( $samples->min() >= $min_samples ){

	my $obsid = $obsid_pdl->at(0);
	push @{$result{obsid}}, $obsid;

	my @products = keys %column_conversion;
	
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
	    
	    push @{$result{$name}}, sclr( medover( eval( $product_string ) ) );


	}




    }
}

use XML::Dumper;
my $perl = \%result;
my $dump = new XML::Dumper;
$dump->pl2xml( $perl, $xml_out_file );
#my $xml = $dump->pl2xml( $perl );
#my $outfile = io($xml_out_file);
#$outfile->print($xml);


