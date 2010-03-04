package WebGUI::Registration;

use strict;

use Carp;
use Class::InsideOut qw{ :std };
use List::Util qw{ first };
use List::MoreUtils qw{ any };
use WebGUI::Pluggable;
use JSON qw{ encode_json decode_json };
use Data::Dumper;
use WebGUI::Utility;
use Tie::IxHash;

public   instance           => my %instance;

use base qw{ WebGUI::Crud };

#-------------------------------------------------------------------
sub crud_definition {
    my $class       = shift;
    my $session     = shift;
    my $definition  = shift;

    $definition->{ tableName } = 'Registration';
    $definition->{ tableKey  } = 'registrationId';

    tie %{ $definition->{ properties } }, 'Tie::IxHash';

    $definition->{ properties }->{ title                            } = {
        fieldType   => 'text',
        label       => 'Title',
    };
    $definition->{ properties }->{ url                              } = {
        fieldType   => 'text',
        label       => 'URL',
    };
    $definition->{ properties }->{ countLoginAsStep                 } = {
        fieldType   => 'yesNo',
        label       => 'Count login as step?',
    };
    $definition->{ properties }->{ loginTitle                       } = {
        fieldType   => 'text',
        label       => 'Login title',
    };
    $definition->{ properties }->{ countConfirmationAsStep          } = {
        fieldType   => 'yesNo',
        label       => 'Count confirmation as step?',
    };
    $definition->{ properties }->{ confirmationTitle                } = {
        fieldType   => 'text',
        -label      => 'Confirmation title',
    };
    $definition->{ properties }->{ registrationManagersGroupId      } = {
        fieldType   => 'group',
        label       => 'Group to manage this registration',
    };
    $definition->{ properties }->{ notificationGroupId              } = {
        fieldType   => 'group',
        label       => 'Group to notify when pending accounts are created.',
    };
    $definition->{ properties }->{ styleTemplateId                  } = {
        fieldType   => 'template',
        label       => 'Style',
        namespace   => 'style',
    };
    $definition->{ properties }->{ stepTemplateId                   } = {
        fieldType   => 'template', 
        label       => 'Step Template',
        namespace   => 'Registration/Step',
    };
    $definition->{ properties }->{ showConfirmationScreen           } = {
        fieldType   => 'yesNo',
        label       => 'Show confirmation screen?',
        defaultValue=> 1,
    },
    $definition->{ properties }->{ confirmationTemplateId           } = {
        fieldType   => 'template',
        label       => 'Confirmation Template',
        namespace   => 'Registration/Confirm',
    };
    $definition->{ properties }->{ registrationCompleteTemplateId   } = {
        fieldType   => 'template',
        label       => 'Registration Complete Message',
        namespace   => 'Registration/CompleteMessage',
    };
    $definition->{ properties }->{ noValidUserTemplateId            } = {
        fieldType   => 'template',
        label       => 'No valid user template',
        namespace   => 'Registration/NoValidUser',
    };
    $definition->{ properties }->{ setupCompleteMailSubject         } = {
        fieldType   => 'text',
        tab         => 'display',
        label       => 'Setup complete notification email subject',
    };
    $definition->{ properties }->{ setupCompleteMailTemplateId      } = {
        fieldType   => 'template',
        namespace   => 'Registration/CompleteMail',
        tab         => 'display',
        label       => 'Registration complete notification email template',
    };
    $definition->{ properties }->{ siteApprovalMailSubject          } = {
        fieldType   => 'text',
        tab         => 'display',
        label       => 'Site approval nofication mail subject',
    };
    $definition->{ properties }->{ siteApprovalMailTemplateId       } = {
        fieldType   => 'template',
        namespace   => 'Registration/ApprovalMail',
        tab         => 'display',
        label       => 'Site approval nofication mail template',
    };
    $definition->{ properties }->{ newAccountWorkflowId             } = {
        fieldType           => 'workflow',
        type                => 'WebGUI::User',
        none                => 1,
        tab                 => 'security',
        label               => 'Run workflow on account creation',
    };
    $definition->{ properties }->{ removeAccountWorkflowId          } = {
        fieldType           => 'workflow',
        type                => 'WebGUI::User',
        includeRealtime     => 1,
        none                => 1,
        tab                 => 'security',
        label               => 'Run workflow on account removal',
    };

    return $definition;
};

#tmp remove later when factoring out registrationId
sub registrationId {
    return shift->getId;
}

#-------------------------------------------------------------------
sub delete {
    my $self    = shift;
    my $session = $self->session;

    # Clean up user instances
    my $it = WebGUI::Registration::Instance->getAllIterator( $session, { 
        constraints => [ { 'registrationId=?' => $self->getId } ],
    });
    while ( my $instance = $it->() ) {
        $instance->delete;
    }

    # Clean up RegistrationStep
    foreach ( @{ $self->getSteps } ) {
        $_->delete;
    }

    # Remove url trigger
    $self->deleteUrlTrigger( $self->get('url') );

    return $self->SUPER::delete;
}

#-------------------------------------------------------------------
sub deleteUrlTrigger {
    my $self    = shift;
    my $url     = shift;
    my $setting = $self->session->setting;

    my $triggers = decode_json( $setting->get('registrationUrlTriggers') || '{}' );
    delete $triggers->{ $url };

    $setting->set( registrationUrlTriggers => encode_json($triggers) );

    return;
}

#-------------------------------------------------------------------
sub getCurrentStep {
    my $self    = shift;
    my $session = $self->session;

    my $registrationStepIds = WebGUI::Registration::Step->getAllIds( $session, { sequenceKeyValue => $self->getId } );

    my $overrideStepId      =  $session->scratch->get( 'overrideStepId' );

    # Return override step only if it is also part of this registration.
    if ( $overrideStepId && isIn( $overrideStepId, @{ $registrationStepIds } ) ) {
        return $self->getStep( $overrideStepId );
    }

    # Find first incomplete step and return it
    foreach my $stepId ( @{ $registrationStepIds } ) {
        # TODO: Catch exception.
        my $step = $self->getStep( $stepId );

        return $step unless $step->isComplete;
    }

    # All steps are complete, return undef.
    return undef;
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

    tie my %props, 'Tie::IxHash', (
        %{ $self->crud_getProperties( $session )        },
    );
    foreach my $key ( keys %props ) {
        next if $props{ $key }{ noFormPost };

        $f->dynamicField(
            %{ $props{ $key } },
            name    => $key,
            value   => $self->get( $key )
        );
    };

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
                isCurrentStep       => $currentStep ? $currentStep->getId eq $step->getId : 0,
                stepNumber          => $stepCounter,
                substep_loop        => $step->getSubstepStatus,
            };
            $stepCounter++
        }
        else {
            push @{ $stepStatus[-1]->{ substep_loop } }, {
               substepName          => $step->get('title'),
               substepComplete      => $step->isComplete,
               isCurrentSubstep     => $currentStep ? $currentStep->getId eq $step->getId : 0,
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
sub getStep {
    my $self    = shift;
    my $stepId  = shift;

    my $step    = WebGUI::Registration::Step->newByDynamicClass( $self->session, $stepId, $self->instance->getStepData( $stepId ) );

    return $step;
}

#-------------------------------------------------------------------
sub getSteps {
    my $self    = shift;
    my $session = $self->session;
   
    my $stepIds = WebGUI::Registration::Step->getAllIds( $session, { sequenceKeyValue => $self->getId} );

    my @steps   = map { WebGUI::Registration::Step->newByDynamicClass( $session, $_ ) } @{ $stepIds };

    return \@steps;
}

#-------------------------------------------------------------------
sub hasValidUser {
    my $self    = shift;

    # Site status checken
    # ie. not pending or complete
    return 0 unless $self->instance->get('status') eq 'incomplete';

    # If a user has been loaded into the Registration that is not a visitor, return true.
####    return $self->user && $self->user->userId ne '1';
    #### TODO:: Gaat dit goed?
    return $self->instance->get('userId') ne 1;
}

#-------------------------------------------------------------------
sub getInstance {
    my $self    = shift;
    my $userId  = shift;
    my $session = $self->session;

    my $instance = 
           WebGUI::Registration::Instance->newByUserId( $session, $self->getId, $userId )
        || WebGUI::Registration::Instance->create( $session, { userId => $userId, registrationId => $self->getId } );
        ;

    return $instance;
}

#-------------------------------------------------------------------
sub new {
    my $class   = shift;
    my $session = shift;
    my $id      = shift;
    my $userId  = shift || $session->user->userId;

    my $self    = $class->SUPER::new( $session, $id );

    $instance{ id $self } = $self->getInstance( $userId );

    return $self;
}

#-------------------------------------------------------------------
sub updateFromFormPost {
    my $self    = shift;
    my $session = $self->session;

    $self->SUPER::updateFromFormPost;

    my $currentUrl  = $self->get('url');
    my $newUrl      = $session->form->process( 'url' );

    $self->deleteUrlTrigger( $currentUrl );
    $self->addUrlTrigger( $newUrl );

    return;
    
}

sub addUrlTrigger {
    my $self    = shift;
    my $url     = shift || croak 'No url passed';
    my $setting = $self->session->setting;

    #### TODO: Checken dat bestaande urls niet worden overschreven.
    my $triggers         = decode_json( $setting->get('registrationUrlTriggers') || '{}' );
    $triggers->{ $url }  = $self->getId;

    $setting->set( 'registrationUrlTriggers', encode_json( $triggers ) );

    return;
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

    return $self->instance->get('status') ne 'incomplete';
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

    # Complete the registration if no confirmation is used.
    return $self->www_completeRegistration unless $self->get( 'showConfirmationScreen' );

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
    my $userId  = $self->instance->user->userId;

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
        toUser  => $userId,
        subject => $self->get('setupCompleteMailSubject'),
    });
    $mail->addText($mailBody);
    $mail->queue;

    # Send email to managers
    if ($self->get('notificationGroupId')) {
        my $mail            = WebGUI::Mail::Send->create( $self->session, {
            toGroup     => $self->get('notificationGroupId'),
            subject     => 'Een nieuwe accountaanvraag is ingediend',
        });

        #### TODO: Gehardcode tekst.
        $mail->addText(
            'Een account staat klaar om gecontroleerd te worden op: '
            . $self->session->url->getSiteURL . $self->session->url->gateway(
                '',
                "registration=admin;func=editRegistrationInstanceData;userId=$userId;registrationId=".$self->registrationId
            )
        );
        $mail->queue;
    }

    #### $self->setRegistrationStatus( 'pending' );
    $self->instance->update({ status => 'pending' });

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
    
####    if ($self->hasValidUser || $self->user->userId eq '1') {
#### TODO: Gaat dit goed?
    if ($self->hasValidUser || $self->session->user->isVisitor) {
        # Set site status flag to setup
        $self->instance->update({ status => 'incomplete' });
    }
    else {
        #### TODO: Dit niet hardcoden.
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
    $self->instance->update({ status => 'incomplete' });

    # Get current step
    my $currentStep = $self->getCurrentStep;

    if ( defined $currentStep ) {
        $output = $currentStep->www_view;
    }
    else {
        # Completed last step succesfully.

        #### TODO: Dubbelchecken of alle stappen zijn gecomplete.
        ####       Of toch niet? Immers wordt dit ook al gedaan in confirmRegistrationData.
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

    my $errors = $currentStep->processStepFormData;
    $self->instance->setStepData( $currentStep->getId, $currentStep->data );

    # Return the step screen if an error occurred during processing.
    return $currentStep->www_view if ( @{ $currentStep->error } );

    # Clear step id override flag.
    $session->scratch->delete( 'overrideStepId' );

    # And return the next screen.
    return $self->www_viewStep;
}


#-------------------------------------------------------------------   
sub www_view {
    my $self = shift;

    return $self->www_viewStep; 
}

#-------------------------------------------------------------------
sub www_registrationComplete {
    my $self = shift;

    #### TODO: gehardcode
    return $self->processStyle('U heeft al een website aangemaakt of uw gegevens worden nog gecontroleerd.');
}

1;

