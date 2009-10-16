#!/usr/bin/env perl

use strict; 
use warnings;
use Cwd;
use Getopt::Long;
use Pod::Help qw( --help );
use Carp;
use Chandra::Time;
use Ska::Run qw( run );


my %opt = ();

eval { main () };
if ( $@ ) {
    print STDERR "# $0: $_\n" foreach split /\n/, $@;
    exit 1;
};
exit 0;


sub main{


    GetOptions (\%opt,
		'tstart=s',
		'tstop=s',
		'dir=s',
		'verbose!',
	);
    

    my $tstart = Chandra::Time->new($opt{tstart})->secs() 
	or croak("Must define time --tstart");
    my $tstop = Chandra::Time->new($opt{tstop})->secs() 
	or croak("Must define time --tstop");
    my $dir = $opt{dir} 
        or croak("Must define destination --dir");

    my %telems = ( 'ccdm0{ccdm10eng}' => 'ccdm*10_eng0.fits*',
		   'aca0{acaimg}' => 'acaf*_img0.fits*' );

    for my $telem_type (keys %telems){
	my $glob = $telems{$telem_type};
	my $files = list_archive_files( $tstart, $tstop, $telem_type ); 
	my $have_files = check_for_files( $dir, $files );
	unless ($have_files){
	    fetch_archive_files( $dir, $tstart, $tstop, $telem_type, $glob );
	    $have_files = check_for_files( $dir, $files );
	}
	unless ($have_files){
	    croak("unable to retrieve $telem_type files") 
	}

    }


}


sub check_for_files{
    
    my ($dir, $files ) = @_;
    
    my $have_files = 1;
    for my $file (@{$files}){
	print "checking ${dir}/${file}" if $opt{verbose};
	if (-e "${dir}/${file}"){
	    print " ... found \n" if $opt{verbose};
	    next;
	}
	else{
	    print " ... missing \n" if $opt{verbose};
	    $have_files = 0;
	    last;
	}
    }
    return $have_files;
}


sub list_archive_files{
    my ($tstart, $tstop, $product) = @_;

    my $browse = <<BROWSE;
tstart=$tstart
tstop=$tstop
browse $product

BROWSE

    my ($status, @lines) = 
       run("echo \"$browse\" | /proj/sot/ska/bin/arc5gl -guestuser -stdin ",
       timeout => 60);

    my @files;
    my $matching = 0;
    for my $line (@lines){
	chomp $line;
	if ($line =~ /.*Filename.*/){
	    $matching = 1;
	    next;
	}
	if (($matching) and  ($line =~ /(\w*\.fits(\.gz)?).*/)){
	    push @files, $1;
	}
    }
    return \@files;
}

sub fetch_archive_files{
    my ($dir, $tstart, $tstop, $product, $glob) = @_;

    my $CWD = cwd;

    my $get = <<GET;
loud
tstart=$tstart
tstop=$tstop
cd $dir
get $product
cd $CWD
GET

    my ($status, @lines) = 
        run("echo \"$get\" | /proj/sot/ska/bin/arc5gl -guestuser -stdin ",
	timeout => 300);

    
    my @gzfiles = glob("${dir}/${glob}*.gz");
    map { run("gunzip $_")} @gzfiles;

    return 0;

}


=pod

=head1 NAME

get_perigee_telem.pl - Retrieve the aca0 and ccdm0 telemetry used by the camera 
health plotting system.

=head1 SYNOPSIS

get_perigee_telem.pl --tstart <tstart> --tstop <tstop> --dir <dir>

=head1 OPTIONS

=over 12

=item B<--tstart>

Beginning of time range for arc5gl retrieval of telemetry

=item B<--tstop>

End of time range for arc5gl retrieval of telemetry

=item B<--dir>

Directory in which to store retrieved telemetry

=item B<--verbose>

Be verbose about file checks and fetching

=back

=head1 DESCRIPTION

The camera health plots require 8x8 image telemetry (which is mostly found during perigee
passes).  This script accepts options for a perigee pass time range (or just an ER time range), 
checks to see if the desired telemetry files (ccdm0 and aca0) already exist in the directory
specified with the --dir option, and retrieves any needed files.

=head1 EXAMPLES

get_perigee_telem.pl --tstart 2009:273:09:44:30.137 \
    --tstop 2009:273:10:34:33.387 \
    --dir "2009:273:09:44:30.137"

=head1 AUTHOR

Jean Connelly, E<lt>jeanconn@localdomain<gt>

=head1 COPYRIGHT & LICENSE

Copyright (C) 2009 by Smithsonian Astropysical Observatory

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.0 or,
at your option, any later version of Perl 5 you may have available.

=cut
