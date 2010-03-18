package WebGUI::Registration::Instance;

use strict;

use WebGUI::Registration::Admin;
use Carp qw{ cluck croak };
use Data::Dump 'pp';
use base qw{ WebGUI::Crud };

sub adminConsole {
    return WebGUI::Registration::Admin::adminConsole( @_ );
}

sub create {
    my $class   = shift;
    my $session = shift;
    my $prop    = shift;

    croak "Need either a userId or a sessionId" unless exists $prop->{userId} || exists $prop->{sessionId};

    my $self = $class->SUPER::create( $session, $prop );

    if ( !defined $prop->{userId} ) {
        my $u = WebGUI::User->create( $session );
        $u->username( $self->session->getId );
        $u->disable;

        $self->update( { userId => $u->userId } );
    }

    return $self;
}


#----------------------------------------------------------------------------
sub crud_definition {
    my $class       = shift;
    my $session     = shift;
    my $definition  = shift;

    $definition->{ tableName    } = 'RegistrationInstance';
    $definition->{ tableKey     } = 'instanceId';
    $definition->{ sequenceKey  } = 'registrationId';

    $definition->{ properties }->{ registrationId } = {
        fieldType       => 'guid',
        noFormPost      => 1,
    };
    $definition->{ properties }->{ userId } = {
        fieldType       => 'guid',
        noFormPost      => 1,
    };
    $definition->{ properties }->{ sessionId } = {
        fieldType       => 'guid',
        noFormPost      => 1,
    };
    $definition->{ properties }->{ status } = {
        fieldType       => 'text',
        defaultValue    => 'incomplete',
        noFormPost      => 1,
    };
    $definition->{ properties }->{ stepData } = {
        fieldType       => 'textarea',
        defaultValue    => {},
        serialize       => 1,
        noFormPost      => 1,
    };

    return $definition;
}

#----------------------------------------------------------------------------
sub new {
    my $class   = shift;
    my $session = shift;
    my @params  = @_;

    my $self = $class->SUPER::new( $session, @_ );

    return $self;
}

#----------------------------------------------------------------------------
sub newBySessionId {
    my $class           = shift;
    my $session         = shift;
    my $registrationId  = shift;
    my $sessionId       = shift;

    my $id = $class->getAllIds( $session, {
        sequenceKeyValue    => $registrationId,
        constraints        => [ 
            { 'sessionId=?'  => $sessionId },
        ],
    } );
    
    return $class->new( $session, $id->[0] ) if $id->[0];

    return;
}
#----------------------------------------------------------------------------
sub newByUserId {
    my $class           = shift;
    my $session         = shift;
    my $registrationId  = shift;
    my $userId          = shift;

    my $id = $class->getAllIds( $session, {
        sequenceKeyValue    => $registrationId,
        constraints        => [ 
            { 'userId=?'  => $userId },
        ],
    } );
    
    return $class->new( $session, $id->[0] ) if $id->[0];

    return;
}

#----------------------------------------------------------------------------
sub getStepData {
    my $self    = shift;
    my $stepId  = shift;

    my $data = $self->get( 'stepData' );

    return $data->{ $stepId };
}

#----------------------------------------------------------------------------
sub setStepData {
    my $self    = shift;
    my $stepId  = shift;
    my $data    = shift;

    my $stepData   = $self->get( 'stepData' );
    $stepData->{ $stepId } = $data;

    $self->update({ stepData => $stepData });

    return;
}

#----------------------------------------------------------------------------
sub user {
    my $self = shift;

    #### TODO: Caching.
    return WebGUI::User->new( $self->session, $self->get('userId') );
}

#----------------------------------------------------------------------------
sub registration {
    my $self = shift;

    return WebGUI::Registration->new( $self->session, $self->get('registrationId'), $self->user->userId ); 
}

#-------------------------------------------------------------------
sub www_delete {
    my $self    = shift;
    my $session = $self->session;

    return $session->privilege->insufficient unless $self->registration->canManage;

    my $output = 'If you proceed the following checked properties will be deleted:<br />';

    # Setup available deletion steps
    my $deleteSteps;
#    $deleteSteps->{ deleteAccountStatus     } = 'Account status';
    $deleteSteps->{ executeWorkflow         } = 'Execute account removal workflow';
    $deleteSteps->{ deleteUserAccount       } = 'Remove user account';

    foreach my $step ( @{ $self->registration->getSteps } ) {
        my $deleteMessage = eval { $step->onDeleteAccount };
        if ( $@ ) {
            $session->log->error("Error occurred in onDelete: $@");
            next;
        }

        $deleteSteps->{ 'step_' . $step->getId } = $deleteMessage if $deleteMessage;
    }

    # Setup Form
    $output .= 
        WebGUI::Form::formHeader( $session )
        . WebGUI::Form::hidden(   $session, { name => 'registration',   value => 'instance'         } )
        . WebGUI::Form::hidden(   $session, { name => 'instanceId',     value => $self->getId       } )
        . WebGUI::Form::hidden(   $session, { name => 'func',           value => 'deleteConfirm'    } )
        ;

    # Wrap deletion steps into the form
    $output .= '<ul><li>';
    $output .=  join    '</li><li>', 
                map     { 
                            WebGUI::Form::checkbox( $session, { name => $_, value => 1, checked => 1 } )
                            . $deleteSteps->{ $_ }
                        }
                keys    %$deleteSteps
                ;
    $output .= '</li></ul>';
    $output .= WebGUI::Form::submit($session, {value => "Delete checked properties"});
    $output .= WebGUI::Form::formFooter($session);

    $output .= '<br /><b><a href="' 
        . $session->url->page( 'registration=registration;func=managePendingInstances;registrationId=' . $self->registration->getId )
        . '">Cancel and return to account list</a></b><br />';

    return $self->registration->adminConsole( $output, 'Delete account' );
}

#-------------------------------------------------------------------
sub www_deleteConfirm {
    my $self    = shift; 
    my $session = $self->session;
    my $form    = $session->form;

    return $session->privilege->insufficient unless $self->registration->canManage;

    my $registration = $self->registration;
    my @actions;

    # Execute workflow
    my $workflowId = $registration->get('removeAccountWorkflowId');
    if ( $session->form->process( 'executeWorkflow' ) && $workflowId ) {
        WebGUI::Workflow::Instance->create($session, {
            workflowId  => $workflowId,
            methodName  => "new",
            className   => "WebGUI::User",
#           mode        => 'realtime',
            parameters  => $self->get('userId'),
            priority    => 1
        });
        push @actions, 'Executiong workflow';
    }
    
    # Execute onDelete handler of each step
    foreach my $step ( @{ $registration->getSteps } ) {
        if ( $form->get( 'step_'.$step->getId ) ) {
            my $message = eval{ $step->onDeleteAccount( 1 ) };
            if ($@) {
                $message = 
                    'An error occured while deleting step '. $step->get('title') 
                    . ' of type ' . $step->namespace
                    . " with the following message: '$@'";
            }
            push @actions, $message;
        }
    }
    
    # Remove user account
    if ( $form->get('deleteUserAccount') ) {
        if ( $self->user->isVisitor || $self->user->userId eq '3' ) {
            push @actions, 'Cannot remove a protected account. Skipping.';
        }
        else {
            $self->user->delete;
            push @actions, 'Removing user account';
        }
    }

    # Delete account status
#    if ( $session->form->process( 'deleteAccountStatus' ) ) {
#        $session->db->write('delete from Registration_status where registrationId=? and userId=?', [
#            $registration->getId,
#            $registration->instance->user->userId,
#        ]);
#        push @actions, 'Removing account status';
#    }

    # remove instance
    $self->delete;

    my $base    = 'registration=registration;registrationId=' . $registration->getId; 
    my $output  = 
        'Removing account:<br />'
        . '<ul><li>' . join( '</li><li>', @actions ) . '</li></ul>'
        . '<a href="' 
        . $session->url->page( "$base;func=managePendingInstances" )
        . '">Return to pending account list</a><br />'
        . '<a href="' 
        . $session->url->page( "$base;func=manageApprovedInstances" )
        . '">Return to approved account list</a>';

    return $self->registration->adminConsole( $output, 'Account deleted' );
}

#----------------------------------------------------------------------------
sub www_edit {
    my $self    = shift;
    my $session = $self->session;

    my $error   = shift || [];
#    my $userId  = shift || $session->form->process( 'userId' );

####    return $session->privilege->insufficient unless canManage( $session );

#    my $registrationId  = $session->form->process( 'registrationId' );
#    my $userId          = $session->form->process( 'userId'         );

    my $registration = $self->registration; ####WebGUI::Registration->new( $session, $registrationId, $userId );

    return adminConsole( $session, "De gebruiker '". $self->instance->user->username ."' heeft al een account.", "Approve account" )
        if $self->get('status') eq 'approved';

    my $steps           = $registration->getSteps;
    my $user            = $self->user; ####WebGUI::User->new( $session, $userId ) unless $userId eq 'new';
    my $userId          = $user->userId;

    my $f = WebGUI::HTMLForm->new( $session );
    $f->hidden(
        name    => 'registration',
        value   => 'instance',
    );
    $f->hidden(
        name    => 'instanceId',
        value   => $self->getId,
    );
    $f->hidden(
        name    => 'userId',    
        value   => $userId,
    );
    $f->hidden(
        name    => 'func',
        value   => 'editSave',
    );

    # User account properties
    my $username    = $session->form->process('username');
    $username     ||= $self->user->username unless $userId eq 'new';
    my $email       = $session->form->process('email'); 
    $email        ||= $self->user->profileField('email') unless $userId eq 'new';
    $f->fieldSetStart( 'Account Data' );
    $f->text(
        name    => 'username',
        label   => 'Username',
        value   => $username,
    );
    $f->email(
        name    => 'email',
        label   => 'Email',
        value   => $email,
    );
    # Make sure we do not pass 'new' as a userId to WG::Op:Auth->getInstance as this will create a 'zombie' account. 
    $f->raw(WebGUI::Operation::Auth::getInstance( $session, 'WebGUI', $userId eq 'new' ? undef : $userId )->editUserForm);
    $f->fieldSetEnd;

    foreach my $step ( @{ $steps } ) {
        foreach my $category ( $step->getSummaryTemplateVars( 1 ) ) {
            $f->fieldSetStart( $category->{ category_label } );
            foreach my $field ( @{ $category->{ field_loop } } ) {
                $f->readOnly(
                    label   => $field->{ field_label        },
                    value   => $field->{ field_formElement  },
                );
            }
            $f->fieldSetEnd;
        }
    }

    $f->submit;

    my $output;
    $output .= 'Errors: <ul><li>'. join( '</li><li>', @$error ) . '</li></ul>' if @$error;
    $output .= $f->print;

    return adminConsole( $session, $output, 'Approve account' );
}


#----------------------------------------------------------------------------
sub www_editSave {
    my $self    = shift;
    my $session = $self->session;

####    return $session->privilege->insufficient unless canManage( $session );

    my @error;

    # ========== Process account data =================================
    my $username        = $session->form->process( 'username'   );
    my $email           = $session->form->process( 'email'      );
    my $userId          = $session->form->process( 'userId'     );
    my $userByUserId    = WebGUI::User->new(            $session, $userId   ) unless $userId eq 'new';
    my $userByUsername  = WebGUI::User->newByUsername(  $session, $username );
    my $userByEmail     = WebGUI::User->newByEmail(     $session, $email    );

    # Check for valid userId
    if ( $userId ne 'new' && !$userByUserId ) {
        push @error, "Invalid userId: [$userId]";
    }

    # Check for duplicate username
    if ( $userByUsername && ( $userByUsername->userId ne $userId ) ) {
        push @error, 'Username already exists.';
    }

    # Check for duplicate email
    if ( $userByEmail && ( $userByEmail->userId ne $userId ) ) {
        push @error, 'Email address is already in use by user: ' . $userByEmail->username;
    }

    # ========== Return to edit screen with errors if an error occurred.
    return www_edit( $session, \@error ) if @error;

    # ========== Process user account data =============================
    # Instanciate or create user
    my $user = WebGUI::User->new( $session, $userId );
    $user->username( $username );
    $user->profileField( 'email', $email );

    # Apply auth plugin stuff
    my $authInstance = WebGUI::Operation::Auth::getInstance($session, 'WebGUI', $user->userId);
    $authInstance->editUserFormSave;

    $userId = $user->userId;

    # ========== Process and error check submitted form data. ==========
#    my $registrationId  = $session->form->process( 'registrationId' );
#    my $registration    = WebGUI::Registration->new( $session, $registrationId, $user->userId );
    my $registration    = $self->registration;
    my $steps           = $registration->getSteps;

    return adminConsole( $session, "De gebruiker '". $self->user->username ."' heeft al een account.", "Approve account" )
        if $self->get('status') eq 'approved';

    foreach my $step ( @{ $steps } ) {
        $step->processStepApprovalData;

        push @error, @{ $step->error };
    }

    # ========== Return to edit screen with errors if an error occurred.
    return www_editRegistrationInstanceData( $session, \@error, $userId ) if @error;

    
    # ========== No errors occurred ====================================

    # Apply the steps and set status to approved. 
    $self->approve;


    # Create notification mail tmpl_vars
    my %userData = %{ $user->get };
    my $var = { 
        map {( "user_$_"   => $userData{ $_ } )} keys %userData,
    };
    $var->{ username            } = $user->username;

    # Send notification mail
    my $mailTemplate    = WebGUI::Asset::Template->new($session, $registration->get('siteApprovalMailTemplateId'));
    my $mailBody        = $mailTemplate->process( $var );
    my $mail            = WebGUI::Mail::Send->create($session, {
        toUser      => $user->userId,
        subject     => $registration->get('siteApprovalMailSubject'),
    });
    $mail->addText($mailBody);
    $mail->queue;

    return WebGUI::Registration::Admin::www_listPendingRegistrations( $session );
}

sub approve {
    my $self            = shift;
    my $session         = $self->session;
    my $registration    = $self->registration;
    my $user            = $self->user;

    # Save the current version tag so that we can the user to his current tag after the application process.
    my $currentVersionTag   = WebGUI::VersionTag->getWorking($session, 1);

    # Create a separate tag for the content applied by the registration steps.
    my $tempVersionTag      = WebGUI::VersionTag->create($session, {
        name    => 
            sprintf( 'Approval of registration %s for %s', 
                $self->registration->get('title'), $self->user->username,
            ),
    });
    $tempVersionTag->setWorking;
    
    # Apply the registration steps 
    foreach my $step ( @{ $registration->getSteps } ) {
        $step->apply;
    }

    # Commit the tag if it contains any content, otherwise delete it.
    if ( $tempVersionTag->getAssetCount > 0 ) {
        $tempVersionTag->commit;
    }
    else {
        $tempVersionTag->rollback;
    }

    # Return the user to the version tag he was in.
    $currentVersionTag->setWorking if (defined $currentVersionTag);
    
    # Run workflow on account creation.
    if ($registration->get('newAccountWorkflowId')) {
        WebGUI::Workflow::Instance->create($session, {
            workflowId  => $registration->get('newAccountWorkflowId'),
            methodName  => "new",
            className   => "WebGUI::User",
            parameters  => $user->userId,
            priority    => 1
        });
    } 
    
    $self->update( { status => 'approved' } );

    return;
}

1;

