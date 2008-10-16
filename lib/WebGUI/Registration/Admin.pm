package WebGUI::Registration::Admin;

use strict;
use WebGUI::Registration;
use WebGUI::Registration::Step;
use WebGUI::AdminConsole;


#-------------------------------------------------------------------
sub adminConsole {
    my $session = shift;
    my $content = shift;
    my $title   = shift;

    my $ac = WebGUI::AdminConsole->new( $session );

    my $registrationId = $session->stow->get('admin_registrationId');

    $ac->addSubmenuItem( $session->url->page('registration=admin;func=view'), 'List registrations');
    $ac->addSubmenuItem( $session->url->page('registration=admin;func=listSteps;registrationId='.$registrationId), 'List registration steps');
    $ac->addSubmenuItem(
        $session->url->page('registration=admin;func=editRegistrationInstanceData;userId=new;registrationId='.$registrationId),
        'Add a new account'
    );

    return $ac->render( $content, $title );
}

##-------------------------------------------------------------------
#sub deleteAccount {
#    my ($output, @deleteGroups);
#    my $session         = shift;
#    my $registration    = shift;
#    my @actions;
#   
#    
#    if ( $session->form->process( 'deleteAccountStatus' ) ) {
#        $session->db->write('delete from Registration_status where registrationId=? and userId=?', [
#            $registration->registrationId,
#            $registration->user->userId,
#        ]);
#        push @actions, 'Removing account status';
#    }
#    
#    # Execute workflow
#    my $workflowId = $registration->get('removeAccountWorkflowId');
#    if ( $session->form->process( 'executeWorkflow' ) && $workflowId ) {
#        WebGUI::Workflow::Instance->create($self->session, {
#            workflowId  => $workflowId,
#            methodName  => "new",
#            className   => "WebGUI::User",
##           mode        => 'realtime',
#            parameters  => $registration->user->userId,
#            priority    => 1
#        });
#        push @actions, 'Executiong workflow';
#    }
#    
#    # Execute onDelete handlers of step
#    foreach my $step ( @{ $registration->getSteps } ) {
#        if ( $session->form->process( 'step_'.$stepId ) ) {
#            push @actions, $step->onDeleteAccount( 1 );
#        }
#    }
#    
#    # Remove user account
#    if ( $session->form->process('removeUseAccount') ) {
#        $registration->user->delete;
#        push @actions, 'Removing user account';
#    }
#    
#    my $output = '<ul><li>' . join( '</li><li>', @actions ) . '</li></ul>';
#    return $output;
#}    

#-------------------------------------------------------------------
sub www_addRegistration {
    my $session = shift;

    my $registration    = WebGUI::Registration->create( $session );

    return $registration->www_edit;
}

#-------------------------------------------------------------------
sub www_addStep {
    my $session = shift;

    return $session->privilege->insufficient unless $session->user->isInGroup( 3 );

    my $registrationId  = $session->form->process('registrationId');
    my $registration    = WebGUI::Registration->new( $session, $registrationId );

    my $namespace = $session->form->process( 'namespace' );
    return "Illegal namespace [$namespace]" unless $namespace =~ /^[\w\d\:]+$/;

    my $step = eval {
        WebGUI::Pluggable::instanciate( $namespace, 'create', [
            $session,
            $registration,
        ] );
    };

    #### TODO: catch exception

    return adminConsole( $session, $step->www_edit, 'New step for '.$registration->get('title') );
}

#-------------------------------------------------------------------
sub www_deleteAccount {
    my $session = shift;

    return $session->privilege->insufficient unless $session->user->isInGroup( 3 );

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
        next unless $@;

        $deleteSteps->{ 'step_' . $step->stepId } = $deleteMessage if $deleteMessage;
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

    return $session->privilege->insufficient unless $session->user->isInGroup( 3 );

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
        if ($session->form->process( 'step_'.$step->stepId ) ) {
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
        . '<a href="' . $session->url->page . '">Return to account list</a>';

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

    return $session->privilege->insufficient unless $session->user->isInGroup( 3 );

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

    my $registrationId  = $session->form->process( 'registrationId' );
    my $userId          = $session->form->process( 'userId'         );

    my $registration    = WebGUI::Registration->new( $session, $registrationId, $userId );
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
    $f->raw(WebGUI::Operation::Auth::getInstance( $session, 'WebGUI', $userId )->editUserForm);
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
sub www_editRegistrationInstanceDataSave {
    my $session = shift;

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

    # ========== Process and error check submitted form data. ==========
    my $registrationId  = $session->form->process( 'registrationId' );
    my $registration    = WebGUI::Registration->new( $session, $registrationId, $userId );
    my $steps           = $registration->getSteps;

    foreach my $step ( @{ $steps } ) {
        $step->processStepApprovalData;

        push @error, @{ $step->error };
    }

    # ========== Return to edit screen with errors if an error occurred.
    return www_editRegistrationInstanceData( $session, \@error ) if @error;

    
    # ========== No errors occurred ====================================
    # Instanciate or create user
    my $user = WebGUI::User->new( $session, $userId );
    $user->username( $username );
    $user->profileField( 'email', $email );

    # Apply auth plugin stuff
    my $authInstance = WebGUI::Operation::Auth::getInstance($session, 'WebGUI', $user->userId);
    $authInstance->editUserFormSave;
    
    # Set the registration object to use the instanciated user
    $registration->user( $user );

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

    $step->processPropertiesFromFormPost;

    return www_listSteps( $session, $step->registration->registrationId );
}

#-------------------------------------------------------------------
sub www_listPendingRegistrations {
    my $session = shift;

    my $registrationId  = $session->form->process( 'registrationId' );
    $session->stow->set('admin_registrationId', $registrationId);

    my @userIds = $session->db->buildArray("select userId from Registration_status where status='pending' and registrationId=?", [
        $registrationId,
    ]);

    my $output ; #= '<h1>Accounts waiting for approval</h1>';
    $output .= '<table>';
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

    return adminConsole( $session, $output, 'Pending accounts' );
}

#-------------------------------------------------------------------
sub www_listSteps {
    my $session         = shift;
    my $registrationId  = shift || $session->form->process('registrationId');

    my $registration    = WebGUI::Registration->new( $session, $registrationId );
    my $steps           = $registration->getSteps;
    
    $session->stow->set('admin_registrationId', $registrationId);

    my $output = '<ul>';
    foreach my $step ( @{ $steps } ) {
        $output .= '<li>'
            . $session->icon->delete('registration=admin;func=deleteStep;stepId='.$step->stepId.';registrationId='.$registrationId)
            . '<a href="'
            .   $session->url->page('registration=admin;func=editStep;stepId='.$step->stepId.';registrationId='.$registrationId)
            . '">'
            . '[stap]'.$step->get( 'title' )
            . '</a></li>';       
    }

    my $availableSteps  = { map {$_ => $_} @{ $session->config->get('registrationSteps') } };
    my $addForm         = 
          WebGUI::Form::formHeader( $session )
        . WebGUI::Form::hidden(     $session, { -name => 'registration',    -value => 'admin'               } )
        . WebGUI::Form::hidden(     $session, { -name => 'func',            -value => 'addStep'             } )
        . WebGUI::Form::hidden(     $session, { -name => 'registrationId',  -value => $registrationId       } )
        . WebGUI::Form::selectBox(  $session, { -name => 'namespace',       -options => $availableSteps     } )
        . WebGUI::Form::submit(     $session, {                             -value => 'Add step'            } )
        . WebGUI::Form::formFooter( $session );


    $output .= "<li>$addForm</li>";

    return adminConsole( $session, $output, 'Edit registration steps for ' . $registration->get('title') );
}

#-------------------------------------------------------------------
sub www_view {
    my $session = shift;

    my @registrationIds = $session->db->buildArray( 'select registrationId from Registration' );

    my $output = '<ul>';
    foreach my $id ( @registrationIds ) {
        my $registration    = WebGUI::Registration->new( $session, $id );

        my $deleteButton = $session->icon->delete(
            "registration=admin;func=deleteRegistration;registrationId=$id",
            undef,
            'Weet u zeker dat u deze registratie wil verwijderen?',
        );
        my $editButton =
              WebGUI::Form::formHeader( $session )
            . WebGUI::Form::hidden(     $session, { -name => 'registration',    -value => 'admin'               } )
            . WebGUI::Form::hidden(     $session, { -name => 'func',            -value => 'editRegistration'    } )
            . WebGUI::Form::hidden(     $session, { -name => 'registrationId',  -value => $id                   } )
            . WebGUI::Form::submit(     $session, {                             -value => 'Edit'                } )
            . WebGUI::Form::formFooter( $session );
        my $stepsButton =
              WebGUI::Form::formHeader( $session )
            . WebGUI::Form::hidden(     $session, { -name => 'registration',    -value => 'admin'               } )
            . WebGUI::Form::hidden(     $session, { -name => 'func',            -value => 'listSteps'           } )
            . WebGUI::Form::hidden(     $session, { -name => 'registrationId',  -value => $id                   } )
            . WebGUI::Form::submit(     $session, {                             -value => 'Steps'               } )
            . WebGUI::Form::formFooter( $session );
        my $accountButton =
              WebGUI::Form::formHeader( $session )
            . WebGUI::Form::hidden(     $session, { -name => 'registration',    -value => 'admin'               } )
            . WebGUI::Form::hidden(     $session, { -name => 'func',            -value => 'listPendingRegistrations' } )
            . WebGUI::Form::hidden(     $session, { -name => 'registrationId',  -value => $id                   } )
            . WebGUI::Form::submit(     $session, {                             -value => 'Manage accounts'     } )
            . WebGUI::Form::formFooter( $session );
            
        $output .= "<li>$deleteButton $editButton $stepsButton $accountButton" .  $registration->get('title') . '</li>';
    }

    $output .= '<li><a href="'.$session->url->page('registration=admin;func=addRegistration').'">NEW REG</a>';
    $output .= '</li></ul>';

    return adminConsole( $session, $output, 'Manage Registrations' );
}

1;
