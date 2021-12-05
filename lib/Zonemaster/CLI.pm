# Brief help module to define the exception we use for early exits.
package Zonemaster::Engine::Exception::NormalExit;
use Moose;
extends 'Zonemaster::Engine::Exception';

# The actual interesting module.
package Zonemaster::CLI;

use 5.014002;

use strict;
use warnings;

use version; our $VERSION = version->declare( "v3.1.1" );

use Locale::TextDomain 'Zonemaster-CLI';
use Moose;
with 'MooseX::Getopt::GLD' => { getopt_conf => [ 'pass_through' ] };

use Zonemaster::Engine;
use Zonemaster::Engine::Logger::Entry;
use Zonemaster::Engine::Translator;
use Zonemaster::Engine::Util qw[pod_extract_for];
use Zonemaster::Engine::Exception;
use Zonemaster::Engine::Zone;
use Zonemaster::Engine::Net::IP;
use Scalar::Util qw[blessed];
use Encode;
use Zonemaster::LDNS;
use POSIX qw[setlocale LC_MESSAGES LC_CTYPE];
use List::Util qw[max];
use Text::Reflow qw[reflow_string];
use JSON::XS;
use File::Slurp;
use Socket qw[AF_INET AF_INET6];

our %numeric = Zonemaster::Engine::Logger::Entry->levels;
our $JSON    = JSON::XS->new->allow_blessed->convert_blessed->canonical;

STDOUT->autoflush( 1 );

has 'version' => (
    is            => 'ro',
    isa           => 'Bool',
    default       => 0,
    required      => 0,
    documentation => __( 'Print version information and exit.' ),
);

has 'level' => (
    is            => 'ro',
    isa           => 'Str',
    required      => 0,
    default       => 'NOTICE',
    initializer   => sub {
        my ( $self, $value, $set, $attr ) = @_;
        $set->( uc $value );
    },
    documentation =>
      __( 'The minimum severity level to display. Must be one of CRITICAL, ERROR, WARNING, NOTICE, INFO or DEBUG.' ),
);

has 'locale' => (
    is            => 'ro',
    isa           => 'Str',
    required      => 0,
    documentation => __( 'The locale to use for messages translation.' ),
);

has 'json' => (
    is            => 'ro',
    isa           => 'Bool',
    default       => 0,
    documentation => __( 'Flag indicating if output should be in JSON or not.' ),
);

has 'json_stream' => (
    traits        => [ 'Getopt' ],
    is            => 'ro',
    isa           => 'Bool',
    default       => 0,
    cmd_aliases   => 'json_stream',
    cmd_flag      => 'json-stream',
    documentation => __( 'Flag indicating if output should be streaming JSON or not.' ),
);

has 'json_translate' => (
    traits        => [ 'Getopt' ],
    is            => 'ro',
    isa           => 'Bool',
    default       => 0,
    cmd_aliases   => 'json_translate',
    cmd_flag      => 'json-translate',
    documentation => __( 'Flag indicating if streaming JSON output should include the translated message of the tag or not.' ),
);

has 'raw' => (
    is            => 'ro',
    isa           => 'Bool',
    default       => 0,
    documentation => __( 'Flag indicating if output should be translated to human language or dumped raw.' ),
);

has 'time' => (
    is            => 'ro',
    isa           => 'Bool',
    documentation => __( 'Print timestamp on entries.' ),
    default       => 1,
);

has 'show_level' => (
    traits        => [ 'Getopt' ],
    is            => 'ro',
    isa           => 'Bool',
    cmd_aliases   => 'show_level',
    cmd_flag      => 'show-level',
    documentation => __( 'Print level on entries.' ),
    default       => 1,
);

has 'show_module' => (
    traits        => [ 'Getopt' ],
    is            => 'ro',
    isa           => 'Bool',
    cmd_aliases   => 'show_module',
    cmd_flag      => 'show-module',
    documentation => __( 'Print the name of the module on entries.' ),
    default       => 0,
);

has 'show_testcase' => (
    traits        => [ 'Getopt' ],
    is            => 'ro',
    isa           => 'Bool',
    cmd_aliases   => 'show_testcase',
    cmd_flag      => 'show-testcase',
    documentation => __( 'Print the name of the test case on entries.' ),
    default       => 0,
);

has 'ns' => (
    is            => 'ro',
    isa           => 'ArrayRef',
    documentation => __( 'A name/ip string giving a nameserver for undelegated tests, or just a name which will be looked up for IP addresses. Can be given multiple times.' ),
);

has 'save' => (
    is            => 'ro',
    isa           => 'Str',
    required      => 0,
    documentation => __( 'Name of a file to save DNS data to after running tests.' ),
);

has 'restore' => (
    is            => 'ro',
    isa           => 'Str',
    required      => 0,
    documentation => __( 'Name of a file to restore DNS data from before running test.' ),
);

has 'ipv4' => (
    is            => 'ro',
    isa           => 'Bool',
    documentation =>
      __( 'Flag to permit or deny queries being sent via IPv4. --ipv4 permits IPv4 traffic, --no-ipv4 forbids it.' ),
);

has 'ipv6' => (
    is            => 'ro',
    isa           => 'Bool',
    documentation =>
      __( 'Flag to permit or deny queries being sent via IPv6. --ipv6 permits IPv6 traffic, --no-ipv6 forbids it.' ),
);

has 'list_tests' => (
    traits        => [ 'Getopt' ],
    is            => 'ro',
    isa           => 'Bool',
    default       => 0,
    cmd_aliases   => 'list_tests',
    cmd_flag      => 'list-tests',
    documentation => __( 'Instead of running a test, list all available tests.' ),
);

has 'test' => (
    is            => 'ro',
    isa           => 'ArrayRef',
    required      => 0,
    documentation => __(
'Specify test to run. Should be either the name of a module, or the name of a module and the name of a method in that module separated by a "/" character (Example: "Basic/basic1"). The method specified must be one that takes a zone object as its single argument. This switch can be repeated.'
    )
);

has 'stop_level' => (
    traits        => [ 'Getopt' ],
    is            => 'ro',
    isa           => 'Str',
    required      => 0,
    initializer   => sub {
        my ( $self, $value, $set, $attr ) = @_;
        $set->( uc $value );
    },
    cmd_aliases   => 'stop_level',
    cmd_flag      => 'stop-level',
    documentation => __(
'As soon as a message at this level or higher is logged, execution will stop. Must be one of CRITICAL, ERROR, WARNING, NOTICE, INFO or DEBUG.'
    )
);

has 'profile' => (
    is            => 'ro',
    isa           => 'Str',
    required      => 0,
    documentation => __( 'Name of profile file to load. (DEFAULT)' ),
);

has 'ds' => (
    is            => 'ro',
    isa           => 'ArrayRef[Str]',
    required      => 0,
    documentation => __( 'Strings with DS data on the form "keytag,algorithm,type,digest"' ),
);

has 'count' => (
    is            => 'ro',
    isa           => 'Bool',
    required      => 0,
    documentation => __( 'Print a count of the number of messages at each level' ),
);

has 'progress' => (
    is            => 'ro',
    isa           => 'Bool',
    default       => !!( -t STDOUT ),
    documentation => __( 'Boolean flag for activity indicator. Defaults to on if STDOUT is a tty, off if it is not. Disable with --no-progress.' ),
);

has 'encoding' => (
    is            => 'ro',
    isa           => 'Str',
    default       => sub {
        my $locale = $ENV{LC_CTYPE} // 'C';
        my ( $e ) = $locale =~ m|\.(.*)$|;
        $e //= 'UTF-8';
        return $e;
    },
    documentation => __( 'Name of the character encoding used for command line arguments' ),
);

has 'nstimes' => (
    is            => 'ro',
    isa           => 'Bool',
    required      => 0,
    default       => 0,
    documentation => __('At the end of a run, print a summary of the times the zone\'s name servers took to answer.'),
);

has 'dump_profile' => (
    traits        => [ 'Getopt' ],
    is            => 'ro',
    isa           => 'Bool',
    required      => 0,
    default       => 0,
    cmd_aliases   => 'dump_profile',
    cmd_flag      => 'dump-profile',
    documentation => __( 'Print the effective profile used in JSON format, then exit.' ),
);

has 'sourceaddr' => (
    is            => 'ro',
    isa           => 'Str',
    required      => 0,
    documentation => __(
            'Source IP address used to send queries. '
          . 'Setting an IP address not correctly configured on a local network interface causes cryptic error messages.'
    ),
);

has 'elapsed' => (
    is            => 'ro',
    isa           => 'Bool',
    required      => 0,
    default       => 0,
    documentation => 'Print elapsed time at end of run.',
);

sub run {
    my ( $self ) = @_;
    my @accumulator;
    my %counter;
    my $printed_something;

    if ( grep /^-/, @{ $self->extra_argv } ) {
        print "Unknown option: ", join( q{ }, grep /^-/, @{ $self->extra_argv } ), "\n";
        print "Run \"zonemaster-cli -h\" to get the valid options\n";
        exit;
    }

    if ( $self->locale ) {
        undef $ENV{LANGUAGE};
        $ENV{LC_ALL} = $self->locale;
    }

    # Set LC_MESSAGES and LC_CTYPE separately (https://www.gnu.org/software/gettext/manual/html_node/Triggering.html#Triggering)
    if ( not defined setlocale( LC_MESSAGES, "" ) ) {
        printf STDERR __( "Warning: setting locale category LC_MESSAGES to %s failed (is it installed on this system?).\n\n" ),
        $ENV{LANGUAGE} || $ENV{LC_ALL} || $ENV{LC_MESSAGES};
    }
    if ( not defined setlocale( LC_CTYPE, "" ) ) {
        printf STDERR __( "Warning: setting locale category LC_CTYPE to %s failed (is it installed on this system?).\n\n" ),
        $ENV{LC_ALL} || $ENV{LC_CTYPE};
    }

    if ( $self->version ) {
        print_versions();
        exit;
    }

    if ( $self->list_tests ) {
        print_test_list();
    }

    if ($self->sourceaddr) {

        Zonemaster::Engine::Profile->effective->set( q{resolver.source}, $self->sourceaddr );
    }

    # Filehandle for diagnostics output
    my $fh_diag = ( $self->json or $self->json_stream or $self->raw )
      ? *STDERR     # Structured output mode (e.g. JSON)
      : *STDOUT;    # Human readable output mode

    if ( $self->profile ) {
        say $fh_diag __x( "Loading profile from {path}.", path => $self->profile );
        my $json    = read_file( $self->profile );
        my $foo     = Zonemaster::Engine::Profile->from_json( $json );
        my $profile = Zonemaster::Engine::Profile->default;
        $profile->merge( $foo );
        Zonemaster::Engine::Profile->effective->merge( $profile );
    }

    # These two must come after any profile from command line has been loaded
    # to make any IPv4/IPv6 option override the profile setting.
    if ( defined ($self->ipv4) ) {
        Zonemaster::Engine::Profile->effective->set( q{net.ipv4}, 0+$self->ipv4 );
    }
    if ( defined ($self->ipv6) ) {
        Zonemaster::Engine::Profile->effective->set( q{net.ipv6}, 0+$self->ipv6 );
    }


    if ( $self->dump_profile ) {
        do_dump_profile();
    }

    if ( $self->stop_level and not defined( $numeric{ $self->stop_level } ) ) {
        die __( "Failed to recognize stop level '" ) . $self->stop_level . "'.\n";
    }

    if ( not defined $numeric{ $self->level } ) {
        die __( "--level must be one of CRITICAL, ERROR, WARNING, NOTICE, INFO, DEBUG, DEBUG2 or DEBUG3.\n" );
    }

    my $translator;
    $translator = Zonemaster::Engine::Translator->new unless ( $self->raw or $self->json or $self->json_stream );
    $translator->locale( $self->locale ) if $translator and $self->locale;

    my $json_translator;
    if ( $self->json_translate ) {
        $json_translator = Zonemaster::Engine::Translator->new;
        $json_translator->locale( $self->locale ) if $self->locale;
    }

    if ( $self->restore ) {
        Zonemaster::Engine->preload_cache( $self->restore );
    }

    # Callback defined here so it closes over the setup above.
    Zonemaster::Engine->logger->callback(
        sub {
            my ( $entry ) = @_;

            $self->print_spinner() if $fh_diag eq *STDOUT;

            $counter{ uc $entry->level } += 1;

            if ( $numeric{ uc $entry->level } >= $numeric{ $self->level } ) {
                $printed_something = 1;

                if ( $translator ) {
                    my $header = q{};
                    if ( $self->time ) {
                        $header .= sprintf "%7.2f ", $entry->timestamp;
                    }

                    if ( $self->show_level ) {
                        $header .= sprintf "%-9s ", translate_severity( $entry->level );
                    }

                    if ( $self->show_module ) {
                        $header .= sprintf "%-12s ", $entry->module;
                    }

                    if ( $self->show_testcase ) {
                        $header .= sprintf "%-14s ", $entry->testcase;
                    }

                    print $header;

                    if ( $entry->level eq q{DEBUG3} and scalar( keys %{$entry->args} ) == 1 and defined $entry->args->{packet} ) {
                        my $packet = $entry->args->{packet};
                        my $padding = q{ } x length $header;
                        $entry->args->{packet} = q{};
                        say $translator->translate_tag( $entry );
                        foreach my $line ( split /\n/, $packet ) {
                            print $padding, $line, "\n";
                        }
                    }
                    else {
                        say $translator->translate_tag( $entry );
                    }
                }
                elsif ( $self->json_stream ) {
                    my %r;

                    $r{timestamp} = $entry->timestamp;
                    $r{module}    = $entry->module;
                    $r{testcase}  = $entry->testcase;
                    $r{tag}       = $entry->tag;
                    $r{level}     = $entry->level;
                    $r{args}      = $entry->args if $entry->args;
                    $r{message}   = $json_translator->translate_tag( $entry ) if $json_translator;

                    say $JSON->encode( \%r );
                }
                elsif ( $self->json ) {
                    # Don't do anything
                }
                else {
                    my $prefix = sprintf "%7.2f %-9s ", $entry->timestamp, $entry->level;
                    if ( $self->show_module ) {
                        $prefix .= sprintf "%-12s ", $entry->module;
                    }
                    if ( $self->show_testcase ) {
                        $prefix .= sprintf "%-14s ", $entry->testcase;
                    }
                    $prefix .= $entry->tag;

                    my $message = $entry->string;
                    $message =~ s/^[A-Z0-9:_]+//;    # strip MODULE:TAG, they're coming in $prefix instead
                    my @lines = split /\n/, $message;

                    printf "%s%s %s\n", $prefix, ' ', shift @lines;
                    for my $line ( @lines ) {
                        printf "%s%s %s\n", $prefix, '>', $line;
                    }
                }
            } ## end if ( $numeric{ uc $entry...})
            if ( $self->stop_level and $numeric{ uc $entry->level } >= $numeric{ $self->stop_level } ) {
                die( Zonemaster::Engine::Exception::NormalExit->new( { message => "Saw message at level " . $entry->level } ) );
            }
        }
    );

    if ( $self->profile ) {
        # Separate initialization from main output in human readable output mode
        print "\n" if $fh_diag eq *STDOUT;
    }

    my ( $domain ) = @{ $self->extra_argv };
    if ( not $domain ) {
        die __( "Must give the name of a domain to test.\n" );
    }

    if ( $translator ) {
        if ( $self->time ) {
            print __( 'Seconds ' );
        }
        if ( $self->show_level ) {
            print __( 'Level     ' );
        }
        if ( $self->show_module ) {
            print __( 'Module       ' );
        }
        if ( $self->show_testcase ) {
            print __( 'Testcase       ' );
        }
        say __( 'Message' );

        if ( $self->time ) {
            print __( '======= ' );
        }
        if ( $self->show_level ) {
            print __( '========= ' );
        }
        if ( $self->show_module ) {
            print __( '============ ' );
        }
        if ( $self->show_testcase ) {
            print __( '============== ' );
        }
        say __( '=======' );
    } ## end if ( $translator )

    $domain = $self->to_idn( $domain );

    if ( $self->ns and @{ $self->ns } > 0 ) {
        $self->add_fake_delegation( $domain );
    }

    if ( $self->ds and @{ $self->ds } ) {
        $self->add_fake_ds( $domain );
    }

    # Actually run tests!
    eval {
        if ( $self->test and @{ $self->test } > 0 ) {
            foreach my $t ( @{ $self->test } ) {
                my ( $module, $method ) = split( '/', $t, 2 );
                if ( $method ) {
                    Zonemaster::Engine->test_method( $module, $method, Zonemaster::Engine->zone( $domain ) );
                }
                else {
                    Zonemaster::Engine->test_module( $module, $domain );
                }
            }
        }
        else {
            Zonemaster::Engine->test_zone( $domain );
        }
    };
    if ( $translator ) {
        if ( not $printed_something ) {
            say __( "Looks OK." );
        }
    }

    if ( $@ ) {
        my $err = $@;
        if ( blessed $err and $err->isa( "Zonemaster::Engine::Exception::NormalExit" ) ) {
            say STDERR "Exited early: " . $err->message;
        }
        else {
            die $err;    # Don't know what it is, rethrow
        }
    }

    if ( $self->count ) {
        say __( "\n\n   Level\tNumber of log entries" );
        say "   =====\t=====================";
        foreach my $level ( sort { $numeric{$b} <=> $numeric{$a} } keys %counter ) {
            printf __( "%8s\t%5d entries.\n" ), translate_severity( $level ), $counter{$level};
        }
    }

    if ( $self->nstimes ) {
        my $zone = Zonemaster::Engine->zone( $domain );
        my $max = max map { length( "$_" ) } ( @{ $zone->ns }, q{Server} );

        print "\n";
        printf "%${max}s %s\n", 'Server', ' Max (ms)      Min      Avg   Stddev   Median     Total';
        printf "%${max}s %s\n", '=' x $max, ' ======== ======== ======== ======== ======== =========';

        foreach my $ns ( @{ $zone->ns } ) {
            printf "%${max}s ", $ns->string;
            printf "%9.2f ",    1000 * $ns->max_time;
            printf "%8.2f ",    1000 * $ns->min_time;
            printf "%8.2f ",    1000 * $ns->average_time;
            printf "%8.2f ",    1000 * $ns->stddev_time;
            printf "%8.2f ",    1000 * $ns->median_time;
            printf "%9.2f\n",   1000 * $ns->sum_time;
        }
    }

    if ($self->elapsed) {
        my $last = Zonemaster::Engine->logger->entries->[-1];
        printf "Total test run time: %0.1f seconds.\n", $last->timestamp;
    }

    if ( $self->json ) {
        say Zonemaster::Engine->logger->json( $self->level );
    }

    if ( $self->save ) {
        Zonemaster::Engine->save_cache( $self->save );
    }

    return;
} ## end sub run

sub add_fake_delegation {
    my ( $self, $domain ) = @_;
    my @ns_with_no_ip;
    my %data;

    foreach my $pair ( @{ $self->ns } ) {
        my ( $name, $ip ) = split( '/', $pair, 2 );

        if ( not $name ) {
            say STDERR "--ns must have be a name or a name/ip pair.";
            exit( 1 );
        }

        if ($ip) {
            push @{ $data{ $self->to_idn( $name ) } }, $ip;
        }
        else {
            push @ns_with_no_ip, $self->to_idn($name);
        }
    }
    foreach my $ns ( @ns_with_no_ip ) {
        if ( not exists $data{ $ns } ) {
            $data{ $ns } = undef;
        }
    }

    return Zonemaster::Engine->add_fake_delegation( $domain => \%data );

}

sub add_fake_ds {
    my ( $self, $domain ) = @_;
    my @data;

    foreach my $str ( @{ $self->ds } ) {
        my ( $tag, $algo, $type, $digest ) = split( /,/, $str );
        push @data, { keytag => $tag, algorithm => $algo, type => $type, digest => $digest };
    }

    Zonemaster::Engine->add_fake_ds( $domain => \@data );

    return;
}

sub print_versions {
    say 'CLI version:    ' . __PACKAGE__->VERSION;
    say 'Engine version: ' . $Zonemaster::Engine::VERSION;
    say "\nTest module versions:";

    my %methods = Zonemaster::Engine->all_methods;
    foreach my $module ( sort keys %methods ) {
        my $mod = "Zonemaster::Engine::Test::$module";
        say "\t$module: " . $mod->version;
    }

    return;
}

my @spinner_strings = ( '  | ', '  / ', '  - ', '  \\ ' );

sub print_spinner {
    my ( $self ) = @_;

    state $counter = 0;

    printf "%s\r", $spinner_strings[ $counter++ % 4 ] if $self->progress;

    return;
}

sub to_idn {
    my ( $self, $str ) = @_;

    if ( $str =~ m/^[[:ascii:]]+$/ ) {
        return $str;
    }

    if ( Zonemaster::LDNS::has_idn() ) {
        return Zonemaster::LDNS::to_idn( decode( $self->encoding, $str ) );
    }
    else {
        say STDERR __( "Warning: Zonemaster::LDNS not compiled with libidn, cannot handle non-ASCII names correctly." );
        return $str;
    }
}

sub print_test_list {
    my %methods = Zonemaster::Engine->all_methods;
    my $maxlen  = max map {
        map { length( $_ ) }
          @$_
    } values %methods;

    foreach my $module ( sort keys %methods ) {
        say $module;
        my $doc = pod_extract_for( $module );
        foreach my $method ( sort @{ $methods{$module} } ) {
            printf "  %${maxlen}s ", $method;
            if ( $doc and $doc->{$method} ) {
                print reflow_string(
                    $doc->{$method},
                    optimum => 65,
                    maximum => 75,
                    indent1 => '   ',
                    indent2 => ( ' ' x ( $maxlen + 6 ) )
                );
            }
            print "\n";
        }
        print "\n";
    }
    exit( 0 );
} ## end sub print_test_list

sub do_dump_profile {
    my $json = JSON::XS->new->canonical->pretty;
    
    print $json->encode( Zonemaster::Engine::Profile->effective->{ q{profile} } );

    exit;
}

sub translate_severity {
    my $severity = shift;
    if ( $severity eq "DEBUG" ) {
        return __( "DEBUG" );
    }
    elsif ( $severity eq "INFO" ) {
        return __( "INFO" );
    }
    elsif ( $severity eq "NOTICE" ) {
        return __( "NOTICE" );
    }
    elsif ( $severity eq "WARNING" ) {
        return __( "WARNING" );
    }
    elsif ( $severity eq "ERROR" ) {
        return __( "ERROR" );
    }
    elsif ( $severity eq "CRITICAL" ) {
        return __( "CRITICAL" );
    }
    else {
        return $severity;
    }
}

1;

__END__
=pod

=encoding UTF-8

=head1 NAME

Zonemaster::CLI - run Zonemaster tests from the command line

=head1 AUTHORS

Vincent Levigneron <vincent.levigneron at nic.fr>
- Current maintainer

Calle Dybedahl <calle at init.se>
- Original author

=head1 LICENSE

This is free software, licensed under:

The (three-clause) BSD License

The full text of the license can be found in the
F<LICENSE> file included with this distribution.

=cut
