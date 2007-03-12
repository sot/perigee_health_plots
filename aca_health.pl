#!/usr/bin/env /proj/sot/ska/bin/perlska


use warnings;
use strict;
use CFITSIO::Simple;


my @columns = ('quality', 'time', 'imgraw');

#my @eightbyeightcolumns = ( 'imgraw', 'quality', 'time', 'TEMPCCD', 'TEMPHOUS','TEMPPRIM','TEMPSEC','HD3TLM62','HD3TLM63','HD3TLM64','HD3TLM65','HD3TLM66','HD3TLM67','HD3TLM72','HD3TLM73','HD3TLM74','HD3TLM75','HD3TLM76','HD3TLM77');

my @eightbyeightcolumns = @columns;

my @ccdmcols = ('time', 'quality', 'cobsrqid' );

#


use Carp;
use PDL;
use Data::Dumper;

#my @ccdm_file_list = glob("ccdm*gz");
#my %ccdm = combine_telem(\@ccdm_file_list, \@ccdmcols);

my @aca0_0_list = glob("aca*_0_*gz");
my @aca0_1_list = glob("aca*_1_*gz");
my @aca0_2_list = glob("aca*_2_*gz");
my @aca0_3_list = glob("aca*_3_*gz");
my @aca0_4_list = glob("aca*_4_*gz");
my @aca0_5_list = glob("aca*_5_*gz");
my @aca0_6_list = glob("aca*_6_*gz");
my @aca0_7_list = glob("aca*_7_*gz");


#my %aca0_0 = combine_telem(\@aca0_0_list, \@eightbyeightcolumns );
#my %aca0_1 = combine_telem(\@aca0_1_list, \@eightbyeightcolumns );
my %aca0_2 = combine_telem(\@aca0_2_list, { type => 'aca8x8'} );
#my %aca0_3 = combine_telem(\@aca0_3_list, \@eightbyeightcolumns );
#my %aca0_4 = combine_telem(\@aca0_4_list, \@eightbyeightcolumns );
#my %aca0_5 = combine_telem(\@aca0_5_list, \@eightbyeightcolumns );
#my %aca0_6 = combine_telem(\@aca0_6_list, \@eightbyeightcolumns );
#my %aca0_7 = combine_telem(\@aca0_7_list, \@eightbyeightcolumns );

my $tstart = 233554382.20;
my $tstop = 233554390.40;

my $match = which( ($aca0_2{time} >= ($tstart - 60)) & ($aca0_2{time} <= ($tstop + 20)));
my @match_array = list $match;

use PDL::NiceSlice;

for my $index (@match_array){
    my $img = $aca0_2{imgraw}->(0:7,0:7,$index);
    print $img;
}

my $obsid = 0;
my $obsid_count = -1;

for my $slot ( 0 ... 7 ){
#    print "slot is $slot \n";


}



package Telemetry::Interval;

use strict;
use warnings;
use Carp;

use Class::MakeMethods::Standard::Hash (
					scalar => [ qw(
						       file_list
						       desired_cols
						       type
						       telem
						       )
						    ],
					);
						       

sub new{

    my $self = {};
    bless $self, $class;
    my $arg_in = shift;

    if (defined $arg_in->{file_list}){
	$self->file_list($arg_in->{file_list});
    }
    if (defined $arg_in->{type}){
	$self->type($arg_in->{type});
    }
    if (defined $arg_in->{desired_cols}){
	$self->desired_cols($arg_in->{desired_cols});
    }

    return $self;
}



sub combine_telem{
# assumes that longest dim is time-dependent
    
    my $self = shift;

    unless ( defined $self->file_list()){
	croak(__PACKAGE__ . "No telemetry files specified.");
    }	     

    unless ( ( defined $self->type() ) or ( defined $self->desired_cols() ) ){
	croak(__PACKAGE__ . "Must specify type of telemetry or list of desired columns.");
    }

    my $file_list = $self->file_list();

    my %template_hash;
    my %telem;
    
    if (defined $self->type()){
	my $type = $self->type();
	if ( -e "${type}.yaml" ){
	    %template_hash = YAML::LoadFile("${type}.yaml");
	}
    }

    if (defined $self->desired_cols()){

	my $desired_cols = $self->desired_cols();

	my $template_file;

	for my $file (@{$file_list}){

	    my %fits = fits_read_bintbl($file);

	    if ( has_all_cols( \%fits, $desired_cols) ){
		$template_file = $file;
		last;
	    }
	}
	if (not defined $template_file){
	    croak(__PACKAGE__ . "could not find matching columns in any telem files");
	}

	%template_hash = fits_read_bintbl( $template_file, @{$desired_cols} );
    }


    for my $file (@{$file_list}){

	my %temp_fits = fits_read_bintbl( $file );

	if (not defined $temp_fits{time}){
	    croak(__PACKAGE__ . "$file is not telemetry, has no 'time' field");
	}
	
	for my $col (@{$desired_cols}){
	    
	    if ( defined $temp_fits{$col} ){

		
		if ( match_dim( $template_hash{$col}, $temp_fits{$col} )){
		    # if this is our first shot, just do the assignment
		    
		    if ( not defined $telem{$col}){
			$telem{$col} = $temp_fits{$col};
			$telem{"${col}_valid"} = ones( $temp_fits{$col}->getdim(longest_dim($temp_fits{$col})) );
		    }
		    else{
			# else, if we have real data, append it
			if ( UNIVERSAL::isa($template_hash{$col}, 'PDL' )){
			    my $temp = $telem{$col}->glue( longest_dim($temp_fits{$col}), $temp_fits{$col});
			    $telem{$col} = $temp;			
			    my $temp_valid = $telem{"${col}_valid"}->append( ones( $temp_fits{$col}->getdim( longest_dim($temp_fits{$col}))));
			    $telem{"${col}_valid"} = $temp_valid;
			    
			}
			else{
			    if ( ref($template_hash{$col}) eq 'ARRAY'){
				my $temp_valid = $telem{"${col}_valid"}->append( ones( scalar(@{$template_hash{$col}})));
				$telem{"${col}_valid"} = $temp_valid;
				push @{$telem{$col}}, @{$temp_fits{$col}};
			    }
			}
		    }
		}

		else{
		    # for the special case of aca imgraw data
		    if ($col eq 'imgraw'){
			%temp_fits = $self->make_imgraw_data_fit({ template => \%template_hash, tempdata => \%temp_fits });
		    }
		    
		    print "inventing data for $file for $col \n";
		    $self->make_up_data({ column => $col, template => \%template_hash, tempdata => \%temp_fits } );		    
		    
		}
		
	    }
	    # if this file doesn't have any data, append zeros for the interval
	    else{
		print "inventing data for $file for $col \n";
		$self->make_up_data({ column => $col, template => \%template_hash, tempdata => \%temp_fits });
	    }
	
	}
    }

    $self->telem(\%telem);
    return \%telem;

}

sub has_all_cols{
    my $fits = shift;
    my $desired_cols = shift;

    my @keys = keys %{$fits};
    my $match = 1;
    for my $col (@{$desired_cols}){
	$col =~ tr/A-Z/a-z/;
	if (not defined $fits->{$col}){
	    $match = 0;
	    last;
	}
    }

    return $match;
}



sub make_imgraw_data_fit{

    my $self = shift;

    my $arg_in = shift;
    my $col = $arg_in->{column};
    my $template = $arg_in->{template};
    my $tempdata = $arg_in->{tempdata};

    my @imgraw_dim = $template->{$col}->dims;
    my $longest_dim = longest_dim($template->{$col});
    $dimarray[$longest_dim] = $tempdata->{'time'}->getdim(0);

    my $temp_zero = zeroes( @dimarray );
    if ( defined $telem{$col} ){
	my $temp = $telem{$col}->glue( $longest_dim, $temp_zero);
	$telem{$col} = $temp;
	my $temp_valid = $telem{"${col}_valid"}->append( zeroes( $tempdata->{'time'}->getdim(0)));
	$telem{"${col}_valid"} = $temp_valid;
    }
    else{
	$telem{$col} = $temp_zero;
	$telem{"${col}_valid"} = zeroes( $tempdata->{'time'}->getdim(0) );
    }

    if ( not defined $telem{$col}){
	$telem{$col} = $temp_fits{$col};
	$telem{"${col}_valid"} = ones( $temp_fits{$col}->getdim(longest_dim($temp_fits{$col})) );
    }
    else{
	# else, if we have real data, append it
	if (UNIVERSAL::isa($template_hash{$col}, 'PDL')){
	    my $temp = $telem{$col}->glue( longest_dim($temp_fits{$col}), $temp_fits{$col});
	    $telem{$col} = $temp;			
	    my $temp_valid = $telem{"${col}_valid"}->append( ones( $temp_fits{$col}->getdim( longest_dim($temp_fits{$col}))));
	    $telem{"${col}_valid"} = $temp_valid;
	    
	}
	else{
	    if ( ref($template_hash{$col}) eq 'ARRAY'){
		my $temp_valid = $telem{"${col}_valid"}->append( ones( scalar(@{$template_hash{$col}})));
		$telem{"${col}_valid"} = $temp_valid;
		push @{$telem{$col}}, @{$temp_fits{$col}};
	    }
	}
    }
    }
}

sub make_up_data{
    my $self = shift;
    my $arg_in = shift;
    my $col = $arg_in->{column};
    my $template_href = $arg_in->{template};
    my $temp_fits_href = $arg_in->{tempdata};
    my $telem_href = $self->telem();
    my @dimarray = $template_href->{$col}->dims;
    my $longest_dim = longest_dim($template_href->{$col});
    $dimarray[$longest_dim] = $temp_fits_href->{'time'}->getdim(0);
    my $temp_zero = zeroes( @dimarray );
    if ( defined $telem_href->{$col} ){
	my $temp = $telem_href->{$col}->glue( $longest_dim, $temp_zero);
	$telem_href->{$col} = $temp;
	my $temp_valid = $telem_href->{"${col}_valid"}->append( zeroes( $temp_fits_href->{'time'}->getdim(0)));
	$telem_href->{"${col}_valid"} = $temp_valid;
    }
    else{
	$telem_href->{$col} = $temp_zero;
	$telem_href->{"${col}_valid"} = zeroes( $temp_fits_href->{'time'}->getdim(0) );
    }
}


sub match_dim{

    my $template = shift;
    my $test = shift;

    if ($template->ndims != $test->ndims){
	return 0;
    }

    my $longest_dim = longest_dim( $template );
    my @template_dims = $template->dims;
    my @test_dims = $test->dims;
    $test_dims[$longest_dim] = $template->getdim($longest_dim);
    for my $i ( 0 .. ($template->ndims) - 1 ){
	if ( $template_dims[$i] != $test_dims[$i]){
	    return 0;
	}
    }
    return 1;
}


sub longest_dim{
    
    my $pdl = shift;
    my @dimlist;
    for my $dim (0 ... $pdl->getndims()-1){
	push @dimlist, $pdl->getdim($dim);
    }
    my $dimpdl = pdl( @dimlist );
    my $dim_index = which( $dimpdl == $dimpdl->max());
    my $longest_dim = $dim_index->at(0);

    return $longest_dim;
}



1;

package Telemetry::Interval::ACA0;

use strict; 
use warnings;
use Carp;

use base 'Telemetry::Interval';

our ISA =  qw( Telemetry::Interval );
1;



