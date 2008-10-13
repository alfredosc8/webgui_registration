package WebGUI::Registration::Step::Message;

use strict;

use WebGUI::Group;

use base qw{ WebGUI::Registration::Step };

#-------------------------------------------------------------------
sub definition {
    my $class       = shift;
    my $session     = shift;
    my $definition  = shift;

    push @{ $definition }, {
        name        => 'Message',
        properties  => {},
        namespace   => 'WebGUI::Registration::Step::Message',
    };

    return $class->SUPER::definition( $session, $definition ); 
}

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

