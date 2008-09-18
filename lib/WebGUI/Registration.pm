package WebGUI::Registration;

use strict;

use Class::InsideOut qw{ :std };
use List::Util qw{ first };
use WebGUI::Pluggable;
use JSON qw{ encode_json decode_json };
use Data::Dumper;
use WebGUI::Utility;

readonly session            => my %session;
readonly registrationId     => my %registrationId;
readonly url                => my %url;
readonly registrationSteps  => my %registrationSteps;
readonly templateId         => my %templateId;
readonly title              => my %title;

#-------------------------------------------------------------------
sub _buildObj {
    my $class           = shift;
    my $session         = shift;
    my $registrationId  = shift;
    my $options         = shift || { };
    my $self            = { };

    # --- Fetch registration steps from db ----------------------
    # TODO: Dit moet natuurlijk gewoon uit de db komen.
    my $registrationSteps = [ 
        { stepId => 'ab001', namespace => 'WebGUI::Registration::Step::StepOne'  },
        { stepId => 'ab002', namespace => 'WebGUI::Registration::Step::StepTwo'  },
    ];

    # Get the completed steps for the current user session
    my $completedStepsJSON  = $session->scratch->get('registration_completedSteps') || '{ }';  #'{ "ab002" : "1" }';
    my $completedSteps      = decode_json( $completedStepsJSON );

    # And apply those complete statuses to the steps in this Registration
    for my $step (@{ $registrationSteps }) {
        $step->{ complete } = exists $completedSteps->{ $step->{stepId} } 
                            ? 1 
                            : 0 
                            ;
    }


    # --- Setup InsideOut object --------------------------------
    bless       $self, $class;
    register    $self;

    my $id                      = id $self;
    $session            { $id } = $session;
    $registrationId     { $id } = $registrationId;
    $url                { $id } = $options->{ url };
    $templateId         { $id } = $options->{ templateId };
    $title              { $id } = $options->{ title };
    $registrationSteps  { $id } = $registrationSteps;

    return $self;
}

#-------------------------------------------------------------------
sub create {
    my $class   = shift;
    my $session = shift;
    my $id      = $session->id->generate;

    $session->db->write('insert into Registration set registrationId=?', [
        $id,
    ] );

    $session->errorHandler->warn("{{$id}}");
    return $class->new( $session, $id );
}
    

#-------------------------------------------------------------------
sub completeStep {
    my $self    = shift;
    my $stepId  = shift;

    #### TODO: Checken of de accessors gegenereerd door C::IO de values kopieren of niet.
    my ($step) = grep { $_->{ stepId } eq $stepId } @{ $self->registrationSteps } ;
    $step->{ complete } = 1;

    # Update completed steps tracker
    $self->session->scratch->set( 'registration_completedSteps',
        encode_json( { 
            map     { $_->{ stepId   } => 1     } 
            grep    { $_->{ complete }          } 
                   @{ $self->registrationSteps }
        } )
    );
   
    $self->session->errorHandler->warn( 'CS: '. $self->session->scratch->get( 'registration_completedSteps' ) );
    # Since we've just completed this step getCurrentStep will return the next.
    return $self->getCurrentStep;
}

#-------------------------------------------------------------------
sub getCurrentStep {
    my $self = shift;

    my $registrationSteps = $self->registrationSteps;

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
sub getEditForm {
    my $self    = shift;
    my $session = $self->session;

    my $f = WebGUI::HTMLForm->new( $session );
    $f->hidden(
        -name       => 'registration',
        -value      => 'register',
    );
    $f->hidden(
        -name       => 'func',
        -value      => 'editSave',
    );
    $f->hidden(
        -name       => 'registrationId',
        -value      => $self->registrationId,
    );
    $f->text(
        -name       => 'title',
        -value      => $self->title,
        -label      => 'Title',
    );
    $f->text(
        -name       => 'url',
        -value      => $self->url,
        -label      => 'URL',
    );
    $f->submit;

#    my $addStepForm = WebGUI::HTMLForm->new( $session );
#    $addStepForm->hidden(
#        -name       => 'registration',
#        -value      => 'addStep',
#    );
#    $addStepForm->selectBox(
#        -name       => "step",
#        -value      => '',
#        -label      => "Add step",
#        -options    => $availableSteps,
#    );
#    $addStepForm->submit( -value => 'Add step' );
# 


    return $f;
}

#-------------------------------------------------------------------
sub new {
    my $class           = shift;
    my $session         = shift;
    my $registrationId  = shift || die "No regid";

    my $options = $session->db->quickHashRef( 'select * from Registration where registrationId=?', [
        $registrationId,
    ]);

    my $self = $class->_buildObj( $session, $registrationId, $options );
    return $self;

#   bless { _steps => $registrationSteps, _session => $session }, $class;
}

#-------------------------------------------------------------------
sub processPropertiesFromFormPost {
    my $self    = shift;
    my $form    = $self->session->form;

    my $title   = $form->process( 'title'  );
    my $url     = $form->process( 'url'    );

    $self->update({
        title   => $title,
        url     => $url,
    });
}

#-------------------------------------------------------------------
sub update {
    my $self    = shift;
    my $options = shift;

    my @available = qw{ title url };
    foreach (keys %$options) {
    $self->session->errorHandler->warn("[[$_]][[".$options->{$_}."]]");
        next unless isIn( $_, @available );
$self->session->errorHandler->warn("hopsa");
        #### TODO: Dit performed natuurlijk niet, maar dat is ook niet echt erg
        $self->session->db->write("update Registration set $_=? where registrationId=?", [
            $options->{ $_ },
            $self->registrationId,
        ] );

        #### TODO: Update state in object.
    }
}

#-------------------------------------------------------------------
#sub session {
#    my $self    = shift;
#
#
#
#    return $self->{_session};
#}

#-------------------------------------------------------------------
sub www_addStep {
    my $self    = shift;
    my $session = $self->session;

    #### TODO: Auth

    my $namespace = $session->form->process( 'namespace' );
    return "Illegal namespace [$namespace]" unless $namespace =~ /^[\w\d\:]+$/;

    my $step = eval {
        WebGUI::Pluggable::instanciate( $namespace, 'create', [
            $session,
            $self
        ] );
    };

    #### TODO: catch exception

    return $step->getEditForm->print;
}

#-------------------------------------------------------------------
sub www_listSteps {
    my $self    = shift;
    my $session = $self->session;

#    my @stepIds = $self->session->db->buildArray( 
#        'select stepId from RegistrationStep where registrationId=? order by stepOrder', 
#        [
#            $self->registrationId,
#        ]
#    );
#    my @steps = map { WebGUI::Registration::Step->newByDynamicClass( $session, $_ ) } @stepIds;

    my $steps = WebGUI::Registration::Step->getStepsForRegistration( $session, $self->registrationId );

    my $output = '<ul>';
    foreach my $step ( @{ $steps } ) {
        $output .= '<li>'
            . '<a href="'
            .   $session->url->page('registration=register;func=editStep;stepId='.$step->stepId.';registrationId='.$self->registrationId)
            . '">'
            . '[stap]'.$step->get( 'title' )
            . '</a></li>';       
    }

    my $availableSteps = {
        'WebGUI::Registration::Step::StepOne'   => 'StepOne',
        'WebGUI::Registration::Step::StepTwo'   => 'StepTwo',
    };
    my $addForm = 
          WebGUI::Form::formHeader( $session )
        . WebGUI::Form::hidden(     $session, { -name => 'registration',    -value => 'register'            } )
        . WebGUI::Form::hidden(     $session, { -name => 'func',            -value => 'addStep'             } )
        . WebGUI::Form::hidden(     $session, { -name => 'registrationId',  -value => $self->registrationId } )
        . WebGUI::Form::selectBox(  $session, { -name => 'namespace',       -options => $availableSteps     } )
        . WebGUI::Form::submit(     $session, {                             -value => 'Add step'            } )
        . WebGUI::Form::formFooter( $session );


    $output .= "<li>$addForm</li>";

    return $output;
}

#-------------------------------------------------------------------
sub www_edit {
    my $self    = shift;

    return $self->getEditForm->print;
}

#-------------------------------------------------------------------
sub www_editSave {
    my $self    = shift;

    $self->processPropertiesFromFormPost;

    return WebGUI::Registration::Admin::www_view( $self->session );
}

#-------------------------------------------------------------------
#### TODO: Hier een do-method van maken?
sub www_editStep {
    my $self    = shift;
    my $session = $self->session;

    my $stepId  = $session->form->process('stepId');
    my $step    = WebGUI::Registration::Step->getStep( $session, $stepId );

    return $step->getEditForm->print;
}

#-------------------------------------------------------------------
#### TODO: Hier een do-method van maken?
sub www_editStepSave {
    my $self    = shift;
    my $session = $self->session;

    my $stepId  = $session->form->process('stepId');
    my $step    = WebGUI::Registration::Step->getStep( $session, $stepId );

    $step->processPropertiesFromFormPost;

    return $self->www_listSteps;
}

#-------------------------------------------------------------------
sub www_do {
    my $self    = shift;
    my $session = shift;
    
    #### TODO: Auth

    my $method  = 'www_' . $session->form->process('do');
    my $stepId  = $session->form->process('stepId');

    return "Illegal method [$method]" unless $method =~ /^[\w_]+$/;

    my $step = eval {
        WebGUI::Registration::Step->newByDynamicClass( $session, $stepId );
    };

    return "Unable to do method [$method]" unless $step->can( $method );

    return $step->$method();
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

