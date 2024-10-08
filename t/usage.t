#!perl
use 5.16.0;
use warnings;
use utf8;
use Test::More;

use Config '%Config';
use Encode                qw( decode_utf8 );
use File::Basename        qw( dirname );
use File::Slurp           qw( read_file write_file );
use File::Spec::Functions qw( catfile );
use File::Temp            qw( tempdir );
use IPC::Open3;
use JSON::XS;
use POSIX;
use Readonly;
use Symbol qw( gensym );
use Test::Differences;
use Zonemaster::CLI;
use JSON::Validator;

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
Readonly::Array my @PERL => do {
    # Detect whether Devel::Cover is running
    my $is_covering = !!( eval 'Devel::Cover::get_coverage()' );
    note $is_covering ? 'Devel::Cover running' : 'Devel::Cover not covering';
    ( $^X, $is_covering ? ( '-MDevel::Cover=-silent,1' ) : () )
};

# MUTABLE GLOBAL VARIABLES

our $test_datafile;

# SETUP

if ( $ENV{ZONEMASTER_RECORD} ) {
    write_file $PATH_NORMAL_DATAFILE,    '';
    write_file $PATH_FAKE_DATA_DATAFILE, '';
    write_file $PATH_FAKE_ROOT_DATAFILE, '';
}

# HELPERS

sub json_schema {
  my ( $schema ) = @_;
    my $validator = JSON::Validator->new;
    $validator->schema( $schema );
    return $validator;
}

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
        elsif ( ref $predicate eq 'Regexp' ) {
            like $stdout, $predicate, 'expected stdout (regex)';
        }
        elsif ( blessed $predicate && blessed $predicate eq 'JSON::Validator' ) {
            my @items  = parse_json_stream( $stdout );
            my @errors = $predicate->validate( [@items] );
            if ( !eq_or_diff \@errors, [], "schema validation" ) {
                diag "actual stdout:\n$stdout" =~ s/\n/\n    /gr;
            }
        }
        else {
            BAIL_OUT( "unrecognized predicate type" );
        }

        is $exitstatus, $Zonemaster::CLI::EXIT_SUCCESS, 'success exit status';
    };
} ## end sub check_success

sub check_success_report {
    my ( $name, $args, $predicates ) = @_;

    subtest $name => sub {
        check_success 'normal mode', $args, $predicates->{text};

        check_success 'raw mode', $args, $predicates->{text};

        check_success 'json mode', [ '--json', @$args ],
          json_schema(
            {
                type  => "array",
                items => $predicates->{json},
            }
          );

        check_success 'json-stream mode', [ '--json-stream', @$args ],
          json_schema(
            {
                type  => "array",
                contains => $predicates->{json},
            }
          );
    };

}

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
        ) or diag "stderr:\n$stderr" =~ s/\n/\n    /gr;
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

    my @cmd = ( @PERL, $PATH_WRAPPER );
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

    check_success 'normal table output, no optional fields, using underscore alias',
      [ '--test=basic01', '--level=INFO', '--no-time', '--no-show_level', '.' ], qr{
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

    check_success 'normal table output, all fields, using underscore aliases',
      [ '--test=basic01', '--level=INFO', '--show_module', '--show_testcase', '.' ], qr{
        ^
        Seconds \s+ Level \s+ Module \s+ Testcase \s+ Message \n
        =+ \s =+ \s =+ \s =+ \s =+ \n
        \s* \Q0.00\E \s+ INFO \s+ System \s+ Unspecified \s+ Using .* \n
    }msx;

    check_success '--encoding', [ '--test=basic01', '--json', '--encoding', 'foobar', '.' ], qr{
        \Q{"results":[]}\E
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

    check_success '--json_stream', [ '--test=basic01', '--json_stream', '--level=INFO', '.' ], sub {
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
        skip 'sv_SE.utf8 locale is unavailable', 5
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

        check_success '--json-stream --json-translate',
          [ '--test=basic01', '--json-stream', '--json-translate', '--locale=sv_SE.utf8', '--level=INFO', '.' ], sub {
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

        check_success '--json-stream --json-translate --locale',
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

    check_success_report '--count', [ '--test=basic01', '--count', '.' ], {
        text => qr{
            \QLooks OK.\E
            .*
            Level \s+ \QNumber of log entries\E
            .*
            INFO \s+ \d+
            .*
            DEBUG \s+ \d+
        }msx,
        json => {
            type       => "object",
            required   => ["count"],
            patternProperties => {
                '^[A-Z]+[0-9]*$' => {
                    type  => "integer",
                },
            },
        },
    };

    check_success_report '--nstimes', [ '--test=basic01', '--nstimes', '.' ], {
        text => qr{
            \QLooks OK.\E
            .*
            Server \s+ Max \s+ Min \s+ Avg \s+ Stddev \s+ Median \s+ Total
            .*
            \Qa.root-servers.net/\E
        }msx,
        json => {
            type       => "object",
            required   => ["nstimes"],
            properties => {
                nstimes => {
                    type  => "array",
                    items => {
                        type     => "object",
                        required => [qw( avg max median min ns stddev total)],
                    },
                },
            },
        },
    };

    check_success_report '--elapsed', [ '--test=basic01', '--elapsed', '.' ], {
        text => qr{
            \QLooks OK.\E
            .*
            \QTotal test run time:\E
        }msx,
        json => {
            type       => "object",
            required   => ["elapsed"],
            properties => {
                elapsed => {
                    type  => "number",
                },
            },
        },
    };

    check_success '--level',
      [ '--profile=t/usage.profile', '--ipv4', '--sourceaddr4', '', '--test=basic', '--raw', '--level=notice', '.' ],
      sub {
        my $stdout = $_[0];

        return ( $stdout =~ qr{NOTICE .* WARNING .* ERROR}msx )
          && ( $stdout !~ qr{INFO}msx );
      };

    check_success '--stop-level',
      [
        '--profile=t/usage.profile', '--ipv4', '--sourceaddr4',        '',
        '--test=basic',              '--raw',  '--stop-level=warning', '.'
      ],
      sub {
        my $stdout = $_[0];

        return ( $stdout =~ qr{NOTICE .* WARNING}msx )
          && ( $stdout !~ qr{ERROR}m );
      };

    check_success '--stop_level',
      [
        '--profile=t/usage.profile', '--ipv4', '--sourceaddr4',        '',
        '--test=basic',              '--raw',  '--stop_level=warning', '.'
      ],
      sub {
        my $stdout = $_[0];

        return ( $stdout =~ qr{NOTICE .* WARNING}msx )
          && ( $stdout !~ qr{ERROR}m );
      };

    my $tempdir  = tempdir( CLEANUP => 1 );
    my $savefile = catfile( $tempdir, 'saved.data' );
    check_success 'run command', [ "--save=$savefile", '--test=basic01', '.' ], sub {
        my @saved_lines    = read_file $savefile;
        my @expected_lines = read_file $PATH_NORMAL_DATAFILE;
        return scalar( @saved_lines ) == scalar( @expected_lines );
    };
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

    check_usage_error '--sourceaddr4', [ '--sourceaddr4', 'foobar', 'example.' ], qr{invalid value}i;

    check_usage_error '--sourceaddr6', [ '--sourceaddr6', 'foobar', 'example.' ], qr{invalid value}i;

    check_usage_error '--level BAD_LEVEL', [ '--level', 'foobar', 'example.' ], qr{--level}i;

    check_usage_error '--stop-level BAD_LEVEL', [ '--stop-level', 'foobar', 'example.' ],
      qr{failed to recognize stop level}i;

    check_usage_error '--json-stream and --no-json', [ '--json-stream', '--no-json', 'example.' ],
      qr{can't be used together}i;

    check_usage_error 'Bad --hints (directory)', [ '--hints', '/', 'example.' ],
      qr{error loading hints file}i;

    check_usage_error 'Bad --hints (syntax)', [ '--hints', 't/usage.t', 'example.' ],
      qr{error loading hints file}i;

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

    check_success '--list_tests', ['--list_tests'], qr{
        Basic
        .*
        basic01
    }msx;

    check_success '--dump-profile', ['--dump-profile'], qr{
        "no_network"
    }msx;

    check_success '--dump_profile', ['--dump_profile'], qr{
        "no_network"
    }msx;

    check_success 'override profile', [ '--dump-profile', '--profile=t/usage.profile' ], sub {
        my ( $profile ) = parse_json_stream( $_[0] );

        my $ipv4    = exists $profile->{net}{ipv4} ? ( $profile->{net}{ipv4} ? '1' : '0' ) : '<missing>';
        my $ipv6    = exists $profile->{net}{ipv6} ? ( $profile->{net}{ipv6} ? '1' : '0' ) : '<missing>';
        my $source4 = $profile->{resolver}{source4} // '<missing>';
        my $source6 = $profile->{resolver}{source6} // '<missing>';

        return
             ( $ipv4 eq '0' )
          && ( $ipv6 eq '0' )
          && ( $source4 eq '192.0.2.1' )
          && ( $source6 eq '2001:db8::1' );
    };

    check_success 'override net.ipv4', [ '--dump-profile', '--profile=t/usage.profile', '--ipv4' ], sub {
        my ( $profile ) = parse_json_stream( $_[0] );

        my $ipv4 = exists $profile->{net}{ipv4} ? ( $profile->{net}{ipv4} ? '1' : '0' ) : '<missing>';

        return $ipv4 eq '1';
    };

    check_success 'override net.ipv6', [ '--dump-profile', '--profile=t/usage.profile', '--ipv6' ], sub {
        my ( $profile ) = parse_json_stream( $_[0] );

        my $ipv6 = exists $profile->{net}{ipv6} ? ( $profile->{net}{ipv6} ? '1' : '0' ) : '<missing>';

        return $ipv6 eq '1';
    };

    check_success 'override resolver.source4',
      [ '--dump-profile', '--profile=t/usage.profile', '--sourceaddr4', '192.0.2.2' ], sub {
        my ( $profile ) = parse_json_stream( $_[0] );

        my $source4 = $profile->{resolver}{source4} // '<missing>';

        return $source4 eq '192.0.2.2';
      };

    check_success 'override resolver.source6',
      [ '--dump-profile', '--profile=t/usage.profile', '--sourceaddr6', '2001:db8::2' ], sub {
        my ( $profile ) = parse_json_stream( $_[0] );

        my $source6 = $profile->{resolver}{source6} // '<missing>';

        return $source6 eq '2001:db8::2';
      };

    check_success '--restore', [ "--restore=$PATH_NORMAL_DATAFILE", '--test=basic01', '--level=INFO', '--raw', '.' ],
      qr{B01_CHILD_FOUND};
};

done_testing;
