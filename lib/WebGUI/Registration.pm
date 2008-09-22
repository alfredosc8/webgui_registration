package WebGUI::Registration;

use strict;

use Class::InsideOut qw{ :std };
use List::Util qw{ first };
use WebGUI::Pluggable;
use JSON qw{ encode_json decode_json };
use Data::Dumper;
use WebGUI::Utility;

readonly session                => my %session;
readonly registrationId         => my %registrationId;
readonly url                    => my %url;
readonly registrationSteps      => my %registrationSteps;
readonly styleTemplateId        => my %styleTemplateId;
readonly stepTemplateId         => my %stepTemplateId;
readonly confirmationTemplateId => my %confirmationTemplateId;
readonly registrationCompleteTemplateId => my %registrationCompleteTemplateId;
readonly title                  => my %title;

#-------------------------------------------------------------------
sub _buildObj {
    my $class           = shift;
    my $session         = shift;
    my $registrationId  = shift;
    my $options         = shift || { };
    my $self            = { };

    # --- Fetch registration steps from db ----------------------
    # TODO: Dit moet natuurlijk gewoon uit de db komen.
    
    my $registrationSteps = $session->db->buildArrayRefOfHashRefs(
        'select * from RegistrationStep where registrationId=? order by stepOrder',
        [
            $registrationId,
        ]
    );

#    my $registrationSteps = [ 
#        { stepId => 'ab001', namespace => 'WebGUI::Registration::Step::StepOne'  },
#        { stepId => 'ab002', namespace => 'WebGUI::Registration::Step::StepTwo'  },
#    ];

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

    my $id                                  = id $self;
    $session                        { $id } = $session;
    $registrationId                 { $id } = $registrationId;
    $url                            { $id } = $options->{ url };
    $styleTemplateId                { $id } = $options->{ styleTemplateId };
    $stepTemplateId                 { $id } = $options->{ stepTemplateId };
    $confirmationTemplateId         { $id } = $options->{ confirmationTemplateId };
    $registrationCompleteTemplateId { $id } = $options->{ registrationCompleteTemplateId };
    $title                          { $id } = $options->{ title };
    $registrationSteps              { $id } = $registrationSteps;

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
    #### TODO: getStep gebruiken
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
    $f->template(
        -name       => 'styleTemplateId',
        -value      => $self->styleTemplateId,
        -label      => 'Style',
        -namespace  => 'style',
    );
    $f->template(
        -name       => 'stepTemplateId',
        -value      => $self->stepTemplateId,
        -label      => 'Step Template',
        -namespace  => 'Registration/Step',
    );
    $f->template(
        -name       => 'confirmationTemplateId',
        -value      => $self->confirmationTemplateId,
        -label      => 'Confirmation Template',
        -namespace  => 'Registration/Confirm',
    );
    $f->template(
        -name       => 'registrationCompleteTemplateId',
        -value      => $self->registrationCompleteTemplateId,
        -label      => 'Registration Complete Message',
        -namespace  => 'Registration/CompleteMessage',
    );
    $f->submit;

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

    my $title                   = $form->process( 'title'           );
    my $url                     = $form->process( 'url'             );
    my $stepTemplateId          = $form->process( 'stepTemplateId'  );
    my $styleTemplateId         = $form->process( 'styleTemplateId' );
    my $confirmationTemplateId  = $form->process( 'confirmationTemplateId'  );
    my $registrationCompleteTemplateId = $form->process( 'registrationCompleteTemplateId' );

    #### TODO: Als de url verandert de oude uit de urltrigger setting halen.

    $self->update({
        title                   => $title,
        url                     => $url,
        styleTemplateId         => $styleTemplateId,
        stepTemplateId          => $stepTemplateId,
        confirmationTemplateId  => $confirmationTemplateId,
        registrationCompleteTemplateId => $registrationCompleteTemplateId,
    });

    # Fetch the urlTriggers setting
    my $urlTriggersJSON = $self->session->setting->get('registrationUrlTriggers');
    my $urlTriggers     = {};

    # Check whether or not the setting already exists
    if ( $urlTriggersJSON ) {
        # If so, decode the JSON string
        $urlTriggers    = decode_json( $urlTriggersJSON );
    }
    else {
        # If not, create the setting
        $self->session->setting->add( 'registrationUrlTriggers', '{}' );
    }

    # Add the url to the setting
    $urlTriggers->{ $url }  = $self->registrationId;
    $self->session->setting->set( 'registrationUrlTriggers', encode_json( $urlTriggers ) );
}

#-------------------------------------------------------------------
sub processStyle {
    my $self    = shift;
    my $content = shift;

    my $styleTemplateId = $self->styleTemplateId;

    return $self->session->style->process( $content, $styleTemplateId );
}

#-------------------------------------------------------------------
sub update {
    my $self    = shift;
    my $options = shift;

    my @available = qw{ title url stepTemplateId styleTemplateId confirmationTemplateId registrationCompleteTemplateId };
    foreach (keys %$options) {
    $self->session->errorHandler->warn("[[$_]][[".$options->{$_}."]]");
        next unless isIn( $_, @available );

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

    $session->errorHandler->warn("}{}{}{$@ $!}{}{}{") if $@;
    #### TODO: catch exception

    return $step->www_edit;
}

#-------------------------------------------------------------------
sub www_confirmRegistrationData {
    my $self    = shift;
    my $session = $self->session;
    
    my $steps           = WebGUI::Registration::Step->getStepsForRegistration( $session, $self->registrationId );
    my @categoryLoop    = ();

    foreach my $step ( @{ $steps } ) {
        push @categoryLoop, $step->getSummaryTemplateVars;
    }
    
    my $var = {
        category_loop   => \@categoryLoop,
        proceed_url     =>
            $session->url->page('registration=register;func=completeRegistration;registrationId='.$self->registrationId),
    };

    my $template = WebGUI::Asset::Template->new( $session, $self->confirmationTemplateId );
    return $self->processStyle( $template->process( $var ) );
}

#-------------------------------------------------------------------
sub www_completeRegistration {
    my $self    = shift;
    my $session = $self->session;

    #### TODO:Check registration complete

    #### TODO: Send Email
#    my $mailTemplate    = WebGUI::Asset::Template->new($self->session, $self->get('setupCompleteMailTemplate'));
#    my $mailBody        = $mailTemplate->process( {} );
#    my $mail            = WebGUI::Mail::Send->create($self->session, {
#        toUser      => $user->userId,
#        subject     => $self->get('setupCompleteMailSubject'),
#    });
#    $mail->addText($mailBody);
#    $mail->queue;

    #### TODO: registration status.
#    $self->setRegistrationStatus( 'pending' );

    my $var = {};
    my $template    = WebGUI::Asset::Template->new( $session, $self->registrationCompleteTemplateId );
    return $self->processStyle( $template->process($var) )
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
            . $session->icon->delete('registration=register;func=deleteStep;stepId='.$step->stepId.';registrationId='.$self->registrationId)
            . '<a href="'
            .   $session->url->page('registration=register;func=editStep;stepId='.$step->stepId.';registrationId='.$self->registrationId)
            . '">'
            . '[stap]'.$step->get( 'title' )
            . '</a></li>';       
    }

    my $availableSteps = {
        'WebGUI::Registration::Step::StepOne'       => 'StepOne',
        'WebGUI::Registration::Step::StepTwo'       => 'StepTwo',
        'WebGUI::Registration::Step::ProfileData'   => 'ProfileData',
        'WebGUI::Registration::Step::Homepage'      => 'Homepage',
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
sub www_deleteStep {
    my $self    = shift;

    my $stepId  = $self->session->form->process('stepId');

    $self->session->db->write('delete from RegistrationStep where stepId=?', [
        $stepId,
    ]);

    return $self->www_listSteps;
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

    return $step->www_edit;
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
sub www_viewStep {
    my $self = shift;

    my $output;
    my $currentStep = $self->getCurrentStep;

    if ( defined $currentStep ) {
        $output = $currentStep->www_view;
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

    # No more steps?
    return $self->www_viewStep unless $currentStep;

    $currentStep->processStepFormData;

    if ( $currentStep->isComplete ) {
        my $nextStep = $self->completeStep( $currentStep->stepId );
    }

    return $self->www_viewStep;
}

1;

