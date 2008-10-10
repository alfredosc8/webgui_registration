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

    return $ac->render( $content, $title );
}

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
sub www_listPendingRegistrations {
    my $session = shift;

    my $registrationId  = $session->form->process( 'registrationId' );

    my @userIds = $session->db->buildArray("select userId from Registration_status where status='pending'and registrationId=?", [
        $registrationId,
    ]);

    my $output ; #= '<h1>Accounts waiting for approval</h1>';
    $output .= '<table>';
    foreach (@userIds) {
        my $user = WebGUI::User->new($session, $_);

        $output .= '<tr><td><a href="'.$session->url->page('func=deleteAccount;uid='.$_).'">DELETE</a></td>';
        $output .= '<td><a href="'
            .
            $session->url->page('registration=admin;registrationId='.$registrationId.';func=editRegistrationInstanceData;userId='.$_)
            .'">EDIT</a></td>';
        $output .= '<td>'.$user->username.'</td>'; #<td>'.$user->profileField('homepageUrl').'</td></tr>';
    }
    $output .= '</table>';

    return adminConsole( $session, $output, 'Pending accounts' );
}

#-------------------------------------------------------------------
sub www_editRegistrationInstanceData {
    my $session = shift;
    my $error   = shift || [];

    my $registrationId  = $session->form->process( 'registrationId' );
    my $userId          = $session->form->process( 'userId'         );

    my $registration    = WebGUI::Registration->new( $session, $registrationId, $userId );
    my $steps           = $registration->getSteps;
    my $user            = WebGUI::User->new( $session, $userId );

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
    $f->readOnly(
        label   => 'Username',
        value   => $user->username,
    );

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

    my $registrationId  = $session->form->process( 'registrationId' );
    my $userId          = $session->form->process( 'userId'         );
    my $registration    = WebGUI::Registration->new( $session, $registrationId, $userId );
    my $steps           = $registration->getSteps;

    my @error;
    # Process and error check submitted form data.
    foreach my $step ( @{ $steps } ) {
        $step->processStepApprovalData;

        push @error, @{ $step->error };
    }

    # Return to edit screen with errors if an error occurred.
    return www_editRegistrationInstanceData( $session, \@error ) if @error;

    # No errors occurred, so apply the registration steps.
    foreach my $step ( @{ $steps } ) {
        $step->apply;
    }

    return "OK!";
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
