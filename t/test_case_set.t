#!perl
use 5.14.2;
use utf8;
use warnings;
use Test::More;

use Log::Any::Test;
use Log::Any qw( $log );
use Test::Differences;
use Test::Exception;
use Zonemaster::Engine;
use Zonemaster::Engine::Profile;

use Zonemaster::CLI::TestCaseSet;

require Test::NoWarnings;

lives_ok {    # Make sure we get to print log messages in case of errors.
    subtest 'parse_modifier_expr' => sub {
        my @cases = (
            {
                name     => 'empty',
                expr     => '',
                expected => [],
            },
            {
                name     => 'absolute term',
                expr     => 'term',
                expected => [ '', 'term' ],
            },
            {
                name     => 'absolute additive',
                expr     => 'term',
                expected => [ '', 'term' ],
            },
            {
                name     => 'absolute subtractive',
                expr     => 'term',
                expected => [ '', 'term' ],
            },
            {
                name     => 'absolute multiple modifiers',
                expr     => 'term1+term2',
                expected => [ '', 'term1', '+', 'term2' ],
            },
            {
                name     => 'relative multiple modifiers',
                expr     => '-term1+term2',
                expected => [ '-', 'term1', '+', 'term2' ],
            },
        );
        for my $case ( @cases ) {
            subtest $case->{name} => sub {
                my @actual = Zonemaster::CLI::TestCaseSet->parse_modifier_expr( $case->{expr} );
                eq_or_diff \@actual, $case->{expected};
            };
        }
    };

    subtest 'new' => sub {
        my @cases = (
            {
                name               => 'empty',
                all_methods        => {},
                initial_test_cases => [],
                expect_ok          => {
                    terms   => ['all'],
                    methods => [],
                },
            },
            {
                name               => 'multiple test modules and test cases',
                all_methods        => { 'alpha' => [ 'bravo', 'charlie' ], 'delta' => ['echo'] },
                initial_test_cases => [ 'bravo', 'echo' ],
                expect_ok          => {
                    terms => [
                        'all',   'alpha',   'alpha/bravo', 'alpha/charlie',
                        'bravo', 'charlie', 'delta',       'delta/echo',
                        'echo'
                    ],
                    methods => [ 'bravo', 'echo' ],
                },
            },
            {
                name               => 'illegal test module name 1',
                all_methods        => { 'all' => [] },
                initial_test_cases => [],
                expect_err         => qr/must not be 'all'/i,
            },
            {
                name               => 'illegal test module name 2',
                all_methods        => { 'alpha/bravo' => [] },
                initial_test_cases => [],
                expect_err         => qr{contains forbidden character '/'}i,
            },
            {
                name               => 'illegal test case name 1',
                all_methods        => { 'alpha' => ['all'] },
                initial_test_cases => [],
                expect_err         => qr/must not be 'all'/i,
            },
            {
                name               => 'illegal test case name 2',
                all_methods        => { 'alpha' => ['bravo/charlie'] },
                initial_test_cases => [],
                expect_err         => qr{contains forbidden character '/'}i,
            },
            {
                name               => 'duplicate term 1',
                all_methods        => { 'alpha' => ['alpha'] },
                initial_test_cases => [],
                expect_err         => qr/same name/i,
            },
            {
                name               => 'duplicate term 2',
                all_methods        => { 'alpha' => [], 'bravo' => ['alpha'] },
                initial_test_cases => [],
                expect_err         => qr/same name/i,
            },
            {
                name               => 'duplicate term 3',
                all_methods        => { 'alpha' => [ 'bravo', 'bravo' ] },
                initial_test_cases => [],
                expect_err         => qr/same name/i,
            },
            {
                name               => 'duplicate term 4',
                all_methods        => { 'alpha' => ['bravo'], 'charlie' => ['bravo'] },
                initial_test_cases => [],
                expect_err         => qr/same name/i,
            },
            {
                name               => 'unrecognized test case 1',
                all_methods        => { 'alpha' => [] },
                initial_test_cases => ['all'],
                expect_err         => qr/unrecognized/i,
            },
            {
                name               => 'unrecognized test case 2',
                all_methods        => { 'alpha' => [] },
                initial_test_cases => ['alpha'],
                expect_err         => qr/unrecognized/i,
            },
        );
        for my $case ( @cases ) {
            subtest $case->{name} => sub {
                my $test_cases;
                local $@;
                eval {
                    $test_cases = Zonemaster::CLI::TestCaseSet->new(    #
                        $case->{initial_test_cases},
                        %{ $case->{all_methods} },
                    );
                };

                my $err = $@;
                my $actual;
                if ( !$err ) {
                    $actual = {
                        terms   => [ sort keys %{ $test_cases->{_all_term_methods} } ],
                        methods => [ $test_cases->to_list ],
                    };
                }

                if ( defined $case->{expect_err} ) {
                    like $err, $case->{expect_err}, "error";
                } else {
                    is $err, "", "no error";
                }
                if ( defined $case->{expect_ok} ) {
                    eq_or_diff $actual, $case->{expect_ok}, "result";
                } else {
                    eq_or_diff $actual, undef, "no result";
                }
            }; ## end sub
        } ## end for my $case ( @cases )
    }; ## end 'new' => sub

    subtest 'apply_modifier' => sub {
        my @cases = (
            {
                name               => 'empty',
                all_methods        => {},
                initial_test_cases => [],
                modifiers          => [],
                expected           => [],
            },
            {
                name               => 'no modifiers',
                all_methods        => { basic => [ 'basic01', 'basic02' ] },
                initial_test_cases => [ 'basic01' ],
                modifiers          => [],
                expected           => [ 'basic01' ],
            },
            {
                name               => 'add a new case',
                all_methods        => { basic => [ 'basic01', 'basic02' ] },
                initial_test_cases => [ 'basic01' ],
                modifiers          => [ '+', 'basic02' ],
                expected           => [ 'basic01', 'basic02' ],
            },
            {
                name               => 'add the same case',
                all_methods        => { basic => [ 'basic01', 'basic02' ] },
                initial_test_cases => [ 'basic01' ],
                modifiers          => [ '+', 'basic01' ],
                expected           => [ 'basic01' ],
            },
            {
                name               => 'replace',
                all_methods        => { basic => [ 'basic01', 'basic02' ] },
                initial_test_cases => [ 'basic01' ],
                modifiers          => [ '', 'basic02' ],
                expected           => [ 'basic02' ],
            },
            {
                name               => 'module expansion',
                all_methods        => { basic => [ 'basic01' ], extra => ['extra01', 'extra02'] },
                initial_test_cases => [ 'basic01' ],
                modifiers          => [ '', 'extra' ],
                expected           => [ 'extra01', 'extra02' ],
            },
            {
                name               => 'all',
                all_methods        => { basic => [ 'basic01' ], extra => ['extra01', 'extra02'] },
                initial_test_cases => [ 'basic01' ],
                modifiers          => [ '', 'all' ],
                expected           => [ 'basic01', 'extra01', 'extra02' ],
            },
            {
                name               => 'multiple modifiers',
                all_methods        => { basic => [ 'basic01' ], extra => ['extra01', 'extra02'] },
                initial_test_cases => [ 'basic01' ],
                modifiers          => [ '', 'all', '-', 'basic' ],
                expected           => [ 'extra01', 'extra02' ],
            },
        );
        for my $case ( @cases ) {
            subtest $case->{name} => sub {
                my $test_cases = Zonemaster::CLI::TestCaseSet->new(    #
                    $case->{initial_test_cases},
                    %{ $case->{all_methods} },
                );

                while ( @{ $case->{modifiers} } ) {
                    my $op   = shift @{ $case->{modifiers} };
                    my $term = shift @{ $case->{modifiers} };
                    $test_cases->apply_modifier( $op, $term );
                }

                eq_or_diff [ $test_cases->to_list ], $case->{expected};
            };
        }
    };
};

for my $msg ( @{ $log->msgs } ) {
    my $text = sprintf( "%s: %s", $msg->{level}, $msg->{message} );
    if ( $msg->{level} =~ /trace|debug|info|notice/ ) {
        note $text;
    }
    else {
        diag $text;
    }
}

Test::NoWarnings::had_no_warnings();
done_testing;
