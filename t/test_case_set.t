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
                name      => 'empty',
                schema    => {},
                selection => [],
                expect_ok => {
                    terms   => ['all'],
                    methods => [],
                },
            },
            {
                name      => 'multiple test modules and test cases',
                schema    => { 'alpha' => [ 'bravo', 'charlie' ], 'delta' => ['echo'] },
                selection => [ 'bravo', 'echo' ],
                expect_ok => {
                    terms => [
                        'all',   'alpha',   'alpha/bravo', 'alpha/charlie',
                        'bravo', 'charlie', 'delta',       'delta/echo',
                        'echo'
                    ],
                    methods => [ 'bravo', 'echo' ],
                },
            },
            {
                name      => 'mixed cases',
                schema    => { 'alpha' => [ 'BRAVO', 'charlie' ] },
                selection => [ 'bravo', 'CHARLIE' ],
                expect_ok => {
                    terms   => [ 'all',   'alpha', 'alpha/bravo', 'alpha/charlie', 'bravo', 'charlie' ],
                    methods => [ 'bravo', 'charlie' ],
                },
            },
            {
                name       => 'illegal test module name 1',
                schema     => { 'all' => [] },
                selection  => [],
                expect_err => qr/must not be 'all'/i,
            },
            {
                name       => 'illegal test module name 2',
                schema     => { 'ALL' => [] },
                selection  => [],
                expect_err => qr/must not be 'all'/i,
            },
            {
                name       => 'illegal test module name 3',
                schema     => { 'alpha/bravo' => [] },
                selection  => [],
                expect_err => qr{contains forbidden character '/'}i,
            },
            {
                name       => 'illegal test case name 1',
                schema     => { 'alpha' => ['all'] },
                selection  => [],
                expect_err => qr/must not be 'all'/i,
            },
            {
                name       => 'illegal test case name 2',
                schema     => { 'alpha' => ['ALL'] },
                selection  => [],
                expect_err => qr/must not be 'all'/i,
            },
            {
                name       => 'illegal test case name 3',
                schema     => { 'alpha' => ['bravo/charlie'] },
                selection  => [],
                expect_err => qr{contains forbidden character '/'}i,
            },
            {
                name       => 'duplicate term 1',
                schema     => { 'alpha' => ['alpha'] },
                selection  => [],
                expect_err => qr/same name/i,
            },
            {
                name       => 'duplicate term 2',
                schema     => { 'alpha' => ['ALPHA'] },
                selection  => [],
                expect_err => qr/same name/i,
            },
            {
                name       => 'duplicate term 3',
                schema     => { 'ALPHA' => ['alpha'] },
                selection  => [],
                expect_err => qr/same name/i,
            },
            {
                name       => 'duplicate term 4',
                schema     => { 'alpha' => [], 'bravo' => ['alpha'] },
                selection  => [],
                expect_err => qr/same name/i,
            },
            {
                name       => 'duplicate term 5',
                schema     => { 'alpha' => [ 'bravo', 'bravo' ] },
                selection  => [],
                expect_err => qr/same name/i,
            },
            {
                name       => 'duplicate term 6',
                schema     => { 'alpha' => ['bravo'], 'charlie' => ['bravo'] },
                selection  => [],
                expect_err => qr/same name/i,
            },
            {
                name       => 'unrecognized test case 1',
                schema     => { 'alpha' => [] },
                selection  => ['all'],
                expect_err => qr/unrecognized/i,
            },
            {
                name       => 'unrecognized test case 2',
                schema     => { 'alpha' => [] },
                selection  => ['alpha'],
                expect_err => qr/unrecognized/i,
            },
        );
        for my $case ( @cases ) {
            subtest $case->{name} => sub {
                my $test_case_set;
                local $@;
                eval {
                    $test_case_set = Zonemaster::CLI::TestCaseSet->new(    #
                        $case->{selection},
                        $case->{schema},
                    );
                };

                my $err = $@;
                my $actual;
                if ( !$err ) {
                    $actual = {
                        terms   => [ sort keys %{ $test_case_set->{_terms} } ],
                        methods => [ $test_case_set->to_list ],
                    };
                }

                if ( defined $case->{expect_err} ) {
                    like $err, $case->{expect_err}, "error";
                }
                else {
                    is $err, "", "no error";
                }
                if ( defined $case->{expect_ok} ) {
                    eq_or_diff $actual, $case->{expect_ok}, "result";
                }
                else {
                    eq_or_diff $actual, undef, "no result";
                }
            };    ## end sub
        } ## end for my $case ( @cases )
    };    ## end 'new' => sub

    subtest 'apply_modifier' => sub {
        my @cases = (
            {
                name      => 'empty',
                schema    => {},
                selection => [],
                modifiers => [],
                expected  => [],
            },
            {
                name      => 'no modifiers',
                schema    => { basic => [ 'basic01', 'basic02' ] },
                selection => ['basic01'],
                modifiers => [],
                expected  => ['basic01'],
            },
            {
                name      => 'add a new case',
                schema    => { basic => [ 'basic01', 'basic02' ] },
                selection => ['basic01'],
                modifiers => [ '+',       'basic02' ],
                expected  => [ 'basic01', 'basic02' ],
            },
            {
                name      => 'add the same case',
                schema    => { basic => [ 'basic01', 'basic02' ] },
                selection => ['basic01'],
                modifiers => [ '+', 'basic01' ],
                expected  => ['basic01'],
            },
            {
                name      => 'replace',
                schema    => { basic => [ 'basic01', 'basic02' ] },
                selection => ['basic01'],
                modifiers => [ '', 'basic02' ],
                expected  => ['basic02'],
            },
            {
                name      => 'module expansion',
                schema    => { basic => ['basic01'], extra => [ 'extra01', 'extra02' ] },
                selection => ['basic01'],
                modifiers => [ '',        'extra' ],
                expected  => [ 'extra01', 'extra02' ],
            },
            {
                name      => 'all',
                schema    => { basic => ['basic01'], extra => [ 'extra01', 'extra02' ] },
                selection => ['basic01'],
                modifiers => [ '', 'all' ],
                expected  => [ 'basic01', 'extra01', 'extra02' ],
            },
            {
                name      => 'multiple modifiers',
                schema    => { basic => ['basic01'], extra => [ 'extra01', 'extra02' ] },
                selection => ['basic01'],
                modifiers => [ '', 'all', '-', 'basic' ],
                expected  => [ 'extra01', 'extra02' ],
            },
            {
                name      => 'invalid operator',
                schema    => { basic => [ 'basic01', 'basic02' ] },
                selection => ['basic01'],
                modifiers => [ '*', 'basic02' ],
                error     => qr{unrecognized operator}i,
            },
        );
        for my $case ( @cases ) {
            subtest $case->{name} => sub {
                my $test_case_set = Zonemaster::CLI::TestCaseSet->new(    #
                    $case->{selection},
                    $case->{schema},
                );

                local $@ = '';
                eval {
                    while ( @{ $case->{modifiers} } ) {
                        my $op   = shift @{ $case->{modifiers} };
                        my $term = shift @{ $case->{modifiers} };
                        $test_case_set->apply_modifier( $op, $term );
                    }
                };
                my $error = $@;

                if ( exists $case->{expected} ) {
                    is $error, '';
                    eq_or_diff [ $test_case_set->to_list ], $case->{expected};
                }
                else {
                    like $error, $case->{error};
                }
            };
        } ## end for my $case ( @cases )
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
