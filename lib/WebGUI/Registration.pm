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
public   user               => my %user;

#-------------------------------------------------------------------
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
        countLoginAsStep => {
            fieldType   => 'yesNo',
            label       => 'Count login as step?',
        },
        loginTitle => {
            fieldType   => 'text',
            label       => 'Login title',
        },
        countConfirmationAsStep => {
            fieldType   => 'yesNo',
            label       => 'Count confirmation as step?',
        },
        confirmationTitle => {
            fieldType   => 'text',
            -label      => 'Confirmation title',
        },
        registrationManagersGroupId => {
            fieldType   => 'group',
            label       => 'Group to manage this registration',
        },
        notificationGroupId => {
            fieldType   => 'group',
            label       => 'Group to notify when pending accounts are created.',
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
        noValidUserTemplateId   => {
            fieldType   => 'template',
            label       => 'No valid user template',
            namespace   => 'Registration/NoValidUser',
        },
        setupCompleteMailSubject => {
            fieldType   => 'text',
            tab         => 'display',
            label       => 'Setup complete notification email subject',
        },
        setupCompleteMailTemplateId => {
            fieldType   => 'template',
            namespace   => 'Registration/CompleteMail',
            tab         => 'display',
            label       => 'Registration complete notification email template',
        },
        siteApprovalMailSubject => {
            fieldType   => 'text',
            tab         => 'display',
            label       => 'Site approval nofication mail subject',
        },
        siteApprovalMailTemplateId => {
            fieldType   => 'template',
            namespace   => 'Registration/ApprovalMail',
            tab         => 'display',
            label       => 'Site approval nofication mail template',
        },
        newAccountWorkflowId => {
            fieldType           => 'workflow',
            type                => 'WebGUI::User',
            none                => 1,
            tab                 => 'security',
            label               => 'Run workflow on account creation',
        },
        removeAccountWorkflowId => {
            fieldType           => 'workflow',
            type                => 'WebGUI::User',
            includeRealtime     => 1,
            none                => 1,
            tab                 => 'security',
            label               => 'Run workflow on account removal',
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
    my $userId          = shift || $session->user->userId,
    my $self            = { };

    # --- Fetch registration steps from db ----------------------
    # TODO: Dit kan wel weg denk ik. Functionaliteit zit nu in getSteps.
    my $registrationSteps = $session->db->buildArrayRefOfHashRefs(
        'select * from RegistrationStep where registrationId=? order by stepOrder',
        [
            $registrationId,
        ]
    );

    # TODO: Check whether userId exists.
    $userId = 1 if $userId eq 'new';
    my $user = WebGUI::User->new( $session, $userId );

    # --- Setup InsideOut object --------------------------------
    bless       $self, $class;
    register    $self;

    my $id                      = id $self;
    $session            { $id } = $session;
    $registrationId     { $id } = $registrationId;
    $registrationSteps  { $id } = $registrationSteps;
    $options            { $id } = $options;
    $user               { $id } = $user;

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

    return $class->new( $session, $id );
}

#-------------------------------------------------------------------
sub delete {
    my $self    = shift;
    my $db      = $self->session->db;

    # Clean up RegistrationStep_accountData
    $db->write(
          ' delete from RegistrationStep_accountData'
        . ' where stepId in (select stepId from RegistrationStep where registrationId=?)',
        [
            $self->registrationId,
        ],
    );

    # Clean up RegistrationStep
    $db->write( 'delete from RegistrationStep where registrationId=?', [
        $self->registrationId,
    ]);

    # Clean up Registration_status
    $db->write( 'delete from Registration_status where registrationId=?', [
        $self->registrationId,
    ]);

    # Clean up Registration
    $db->write( 'delete from Registration where registrationId=?', [
        $self->registrationId,
    ]);

    my $urlTriggersJSON = $self->session->setting->get('registrationUrlTriggers');
    my $urlTriggers     = decode_json( $urlTriggersJSON );
    delete $urlTriggers->{ $self->get('url') };
    $self->session->setting->set('registrationUrlTriggers', encode_json( $urlTriggers ) );

    $self->DESTROY;
}

#-------------------------------------------------------------------
sub getCurrentStep {
    my $self    = shift;
    my $session = $self->session;

    my @registrationStepIds =  map { $_->{stepId} } @{ $self->registrationSteps };
    my $overrideStepId      =  $session->scratch->get( 'overrideStepId' );

    # Return override step only if it is also part of this registration.
    if ( $overrideStepId && isIn( $overrideStepId, @registrationStepIds ) ) {
        return $self->getStep( $overrideStepId );
    }

    # Find first incomplete step and return it
    foreach my $stepId ( @registrationStepIds ) {
        # TODO: Catch exception.
        my $step = $self->getStep( $stepId );

        return $step unless $step->isComplete;
    }

    # All steps are complete, return undef.
    return undef;
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
            die "Unknown key in Registration->get [$key]";
        }
    }

    return { %{ $self->options } };
}

#-------------------------------------------------------------------
sub getEditForm {
    my $self    = shift;
    my $session = $self->session;

    my $f = WebGUI::HTMLForm->new( $session );
    $f->hidden(
        -name       => 'registration',
        -value      => 'admin',
    );
    $f->hidden(
        -name       => 'func',
        -value      => 'editRegistrationSave',
    );
    $f->hidden(
        -name       => 'registrationId',
        -value      => $self->registrationId,
    );
    $f->readOnly(
        -label      => 'Registration id',
        -value      => $self->registrationId,
    );
    $f->dynamicForm( $self->definition( $session ), 'properties', $self );
    $f->submit;

    return $f;
}

#-------------------------------------------------------------------
sub getStepStatus {
    my $self    = shift;
    my $session = $self->session;

    my @steps       = @{ $self->getSteps };
    my $currentStep = $self->getCurrentStep;
    my @stepStatus;
    my $stepCounter = 1;

    # Add login step
    if ($self->get('countLoginAsStep')) {
        push @stepStatus, {
            stepName            => $self->get('loginTitle'),
            stepComplete        => $session->user->userId ne '1',
            isCurrentStep       => $session->user->userId eq '1',
            stepNumber          => $stepCounter,
            substep_loop        => [],
        };
        $stepCounter++
    }

    # Add registration steps
    foreach my $step (@steps) {
        next if $step->isInvisible;

        my $substeps = $step->getSubstepStatus;

        if ($step->get('countStep') || !@stepStatus ) {
            push @stepStatus, {
                stepName            => $step->get('title'),
                stepComplete        => $step->isComplete,
                isCurrentStep       => $currentStep ? $currentStep->stepId eq $step->stepId : 0,
                stepNumber          => $stepCounter,
                substep_loop        => $step->getSubstepStatus,
            };
            $stepCounter++
        }
        else {
            push @{ $stepStatus[-1]->{ substep_loop } }, {
               substepName          => $step->get('title'),
               substepComplete      => $step->isComplete,
               isCurrentSubstep     => $currentStep ? $currentStep->stepId eq $step->stepId : 0,
            };
        }    
    }

    # Add confirmation step
    if ($self->get('countConfirmationAsStep')) {
        push @stepStatus, {
            stepName            => $self->get('confirmationTitle'),
            stepComplete        => $session->user->userId ne '1',
            isCurrentStep       => $session->user->userId eq '1',
            stepNumber          => $stepCounter,
            substep_loop        => [],
        };
        $stepCounter++
    }


    return \@stepStatus;
}

#-------------------------------------------------------------------
sub getRegistrationStatus {
    my $self    = shift;
    my $session = $self->session;

    my $status  = $session->db->quickScalar(
        'select status from Registration_status where registrationId=? and userId=?', 
        [
            $self->registrationId,
            $self->user->userId,
        ]
    );

    return $status || 'setup';
}

#-------------------------------------------------------------------
sub getStep {
    my $self    = shift;
    my $stepId  = shift;

    my $step    = WebGUI::Registration::Step->newByDynamicClass( $self->session, $stepId, $self );

    return $step;
}

#-------------------------------------------------------------------
sub getSteps {
    my $self    = shift;
    
    my @steps;
    my @stepIds = $self->session->db->buildArray(
        'select stepId from RegistrationStep where registrationId=? order by stepOrder',
        [
            $self->registrationId,
        ]
    );

    foreach my $stepId (@stepIds) {
        my $step = $self->getStep( $stepId );
        push @steps, $step;
    }

    return \@steps;
}

#-------------------------------------------------------------------
sub hasValidUser {
    my $self    = shift;

    # Site status checken
    # ie. not pending or complete
    return 0 unless $self->getRegistrationStatus eq 'setup';

    # If a user has been loaded into the Registration that is not a visitor, return true.
    return $self->user && $self->user->userId ne '1';
}

#-------------------------------------------------------------------
sub new {
    my $class           = shift;
    my $session         = shift;
    my $registrationId  = shift || die "No regid";
    my $userId          = shift || $session->user->userId;

    my $options = $session->db->quickHashRef( 'select * from Registration where registrationId=?', [
        $registrationId,
    ]);

    my $self = $class->_buildObj( $session, $registrationId, $options, $userId );
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

    #### TODO: Als de url verandert de oude uit de urltrigger setting halen.

    $self->update( $data );

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

    # Remove the current url from the url trigger setting
    delete $urlTriggers->{ $self->get('url') };

    # And add the new url to the setting
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
sub registrationComplete {
    my $self = shift;

    return $self->getRegistrationStatus ne 'setup';
}

#-------------------------------------------------------------------
sub registrationStepsComplete {
    my $self    = shift;

    my $currentStep = $self->getCurrentStep;

    # If current step is undef all steps and thus the registration is complete.
    return 1 unless defined $currentStep;

    # If it is defined, not all steps are not complete yet.
    return 0;
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
        $self->user->userId,
    ]);
    $session->db->write('insert into Registration_status (status, registrationId, userId) values (?,?,?)', [
        $status,
        $self->registrationId,
        $self->user->userId,
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
sub www_changeStep {
    my $self    = shift;
    my $session = $self->session;

    my $allStepsComplete    = ( defined $self->getCurrentStep ) ? 0 : 1;
    my $stepId              = $session->form->process( 'stepId' );

    if ($allStepsComplete && $stepId) {
        $session->scratch->set( 'overrideStepId', $stepId );
    }

    return $self->www_viewStep;
}

#-------------------------------------------------------------------
sub www_confirmRegistrationData {
    my $self    = shift;
    my $session = $self->session;

    # If the registration process has been completed display a message stating that.
    return $self->www_registrationComplete if $self->registrationComplete;

    # Check whether the user is allowed to register.
    return $session->privilege->noAccess unless $self->hasValidUser;

    # If not all steps are completed yet, go to the step form
    return $self->www_viewStep unless $self->registrationStepsComplete;

    my $steps           = $self->getSteps;
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

    # If the registration process has been completed display a message stating that.
    return $self->www_registrationComplete if $self->registrationComplete;

    # Check whether the user is allowed to register.
    return $self->www_noValidUser unless $self->hasValidUser;

    # If not all steps are completed yet, go to the step form
    return $self->www_viewStep unless $self->registrationStepsComplete;

    # Send email to user 
    my $mailTemplate    = WebGUI::Asset::Template->new($self->session, $self->get('setupCompleteMailTemplateId'));
    my $mailBody        = $mailTemplate->process( {} );
    my $mail            = WebGUI::Mail::Send->create( $self->session, {
        toUser      => $self->user->userId,
        subject     => $self->get('setupCompleteMailSubject'),
    });
    $mail->addText($mailBody);
    $mail->queue;

    # Send email to managers
    if ($self->get('notificationGroupId')) {
        my $mail            = WebGUI::Mail::Send->create( $self->session, {
            toGroup     => $self->get('notificationGroupId'),
            subject     => 'Een nieuwe accountaanvraag is ingediend',
        });
        $mail->addText(
            'Een account staat klaar om gecontroleerd te worden op: '
            . $self->session->url->getSiteURL . $self->session->url->gateway(
                '',
                'registration=admin;func=editRegistrationInstanceData;userId='.$self->user->userId.';registrationId='.$self->registrationId
            )
        );
        $mail->queue;
    }

    $self->setRegistrationStatus( 'pending' );

    my $var = {};
    my $template    = WebGUI::Asset::Template->new( $session, $self->get('registrationCompleteTemplateId') );
    return $self->processStyle( $template->process($var) )
}

#-------------------------------------------------------------------
sub www_createAccount {
    my $self    = shift;
    my $session = $self->session;

#### TODO: De redirect hoeft denk ik niet meer
    $self->session->scratch->set('redirectAfterLogin', $session->url->page('func=viewStep'));

    # Cannot use WG::Op::www_auth b/c the user style is hard coded in there...
    return $self->processStyle( WebGUI::Auth::WebGUI->new( $session )->createAccount );
    return WebGUI::Operation::Auth::www_auth( $session, 'createAccount' );
}


#-------------------------------------------------------------------
sub www_login {
    my $self    = shift;
    my $session = $self->session;

#### TODO: De redirect hoeft denk ik niet meer
    $session->scratch->set('redirectAfterLogin', $session->url->page('func=viewStep'));

    # Cannot use WG::Op::www_auth b/c the user style is hardcoded...
    return $self->processStyle( WebGUI::Auth::WebGUI->new($session)->init );
    return WebGUI::Operation::Auth::www_auth($session, 'init');
}

#-------------------------------------------------------------------
sub www_noValidUser {
    my $self    = shift;
    my $session = $self->session;
    
    if ($self->hasValidUser || $self->user->userId eq '1') {
        # Set site status flag to setup
        $self->setRegistrationStatus('setup');
    }
    else {
        return $self->processStyle('U heeft al een website aangemaakt of uw gegevens worden nog gecontroleerd.');
    }

    # If user is Visitor he'll have to log in. Make sure that he's redirected to the correct place after doing
    # that.
    if ($session->user->userId eq '1') {
        $session->scratch->set('redirectAfterLogin', $session->url->page('func=viewStep'));
    }

    my $var;
    $var->{ login_button            } =
        WebGUI::Form::formHeader($session)
        . WebGUI::Form::hidden($session, { name => 'func',      value => 'login'                     } )
        . WebGUI::Form::submit($session, {                      value => 'Inloggen'                 } )
        . WebGUI::Form::formFooter($session);
    $var->{ login_url               } = $session->url->page('func=login');
    $var->{ createAccount_button    } =
        WebGUI::Form::formHeader($session)
        . WebGUI::Form::hidden($session, { name => 'func',      value => 'createAccount'            } )
        . WebGUI::Form::submit($session, {                      value => 'Account aanmaken'         } )
        . WebGUI::Form::formFooter($session);
    $var->{ createAccount_url       } = $session->url->page('func=createAccount');

#### TODO: Kan dit kan weg?...
    $var->{ proceed_button          } =
        WebGUI::Form::formHeader($session)
        . WebGUI::Form::hidden($session, { name => 'func',      value => 'viewStep'   } )
        . WebGUI::Form::submit($session, {                      value => 'Volgende stap'            } )
        . WebGUI::Form::formFooter($session);
    $var->{ proceed_url             } = $session->url->page('func=viewStep');
    $var->{ isVisitor               } = ($session->user->userId eq '1');
#### TODO: ...tot hierrr
    my $template = WebGUI::Asset::Template->new($self->session, $self->get('noValidUserTemplateId'));
    return $self->processStyle( $template->process($var) );
}

#-------------------------------------------------------------------
sub www_viewStep {
    my $self    = shift;
    my $session = $self->session;

    return $self->www_noValidUser unless $self->hasValidUser;

    my $output;

    # Set site status
    $self->setRegistrationStatus( 'setup' );

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
    my $session = $self->session;

    return $self->www_noValidUser unless $self->hasValidUser;

    my $currentStep = $self->getCurrentStep;

    # No more steps?
    return $self->www_viewStep unless $currentStep;

    $currentStep->processStepFormData;

    # Return the step screen if an error occurred during processing.
    return $currentStep->www_view if (@{ $currentStep->error });

    # Clear step id override flag.
    $session->scratch->delete( 'overrideStepId' );

    # And return the next screen.
    return $self->www_viewStep;
}


#-------------------------------------------------------------------   
sub www_view {
    my $self = shift;
    return $self->www_setupSite unless ($self->canEdit || $self->canInstallUserPage);

    return $self->SUPER::www_view;
}

#-------------------------------------------------------------------
sub www_registrationComplete {
    my $self = shift;

    return $self->processStyle('U heeft al een website aangemaakt of uw gegevens worden nog gecontroleerd.');
}

1;

