# Brief help module to define the exception we use for early exits.
package Zonemaster::Engine::Exception::NormalExit;
use Moose;
extends 'Zonemaster::Engine::Exception';

# The actual interesting module.
package Zonemaster::CLI;

use 5.014002;

use strict;
use warnings;

use version; our $VERSION = version->declare( "v7.0.0" );

use Locale::TextDomain 'Zonemaster-CLI';
use Moose;
with 'MooseX::Getopt::GLD' => { getopt_conf => [ 'pass_through' ] };

use Encode;
use Readonly;
use File::Slurp;
use JSON::XS;
use List::Util qw[max uniq];
use POSIX qw[setlocale LC_MESSAGES LC_CTYPE];
use Scalar::Util qw[blessed];
use Try::Tiny;
use Net::IP::XS;

use Zonemaster::LDNS;
use Zonemaster::Engine;
use Zonemaster::Engine::Exception;
use Zonemaster::Engine::Normalization qw[normalize_name];
use Zonemaster::Engine::Logger::Entry;
use Zonemaster::Engine::Translator;
use Zonemaster::Engine::Util qw[parse_hints];

our %numeric = Zonemaster::Engine::Logger::Entry->levels;
our $JSON    = JSON::XS->new->allow_blessed->convert_blessed->canonical;

Readonly our $EXIT_SUCCESS       => 0;
Readonly our $EXIT_GENERIC_ERROR => 1;
Readonly our $EXIT_USAGE_ERROR   => 2;

Readonly our $IPV4_RE => qr/^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$/;
Readonly our $IPV6_RE => qr/^[0-9a-f:]*:[0-9a-f:]+(:[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3})?$/i;

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
'Specify test case to be run. Should be the case-insensitive name of a test module (e.g. "Delegation") and/or a test case (e.g. "Delegation/delegation01" or "delegation01"). This switch can be repeated.'
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

has 'sourceaddr4' => (
    is            => 'ro',
    isa           => 'Str',
    required      => 0,
    documentation => __(
            'Source IPv4 address used to send queries. '
          . 'Setting an IPv4 address not correctly configured on a local network interface fails silently.'
    ),
);

has 'sourceaddr6' => (
    is            => 'ro',
    isa           => 'Str',
    required      => 0,
    documentation => __(
            'Source IPv6 address used to send queries. '
          . 'Setting an IPv6 address not correctly configured on a local network interface fails silently.'
    ),
);

has 'elapsed' => (
    is            => 'ro',
    isa           => 'Bool',
    required      => 0,
    default       => 0,
    documentation => __( 'Print elapsed time (in seconds) at end of run.' ),
);

# Returns an integer representing an OS exit status.
sub run {
    my ( $self ) = @_;
    my @accumulator;
    my %counter;
    my $printed_something;

    if ( grep /^-/, @{ $self->extra_argv } ) {
        say STDERR "Unknown option: ", join( q{ }, grep /^-/, @{ $self->extra_argv } );
        say STDERR "Run \"zonemaster-cli -h\" to get the valid options";
        return $EXIT_USAGE_ERROR;
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
        return $EXIT_SUCCESS;
    }

    if ( $self->list_tests ) {
        print_test_list();
        return $EXIT_SUCCESS;
    }

    if ( $self->sourceaddr4 ) {
        Zonemaster::Engine::Profile->effective->set( q{resolver.source4}, $self->sourceaddr4 );
    }

    if ( $self->sourceaddr6 ) {
        Zonemaster::Engine::Profile->effective->set( q{resolver.source6}, $self->sourceaddr6 );
    }

    # errors and warnings
    if ( $self->json_stream and not $self->json and grep( /^--no-?json$/, @{ $self->ARGV } ) ) {
        say STDERR __( "Error: --json-stream and --no-json can't be used together." );
        return $EXIT_USAGE_ERROR;
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

    my @testing_suite;
    if ( $self->test and @{ $self->test } > 0 ) {
        my %existing_tests = Zonemaster::Engine->all_methods;
        my @existing_test_modules = keys %existing_tests;
        my @existing_test_cases = map { @{ $existing_tests{$_} } } @existing_test_modules;

        foreach my $t ( @{ $self->test } ) {
            # There should be at most one slash character
            if ( $t =~ tr/\/// > 1 ) {
                say STDERR __( "Error: Invalid input '$t' in --test. There must be at most one slash ('/') character.");
                return $EXIT_USAGE_ERROR;
            }

            # The case does not matter
            $t = lc( $t );

            my ( $module, $method );
            # Fully qualified module and test case (e.g. Example/example12), or just a test case (e.g. example12). Note the different capturing order.
            if ( ( ($module, $method) = $t =~ m#^ ( [a-z]+ ) / ( [a-z]+[0-9]{2} ) $#ix )
                or
                 ( ($method, $module) = $t =~ m#^ ( ( [a-z]+ ) [0-9]{2} ) $#ix ) )
            {
                # Check that test module exists
                if ( grep( /^$module$/,  map { lc($_) } @existing_test_modules ) ) {
                    # Check that test case exists
                    if ( grep( /^$method$/, @existing_test_cases ) ) {
                        push @testing_suite, "$module/$method";
                    }
                    else {
                        say STDERR __( "Error: Unrecognized test case '$method' in --test. Use --list-tests for a list of valid choices." );
                        return $EXIT_USAGE_ERROR;
                    }
                }
                else {
                    say STDERR __( "Error: Unrecognized test module '$module' in --test. Use --list-tests for a list of valid choices." );
                    return $EXIT_USAGE_ERROR;
                }
            }
            # Just a module name (e.g. Example) or something invalid.
            else {
                $t =~ s{/$}{};
                # Check that test module exists
                if ( grep( /^$t$/,  map { lc($_) } @existing_test_modules ) ) {
                    push @testing_suite, $t;
                }
                else {
                    say STDERR __( "Error: Invalid input '$t' in --test." );
                    return $EXIT_USAGE_ERROR;
                }
            }
        }

        # Start with all profile-enabled test cases
        my @actual_test_cases = @{ Zonemaster::Engine::Profile->effective->get( 'test_cases' ) };

        # Derive test module from each profile-enabled test case
        my %actual_test_modules;
        foreach my $t ( @actual_test_cases ) {
            my ( $module ) = $t =~ m#^ ( [a-z]+ ) [0-9]{2} $#ix;
            $actual_test_modules{$module} = 1;
        }

        # Check if more test cases need to be included in the profile
        foreach my $t ( @testing_suite ) {
            # Either a module/method, or just a module
            my ( $module, $method ) = split('/', $t);
            if ( $method ) {
                # Test case in not already in the profile, we add it explicitly and notify the user
                if ( not grep( /^$method$/, @actual_test_cases ) ) {
                    say $fh_diag __x( "Notice: Engine does not have test case '$method' enabled in the profile. Forcing...");
                    push @actual_test_cases, $method;
                }
            }
            else {
                # No test case from this module is already in the profile, we can add them all
                if ( not grep( /^$module$/, keys %actual_test_modules ) ) {
                    # Get the test module with the right case
                    ( $module ) = grep { lc( $module ) eq lc( $_ ) } @existing_test_modules;
                    # No need to bother to check for duplicates here
                    push @actual_test_cases, @{ $existing_tests{$module} };
                }
            }
        }

        # Configure Engine to include all of the required test cases in the profile
        Zonemaster::Engine::Profile->effective->set( 'test_cases', [ uniq sort @actual_test_cases ] );
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
        return $EXIT_SUCCESS;
    }

    if ( $self->stop_level and not defined( $numeric{ $self->stop_level } ) ) {
        say STDERR __x( "Failed to recognize stop level 'level'.", level => $self->stop_level );
        return $EXIT_USAGE_ERROR;
    }

    if ( not defined $numeric{ $self->level } ) {
        say STDERR __( "--level must be one of CRITICAL, ERROR, WARNING, NOTICE, INFO, DEBUG, DEBUG2 or DEBUG3." );
        return $EXIT_USAGE_ERROR;
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

                        my $message = $entry->argstr;
                        my @lines = split /\n/, $message;

                        printf "%s%s %s\n", $prefix, ' ', @lines ? shift @lines : '';
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

    if ( scalar @{ $self->extra_argv } > 1 ) {
        say STDERR __( "Only one domain can be given for testing. Did you forget to prepend an option with '--<OPTION>'?" );
        return $EXIT_USAGE_ERROR;
    }

    my ( $domain ) = @{ $self->extra_argv };

    if ( !defined $domain ) {
        say STDERR __( "Must give the name of a domain to test." );
        return $EXIT_USAGE_ERROR;
    }

    ( my $errors, $domain ) = normalize_name( decode( 'utf8', $domain ) );

    if ( scalar @$errors > 0 ) {
        my $error_message;
        foreach my $err ( @$errors ) {
            $error_message .= $err->string . "\n";
        }
        print STDERR $error_message;
        return $EXIT_USAGE_ERROR;
    }

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
        local $@;
        eval {
            $self->add_fake_delegation( $domain );
            1;
        } or do {
            print STDERR $@;
            return $EXIT_USAGE_ERROR;
        };
    }

    if ( $self->ds and @{ $self->ds } ) {
        $self->add_fake_ds( $domain );
    }

    if ( $self->profile or $self->test ) {
        # Separate initialization from main output in human readable output mode
        print "\n" if $fh_diag eq *STDOUT;
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
            foreach my $t ( @testing_suite ) {
                # Either a module/method, or just a module
                my ( $module, $method ) = split('/', $t);
                if ( $method ) {
                    Zonemaster::Engine->test_method( $module, $method, $domain );
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

    return $EXIT_SUCCESS;
}

sub add_fake_delegation {
    my ( $self, $domain ) = @_;
    my @ns_with_no_ip;
    my %data;

    foreach my $pair ( @{ $self->ns } ) {
        my ( $name, $ip ) = split( '/', $pair, 2 );

        if ( $pair =~ tr/\/// > 1 or not $name ) {
            die __( "--ns must be a name or a name/ip pair." ) . "\n";
        }

        ( my $errors, $name ) = normalize_name( decode( 'utf8', $name ) );

        if ( scalar @$errors > 0 ) {
            my $error_message = "Invalid name in --ns argument:\n" ;
            foreach my $err ( @$errors ) {
                $error_message .= "\t" . $err->string . "\n";
            }
            die $error_message;
        }

        if ( $ip ) {
            my $net_ip = Net::IP::XS->new( $ip );
            if ( ( $ip =~ /($IPV4_RE)/ && Net::IP::XS::ip_is_ipv4( $ip ) )
                or
                 ( $ip =~ /($IPV6_RE)/ && Net::IP::XS::ip_is_ipv6( $ip ) )
            ) {
                push @{ $data{ $name } }, $ip;
            }
            else {
                die Net::IP::XS::Error() ? "Invalid IP address in --ns argument:\n\t". Net::IP::XS::Error() ."\n" : "Invalid IP address in --ns argument.\n";
            }
        }
        else {
            push @ns_with_no_ip, $name;
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

    return;
}

sub do_dump_profile {
    my $json = JSON::XS->new->canonical->pretty;

    print $json->encode( Zonemaster::Engine::Profile->effective->{ q{profile} } );

    return;
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
