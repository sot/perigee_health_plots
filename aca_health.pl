#!/usr/bin/env /proj/sot/ska/bin/perlska


use warnings;
use strict;



my @columns = ('quality', 'time', 'imgraw');

#my @eightbyeightcolumns = ( 'imgraw', 'quality', 'time', 'TEMPCCD', 'TEMPHOUS','TEMPPRIM','TEMPSEC','HD3TLM62','HD3TLM63','HD3TLM64','HD3TLM65','HD3TLM66','HD3TLM67','HD3TLM72','HD3TLM73','HD3TLM74','HD3TLM75','HD3TLM76','HD3TLM77');

my @eightbyeightcolumns = @columns;

my @ccdmcols = ('time', 'quality', 'cobsrqid' );
#my @ccdmcols = ('time', 'quality' );

#

require "/proj/gads6/jeanproj/perigee_health_plots/Telemetry.pm";
use Carp;
use PDL;
use Data::Dumper;

my @ccdm_file_list = glob("ccdm*gz");
my $ccdm = Telemetry::Interval->new({ file_list => \@ccdm_file_list, columns => \@ccdmcols});
$ccdm->combine_telem();


my @aca0_0_list = glob("aca*_0_*gz");
my @aca0_1_list = glob("aca*_1_*gz");
my @aca0_2_list = glob("aca*_2_*gz");
my @aca0_3_list = glob("aca*_3_*gz");
my @aca0_4_list = glob("aca*_4_*gz");
my @aca0_5_list = glob("aca*_5_*gz");
my @aca0_6_list = glob("aca*_6_*gz");
my @aca0_7_list = glob("aca*_7_*gz");



my $aca0_0 = Telemetry::Interval::ACA0->new({ file_list => \@aca0_0_list } );
$aca0_0->combine_telem();
my $aca0_1 = Telemetry::Interval::ACA0->new({ file_list => \@aca0_1_list } );
$aca0_1->combine_telem();
my $aca0_2 = Telemetry::Interval::ACA0->new({ file_list => \@aca0_2_list } );
$aca0_2->combine_telem();
my $aca0_6 = Telemetry::Interval::ACA0->new({ file_list => \@aca0_6_list } );
$aca0_6->combine_telem();
my $aca0_7 = Telemetry::Interval::ACA0->new({ file_list => \@aca0_7_list } );
$aca0_7->combine_telem();


print "time ", $aca0_7->telem()->{time}->nelem(), "\n";
print "hdr3 ", $aca0_7->telem()->{hd3tlm76}->nelem(), "\n";

my $maxtimepdl = pdl( $aca0_0->telem()->{time}->max, 
		      $aca0_1->telem()->{time}->max, 
		      $aca0_2->telem()->{time}->max,
		      $aca0_6->telem()->{time}->max,
		      $aca0_7->telem()->{time}->max);
my $maxtime =  $maxtimepdl->min ;
my $mintimepdl = pdl( $aca0_0->telem()->{time}->min, 
		      $aca0_1->telem()->{time}->min, 
		      $aca0_2->telem()->{time}->min,
		      $aca0_6->telem()->{time}->min,
		      $aca0_7->telem()->{time}->min);

my $mintime =  $mintimepdl->max ;

my $time_interval = 20;
my $min_samples = 4;
my $n_intervals = ($maxtime - $mintime)/($time_interval);
print "$n_intervals \n";
my $obsid = 0;
my $obsid_cnt = -1;

my @result;

use PDL::NiceSlice;

for my $i ( 0 ... floor($n_intervals) ){
#for my $i ( 0 ... 10 ){
    my $range_start = $mintime + ($i * $time_interval);
    my $range_end = $range_start + $time_interval;
    my $ok_slot0 = which( ( $aca0_0->telem()->{time} >= $range_start )
			  & ( $aca0_0->telem()->{time} < $range_end )
			  & ( $aca0_0->telem()->{imgdim}  == 8) );
    my $ok_slot1 = which( ( $aca0_1->telem()->{time} >= $range_start )
			  & ( $aca0_1->telem()->{time} < $range_end )
			  & ( $aca0_1->telem()->{imgdim} == 8 ) );
    my $ok_slot2 = which( ( $aca0_2->telem()->{time} >= $range_start )
			  & ( $aca0_2->telem()->{time} < $range_end )
			  & ( $aca0_2->telem()->{imgdim} == 8 ) );
    my $ok_slot6 = which( ( $aca0_6->telem()->{time} >= $range_start )
			  & ( $aca0_6->telem()->{time} < $range_end )
			  & ( $aca0_6->telem()->{imgdim} == 8 ) );
    my $ok_slot7 = which( ( $aca0_7->telem()->{time} >= $range_start )
			  & ( $aca0_7->telem()->{time} < $range_end )
			  & ( $aca0_7->telem()->{imgdim} == 8 ) );

#    print "$i \t", $ok_slot7, "\n";
    

    if ( ( $ok_slot0->nelem >= $min_samples )
	 and ( $ok_slot1->nelem >= $min_samples )
	 and ( $ok_slot2->nelem >= $min_samples )
	 and ( $ok_slot6->nelem >= $min_samples )
	 and ( $ok_slot7->nelem >= $min_samples )){
	my $time = medover( $aca0_7->telem()->{time}->($ok_slot7));
	
	my $dac = medover( 256*( $aca0_7->telem()->{hd3tlm76}->($ok_slot7 )) 
			   + ( $aca0_7->telem()->{hd3tlm77}->($ok_slot7)) 
			   );
	my $h066 = medover( $256( $aca0_0->telem()->{hd3tlm66}->($ok_slot0))
			    + ( $aca0_0->telem()->{hd3tlm67}->($ok_slot0))
			    );
	my $h072 = medover( $256( $aca0_0->telem()->{hd3tlm72}->($ok_slot0))
			    + ( $aca0_0->telem()->{hd3tlm73}->($ok_slot0))
			    );
	my $h074 = medover( $256( $aca0_0->telem()->{hd3tlm74}->($ok_slot0))
			    + ( $aca0_0->telem()->{hd3tlm75}->($ok_slot0))
			    );
	my $h174 = medover( $256( $aca0_1->telem()->{hd3tlm74}->($ok_slot1))
			    + ( $aca0_1->telem()->{hd3tlm75}->($ok_slot1))
			    );
	my $h176 = medover( $256( $aca0_1->telem()->{hd3tlm76}->($ok_slot1))
			    + ( $aca0_1->telem()->{hd3tlm77}->($ok_slot1))
			    );
	my $h262 = medover( $256( $aca0_2->telem()->{hd3tlm62}->($ok_slot2))
			    + ( $aca0_2->telem()->{hd3tlm63}->($ok_slot2))
			    );
	my $h264 = medover( $256( $aca0_2->telem()->{hd3tlm64}->($ok_slot2))
			    + ( $aca0_2->telem()->{hd3tlm65}->($ok_slot2))
			    );
	my $h266 = medover( $256( $aca0_2->telem()->{hd3tlm66}->($ok_slot2))
			    + ( $aca0_2->telem()->{hd3tlm67}->($ok_slot2))
			    );
	
	my $h272 = medover( $256( $aca0_2->telem()->{hd3tlm72}->($ok_slot2))
			    + ( $aca0_2->telem()->{hd3tlm73}->($ok_slot2))
			    );
	my $h274 = medover( $256( $aca0_2->telem()->{hd3tlm74}->($ok_slot2))
			    + ( $aca0_2->telem()->{hd3tlm75}->($ok_slot2))
			    );
	my $h276 = medover( $256( $aca0_2->telem()->{hd3tlm76}->($ok_slot2))
			    + ( $aca0_2->telem()->{hd3tlm77}->($ok_slot2))
			    );
	
	my $aca_temp = medover( (1/256.)*( $aca0_7->telem()->{hd3tlm73}->($ok_slot7)) 
				+ ( $aca0_7->telem()->{hd3tlm72}->($ok_slot7)) 
				);
	
	my $ccd_temp = medover( ( 256*( $aca0_6->telem()->{hd3tlm76}->($ok_slot6 )) 
				  + ( $aca0_6->telem()->{hd3tlm77}->($ok_slot6) ) 
				  - 65536
				  )
				/ 100.
				)
	    ;


	print $time, " ", $dac, " ",  $ccd_temp, " ", $aca_temp, "\n";

	
#	print $aca0_7->telem()->{time}->nelem, "\n";
#	print $aca0_7->telem()->{hd3tlm76}->nelem, "\n";
#	print $aca0_7->telem()->{hd3tlm77}->nelem, "\n";
#
#	my %curr_result;

    }	

}

print Dumper @result;
#
#
#

#my $tstart = 233554382.20;
#my $tstop = 233554390.40;
#
#my $match = which( ($aca0_2{time} >= ($tstart - 60)) & ($aca0_2{time} <= ($tstop + 20)));
#my @match_array = list $match;
#
#use PDL::NiceSlice;
#
#for my $index (@match_array){
#    my $img = $aca0_2{imgraw}->(0:7,0:7,$index);
#    print $img;
#}
#
#my $obsid = 0;
#my $obsid_count = -1;
#
#for my $slot ( 0 ... 7 ){
##    print "slot is $slot \n";
#
#
#}
#




