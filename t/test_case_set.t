#!perl
use 5.14.2;
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
