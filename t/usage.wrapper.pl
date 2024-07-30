#!/usr/bin/env perl
use v5.16;
use warnings;

use File::Basename        qw( dirname );
use File::Spec::Functions qw( catfile );
use Zonemaster::CLI;
use Zonemaster::Engine::Nameserver;
use Zonemaster::Engine::Profile;

use lib catfile( dirname( dirname( __FILE__ ) ), 'script' );

# Parse command line options upto and including '--'.

my $opt_record = 0;
my $opt_datafile;
while ( @ARGV ) {
    my $arg = shift @ARGV;
    if ( substr( $arg, 0, 2 ) eq '--' ) {
        if ( $arg eq '--' ) {
            last;
        }
        elsif ( $arg eq '--record' ) {
            $opt_record = 1;
        }
        else {
            die "unrecognized option '$arg'";
        }
    }
    else {
        if ( defined $opt_datafile ) {
            die "too many data files provided";
        }
        $opt_datafile = $arg;
    }
} ## end while ( @ARGV )

if ( $opt_record && !defined $opt_datafile ) {
    die "must not specify --record without also specifying a data file";
}

# Prime Zonemaster Engine before letting zonemaster-cli do its thing

if ( !$opt_record ) {
    Zonemaster::Engine::Profile->effective->set( q{no_network}, 1 );
}

if ( $opt_datafile ) {
    Zonemaster::Engine::Nameserver->restore( $opt_datafile );
}

our $EXIT_STATUS;
our $EMITTED_WARNING = 0;
do {
    # Intercept warn()
    local $SIG{__WARN__} = sub {
        print STDERR "__WARN__: " . $_[0];
        $EMITTED_WARNING = 1;
    };

    # Run Zonemaster::CLI
    eval {
        $EXIT_STATUS = Zonemaster::CLI->new_with_options->run;
        1;
    } or do {
        print STDERR $@;
        $EXIT_STATUS = $Zonemaster::CLI::EXIT_GENERIC_ERROR;
    };
};

# Wrap up and terminate

if ( $opt_record ) {
    Zonemaster::Engine::Nameserver->save( $opt_datafile );
}

if ( $EMITTED_WARNING ) {
    say STDERR "EXIT 125: one or more warnings were emitted";
    exit 125;
}

exit $EXIT_STATUS;
