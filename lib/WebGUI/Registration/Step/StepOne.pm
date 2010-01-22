package WebGUI::Registration::Step::StepOne;

use strict;

use base qw{ WebGUI::Registration::Step };

sub crud_definition {
    my $class       = shift;
    my $session     = shift;
    my $definition  = $class->SUPER::crud_definition( $session );

    $definition->{ dynamic }->{ defaultSetting } => {
        fieldType       => 'yesNo',
        label           => 'Default setting',
        defaultValue    => 0,
    };

    return $definition;
#    push @{ $definition }, {
#        name        => 'StepOne',
#        properties  => \%fields,
#        namespace   => 'WebGUI::Registration::Step::StepOne',
#    };
#
#    return $class->SUPER::definition( $session, $definition );
}


#-------------------------------------------------------------------
sub getStepForm {
    my $self    = shift;

    my $f = $self->SUPER::getStepForm;
    $f->yesNo(
        -name   => 'hopsa',
        -value  => 0,
        -label  => 'Compleet?',
    );
    $f->submit;

    return $f;
}

#-------------------------------------------------------------------
sub processStepFormData {
    my $self    = shift;

    my $proceed = $self->session->form->process('hopsa');

    $self->setConfigurationData('hopsa' => $proceed );
}

#-------------------------------------------------------------------
sub isComplete {
    my $self = shift;

    return $self->getConfigurationData->{ hopsa };
}

#-------------------------------------------------------------------
sub view {
    my $self = shift;

    return $self->getStepForm->print;
}

1;

