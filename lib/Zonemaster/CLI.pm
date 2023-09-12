# Brief help module to define the exception we use for early exits.
package Zonemaster::Engine::Exception::NormalExit;
use Moose;
extends 'Zonemaster::Engine::Exception';

# The actual interesting module.
package Zonemaster::CLI;

use 5.014002;

use strict;
use warnings;

use version; our $VERSION = version->declare( "v6.0.2" );

use Locale::TextDomain 'Zonemaster-CLI';
use Moose;
with 'MooseX::Getopt::GLD' => { getopt_conf => [ 'pass_through' ] };

use Encode;
use File::Slurp;
use JSON::XS;
use List::Util qw[max];
use POSIX qw[setlocale LC_MESSAGES LC_CTYPE];
use Scalar::Util qw[blessed];
use Socket qw[AF_INET AF_INET6];
use Text::Reflow qw[reflow_string];
use Try::Tiny;
use Zonemaster::Engine;
use Zonemaster::Engine::Exception;
use Zonemaster::Engine::Logger::Entry;
use Zonemaster::Engine::Translator;
use Zonemaster::Engine::Util qw[parse_hints];
use Zonemaster::Engine::Zone;
use Zonemaster::LDNS;

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
    is            => 'rw',
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
    cmd_aliases   => 'json_translate',
    cmd_flag      => 'json-translate',
    documentation => __( 'Deprecated. Flag indicating if JSON output should include the translated message of the tag or not.' ),
);

has 'raw' => (
    is            => 'rw',
    isa           => 'Bool',
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

has 'hints' => (
    is            => 'ro',
    isa           => 'Str',
    required      => 0,
    documentation => __( 'Name of a root hints file to override the defaults.' ),
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
'Specify test to run case-insensitively. Should be either the name of a module, or the name of a module and the name of a method in that module separated by a "/" character (Example: "Basic/basic01"). This switch can be repeated.'
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
    documentation => __( 'At the end of a run, print a summary of the times (in milliseconds) the zone\'s name servers took to answer.' ),
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
            'Deprecated (planned removal: v2024.1). '
          . 'Use --sourceaddr4 and/or --sourceaddr6. '
          . 'Source IP address used to send queries. '
          . 'Setting an IP address not correctly configured on a local network interface causes cryptic error messages.'
    ),
);

has 'sourceaddr4' => (
    is            => 'ro',
    isa           => 'Str',
    required      => 0,
    documentation => __(
            'Source IPv4 address used to send queries. '
          . 'Setting an IPv4 address not correctly configured on a local network interface fails silently. '
          . 'Can not be combined with --sourceaddr.'
    ),
);

has 'sourceaddr6' => (
    is            => 'ro',
    isa           => 'Str',
    required      => 0,
    documentation => __(
            'Source IPv6 address used to send queries. '
          . 'Setting an IPv6 address not correctly configured on a local network interface fails silently. '
          . 'Can not be combined with --sourceaddr.'
    ),
);

has 'elapsed' => (
    is            => 'ro',
    isa           => 'Bool',
    required      => 0,
    default       => 0,
    documentation => __( 'Print elapsed time (in seconds) at end of run.' ),
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

    if ( $self->sourceaddr ) {
        if ( $self->sourceaddr4 or $self->sourceaddr6 ) {
            die __( "Error: --sourceaddr can't be combined with --sourceaddr4 or --sourceaddr6." ) . "\n";
        }
        printf STDERR "%s\n\n", __( "Warning: --sourceaddr is deprecated (planned removal: v2024.1). Use --sourceaddr4 and/or --sourceaddr6 instead." );
        Zonemaster::Engine::Profile->effective->set( q{resolver.source}, $self->sourceaddr );
    }

    if ( $self->sourceaddr4 ) {
        Zonemaster::Engine::Profile->effective->set( q{resolver.source4}, $self->sourceaddr4 );
    }

    if ( $self->sourceaddr6 ) {
        Zonemaster::Engine::Profile->effective->set( q{resolver.source6}, $self->sourceaddr6 );
    }

    # errors and warnings
    if ( $self->json_stream and not $self->json and grep( /^--no-?json$/, @{ $self->ARGV } ) ) {
        die __( "Error: --json-stream and --no-json can't be used together." ) . "\n";
    }

    if ( defined $self->json_translate ) {
        unless ( $self->json or $self->json_stream ) {
            printf STDERR __( "Warning: --json-translate has no effect without either --json or --json-stream." ) . "\n";
        }
        if ( $self->json_translate ) {
            printf STDERR __( "Warning: deprecated --json-translate, use --no-raw instead." ) . "\n";
        }
        else {
            printf STDERR __( "Warning: deprecated --no-json-translate, use --raw instead." ) . "\n";
        }
    }

    # align values
    $self->json( 1 ) if $self->json_stream;
    $self->raw( $self->raw // ( defined $self->json_translate ? !$self->json_translate : 0 ) );

    # Filehandle for diagnostics output
    my $fh_diag = ( $self->json or $self->raw )
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
    $translator = Zonemaster::Engine::Translator->new unless $self->raw;
    $translator->locale( $self->locale ) if $translator and $self->locale;

    if ( $self->restore ) {
        Zonemaster::Engine->preload_cache( $self->restore );
    }

    my $level_width = 0;
    foreach ( keys %numeric ) {
        if ( $numeric{ $self->level } <= $numeric{$_} ) {
            my $width_l10n = length( decode_utf8( translate_severity( $_ ) ) );
            $level_width = $width_l10n if $width_l10n > $level_width;
        }
    }

    my %field_width = (
        seconds  => 7,
        level    => $level_width,
        module   => 12,
        testcase => 14
    );
    my %header_names = ();
    my %remaining_space = ();
    if ( $translator ) {
        %header_names = (
            seconds  => __( 'Seconds' ),
            level    => __( 'Level' ),
            module   => __( 'Module' ),
            testcase => __( 'Testcase' ),
            message  => __( 'Message' )
        );
        foreach ( keys %header_names ) {
            $field_width{$_} = _max( $field_width{$_}, length( decode_utf8( $header_names{$_} ) ) );
            $remaining_space{$_} = $field_width{$_} - length( decode_utf8( $header_names{$_} ) );
        }
    }

    # Callback defined here so it closes over the setup above.
    Zonemaster::Engine->logger->callback(
        sub {
            my ( $entry ) = @_;

            $self->print_spinner() if $fh_diag eq *STDOUT;

            $counter{ uc $entry->level } += 1;

            if ( $numeric{ uc $entry->level } >= $numeric{ $self->level } ) {
                $printed_something = 1;

                if ( $self->json and $self->json_stream ) {
                    my %r;

                    $r{timestamp} = $entry->timestamp if $self->time;
                    $r{module}    = $entry->module if $self->show_module;
                    $r{testcase}  = $entry->testcase if $self->show_testcase;
                    $r{tag}       = $entry->tag;
                    $r{level}     = $entry->level if $self->show_level;
                    $r{args}      = $entry->args if $entry->args;
                    $r{message}   = $translator->translate_tag( $entry ) unless $self->raw;

                    say $JSON->encode( \%r );
                }
                elsif ( $self->json and not $self->json_stream ) {
                    # Don't do anything
                }
                else {
                    my $prefix = q{};
                    if ( $self->time ) {
                        $prefix .= sprintf "%*.2f ", ${field_width{seconds}}, $entry->timestamp;
                    }

                    if ( $self->show_level ) {
                        $prefix .= $self->raw ? $entry->level : translate_severity( $entry->level );
                        my $space_l10n = ${field_width{level}} - length( decode_utf8( translate_severity($entry->level) ) ) + 1;
                        $prefix .= ' ' x $space_l10n;
                    }

                    if ( $self->show_module ) {
                        $prefix .= sprintf "%-*s ", ${field_width{module}}, $entry->module;
                    }

                    if ( $self->show_testcase ) {
                        $prefix .= sprintf "%-*s ", ${field_width{testcase}}, $entry->testcase;
                    }

                    if ( $self->raw ) {
                        $prefix .= $entry->tag;

                        my $message = $entry->string;
                        $message =~ s/^[A-Z0-9:_]+//;    # strip MODULE:TAG, they're coming in $prefix instead
                        my @lines = split /\n/, $message;

                        printf "%s%s %s\n", $prefix, ' ', shift @lines;
                        for my $line ( @lines ) {
                            printf "%s%s %s\n", $prefix, '>', $line;
                        }
                    }
                    else {
                        if ( $entry->level eq q{DEBUG3} and scalar( keys %{$entry->args} ) == 1 and defined $entry->args->{packet} ) {
                            my $packet = $entry->args->{packet};
                            my $padding = q{ } x length $prefix;
                            $entry->args->{packet} = q{};
                            printf "%s%s\n", $prefix, $translator->translate_tag( $entry );
                            foreach my $line ( split /\n/, $packet ) {
                                printf "%s%s\n", $padding, $line;
                            }
                        }
                        else {
                            printf "%s%s\n", $prefix, $translator->translate_tag( $entry );
                        }
                    }
                }
            }
            if ( $self->stop_level and $numeric{ uc $entry->level } >= $numeric{ $self->stop_level } ) {
                die( Zonemaster::Engine::Exception::NormalExit->new( { message => "Saw message at level " . $entry->level } ) );
            }
        }
    );

    if ( $self->profile ) {
        # Separate initialization from main output in human readable output mode
        print "\n" if $fh_diag eq *STDOUT;
    }

    if ( scalar @{ $self->extra_argv } > 1 ) {
        die __( "Only one domain can be given for testing. Did you forget to prepend an option with '--<OPTION>'?\n" );
    }

    my ( $domain ) = @{ $self->extra_argv };
    if ( not $domain ) {
        die __( "Must give the name of a domain to test.\n" );
    }

    if ( $domain =~ m/\.\./i ) {
        die __( "The domain name contains consecutive dots.\n" );
    }

    $domain =~ s/\.$// unless $domain eq '.';
    $domain = $self->to_idn( $domain );

    if ( defined $self->hints ) {
        my $hints_data;
        try {
            my $hints_text = read_file( $self->hints );
            $hints_data = parse_hints( $hints_text )
        }
        catch {
            die "Error loading hints file: $_";
        }
        Zonemaster::Engine::Recursor->remove_fake_addresses( '.' );
        Zonemaster::Engine::Recursor->add_fake_addresses( '.', $hints_data );
    }

    if ( $self->ns and @{ $self->ns } > 0 ) {
        $self->add_fake_delegation( $domain );
    }

    if ( $self->ds and @{ $self->ds } ) {
        $self->add_fake_ds( $domain );
    }

    if ( not $self->raw and not $self->json ) {
        my $header = q{};

        if ( $self->time ) {
            $header .= sprintf "%s%s ", $header_names{seconds}, " " x $remaining_space{seconds};
        }
        if ( $self->show_level ) {
            $header .= sprintf "%s%s ", $header_names{level}, " " x $remaining_space{level};
        }
        if ( $self->show_module ) {
            $header .= sprintf "%s%s ", $header_names{module}, " " x $remaining_space{module};
        }
        if ( $self->show_testcase ) {
            $header .= sprintf "%s%s ", $header_names{testcase}, " " x $remaining_space{testcase};
        }
        $header .= sprintf "%s\n", $header_names{message};

        if ( $self->time ) {
            $header .= sprintf "%s ", "=" x $field_width{seconds};
        }
        if ( $self->show_level ) {
            $header .= sprintf "%s ", "=" x $field_width{level};
        }
        if ( $self->show_module ) {
            $header .= sprintf "%s ", "=" x $field_width{module};
        }
        if ( $self->show_testcase ) {
            $header .= sprintf "%s ", "=" x $field_width{testcase};
        }
        $header .= sprintf "%s\n", "=" x $field_width{message};

        print $header;
    }

    # Actually run tests!
    eval {
        if ( $self->test and @{ $self->test } > 0 ) {
            foreach my $t ( @{ $self->test } ) {
                my ( $module, $method ) = split( '/', lc($t), 2 );
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
    if ( not $self->raw and not $self->json ) {
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

    my $json_output = {};

    if ( $self->count ) {
        if ( $self->json ) {
            $json_output->{count} = {};
            foreach my $level ( sort { $numeric{$b} <=> $numeric{$a} } keys %counter ) {
                $json_output->{count}{$level} = $counter{$level};
            }
        }
        else {
            say __( "\n\n   Level\tNumber of log entries" );
            say "   =====\t=====================";
            foreach my $level ( sort { $numeric{$b} <=> $numeric{$a} } keys %counter ) {
                printf __( "%8s\t%5d entries.\n" ), translate_severity( $level ), $counter{$level};
            }
        }
    }

    if ( $self->nstimes ) {
        my $zone = Zonemaster::Engine->zone( $domain );
        my $max = max map { length( "$_" ) } ( @{ $zone->ns }, q{Server} );

        if ( $self->json ) {
            my @times = ();
            foreach my $ns ( @{ $zone->ns } ) {
                push @times, {
                    'ns'     => $ns->string,
                    'max'    => 1000 * $ns->max_time,
                    'min'    => 1000 * $ns->min_time,
                    'avg'    => 1000 * $ns->average_time,
                    'stddev' => 1000 * $ns->stddev_time,
                    'median' => 1000 * $ns->median_time,
                    'total'  => 1000 * $ns->sum_time
                };
            }
            $json_output->{nstimes} = \@times;
        }
        else {
            print "\n";
            printf "%${max}s %s\n", 'Server', '      Max      Min      Avg   Stddev   Median     Total';
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
    }

    if ($self->elapsed) {
        my $last = Zonemaster::Engine->logger->entries->[-1];

        if ( $self->json ) {
            $json_output->{elapsed} = $last->timestamp;
        }
        else {
            printf "Total test run time: %0.1f seconds.\n", $last->timestamp;
        }
    }

    if ( $self->json and not $self->json_stream ) {
        my $res = Zonemaster::Engine->logger->json( $self->level );
        $res = $JSON->decode( $res );
        foreach ( @$res ) {
            unless ( $self->raw ) {
                my %e = %$_;
                my $entry = Zonemaster::Engine::Logger::Entry->new( \%e );
                $_->{message} = $translator->translate_tag( $entry );
            }
            delete $_->{timestamp} unless $self->time;
            delete $_->{level} unless $self->show_level;
            delete $_->{module} unless $self->show_module;
            delete $_->{testcase} unless $self->show_testcase;
        }
        $json_output->{results} = $res;
    }

    if ( scalar keys %$json_output ) {
        say $JSON->encode( $json_output );
    }

    if ( $self->save ) {
        Zonemaster::Engine->save_cache( $self->save );
    }

    return;
}

sub add_fake_delegation {
    my ( $self, $domain ) = @_;
    my @ns_with_no_ip;
    my %data;

    foreach my $pair ( @{ $self->ns } ) {
        my ( $name, $ip ) = split( '/', $pair, 2 );

        if ( not $name ) {
            say STDERR __( "--ns must be a name or a name/ip pair." );
            exit( 1 );
        }

        if ( $name =~ m/\.\./i ) {
            say STDERR __x( "The name of the nameserver '{nsname}' contains consecutive dots.", nsname => $name );
            exit ( 1 );
        }

        $name =~ s/\.$// unless $name eq '.';

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
    say 'Zonemaster-CLI version ' . __PACKAGE__->VERSION;
    say 'Zonemaster-Engine version ' . $Zonemaster::Engine::VERSION;
    say 'Zonemaster-LDNS version ' . $Zonemaster::LDNS::VERSION;
    say 'NL NetLabs LDNS version ' . Zonemaster::LDNS::lib_version();

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
        say STDERR __( "Warning: Zonemaster::LDNS not compiled with IDN support, cannot handle non-ASCII names correctly." );
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
        foreach my $method ( sort @{ $methods{$module} } ) {
            printf "  %${maxlen}s\n", $method;
        }
        print "\n";
    }
    exit( 0 );
}

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

sub _max {
    my ( $a, $b ) = @_;
    $a //= 0;
    $b //= 0;
    return ( $a > $b ? $a : $b ) ;
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

This is free software under a 2-clause BSD license. The full text of the license can
be found in the F<LICENSE> file included with this distribution.

=cut
