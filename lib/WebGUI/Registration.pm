package WebGUI::Registration;

use strict;

use List::Util;
use WebGUI::Pluggable;
use JSON;
use Data::Dumper;

#-------------------------------------------------------------------
sub completeStep {
    my $self    = shift;
    my $stepId  = shift;

    #### TODO: Actually set the step to completed
    
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
            $currentStep->{ id },
        ]);
    };

    #### TODO: Catch exceptions;

    return $plugin;
}

#-------------------------------------------------------------------
sub new {
    my $class   = shift;
    my $session = shift;

    # TODO: Dit moet natuurlijk gewoon uit de db komen.
    my $registrationSteps = [ 
        { id => 'ab001', namespace => 'WebGUI::Registration::Step::ProfileData'  },
        { id => 'ab002', namespace => 'WebGUI::Registration::Step::UserHomepage' },
    ];

    # Get the completed steps for the current user
    my $completedStepsJSON  = $session->scratch->get('registration_completedSteps') || '{ "ab002" : "1" }';
    my $completedSteps      = decode_json( $completedStepsJSON );

    # Set complete status of steps
    $_->{ complete } = exists $completedSteps->{ $_->{id} } ? 1 : 0 for @{ $registrationSteps };

    $session->errorHandler->warn( Dumper( $registrationSteps ) );
        
    bless { _steps => $registrationSteps }, $class;
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
sub www_register {
    my $self = shift;

    my $output;
    my $currentStep = $self->getCurrentStep;

    $currentStep->processFormPost;

    if ( $currentStep->complete ) {
        my $nextStep = $self->completeStep( $currentStep->getId );

        if ( defined $nextStep ) {
            $output = $nextStep->getRegistrationForm;
        }
        else {
            # Completed last step succesfully.
            
            #### TODO: Dubbelchecken of alle stappen zijn gecomplete.
            $output = $self->www_confirmRegistrationData;
        }
    }
    else {
        $output = $currentStep->getRegistrationForm;
    }

    return $output;
}

1;

