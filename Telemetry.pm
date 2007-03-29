package Telemetry::BinTable::Header;

use strict;
use warnings;

sub new{
    
    my $class = shift;
    my $self = shift;
    bless $self, $class;
    return $self;

}

1;

package Telemetry::BinTable::Table;

use strict;
use warnings;

sub new{

    my $class = shift;
    my $self = shift;
    bless $self, $class;
    return $self;

}
   
1;

package Telemetry::BinTable;
# class to store the header of a fits file and 
# to read and store the binary table

use strict;
use warnings;
use Carp;
use Class::MakeMethods::Standard::Hash( 
					scalar => [ qw(
						       file
						       columns
						       order
						       header
						       hdrtable
						       bintable
						       )
						    ],
					);
use CFITSIO::Simple;

sub new{
    my $class = shift;
    my $self = {};
    bless $self, $class;
    my $arg_in = shift;
    if ( defined $arg_in->{file} ){
	$self->file($arg_in->{file});
    }
    if ( defined $arg_in->{columns}){
	$self->columns($arg_in->{columns});
    }
    return $self;
}

sub length{
    my $self = shift;
    my $value = shift;
    if (defined $value){
	$self->{length} = $value;
    }

    if (defined $self->{length}){
	return $self->{length};
    }
    else{
	$self->process();
	return $self->{length};
    }

}

sub print{
    my $self = shift;
    $self->process();
    my %table = %{$self->table()};
    for my $keyword ( @{$self->order()} ){
	my $data = $table{$keyword};
	print $data->{order}, "\t";
	print $keyword, "\t";
	if (defined $data->{UNIT}){
	    print $data->{UNIT};
	}
	print "\t";
	if (defined $data->{FORM}){
	    print $data->{FORM}
	}
	if (defined $data->{DIM}){
	    print "(", $data->{DIM}, ")";
	}
	print "\t";
	if ((defined $data->{LMIN}) and (defined $data->{LMAX})){
	    print $data->{LMIN}, ":", $data->{LMAX};
	}
	print "\t";
	if (defined $data->{comment}){
	    print $data->{comment};
	}
	print "\n";
    }
}

sub process{
    my $self = shift;
    unless (defined $self->file() ){
	croak(__PACKAGE__ . "Telemetry file must be defined");
    }
    my $hdr = fits_read_hdr( $self->file, 2);
    $self->header($hdr);
    my @columns;
    if (defined $self->columns()){
	@columns = @{$self->{columns}};
    }
    my %fits = fits_read_bintbl( $self->file, @columns );
    my $table = Telemetry::BinTable::Table->new(\%fits);
    $self->bintable($table);
    $self->length( $fits{time}->nelem );
    my @order;
    my %data;
    # possible columns 1 - 9999
    for my $i (1 ... 9999){
	my $keyword = $hdr->{"TTYPE$i"};
	if (defined $keyword){
	    # strip off trailing spaces
	    $keyword =~ s/\s+$//;
	    #lowercase everything
	    $keyword =~ tr/A-Z/a-z/;
	    push @order, $keyword;
	    my %keyvals;
	    $keyvals{order} = $i;
#	    print Dumper $hdr->{"COMMENTS"};
	    if (defined $hdr->{"COMMENTS"}->{"TTYPE$i"}){
		my $comment = $hdr->{"COMMENTS"}->{"TTYPE$i"};
		$comment =~ s/\s+$//;
		$keyvals{comment} = $comment;
	    }
	    for my $hdrkey qw( UNIT LMAX LMIN FORM DIM ){
		if (defined $hdr->{"T${hdrkey}${i}"}){
		    my $infokey =  $hdr->{"T${hdrkey}${i}"};
		    #strip off trailing spaces
		    $infokey =~ s/\s+$//;
		    #lowercase everything
		    my $lowerhdrkey = $hdrkey;
		    $lowerhdrkey =~ tr/A-Z/a-z/;
		    $keyvals{$lowerhdrkey} = $infokey;
		}
	    }

	    $data{$keyword} = \%keyvals;	    
	}
	else{
	    last;
	}
	
    }
    my $newheader = Telemetry::BinTable::Header->new(\%data);
    $self->hdrtable($newheader);
    $self->order(\@order);
}

1;


package Telemetry::BinTable::ACA0;

use strict;
use warnings;

use base 'Telemetry::BinTable';

use PDL;
use PDL::NiceSlice;

our @ISA =  qw( Telemetry::BinTable );

# Set some global vars with directory locations

#use Grabenv qw( grabenv );

my $SKA = $ENV{SKA} || '/proj/sot/ska';
my $template_file = "${SKA}/data/perigee_health_plots/aca8x8.fits.gz";

sub define_template{

    my $new_template = shift;
    if( -e $new_template ){
	$template_file = $new_template;
    }
    else{
	croak(__PACKAGE__ . ": Template file $new_template does not exist");
    }
}

sub process{
    my $self = shift;
    $self->Telemetry::BinTable::process();
    # Convert any image data to 8x8 PDL
    my $imgraw = $self->bintable->{imgraw};
    my $templateraw = zeroes( 8, 8, $self->length);
    my $dim = $imgraw->getdim(0);
    $templateraw(0:($dim-1), 0:($dim-1), :) .= $imgraw;
    $self->bintable->{imgraw} = $templateraw;
    # Add any columns that would only exist in the 8x8 data
    my $template = Telemetry::BinTable->new({ file => $template_file });
    $template->process();
    for my $key ( keys %{$template->bintable} ){
	next if ( defined $self->bintable->{$key} );
	my $tempdata = zeroes( $self->length );
	$self->bintable->{$key} = $tempdata;
    }
    $self->bintable->{imgdim} = zeroes( $self->length ) + $dim;
    my @columns = keys %{$template->bintable};
    $self->columns(\@columns);

}    


1;





package Telemetry::Interval;

use base 'Telemetry::BinTable';

use strict;
use warnings;
use Carp;
use PDL;

use Class::MakeMethods::Standard::Hash (
					scalar => [ qw(
						       file_list
						       telem
						       telemtype
						       columns
						       )
						    ],
					);
						       

sub new{

    my $class = shift;
    my $self = {};

    bless $self, $class;
    my $arg_in = shift;

    if (defined $arg_in->{file_list}){
	$self->file_list($arg_in->{file_list});
    }
    if (defined $arg_in->{telemtype}){
	$self->telemtype($arg_in->{telemtype});
    }
    if (defined $arg_in->{columns}){
	$self->columns($arg_in->{columns});
    }

    return $self;
}



sub combine_telem{

    my $self = shift;

    unless ( defined $self->file_list()){
	croak(__PACKAGE__ . "No telemetry files specified.");
    }	     

    unless ( ( defined $self->telemtype() ) or ( defined $self->columns() ) ){
	croak(__PACKAGE__ . "Must specify type of telemetry or list of columns.");
    }

    my $file_list = $self->file_list();

    my %telem;

    
    for my $file (@{$self->file_list()}){
	my $telem_chunk; 
	if (defined $self->telemtype()){
	    if ($self->telemtype() eq 'aca0'){
		$telem_chunk = Telemetry::BinTable::ACA0->new({ file => $file, columns => $self->columns() });
		$telem_chunk->process();
	    }
	}
	else{
	    $telem_chunk = Telemetry::BinTable->new({ file => $file, columns => $self->columns() });
	    $telem_chunk->process();
	}

	my @columns;
	if ( defined $self->columns() ){
	    @columns = @{$self->columns()};
	}
	else{
	    if (scalar(keys %telem) > 0){
		@columns = keys %telem;
	    }
	    else{
		@columns = keys %{$telem_chunk->bintable()};
	    }
	}

	for my $col ( @columns ){
	    if ( not defined $telem{$col} ){
		$telem{$col} = $telem_chunk->bintable->{$col};
	    }
	    else{
		# if we have data, append it
		if (UNIVERSAL::isa( $telem{$col}, 'PDL' )){
		    my $time_dim = time_dim( $telem_chunk->bintable->{$col}, $telem_chunk->length() );
		    my $temp = $telem{$col}->glue( $time_dim, $telem_chunk->bintable->{$col} );
		    $telem{$col} = $temp;
		}
		else{
		    if ( ref($telem{$col}) eq 'ARRAY' ){
			push @{$telem{$col}}, @{$telem_chunk->bintable->{$col}};
		    }
		    else{
			croak(__PACKAGE__ . " Unexpected data type when trying to append data for $col ");
		    }
		}
	    }
	}


    }

    my $telem = Telemetry::BinTable::Table->new(\%telem);
    $self->telem($telem);
    return $self;
}




sub time_dim{
    
    my $pdl = shift;
    my $length = shift;
    
    my @dimlist;
    for my $dim (0 ... $pdl->getndims()-1){
	push @dimlist, $pdl->getdim($dim);
    }

    my $dimpdl = pdl( @dimlist );
    my $dim_index = which( $dimpdl == $length );
    my @dim_index_list = $dim_index->list;
    my $time_dim = $dim_index_list[-1];

    return $time_dim;
}

1;



package Telemetry::Interval::ACA0;

use strict; 
use warnings;
use Carp;
use Data::Dumper;
use base 'Telemetry::Interval';

our @ISA =  qw( Telemetry::Interval );

sub new{
    my $class = shift;
    my $arg_in = shift;

    $arg_in->{telemtype} = 'aca0';

    my $self = Telemetry::Interval->new($arg_in);
    bless $self, $class;
    return $self;

}



1;



