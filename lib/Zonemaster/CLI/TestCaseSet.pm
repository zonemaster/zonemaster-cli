package Zonemaster::CLI::TestCaseSet;
use 5.014;
use strict;
use warnings;
use utf8;

sub parse_modifier_expr {
    my ( $class, $modifier_expr ) = @_;

    my @modifiers;
    for my $op_and_term ( split /(?=[+-])/, $modifier_expr ) {
        $op_and_term =~ /([+-]?)(.*)/;
        my ( $op, $term ) = ( $1, $2 );

        push @modifiers, ( $op, $term );
    }

    return @modifiers;
}

sub new {
    my ( $class, $initial_cases, %all_methods ) = @_;

    my $obj = {
        _cur_cases      => { map { $_ => 1 } @$initial_cases },
        _all_term_cases => _get_all_term_cases( \%all_methods ),
    };

    bless $obj, $class;

    return $obj;
}

sub apply_modifier {
    my ( $self, $op, $term ) = @_;

    my @cases = @{ $self->{_all_term_cases}{ lc $term } };

    if ( $op eq '' ) {
        $self->{_cur_cases} = {};
    }

    if ( $op eq '-' ) {
        for my $case ( @cases ) {
            delete $self->{_cur_cases}{$case};
        }
    }
    else {
        for my $case ( @cases ) {
            $self->{_cur_cases}{$case} = 1;
        }
    }

    return;
} ## end sub apply_modifier

sub to_list {
    my ( $self ) = @_;

    return sort keys %{ $self->{_cur_cases} };
}

sub _get_all_term_cases {
    my ( $all_methods ) = @_;

    my $terms = {};
    $terms->{all} = [];

    for my $module ( keys %$all_methods ) {
        $terms->{ lc $module } = [];
        for my $method ( @{ $all_methods->{$module} } ) {
            $terms->{ lc $method } = [$method];
            $terms->{ lc "$module/$method" } = [$method];
            push @{$terms->{ lc $module }}, $method;
            push @{$terms->{all}},          $method;
        }
    }

    return $terms;
}

1;
