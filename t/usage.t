#!perl
use 5.16.0;
use warnings;
use utf8;
use Test::More;

use Config '%Config';
use Encode                qw( decode_utf8 );
use File::Basename        qw( dirname );
use File::Slurp           qw( write_file );
use File::Spec::Functions qw( catfile );
use IPC::Open3;
use JSON::XS;
use POSIX;
use Readonly;
use Symbol qw( gensym );
use Test::Differences;
use Zonemaster::CLI;

# CONSTANTS

Readonly::Array my @SIG_NAMES => do {
    my @sig_names;
    @sig_names[ split ' ', $Config{sig_num} ] = split ' ', $Config{sig_name};
    @sig_names;
};

Readonly::Scalar my $PATH_WRAPPER            => catfile( dirname( __FILE__ ), 'usage.wrapper.pl' );
Readonly::Scalar my $PATH_NORMAL_DATAFILE    => catfile( dirname( __FILE__ ), 'usage.normal.data' );
Readonly::Scalar my $PATH_FAKE_DATA_DATAFILE => catfile( dirname( __FILE__ ), 'usage.fake-data.data' );
Readonly::Scalar my $PATH_FAKE_ROOT_DATAFILE => catfile( dirname( __FILE__ ), 'usage.fake-root.data' );

# MUTABLE GLOBAL VARIABLES

our $test_datafile;

# SETUP

if ( $ENV{ZONEMASTER_RECORD} ) {
    write_file $PATH_NORMAL_DATAFILE,    '';
    write_file $PATH_FAKE_DATA_DATAFILE, '';
    write_file $PATH_FAKE_ROOT_DATAFILE, '';
}

# HELPERS

sub check_success {
    my ( $name, $args, $predicate ) = @_;

    subtest $name => sub {
        my $result = _run_zonemaster_cli( $test_datafile, @$args );

        my $stdout     = delete $result->{stdout};
        my $stderr     = delete $result->{stderr};
        my $exitstatus = delete $result->{exitstatus};

        if ( $stderr ne '' ) {
            note "stderr:\n$stderr" =~ s/\n/\n    /gr;
        }

        if ( ref $predicate eq 'CODE' ) {
            if ( $predicate->( $stdout ) ) {
                pass 'expected stdout (sub)';
            }
            else {
                fail 'expected stdout (sub)';
                diag "actual stdout:\n$stdout" =~ s/\n/\n    /gr;
            }
        }
        else {
            like $stdout, $predicate, 'expected stdout (regex)';
        }

        is $exitstatus, $Zonemaster::CLI::EXIT_SUCCESS, 'success exit status';
    };
} ## end sub check_success

sub check_usage_error {
    my ( $name, $args, $error_pattern ) = @_;

    subtest $name => sub {
        my $result = _run_zonemaster_cli( undef, @$args );

        my $stderr = delete $result->{stderr};
        like $stderr, $error_pattern, 'expected error message';

        eq_or_diff(
            $result,
            {
                stdout     => '',
                exitstatus => $Zonemaster::CLI::EXIT_USAGE_ERROR,
            },
            'no stdout and usage error exit code'
        ) or note "stderr:\n$stderr" =~ s/\n/\n    /gr;
    };
}

sub parse_json_stream {
    my ( $text ) = @_;

    my $decoder = JSON::XS->new;

    my @items;
    while ( 1 ) {
        $text =~ s/^\s+//;
        if ( $text eq '' ) {
            last;
        }

        my ( $item, $len ) = $decoder->decode_prefix( $text );

        push @items, $item;
        $text = substr $text, $len;
        $text =~ s/^\s+//;
    }
    return @items;
} ## end sub parse_json_stream

sub has_locale {
    my ( $locale ) = @_;
    my $old_locale = setlocale( LC_CTYPE );
    my $success    = defined setlocale( LC_CTYPE, $locale );
    setlocale( LC_CTYPE, $old_locale );
    return $success;
}

sub _run_zonemaster_cli {
    my ( $datafile, @args ) = @_;

    my @cmd = ( $PATH_WRAPPER );
    if ( defined $datafile ) {
        if ( $ENV{ZONEMASTER_RECORD} ) {
            push @cmd, '--record';
        }
        push @cmd, $datafile;
    }
    push @cmd, '--', @args;

    my $pid = open3( my $stdin, my $stdout, my $stderr = gensym, @cmd );
    waitpid( $pid, 0 );
    my $exitcode = $?;

    if ( POSIX::WIFEXITED( $exitcode ) ) {
        local $/ = undef;
        return {
            stdout     => scalar <$stdout>,
            stderr     => scalar <$stderr>,
            exitstatus => POSIX::WEXITSTATUS( $exitcode ),
        };
    }
    elsif ( POSIX::WIFSIGNALED( $exitcode ) ) {
        die "child process terminated by signal: " . $SIG_NAMES[ POSIX::WTERMSIG( $exitcode ) ];
    }
    elsif ( POSIX::WIFSTOPPED( $exitcode ) ) {
        die "child process stopped by signal: " . $SIG_NAMES[ POSIX::WSTOPSIG( $exitcode ) ];
    }
    else {
        die "unrecognized exit code $exitcode";
    }
} ## end sub _run_zonemaster_cli

# TESTS

do {
    local $test_datafile = undef;
    note "TESTS USING NO NETWORK AND NO FILE FOR RECORDED DATA:";

    check_usage_error 'no domain', [], qr{must give the name of a domain to test}i;

    check_usage_error 'too many domains', [ 'example.com', 'example.net' ],
      qr{only one domain can be given for testing}i;

    check_usage_error 'invalid domain', ['!%~&'], qr{character not permitted}i;

    check_usage_error 'unrecognized option', ['--foobar'], qr{unknown option}i;

    check_usage_error '--test BAD_MODULE', [ '--test', '!%~&', 'example.' ], qr{invalid input}i;

    check_usage_error '--test UNKNOWN_MODULE/TESTCASE', [ '--test', 'foobar/foobar01', 'example.' ],
      qr{unrecognized test module}i;

    check_usage_error '--test MODULE/UNKNOWN_TESTCASE', [ '--test', 'basic/foobar01', 'example.' ],
      qr{unrecognized test case}i;

    check_usage_error '--test MODULE//TESTCASE', [ '--test', 'basic//basic01', 'example.' ], qr{invalid input}i;

    check_usage_error '--ns BAD_NAME', [ '--ns', '!%~&', 'example.' ], qr{invalid name}i;

    check_usage_error '--ns NAME//IP', [ '--ns', 'ns1.example//192.0.2.1', 'example.' ], qr{--ns}i;

    check_usage_error '--ns NAME/BAD_IP', [ '--ns', 'ns1.example/foobar', 'example.' ], qr{invalid ip address}i;

    check_usage_error '--level BAD_LEVEL', [ '--level', 'foobar', 'example.' ], qr{--level}i;

    check_usage_error '--stop-level BAD_LEVEL', [ '--stop-level', 'foobar', 'example.' ],
      qr{failed to recognize stop level}i;

    check_usage_error '--json-stream and --no-json', [ '--json-stream', '--no-json', 'example.' ],
      qr{can't be used together}i;

    check_success '--version', ['--version'], qr{
        ^\QZonemaster-CLI version\E .*
        ^\QZonemaster-Engine version\E .*
        ^\QZonemaster-LDNS version\E .*
        ^\QNL NetLabs LDNS version\E .*
    }msx;

    check_success '--list-tests', ['--list-tests'], qr{
        Basic
        .*
        basic01
    }msx;

    check_success '--dump-profile', ['--dump-profile'], qr{
        "no_network"
    }msx;
};

do {
    local $test_datafile = $PATH_NORMAL_DATAFILE;
    note "TESTS USING $test_datafile FOR RECORDED DATA:";

    check_success 'normal table output', [ '--test=basic01', '--level=INFO', '.' ], qr{
        ^
        Seconds \s+ Level \s+ Message \n
        =+ \s =+ \s =+ \n
        \s* \Q0.00\E \s+ INFO \s+ .* \s [v0-9.]+ \s  .* \n
    }msx;

    check_success 'normal table output, no optional fields',
      [ '--test=basic01', '--level=INFO', '--no-time', '--no-show-level', '.' ], qr{
        ^
        Message \n
        =+ \n
        Using .* \n
    }msx;

    check_success 'normal table output, all fields',
      [ '--test=basic01', '--level=INFO', '--show-module', '--show-testcase', '.' ], qr{
        ^
        Seconds \s+ Level \s+ Module \s+ Testcase \s+ Message \n
        =+ \s =+ \s =+ \s =+ \s =+ \n
        \s* \Q0.00\E \s+ INFO \s+ System \s+ Unspecified \s+ Using .* \n
    }msx;

    check_success '--json', [ '--test=basic01', '--json', '.' ], qr{
        \Q{"results":[]}\E
    }msx;

    check_success '--json-stream', [ '--test=basic01', '--json-stream', '--level=INFO', '.' ], sub {
        my $found = 0;
        for my $item ( parse_json_stream( $_[0] ) ) {
            if ( $item->{tag} eq 'GLOBAL_VERSION' ) {
                if ( $item->{message} !~ /^Using / ) {
                    return 0;
                }
                $found = 1;
            }
        }
        return $found;
    };

    check_success '--raw', [ '--test=basic01', '--level=INFO', '--raw', '.' ], qr{
        ^
        \s* \Q0.00\E \s+ INFO \s+ GLOBAL_VERSION \s+ version= [v0-9.]+ \n
    }msx;

  SKIP: {
        skip 'sv_SE.utf8 locale is unavailable', 3
          if !has_locale( 'sv_SE.utf8' );

        check_success '--json-stream --no-raw',
          [ '--test=basic01', '--json-stream', '--no-raw', '--locale=sv_SE.utf8', '--level=INFO', '.' ], sub {
            my $found = 0;
            for my $item ( parse_json_stream( decode_utf8( $_[0] ) ) ) {
                if ( $item->{tag} eq 'GLOBAL_VERSION' ) {
                    if ( $item->{message} !~ qr{^Använder } ) {
                        return 0;
                    }
                    $found = 1;
                }
            }
            return $found;
          };

        check_success '--json-stream --no-raw --locale',
          [ '--test=basic01', '--json-stream', '--no-raw', '--locale=sv_SE.utf8', '--level=INFO', '.' ], sub {
            my $found = 0;
            for my $item ( parse_json_stream( decode_utf8( $_[0] ) ) ) {
                if ( $item->{tag} eq 'GLOBAL_VERSION' ) {
                    if ( $item->{message} !~ qr{^Använder } ) {
                        return 0;
                    }
                    $found = 1;
                }
            }
            return $found;
          };

        check_success '--locale', [ '--test=basic01', '--locale=sv_SE.utf8', '.' ], qr{
            \QSer OK ut.\E
        }msx;
    } ## end SKIP:

    check_success '--count', [ '--test=basic01', '--count', '.' ], qr{
        \QLooks OK.\E
        .*
        Level \s+ \QNumber of log entries\E
        .*
        INFO \s+ \d+
        .*
        DEBUG \s+ \d+
    }msx;

    check_success '--nstimes', [ '--test=basic01', '--nstimes', '.' ], qr{
        \QLooks OK.\E
        .*
        Server \s+ Max \s+ Min \s+ Avg \s+ Stddev \s+ Median \s+ Total
        .*
        \Qa.root-servers.net/\E
    }msx;

    check_success '--elapsed', [ '--test=basic01', '--elapsed', '.' ], qr{
        \QLooks OK.\E
        .*
        \QTotal test run time:\E
    }msx;
};

do {
    local $test_datafile = $PATH_FAKE_DATA_DATAFILE;
    note "TESTS USING $test_datafile FOR RECORDED DATA:";

  SKIP: {
        skip 'crashing test that has never worked on replay (FIXME)', 2
          if not $ENV{ZONEMASTER_RECORD};

        check_success '--ns', [ '--noipv6', '--raw', '--ns=ns1.a.example/9.9.9.9', 'a.se' ], qr{B02_NO_WORKING_NS};

        check_success '--ds',
          [
            '--noipv6', '--raw', '--test=dnssec02',
            '--ds=0,8,2,0000000000000000000000000000000000000000000000000000000000000000',
            'zonemaster.net'
          ],
          qr{DS02_NO_DNSKEY_FOR_DS};
    }
};

do {
    local $test_datafile = $PATH_FAKE_ROOT_DATAFILE;
    note "TESTS USING $test_datafile FOR RECORDED DATA:";

    check_success '--hints', [ '--noipv6', '--raw', '--hints=t/usage.hints', 'example.' ], qr{CANNOT_CONTINUE}i;
};

done_testing;
