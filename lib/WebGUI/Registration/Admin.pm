package WebGUI::Registration::Admin;

use strict;
use WebGUI::Registration;

use WebGUI::AdminConsole;


#-------------------------------------------------------------------
sub www_addRegistration {
    my $session = shift;

    my $registration    = WebGUI::Registration->create( $session );

    return $registration->www_edit;
}

#-------------------------------------------------------------------
sub www_editSave {

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
        $output .= '<td>'.$user->username.'</td><td>'.$user->profileField('homepageUrl').'</td></tr>';
    }
    $output .= '</table>';

    return WebGUI::AdminConsole->new( $session )->render( $output, 'Pending accounts' );
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

    return WebGUI::AdminConsole->new( $session )->render( $output, 'Approve account' );
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
#        $step->apply;
    }

    return "OK!";
}

#-------------------------------------------------------------------
sub www_view {
    my $session = shift;

    my @registrationIds = $session->db->buildArray( 'select registrationId from Registration' );

    my $output = '<ul>';
    foreach my $id ( @registrationIds ) {
        $session->errorHandler->warn("[$id]");
        my $registration    = WebGUI::Registration->new( $session, $id );

        my $editButton =
              WebGUI::Form::formHeader( $session )
            . WebGUI::Form::hidden(     $session, { -name => 'registration',    -value => 'register'    } )
            . WebGUI::Form::hidden(     $session, { -name => 'func',            -value => 'edit'        } )
            . WebGUI::Form::hidden(     $session, { -name => 'registrationId',  -value => $id           } )
            . WebGUI::Form::submit(     $session, {                             -value => 'Edit'        } )
            . WebGUI::Form::formFooter( $session );
        my $stepsButton =
              WebGUI::Form::formHeader( $session )
            . WebGUI::Form::hidden(     $session, { -name => 'registration',    -value => 'register'    } )
            . WebGUI::Form::hidden(     $session, { -name => 'func',            -value => 'listSteps'   } )
            . WebGUI::Form::hidden(     $session, { -name => 'registrationId',  -value => $id           } )
            . WebGUI::Form::submit(     $session, {                             -value => 'Steps'       } )
            . WebGUI::Form::formFooter( $session );
        my $accountButton =
              WebGUI::Form::formHeader( $session )
            . WebGUI::Form::hidden(     $session, { -name => 'registration',    -value => 'admin'           } )
            . WebGUI::Form::hidden(     $session, { -name => 'func',            -value => 'listPendingRegistrations' } )
            . WebGUI::Form::hidden(     $session, { -name => 'registrationId',  -value => $id               } )
            . WebGUI::Form::submit(     $session, {                             -value => 'Manage accounts' } )
            . WebGUI::Form::formFooter( $session );
            
        $output .= "<li>$editButton $stepsButton $accountButton" .  $registration->get('title') . '</li>';
    }

    $output .= '<li><a href="'.$session->url->page('registration=admin;func=addRegistration').'">NEW REG</a>';
    $output .= '</li></ul>';

    return $output;
}

1;
