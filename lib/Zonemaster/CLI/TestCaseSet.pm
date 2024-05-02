package Zonemaster::CLI::TestCaseSet;
use 5.014;
use warnings;
use utf8;

use Carp qw( croak );

=head1 NAME

    Zonemaster::CLI::TestCaseSet - A mutable set of test methods names.

=head1 SYNOPSIS

    use Zonemaster::Engine::TestCaseSet;

    # Construct a working subset of test methods {alpha01, alpha02, alpha03,
    # beta01} of test methods out of the full set {alpha01, alpha02, alpha03,
    # beta01, beta02} distributed across the test modules {alpha, beta}.
    my $working_set = Zonemaster::CLI::TestCaseSet->new(
        \qw( alpha01 alpha02 alpha03 beta01 ),
        {
            alpha => \qw( alpha01 alpha02 alpha03 ),
            beta  => \qw( beta01 beta02 ),
        },
    );

    # Parse a modifier expression into a list of modifiers.
    my @modifiers = Zonemaster::CLI::TestCaseSet->parse_modifier_expr( '-alpha+alpha02' );

    # Traverse the list of modifiers, chunked into (operator, term) pairs.
    while ( @modifiers ) {
        my $op   = shift @modifiers;
        my $term = shift @modifiers;

        # Modify the working subset by applying each operator and term.
        if ( !$working_set->apply_modifier( $op, $term ) ) {
            die "Error: Unrecognized term '$term'.\n";
        }
    }

    # Make sure the working subset ends up in the expected state.
    if ( join(' ', $working_set->to_list) ne 'alpha02 beta01' ) {
        die;
    }

=head1 DESCRIPTION

A TestCaseSet primarily represents an immutable full set of test methods and a
mutable subset thereof. The full set of test methods is distributed across the
set of test modules.

=head2 TERM EXPANSION

Terms are expanded in one of three ways.

=over 4

=item The full set of all test methods.

The term matching the string C<'all'>.

=item The set of all test methods inside one test module.

Terms matching the name of a test module.

=item The singleton set of a single test methods

Terms matching the name of a test methods or the concatenation of a test module,
a slash and a test methods belonging to that test module.

=back

Term names are matched case insensitively.

=head1 SUBROUTINES

=cut

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

=head1 CONSTRUCTORS

=head2 new()

In the full set of test methods, methods names must not share the same name as
other test methods or test modules.

=cut

sub new {
    my ( $class, $initial_methods, %all_methods ) = @_;

    my %flattened_methods = map { $_ => 1 } map { @{ $_ } } values %all_methods;
    for my $method ( @$initial_methods ) {
        if ( !exists $flattened_methods{$method} ) {
            croak "Unrecognized initial method '$method'";
        }
    }

    my $obj = {
        _cur_methods      => { map { $_ => 1 } @$initial_methods },
        _all_term_methods => _get_all_term_methods( \%all_methods ),
    };

    bless $obj, $class;

    return $obj;
}

=head1 INSTANCE METHODS

=head2 apply_modifier()

Update the working subset.

The given operator is applied to two operands and the result is assigned to the
working subset. The left hand side operand is the current value of the working
subset. The right hand side operand is calculated by L<expanding|/"TERM
EXPANSION"> the given term to a subset of test methods.

Three operators are supported.

=over 4

=item C<'+'>

Returns the union of the left and right hand side operands

=item C<'-'>

Returns the set difference of the left and right hand side operands

=item C<''>

Ignores the left hand side operand and returns the right hand side operand.

=back

Returns true if the operation is successful.

Returns false if the term could not be expanded.

Dies if the operator is not recognized.

=cut

sub apply_modifier {
    my ( $self, $op, $term ) = @_;

    my $methods_ref = $self->{_all_term_methods}{ lc $term };

    if ( !defined $methods_ref ) {
        return 0;
    }

    if ( $op eq '' ) {
        $self->{_cur_methods} = {};
        $op = '+';
    }

    if ( $op eq '-' ) {
        for my $method ( @$methods_ref ) {
            delete $self->{_cur_methods}{$method};
        }
    }
    elsif ( $op eq '+' ) {
        for my $method ( @$methods_ref ) {
            $self->{_cur_methods}{$method} = 1;
        }
    }
    else {
        croak "Unrecognized operator '$op'";
    }

    return 1;
} ## end sub apply_modifier

sub to_list {
    my ( $self ) = @_;

    return sort keys %{ $self->{_cur_methods} };
}

sub _get_all_term_methods {
    my ( $all_methods ) = @_;

    my $terms = {};
    $terms->{all} = [];

    for my $module ( keys %$all_methods ) {
        if ( lc $module eq 'all' ) {
            croak "module name must not be 'all'";
        }
        if ( $module =~ qr{/} ) {
            croak "module name contains forbidden character '/': '$module'";
        }
        if ( exists $terms->{ lc $module } ) {
            croak "found module with same name as another method or module: '$module'";
        }
        $terms->{ lc $module } = [];
        for my $method ( @{ $all_methods->{$module} } ) {
            if ( lc $method eq 'all' ) {
                croak "method name must not be 'all'";
            }
            if ( $method =~ qr{/} ) {
                croak "method name contains forbidden character '/': '$method'";
            }
            if ( exists $terms->{ lc $method } ) {
                croak "found method with same name as another method or module: '$method'";
            }
            $terms->{ lc $method } = [$method];
            $terms->{ lc "$module/$method" } = [$method];
            push @{ $terms->{ lc $module } }, $method;
            push @{ $terms->{all} },          $method;
        }
    } ## end for my $module ( keys %$all_methods)

    return $terms;
} ## end sub _get_all_term_methods

1;
