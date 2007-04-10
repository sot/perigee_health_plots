#!/usr/bin/env /proj/sot/ska/bin/perlska

use warnings;
use strict;
use Getopt::Long;

use Telemetry;
use Carp;
use PDL;
use PDL::NiceSlice;
use YAML;
use Data::ParseTable qw( parse_table );
use Ska::Convert qw( date2time );
use XML::Dumper;



my %opt = ();

#our %opt = ();

GetOptions (\%opt,
            'help!',
	    'config=s',
            'dir=s',
	    'missing!',
	    'verbose|v!',
	    'delete!'
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
    %config = YAML::LoadFile( "${SHARE}/perigee_telem_parse.yaml" );
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



my $xml_out_file;
if (defined $config{xml_out_file}){
    $xml_out_file = $config{xml_out_file};
}
else{
    $xml_out_file = "data.xml.gz";
}

# Search for directories in $WORKING_DIR that have telemetry but don't have 
# $xml_out_file

my @todo_directories;

# first get a list of directories.
my @telem_dirs = glob("${WORKING_DIR}/????:*");

# step backward through them until I find one that has an $xml_out_file
for my $dir ( reverse @telem_dirs ){
    if ( -e "${dir}/$xml_out_file" ){
	last unless $opt{missing};
    }
    else{
	push @todo_directories, $dir;
    }
}


for my $dir (@todo_directories){
    if ($opt{verbose}){
	print "parsing telemetry for $dir \n";
    }
    my $result = perigee_parse({ dir => $dir,
				 ska => $SKA,
				 time_interval => $config{time_interval},
				 min_samples => $config{min_samples},
				 column_config  => $config{column_config},
				 pass_time_file => $config{pass_time_file},
			     });



    # let's find points outside the expected ranges from the median
    my %threshold;
    if (defined $config{threshold}){
	%threshold = %{$config{threshold}};
    }
    for my $column (keys %threshold){

	print "column is $column \n";

	my $column_pdl = pdl( @{$result->{telem}->{$column}} );

	my $limit = $threshold{$column};

	my $not_ok = which( ($column_pdl < ( medover( $column_pdl ) - $limit ))
			    | ( $column_pdl > ( medover( $column_pdl ) + $limit )));

	if ( $not_ok->nelem > 0 ){
	    $result->{info}->{bad_points}->{$column} = [ $not_ok->list ];
	}
    }

    use Data::Dumper;
    print Dumper $result->{info};
    my $dump = new XML::Dumper;
    $dump->pl2xml( $result, "${dir}/$xml_out_file" );
    chmod 0775, "${dir}/$xml_out_file";

    if ( -e "${dir}/$xml_out_file" ){
	if ($opt{delete}){
	    unlink("${dir}/acaf*fits.gz");
	    unlink("${dir}/ccdm*fits.gz");
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
sub perigee_parse{
##***************************************************************************

    my $args = shift;

#    use Data::Dumper;
#    print Dumper $args;

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
#    my $pass_time_file = "${DIR}/pass_times.txt";
    my $pass_time_file = "${DIR}/$args->{pass_time_file}";
#    my $xml_out_file = "${DIR}/$args->{xml_out_file}";
#    my $xml_out_file = "${DIR}/data.xml.gz";
    
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
    my $ccdm = Telemetry::Interval->new({ file_list => \@ccdm_file_list, columns => \@ccdmcols})->combine_telem();


my %aca0;
for my $slot ( 0, 1, 2, 6, 7 ){
    my @file_list = glob("${DIR}/aca*_${slot}_*gz");
    my $aca_telem = Telemetry::Interval::ACA0->new({ file_list => \@file_list })->combine_telem();
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



