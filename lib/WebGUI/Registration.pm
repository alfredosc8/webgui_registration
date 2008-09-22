package WebGUI::Registration;

use strict;

use Class::InsideOut qw{ :std };
use List::Util qw{ first };
use List::MoreUtils qw{ any };
use WebGUI::Pluggable;
use JSON qw{ encode_json decode_json };
use Data::Dumper;
use WebGUI::Utility;

readonly session            => my %session;
readonly registrationId     => my %registrationId;
readonly registrationSteps  => my %registrationSteps;
readonly options            => my %options;

sub definition {
    my $class       = shift;
    my $session     = shift;
    my $definition  = shift;

    tie my %fields, 'Tie::IxHash', (
        title   => {
            fieldType   => 'text',
            label       => 'Title',
        },
        url     => {
            fieldType   => 'text',
            label       => 'URL',
        },
        styleTemplateId => {
            fieldType   => 'template',
            label       => 'Style',
            namespace   => 'style',
        },
        stepTemplateId  => {
            fieldType   => 'template', 
            label       => 'Step Template',
            namespace   => 'Registration/Step',
        },
        confirmationTemplateId  => {
            fieldType   => 'template',
            label       => 'Confirmation Template',
            namespace   => 'Registration/Confirm',
        },
        registrationCompleteTemplateId => {
            fieldType   => 'template',
            label       => 'Registration Complete Message',
            namespace   => 'Registration/CompleteMessage',
        },
    );

    push  @{ $definition }, {
        properties      => \%fields,
        tableName       => 'Registration',
    };

    return $definition;
};


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

    my $id                      = id $self;
    $session            { $id } = $session;
    $registrationId     { $id } = $registrationId;
    $registrationSteps  { $id } = $registrationSteps;
    $options            { $id } = $options;

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
sub get {
    my $self    = shift;
    my $key     = shift;

    if ( $key ) {
        if ( exists $self->options->{ $key } ) {
            return $self->options->{ $key };
        }
        else {
            #### TODO: throw exception.
            die "Unknown key in Registration->get";
        }
    }

    return { %{ $self->options } };
}

#-------------------------------------------------------------------
sub getCurrentUserId {
    my $self    = shift;

    return $self->session->user->userId;
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
    $f->dynamicForm( $self->definition( $session ), 'properties', $self );
    $f->submit;

    return $f;
}

#-------------------------------------------------------------------
sub getRegistrationStatus {
    my $self    = shift;
    my $session = shift;

    my $status  = $session->db->quickScalar(
        'select status from Registration_status where registrationId=? and userId=?', 
        [
            $self->registrationId,
            $self->getCurrentUserId,
        ]
    );

    return $status || 'setup';
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
    my $session = $self->session;

    my $formParam   = $session->form->paramsHashRef;
    my $data        = { };

    foreach my $definition ( @{ $self->definition( $session ) } ) {
        foreach my $key ( keys %{ $definition->{ properties } } ) {
            if ( exists $formParam->{ $key } ) {
                $data->{ $key } = $session->form->process(
                    $key,
                    $definition->{ properties }->{ $key }->{ fieldType      },
                    $definition->{ properties }->{ $key }->{ defaultValue   },
                );
            }
        }
    }

#    my $title                   = $form->process( 'title'           );
#    my $url                     = $form->process( 'url'             );
#    my $stepTemplateId          = $form->process( 'stepTemplateId'  );
#    my $styleTemplateId         = $form->process( 'styleTemplateId' );
#    my $confirmationTemplateId  = $form->process( 'confirmationTemplateId'  );
#    my $registrationCompleteTemplateId = $form->process( 'registrationCompleteTemplateId' );

    #### TODO: Als de url verandert de oude uit de urltrigger setting halen.

    $self->update( $data );

#    $self->update({
#        title                   => $title,
#        url                     => $url,
#        styleTemplateId         => $styleTemplateId,
#        stepTemplateId          => $stepTemplateId,
#        confirmationTemplateId  => $confirmationTemplateId,
#        registrationCompleteTemplateId => $registrationCompleteTemplateId,
#    });

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
    $urlTriggers->{ $data->{ url } }  = $self->registrationId;
    $self->session->setting->set( 'registrationUrlTriggers', encode_json( $urlTriggers ) );
}

#-------------------------------------------------------------------
sub processStyle {
    my $self    = shift;
    my $content = shift;

    my $styleTemplateId = $self->get('styleTemplateId');

    return $self->session->style->process( $content, $styleTemplateId );
}


#-------------------------------------------------------------------
sub setRegistrationStatus {
    my $self    = shift;
    my $status  = shift;
    my $session = $self->session;
    
    # Check whether a valid status is passed
    #### TODO: throw exception;
    die "wrong status [$status]" unless any { $status eq $_ } qw{ setup pending approved };

    # Write the status to the db
    $session->db->write('delete from Registration_status where registrationId=? and userId=?', [
        $self->registrationId,
        $self->getCurrentUserId,
    ]);
    $session->db->write('insert into Registration_status (status, registrationId, userId) values (?,?,?)', [
        $status,
        $self->registrationId,
        $self->getCurrentUserId,
    ]);
}

#-------------------------------------------------------------------
sub update {
    my $self    = shift;
    my $options = shift;
    my $session = shift;
    my $update  = {};

    foreach my $definition ( @{ $self->definition( $session ) } ) {
        foreach my $key ( keys %{ $definition->{ properties } } ) {
            next unless exists $options->{ $key };

            push @{ $update->{ $definition->{tableName} }->{ columns } }, $key;
            push @{ $update->{ $definition->{tableName} }->{ data    } }, $options->{ $key };
        }
    }
    
    foreach my $table ( keys %{ $update } ) {
        my $updateString = join ', ', map { "$_=?" } @{ $update->{ $table }->{ columns } };

        $self->session->db->write("update $table set $updateString where registrationId=?", [
            @{ $update->{ $table }->{ data } },
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

    my $template = WebGUI::Asset::Template->new( $session, $self->get('confirmationTemplateId') );
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

    $self->setRegistrationStatus( 'pending' );

    my $var = {};
    my $template    = WebGUI::Asset::Template->new( $session, $self->get('registrationCompleteTemplateId') );
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

    # Set site status
    $self->setRegistrationStatus( 'pending' );

    # Get current step
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

