package WebGUI::Registration::Step::StepTwo;

use strict;

use base qw{ WebGUI::Registration::Step };

#-------------------------------------------------------------------
sub definition {
    my $class       = shift;
    my $session     = shift;
    my $definition  = shift;

    push @{ $definition }, {
        name        => 'StepTwo',
        properties  => { },
        namespace   => 'WebGUI::Registration::Step::StepTwo',
    };

    return $class->SUPER::definition( $session, $definition );
}

#-------------------------------------------------------------------
sub isComplete {
    return 0;
}

#-------------------------------------------------------------------
sub view {
    return 'Step 2';
}

1;

