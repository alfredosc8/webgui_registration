package WebGUI::Registration::Step::StepTwo;

use strict;

use base qw{ WebGUI::Registration::Step };

#-------------------------------------------------------------------
sub isComplete {
    return 0;
}

#-------------------------------------------------------------------
sub view {
    return 'Step 2';
}

1;

