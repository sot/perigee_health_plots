#!/usr/bin/env /proj/sot/ska/bin/perl

use strict;
use warnings;

use Getopt::Long;

use Carp;
use PDL;
use PDL::NiceSlice;
use YAML;


use Ska::Convert qw( date2time );
use IO::All;

use Hash::Merge qw( merge );



my %opt = ();

#our %opt = ();

GetOptions (\%opt,
            'help!',
	    'shared_config=s',
	    'config=s',
            'dir=s',
	    'missing!',
	    'verbose|v!',
	    'delete!'
	    );

usage( 1 )
    if $opt{help};

#use Data::Dumper;
#print Dumper %opt;

# Set some global vars with directory locations
my $SKA = $ENV{SKA} || '/proj/sot/ska';
my $TASK = 'perigee_health_plots';
my $SHARE = "$ENV{SKA}/share/${TASK}";

my %share_config;
if ( defined $opt{shared_config}){
    %share_config = YAML::LoadFile( $opt{shared_config} );
}
else{
    %share_config = YAML::LoadFile( "${SHARE}/shared.yaml" );
}


my %task_config;
if ( defined $opt{config} ){
    %task_config = YAML::LoadFile( $opt{config} );
}
else{
    %task_config = YAML::LoadFile( "${SHARE}/check_telem.yaml");
}

# combine config
Hash::Merge::set_behavior( 'RIGHT_PRECEDENT' );

my %config = %{ merge( \%share_config, \%task_config )};
#print Dumper %config;

my $WORKING_DIR = $ENV{PWD};
if ( defined $opt{dir} or defined $config{general}->{pass_dir} ){

    if (defined $opt{dir}){
        $WORKING_DIR = $opt{dir};
    }
    else{
        $WORKING_DIR = $config{general}->{pass_dir};
    }

}

#print Dumper $WORKING_DIR;

my $data_file = $config{general}->{data_file};
my $out_file = $config{task}->{result};
#if (defined $config{xml_out_file}){
#    $xml_out_file = $config{xml_out_file};
#}
#else{
#    $xml_out_file = "data.xml.gz";
#}

# Search for directories in $WORKING_DIR that have telemetry but don't have 
# $xml_out_file

my @todo_directories;

# first get a list of directories.
my @telem_dirs = glob("${WORKING_DIR}/????:*");
#print Dumper @telem_dirs;

# step backward through them until I find one that has an $xml_out_file
for my $dir ( @telem_dirs ){
    if ( -e "${dir}/$out_file" ){
	print "weird\n";
	last unless $opt{missing};
    }
    else{
	push @todo_directories, $dir;
    }
}

#use Data::Dumper;
#print Dumper @todo_directories;


for my $dir (@todo_directories){
    if ($opt{verbose}){
	print "parsing telemetry for $dir \n";
    }
    my $result = telem_check({ dir => $dir,
			       data_file => $data_file,
			       config => $config{task},
			   });

#    my $yaml_out = io("${dir}/$out_file");
#    $yaml_out->print(Dump($result));

#    chmod 0775, "${dir}/$out_file";

    if ( -e "${dir}/$out_file" ){
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
sub telem_check{
##***************************************************************************

    my $args = shift;

#    use Data::Dumper;
#    print Dumper $args;

    my $DIR = $args->{dir};
    my $data_file = $args->{data_file};
    my $task_config = $args->{config};

    my $parsed_data = YAML::LoadFile("${DIR}/${data_file}");

    if ( defined $parsed_data->{info}->{bad_points}){
	print "Bad points \n";
#	print Dumper $parsed_data->{info};
	for my $type (keys %{$parsed_data->{info}->{bad_points}}){
	    my $pdl = pdl($parsed_data->{telem}->{$type});
	    my $points = pdl( @{$parsed_data->{info}->{bad_points}->{$type}});
	    print "$type :\n";
	    print $pdl->($points);
	    print "\n";
	    
	}
    }

    for my $threshold (keys %{$task_config->{telem_threshold}}){
	my $pdl = pdl($parsed_data->{telem}->{$threshold});
	my ($mean,$rms,$median,$min,$max) = $pdl->stats;
#	print "thresh is " . $task_config->{telem_threshold}->{$threshold} . "\n";
	if ( $max >= $task_config->{telem_threshold}->{$threshold}){
	    print "whoa doggies, $threshold is $max \n";
	}
    }
    my $result = 1;
    return $result;


}





