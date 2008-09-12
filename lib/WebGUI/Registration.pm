package WebGUI::Registration;

use strict;

use List::Util qw{ first };
use WebGUI::Pluggable;
use JSON qw{ encode_json decode_json };
use Data::Dumper;

#-------------------------------------------------------------------
sub completeStep {
    my $self    = shift;
    my $stepId  = shift;

    #### TODO: Actually set the step to completed
    my ($step) = grep { $_->{ stepId } eq $stepId } @{ $self->{ _steps } };
    $step->{ complete } = 1;

    # Update completed steps tracker
    $self->session->scratch->set( 'registration_completedSteps',
        encode_json( { 
            map     { $_->{ stepId   } => 1     } 
            grep    { $_->{ complete }          } 
                   @{ $self->{ _steps } }
        } )
    );
   
    $self->session->errorHandler->warn( 'CS: '. $self->session->scratch->get( 'registration_completedSteps' ) );
    # Since we've just completed this step getCurrentStep will return the next.
    return $self->getCurrentStep;
}

#-------------------------------------------------------------------
sub getCurrentStep {
    my $self = shift;

    my $registrationSteps = $self->{_steps};

    # Fetch configuration data 
    my $currentStep = first { $_->{complete} == 0 } @$registrationSteps;

    # If all step are complete return undef.
    return undef unless defined $currentStep;

    # Load registration step plugin
    my $plugin = eval { 
        WebGUI::Pluggable::instanciate( $currentStep->{namespace}, 'new', [
            $self->session,
            $currentStep->{ stepId },
        ]);
    };

    $self->session->errorHandler->warn( $@.$! );
    #### TODO: Catch exceptions;

    return $plugin;
}

#-------------------------------------------------------------------
sub new {
    my $class   = shift;
    my $session = shift;

    # TODO: Dit moet natuurlijk gewoon uit de db komen.
    my $registrationSteps = [ 
        { stepId => 'ab001', namespace => 'WebGUI::Registration::Step::StepOne'  },
        { stepId => 'ab002', namespace => 'WebGUI::Registration::Step::StepTwo'  },
    ];

    # Get the completed steps for the current user
    my $completedStepsJSON  = $session->scratch->get('registration_completedSteps') || '{ }';  #'{ "ab002" : "1" }';
    my $completedSteps      = decode_json( $completedStepsJSON );

$session->errorHandler->warn( 'new: '. $session->scratch->get( 'registration_completedSteps' ) );

    # Set complete status of steps
    $_->{ complete } = exists $completedSteps->{ $_->{stepId} } ? 1 : 0 for @{ $registrationSteps };

    $session->errorHandler->warn( Dumper( $registrationSteps ) );
        
    bless { _steps => $registrationSteps, _session => $session }, $class;
}

#-------------------------------------------------------------------
sub session {
    my $self    = shift;

    return $self->{_session};
}

#-------------------------------------------------------------------
sub www_edit {

}

#-------------------------------------------------------------------
sub www_editSave {

}

#-------------------------------------------------------------------
sub www_confirmregistrationData {

}

#-------------------------------------------------------------------
sub www_viewStep {
    my $self = shift;

    my $output;
    my $currentStep = $self->getCurrentStep;

    if ( defined $currentStep ) {
        $output = $currentStep->view . $currentStep->getStepForm->print;
    }
    else {
        # Completed last step succesfully.
            
        #### TODO: Dubbelchecken of alle stappen zijn gecomplete.
        $output = $self->www_confirmRegistrationData;
    }

    return $output;
}

#-------------------------------------------------------------------
sub www_viewStepSave {
    my $self    = shift;

    my $currentStep = $self->getCurrentStep;

    $currentStep->processStepFormData;

    if ( $currentStep->isComplete ) {
        my $nextStep = $self->completeStep( $currentStep->stepId );
    }


    return $self->www_viewStep;
}

1;
