package WebGUI::Registration::Admin;

use strict;
use WebGUI::Registration;
use WebGUI::Registration::Step;
use WebGUI::AdminConsole;

use Data::Dumper;

#-------------------------------------------------------------------
sub adminConsole {
    my $session = shift;
    my $content = shift;
    my $title   = shift;
    my $url     = $session->url;
    my $ac      = WebGUI::AdminConsole->new( $session );

    my $registrationId  = $session->stow->get('admin_registrationId');
    my $baseParams      = 'registration=admin;registrationId='.$registrationId;

    if ( $session->user->isInGroup( 3 ) ) {
        $ac->addSubmenuItem( $url->page( 'registration=admin;func=view'             ), 'List registrations'      );
        $ac->addSubmenuItem( $url->page( 'registration=admin;func=addRegistration'  ), 'Add a new registration'  );
    }
    if ( $session->user->isInGroup( 3 ) && $registrationId ) {
        $ac->addSubmenuItem( $url->page( "$baseParams;func=listSteps"   ), 'List registration steps' );
    }

    if ( $registrationId && canManage( $session, $registrationId ) ) {
        $ac->addSubmenuItem( $url->page( "$baseParams;func=listPendingRegistrations"    ), 'List pending registrations' );
        $ac->addSubmenuItem( $url->page( "$baseParams;func=listApprovedRegistrations"   ), 'List approved registrations');
        $ac->addSubmenuItem( $url->page( "$baseParams;func=editRegistrationInstanceData;userId=new"), 'Add a new account');
    }

    $ac->setIcon('/extras/spacer.gif');

    return $ac->render( $content, $title );
}

#-------------------------------------------------------------------
sub canManage {
    my $session         = shift;
    my $registrationId  = shift || $session->form->param('registrationId'); 

    my $registration    = WebGUI::Registration->new( $session, $registrationId );

    return $session->user->isInGroup( $registration->get('registrationManagersGroupId') );
}

#-------------------------------------------------------------------
sub getRegistrations {
    my $session         = shift;
    my $registrationId  = shift;
    my $status          = shift;

    my @userIds = $session->db->buildArray(
        "select t1.userId from Registration_status as t1, users as t2 "
        ." where t1.userId=t2.userId and t1.status=? and registrationId=? "
        ." order by t2.username ", 
        [
            $status,
            $registrationId,
        ]
    );

    my $output = '<table>';
    foreach (@userIds) {
        my $user = WebGUI::User->new($session, $_);

        $output .= '<tr><td><a href="'
            . $session->url->page('registration=admin;registrationId='.$registrationId.';func=deleteAccount;uid='.$_).'">DELETE</a></td>';
        $output .= '<td><a href="'
            . $session->url->page('registration=admin;registrationId='.$registrationId.';func=editRegistrationInstanceData;userId='.$_)
            . '">EDIT</a></td>';
        $output .= '<td>'.$user->username.'</td>'; #<td>'.$user->profileField('homepageUrl').'</td></tr>';
    }
    $output .= '</table>';
}



#-------------------------------------------------------------------
sub www_addRegistration {
    my $session = shift;

    return $session->privilege->insufficient unless $session->user->isInGroup( 3 );

    my $registration    = WebGUI::Registration->create( $session );

    return adminConsole( $session, $registration->getEditForm->print, 'Add Registration');
}

#-------------------------------------------------------------------
sub www_addStep {
    my $session = shift;

    return $session->privilege->insufficient unless canManage( $session );

    my $registrationId  = $session->form->process('registrationId');
    my $registration    = WebGUI::Registration->new( $session, $registrationId );

    my $namespace = $session->form->process( 'namespace' );
    return "Illegal namespace [$namespace]" unless $namespace =~ /^[\w\d\:]+$/;

    my $step = eval {
        WebGUI::Pluggable::instanciate( $namespace, 'create', [
            $session,
            { registrationId => $registrationId },
        ] );
    };

    $session->log->warn( "ERRORT: $@" ) if $@;

    #### TODO: catch exception

    return adminConsole( $session, $step->www_edit, 'New step for '.$registration->get('title') );
}

#-------------------------------------------------------------------
sub www_createInstanceForExistingUser {
    my $session = shift;

    return $session->privilege->insufficient unless canManage( $session );

    my $f = WebGUI::HTMLForm->new( $session );
    $f->hidden(
        name    => 'registration',
        value   => 'admin',
    );
    $f->hidden(
        name    => 'func',
        value   => 'editRegistrationInstanceData',
    );
    $f->hidden(
        name    => 'registrationId',
        value   => $session->form->process('registrationId'),
    );
    $f->user(
        name    => 'userId',
        label   => 'Choose',
    );
    $f->submit(
        value   => 'Proceed',
    );

    return adminConsole( $session, $f->print, 'Add account for existing user' );
}

#-------------------------------------------------------------------
sub www_deleteAccount {
    my $session = shift;

    return $session->privilege->insufficient unless canManage( $session );

    my $userId          = $session->form->param('uid');
    my $registrationId  = $session->form->param('registrationId');
    my $registration    = WebGUI::Registration->new( $session, $registrationId, $userId );

    my $output = 'If you proceed the following checked properties will be deleted:<br />';

    # Setup available deletion steps
    my $deleteSteps;
    $deleteSteps->{ deleteAccountStatus     } = 'Account status';
    $deleteSteps->{ executeWorkflow         } = 'Execute account removal workflow';
    $deleteSteps->{ deleteUserAccount       } = 'Remove user account';

    foreach my $step ( @{ $registration->getSteps } ) {
        my $deleteMessage = eval { $step->onDeleteAccount };
        if ( $@ ) {
            $session->errorHandler->warn("Error occurred in onDelete: $@");
            next;
        }

        $deleteSteps->{ 'step_' . $step->getId } = $deleteMessage if $deleteMessage;
    }

    # Setup Form
    $output .= 
        WebGUI::Form::formHeader($session)
        . WebGUI::Form::hidden( $session, { name => 'registration',     value => 'admin'                } )
        . WebGUI::Form::hidden( $session, { name => 'registrationId',   value => $registrationId        } )
        . WebGUI::Form::hidden( $session, { name => 'func',             value => 'deleteAccountConfirm' } )
        . WebGUI::Form::hidden( $session, { name => 'uid',              value => $userId                } )
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
        . $session->url->page('registration=admin;func=listPendingRegistrations;registrationId='.$registrationId) 
        . '">Cancel and return to account list</a></b><br />';

    return adminConsole( $session, $output, 'Delete account' );
}

#-------------------------------------------------------------------
sub www_deleteAccountConfirm {
    my $session = shift;
    my @actions;

    return $session->privilege->insufficient unless canManage( $session );

    my $userId          = $session->form->param('uid');
    my $registrationId  = $session->form->param('registrationId');
    my $registration    = WebGUI::Registration->new( $session, $registrationId, $userId );
  
    # Execute workflow
    my $workflowId = $registration->get('removeAccountWorkflowId');
    if ( $session->form->process( 'executeWorkflow' ) && $workflowId ) {
        WebGUI::Workflow::Instance->create($session, {
            workflowId  => $workflowId,
            methodName  => "new",
            className   => "WebGUI::User",
#           mode        => 'realtime',
            parameters  => $registration->user->userId,
            priority    => 1
        });
        push @actions, 'Executiong workflow';
    }
    
    # Execute onDelete handler of each step
    foreach my $step ( @{ $registration->getSteps } ) {
        if ($session->form->process( 'step_'.$step->getId ) ) {
            my $message = eval{ $step->onDeleteAccount( 1 ) };
            if ($@) {
                $message = 
                    'Error occured while deleting step '. $step->get('title') 
                    . ' of type ' . $step->namespace
                    . " with the following message: '$@, $!'";
            }
            push @actions, $message;
        }
    }
    
    # Remove user account
    if ( $session->form->process('deleteUserAccount') ) {
        $registration->user->delete;
        push @actions, 'Removing user account';
    }

    # Delete account status
    if ( $session->form->process( 'deleteAccountStatus' ) ) {
        $session->db->write('delete from Registration_status where registrationId=? and userId=?', [
            $registration->registrationId,
            $registration->user->userId,
        ]);
        push @actions, 'Removing account status';
    }
 
    my $output = 
        'Removing account:<br />'
        . '<ul><li>' . join( '</li><li>', @actions ) . '</li></ul>'
        . '<a href="' 
        . $session->url->page('registration=admin;func=listPendingRegistrations;registrationId='.$registrationId)
        . '">Return to pending account list</a><br />'
        . '<a href="' 
        . $session->url->page('registration=admin;func=listApprovedRegistrations;registrationId='.$registrationId)
        . '">Return to approved account list</a>';

    return adminConsole( $session, $output, 'Account deleted' );
}

#-------------------------------------------------------------------
sub www_deleteRegistration {
    my $session = shift;

    return $session->privilege->insufficient unless $session->user->isInGroup( 3 );

    my $registrationId  = $session->form->process('registrationId');
    my $registration    = WebGUI::Registration->new( $session, $registrationId );
    $registration->delete;

    return www_view( $session );
}

#-------------------------------------------------------------------
sub www_deleteStep {
    my $session = shift;

    return $session->privilege->insufficient unless canManage( $session );

    my $stepId  = $session->form->process('stepId');
    my $step    = WebGUI::Registration::Step->newByDynamicClass( $session, $stepId );
    $step->delete;

    return www_listSteps( $session, $step->registration->registrationId );
}


#-------------------------------------------------------------------
sub www_editRegistration {
    my $session = shift;

    return $session->privilege->insufficient unless $session->user->isInGroup( 3 );

    my $registrationId  = $session->form->process('registrationId');
    my $registration    = WebGUI::Registration->new( $session, $registrationId );

    return adminConsole( $session, $registration->getEditForm->print, 'Edit Registration');
}

#-------------------------------------------------------------------
sub www_editRegistrationSave {
    my $session = shift;

    return $session->privilege->insufficient unless $session->user->isInGroup( 3 );
    
    my $registrationId  = $session->form->process('registrationId');
    my $registration    = WebGUI::Registration->new( $session, $registrationId );

    $registration->processPropertiesFromFormPost;

    return www_view( $session );
}

#-------------------------------------------------------------------
sub www_editRegistrationInstanceData {
    my $session = shift;
    my $error   = shift || [];
    my $userId  = shift || $session->form->process( 'userId' );

    return $session->privilege->insufficient unless canManage( $session );

    my $registrationId  = $session->form->process( 'registrationId' );
#    my $userId          = $session->form->process( 'userId'         );

    my $registration    = WebGUI::Registration->new( $session, $registrationId, $userId );

    return adminConsole( $session, "De gebruiker '". $registration->user->username ."' heeft al een account.", "Approve account" )
        if $registration->getRegistrationStatus eq 'approved';

    my $steps           = $registration->getSteps;
    my $user            = WebGUI::User->new( $session, $userId ) unless $userId eq 'new';

    my $f = WebGUI::HTMLForm->new( $session );
    $f->hidden(
        name    => 'registration',
        value   => 'admin',
    );
    $f->hidden(
        name    => 'registrationId',
        value   => $registrationId,
    );
    $f->hidden(
        name    => 'userId',    
        value   => $userId,
    );
    $f->hidden(
        name    => 'func',
        value   => 'editRegistrationInstanceDataSave',
    );

    # User account properties
    my $username    = $session->form->process('username');
    $username     ||= $registration->user->username unless $userId eq 'new';
    my $email       = $session->form->process('email'); 
    $email        ||= $registration->user->profileField('email') unless $userId eq 'new';
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

#-------------------------------------------------------------------
#### TODO: Deze code moet eigenlijk naar WG::Registration
sub www_editRegistrationInstanceDataSave {
    my $session = shift;

    return $session->privilege->insufficient unless canManage( $session );

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
    return www_editRegistrationInstanceData( $session, \@error ) if @error;

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
    my $registrationId  = $session->form->process( 'registrationId' );
    my $registration    = WebGUI::Registration->new( $session, $registrationId, $user->userId );
    my $steps           = $registration->getSteps;

    return adminConsole( $session, "De gebruiker '". $registration->user->username ."' heeft al een account.", "Approve account" )
        if $registration->getRegistrationStatus eq 'approved';

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
        name    => 'Installation of user pages for '.$registration->user->username,
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

    $registration->setRegistrationStatus( 'approved' );

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

    return www_listPendingRegistrations( $session );
}

#-------------------------------------------------------------------
sub www_editStep {
    my $session = shift;

    return $session->privilege->insufficient unless $session->user->isInGroup( 3 );

    my $stepId  = $session->form->process('stepId');
    my $step    = WebGUI::Registration::Step->newByDynamicClass( $session, $stepId );
    $session->stow->set('admin_registrationId', $step->registration->registrationId);

    return adminConsole( $session, $step->www_edit, 'Edit step for ' . $step->registration->get('title') );
}

#-------------------------------------------------------------------
sub www_editStepSave {
    my $session = shift;

    return $session->privilege->insufficient unless $session->user->isInGroup( 3 );

    my $stepId  = $session->form->process('stepId');
    my $step    = WebGUI::Registration::Step->newByDynamicClass( $session, $stepId );

    $step->updateFromFormPost;

    return www_listSteps( $session, $step->registration->registrationId );
}

#-------------------------------------------------------------------
sub www_listApprovedRegistrations {
    my $session = shift;

    return $session->privilege->insufficient unless canManage( $session );

    my $registrationId  = $session->form->process( 'registrationId' );
    $session->stow->set('admin_registrationId', $registrationId);

    my $output = getRegistrations( $session, $registrationId, 'approved' );

    return adminConsole( $session, $output, 'Approved accounts' );
}

#-------------------------------------------------------------------
sub www_listPendingRegistrations {
    my $session = shift;

    return $session->privilege->insufficient unless canManage( $session );

    my $registrationId  = $session->form->process( 'registrationId' );
    $session->stow->set('admin_registrationId', $registrationId);

    my $output = getRegistrations( $session, $registrationId, 'pending' );

    return adminConsole( $session, $output, 'Pending accounts' );
}

#-------------------------------------------------------------------
sub www_listSteps {
    my $session         = shift;
    my $registrationId  = shift || $session->form->process('registrationId');

    $session->stow->set('admin_registrationId', $registrationId);

    return $session->privilege->insufficient unless canManage( $session, $registrationId );
    return www_managerScreen( $session ) unless $session->user->isInGroup( 3 );

    my $registration    = WebGUI::Registration->new( $session, $registrationId );
    my $steps           = $registration->getSteps;

    # Registration properties 
    my $output = 
        '<fieldset><legend>Registration properties</legend>' . $registration->getEditForm->print . '</fieldset>'; 

    my $icon = $session->icon;

    $output .= '<fieldset><legend>Registration steps</legend><ul>';
    foreach my $step ( @{ $steps } ) {
        my $baseParams = 'registration=admin;stepId=' . $step->getId . ';registrationId=' . $registrationId;
        
        $output .= 
            '<li>'
            . $icon->delete(    "$baseParams;func=deleteStep"   )
            . $icon->moveUp(    "$baseParams;func=moveStepUp"   )
            . $icon->moveDown(  "$baseParams;func=moveStepDown" )
            . $icon->edit(      "$baseParams;func=editStep"     )
            . $step->get( 'title' )
            .'</li>';       
    }

    my $availableSteps  = { map {$_ => $_} @{ $session->config->get('registrationSteps')  || [] } };
    my $addForm         = 
          WebGUI::Form::formHeader( $session )
        . WebGUI::Form::hidden(     $session, { -name => 'registration',    -value => 'admin'               } )
        . WebGUI::Form::hidden(     $session, { -name => 'func',            -value => 'addStep'             } )
        . WebGUI::Form::hidden(     $session, { -name => 'registrationId',  -value => $registrationId       } )
        . WebGUI::Form::selectBox(  $session, { -name => 'namespace',       -options => $availableSteps     } )
        . WebGUI::Form::submit(     $session, {                             -value => 'Add step'            } )
        . WebGUI::Form::formFooter( $session );


    $output .= "<li>$addForm</li></ul></fieldset>";

    return adminConsole( $session, $output, 'Edit registration steps for ' . $registration->get('title') );
}

#-------------------------------------------------------------------
sub www_managerScreen {
    my $session = shift;
   
    return $session->privilege->insufficient unless canManage( $session );

    my $message = 'Gebruik het menu rechts voor accountbeheer.';

    return adminConsole( $session, $message, 'Accountbeheer' );
}

#-------------------------------------------------------------------
sub www_moveStepDown {
    my $session = shift;
    my $stepId  = $session->form->process( 'stepId' );

    return $session->privilege->insufficient unless $session->user->isInGroup( 3 );
    
    my $step = WebGUI::Registration::Step->newByDynamicClass( $session, $stepId );
    return "Cannaot instanciate step $stepId" unless $step;

    $step->demote;

    return www_listSteps( $session );
}

#-------------------------------------------------------------------
sub www_moveStepUp {
    my $session = shift;
    my $stepId  = $session->form->process( 'stepId' );

    return $session->privilege->insufficient unless $session->user->isInGroup( 3 );
    
    my $step = WebGUI::Registration::Step->newByDynamicClass( $session, $stepId );
    return "Cannaot instanciate step $stepId" unless $step;

    $step->promote;

    return www_listSteps( $session );
}

#-------------------------------------------------------------------
sub www_view {
    my $session = shift;

#    return $session->privilege->insufficient unless $session->user->isInGroup( 3 );
#    return $session->privilege->insufficient unless canManage( $session );

    my @registrationIds = $session->db->buildArray( 'select registrationId from Registration' );

    my $output = '<ul>';
    foreach my $id ( @registrationIds ) {
        my $registration    = WebGUI::Registration->new( $session, $id );

        next unless canManage( $session, $id );

        my $deleteButton    = $session->icon->delete(
            "registration=admin;func=deleteRegistration;registrationId=$id",
            undef,
            'Weet u zeker dat u deze registratie wil verwijderen?',
        );
        my $editButton      = $session->icon->edit(
            "registration=admin;func=listSteps;registrationId=$id",
        );

        $output .= "<li>$deleteButton $editButton" .  $registration->get('title') . '</li>';
    }

    $output .= '</ul>';

    return adminConsole( $session, $output, 'Manage Registrations' );
}

1;
