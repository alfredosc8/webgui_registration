package WebGUI::Registration::Admin;

use strict;

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

        $output .= "<li>$editButton $stepsButton " .  $registration->get('title') . '</li>';
    }

    $output .= '<li><a href="'.$session->url->page('registration=admin;func=addRegistration').'">NEW REG</a>';
    $output .= '</li></ul>';

    return $output;
}

1;
