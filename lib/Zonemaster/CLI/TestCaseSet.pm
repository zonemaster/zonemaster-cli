package Zonemaster::CLI::TestCaseSet;
use 5.014;
use warnings;
use utf8;

use Carp qw( croak );

=head1 NAME

    Zonemaster::CLI::TestCaseSet - Manage and modify Zonemaster test case selections

=head1 SYNOPSIS

    use Zonemaster::CLI::TestCaseSet;

    # Define the names of the available test modules and their test cases
    my $schema = {
        alpha => [qw( alpha01 alpha02 alpha03 )],
        beta  => [qw( beta01 beta02 )],
    };

    # Construct an initial selection of test cases
    my $selection = Zonemaster::CLI::TestCaseSet->new(
        [qw( alpha01 alpha02 alpha03 beta01 )],
        $schema,
    );

    # Parse and apply a modifier expression
    my @modifiers = Zonemaster::CLI::TestCaseSet->parse_modifier_expr( '-alpha+alpha02' );
    while ( @modifiers ) {
        my ( $op, $term ) = splice @modifiers, 0, 2;
        $selection->apply_modifier( $op, $term )
          or die "Error: Unrecognized term '$term'.\n";
    }

    # Output final test case selection
    print join( ' ', $selection->to_list );    # alpha02 beta01

=head1 DESCRIPTION

Zonemaster::CLI::TestCaseSet represents a mutable selection of test cases,
together with an immutable schema defining available test modules and their
associated test cases.

The schema is defined as a mapping of test module names to their associated test
case names.

The selection can be adjusted using modifier expressions.

=head2 MODIFIER EXPRESSIONS

A modifier expression describes a change to the current selection.
Expressions combine terms using operators, e.g., C<'-alpha+alpha02'>.

These operators are supported:

=over 4

=item C<'+'> (union)

Add test cases to the current selection.
The set of test cases to add is the expansion of C<$term>.

=item C<'-'> (difference)

Remove test cases from the current selection.
The set of test cases to remove is the expansion of C<$term>.

=item C<''> (replace)

Replace the current selection.
The new selection is the set of test cases expanded from C<$term>.

=back

Terms expand into sets of test cases in one of three ways:

=over 4

=item C<all>

Expands to all available test cases defined by the schema.

=item Test module name

Expands to all test cases associated with the test module.

=item Test case name

Expands directly to the specified test case itself.
Test cases may be specified plainly (e.g., C<Case10>) or fully qualified
(module/testcase, e.g., C<Case/Case10>).

=back

Term matching is case-insensitive.

=cut

=head1 CONSTRUCTORS

=head2 new( $selection, $schema )

Construct a new TestCaseSet object.

=over 4

=item C<$selection> (arrayref)

Initial selection of test case names.

=item C<$schema> (hashref)

A hash mapping test module names to arrays of their associated test case names.

=back

Dies if:
- Any test case name in C<$schema> is repeated.
- C<$selection> contains names not found in C<$schema>.

=cut

sub new {
    my ( $class, $selection, $schema ) = @_;

    my %cases = map { lc $_ => 1 } map { @{$_} } values %$schema;
    for my $case ( @$selection ) {
        if ( !exists $cases{ lc $case } ) {
            croak "Unrecognized initial test case '$case'";
        }
    }

    my $obj = {
        _selection => { map { lc $_ => 1 } @$selection },
        _terms     => _get_schema_terms( $schema ),
    };

    bless $obj, $class;

    return $obj;
}

=head1 CLASS METHODS

parse_modifier_expr( $modifier_expr )

Parse a string containing a modifier expression and returns a list of
alternating operators and terms.

The returned list always starts with an operator.

For example, parsing C<'-alpha+beta02'> returns:

    ('-', 'alpha', '+', 'beta02')

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

=head1 INSTANCE METHODS

=head2 apply_modifier( $operator, $term )

Update the selection using the given operator and term.

Returns true if successful, or false if the term could not be expanded based on
the schema.

Dies if the operator is invalid.

=head3 Example:

    $selection->apply_modifier('+', 'beta') 
        or die "Unrecognized term";

=cut

sub apply_modifier {
    my ( $self, $op, $term ) = @_;

    my $cases_ref = $self->{_terms}{ lc $term };

    if ( !defined $cases_ref ) {
        return 0;
    }

    if ( $op eq '' ) {
        $self->{_selection} = {};
        $op = '+';
    }

    if ( $op eq '-' ) {
        for my $case ( @$cases_ref ) {
            delete $self->{_selection}{$case};
        }
    }
    elsif ( $op eq '+' ) {
        for my $case ( @$cases_ref ) {
            $self->{_selection}{$case} = 1;
        }
    }
    else {
        croak "Unrecognized operator '$op'";
    }

    return 1;
} ## end sub apply_modifier

=head2 to_list

Return a lowercase list of the currently selected test case names.

=cut

sub to_list {
    my ( $self ) = @_;

    return sort keys %{ $self->{_selection} };
}

sub _get_schema_terms {
    my ( $schema ) = @_;

    my $terms = {};
    $terms->{all} = [];

    for my $module ( keys %$schema ) {
        if ( lc $module eq 'all' ) {
            croak "test module name must not be 'all'";
        }
        if ( $module =~ qr{/} ) {
            croak "test module name contains forbidden character '/': '$module'";
        }
        if ( exists $terms->{ lc $module } ) {
            croak "found test module with same name as another test case or test module: '$module'";
        }
        $terms->{ lc $module } = [];
        for my $case ( @{ $schema->{$module} } ) {
            if ( lc $case eq 'all' ) {
                croak "test case name must not be 'all'";
            }
            if ( $case =~ qr{/} ) {
                croak "test case name contains forbidden character '/': '$case'";
            }
            if ( exists $terms->{ lc $case } ) {
                croak "found test case with same name as another test case or test module: '$case'";
            }
            $terms->{ lc $case } = [$case];
            $terms->{ lc "$module/$case" } = [$case];
            push @{ $terms->{ lc $module } }, $case;
            push @{ $terms->{all} },          $case;
        }
    } ## end for my $module ( keys %$schema)

    return $terms;
} ## end sub _get_schema_terms

1;
