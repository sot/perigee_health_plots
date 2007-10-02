package Ska::Perigee::Pass;

use strict;
use warnings;

use Ska::Perigee::DataObject;

use base 'Ska::Perigee::DataObject';

our @ISA = qw( Ska::Perigee::DataObject );

use PDL;

use Ska::Perigee::Data;


sub new{
    my $class = shift;
    my $arg_in = shift;

    my $self = Ska::Perigee::DataObject->new($arg_in);
    bless $self, $class;
    return $self;

}

sub plot{

    my $self = shift;
    my %config = %{$self->config()};
    my @passlist = @{$self->passlist()};
    my %opt = %{$self->opt()};
    my @todo_directories = @passlist;
    

    if ($opt{verbose}){
        if (scalar(@todo_directories)){
            print "Plotting health for:\n";
            for my $dir (@todo_directories){
                print "\t${dir}\n";
            }
        }
        else{
            print "Health plots up to date\n";
        }
    }
    eval{
        $self->plot_health( \@todo_directories, \%config, \%opt );
    };
    if ($@){
        print __PACKAGE__ . "::plot_health croaked with:\n $@ \n";
    }
    
}



1;
