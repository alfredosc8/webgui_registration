package WebGUI::Registration::Instance;

use strict;

use WebGUI::Registration::Admin;


use base qw{ WebGUI::Crud };

sub adminConsole {
    return WebGUI::Registration::Admin::adminConsole( @_ );
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
sub newByUserId {
    my $class           = shift;
    my $session         = shift;
    my $registrationId  = shift;
    my $userId          = shift;

    my $id = $class->getAllIds( $session, {
        sequenceKeyValue    => $registrationId,
        contstraints        => [ 
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

sub registration {
    my $self = shift;

    return WebGUI::Registration->new( $self->session, $self->get('registrationId'), $self->user->userId ); 
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
    # Instanciate or create user
#    my $user = WebGUI::User->new( $session, $userId );
#    $user->username( $username );
#    $user->profileField( 'email', $email );
#
#    # Apply auth plugin stuff
#    my $authInstance = WebGUI::Operation::Auth::getInstance($session, 'WebGUI', $user->userId);
#    $authInstance->editUserFormSave;
    
    # Set the registration object to use the instanciated user
#    $registration->user( $user );

    # Save the current version tag so that we can the user to his current tag after the application process.
    my $currentVersionTag   = WebGUI::VersionTag->getWorking($session, 1);

    # Create a separate tag for the content applied by the registration steps.
    my $tempVersionTag      = WebGUI::VersionTag->create($session, {
        name    => 'Installation of user pages for '.$self->user->username,
    });
    $tempVersionTag->setWorking;
    
    # Apply the registration steps 
    foreach my $step ( @{ $steps } ) {
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

    # Create notification mail tmpl_vars
    my $var;
    #### TODO: homepageurl niet hardcoden
    $var->{ homepage_url        } = $user->profileField( 'homepageUrl' );
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







1;

