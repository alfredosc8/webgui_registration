package WebGUI::Registration::Admin;

use strict;
use WebGUI::Registration;
####use WebGUI::Registration::Step;
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

    my $it = WebGUI::Registration::Instance->getAllIterator( $session, {
        constraints => [
            { 'registrationId=? and status=?' => [ $registrationId, $status ] },
        ],
    } );
    my $output = '<table>';

    while ( my $instance = $it->() ) {
        my $id      = $instance->getId;
        my $user    = $instance->user;

        $output .= '<tr><td><a href="'
            . $session->url->page('registration=admin;registrationId='.$registrationId.';func=deleteAccount;uid='.$_).'">DELETE</a></td>';
        $output .= '<td><a href="'
            . $session->url->page( "registration=instance;instanceId=$id;func=edit" )
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
            $registration->getId,
            $registration->instance->user->userId,
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

##-------------------------------------------------------------------
#sub www_deleteRegistration {
#    my $session = shift;
#
#    return $session->privilege->insufficient unless $session->user->isInGroup( 3 );
#
#    my $registrationId  = $session->form->process('registrationId');
#    my $registration    = WebGUI::Registration->new( $session, $registrationId );
#    $registration->delete;
#
#    return www_view( $session );
#}

##-------------------------------------------------------------------
#sub www_editRegistration {
#    my $session = shift;
#
#    return $session->privilege->insufficient unless $session->user->isInGroup( 3 );
#
#    my $registrationId  = $session->form->process('registrationId');
#    my $registration    = WebGUI::Registration->new( $session, $registrationId );
#
#    return adminConsole( $session, $registration->getEditForm->print, 'Edit Registration');
#}

##-------------------------------------------------------------------
#sub www_editRegistrationSave {
#    my $session = shift;
#
#    return $session->privilege->insufficient unless $session->user->isInGroup( 3 );
#    
#    my $registrationId  = $session->form->process('registrationId');
#    my $registration    = WebGUI::Registration->new( $session, $registrationId );
#
#    $registration->updateFromFormPost;
#
#    return www_view( $session );
#}

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
        #my $baseParams = 'registration=admin;stepId=' . $step->getId . ';registrationId=' . $registrationId;
        my $baseParams = 'registration=step;stepId=' . $step->getId;
        
        $output .= 
            '<li>'
            . $icon->delete(    "$baseParams;func=delete"   )
            . $icon->moveUp(    "$baseParams;func=promote"   )
            . $icon->moveDown(  "$baseParams;func=demote" )
            . $icon->edit(      "$baseParams;func=edit"     )
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
sub www_view {
    my $session = shift;

#    return $session->privilege->insufficient unless $session->user->isInGroup( 3 );
#    return $session->privilege->insufficient unless canManage( $session );

#    my @registrationIds = $session->db->buildArray( 'select registrationId from Registration' );
    my $registrationIds = WebGUI::Registration->getAllIds( $session );

    my $output = '<ul>';
    foreach my $id ( @{ $registrationIds } ) {
        my $registration    = WebGUI::Registration->new( $session, $id );

        next unless canManage( $session, $id );

        my $deleteButton    = $session->icon->delete(
            "registration=registration;func=delete;registrationId=$id",
            undef,
            'Weet u zeker dat u deze registratie wil verwijderen?',
        );
#        my $editButton      = $session->icon->edit(
##### TODO: Manage scherm
#            "registration=registration;func=edit;registrationId=$id",
#        );

        $output .= "<li>$deleteButton <a href=\"" 
            . $session->url->page("registration=registration;func=manage;registrationId=$id") 
            . '">' . $registration->get('title') . '</a></li>';
    }

    $output .= '</ul>';

    return adminConsole( $session, $output, 'Manage Registrations' );
}

1;
