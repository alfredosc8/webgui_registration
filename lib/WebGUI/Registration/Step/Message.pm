package WebGUI::Registration::Step::Message;

use strict;

use WebGUI::Group;

use base qw{ WebGUI::Registration::Step };

#-------------------------------------------------------------------
sub isComplete {
    my $self    = shift;

    return exists $self->getConfigurationData->{ messageSeen };
}

#-------------------------------------------------------------------
sub isInvisible {
    return 1;
}

#-------------------------------------------------------------------
sub processStepFormData {
    my $self    = shift;

    $self->setConfigurationData( 'messageSeen', 1 );
}

1;

