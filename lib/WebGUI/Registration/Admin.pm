package WebGUI::Registration::Admin;

use strict;
use WebGUI::Registration;
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

    $ac->setIcon('/extras/spacer.gif');

    return $ac->render( $content, $title );
}

#-------------------------------------------------------------------
sub www_addRegistration {
    my $session = shift;

    return $session->privilege->insufficient unless $session->user->isInGroup( 3 );

    my $registration    = WebGUI::Registration->create( $session );

    my $form = $registration->getEditForm;
    $form->submit;

    return adminConsole( $session, $form->print, 'Add Registration');
}


##-------------------------------------------------------------------
#sub www_createInstanceForExistingUser {
#    my $session = shift;
#
#    return $session->privilege->insufficient unless canManage( $session );
#
#    my $f = WebGUI::HTMLForm->new( $session );
#    $f->hidden(
#        name    => 'registration',
#        value   => 'admin',
#    );
#    $f->hidden(
#        name    => 'func',
#        value   => 'editRegistrationInstanceData',
#    );
#    $f->hidden(
#        name    => 'registrationId',
#        value   => $session->form->process('registrationId'),
#    );
#    $f->user(
#        name    => 'userId',
#        label   => 'Choose',
#    );
#    $f->submit(
#        value   => 'Proceed',
#    );
#
#    return adminConsole( $session, $f->print, 'Add account for existing user' );
#}


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
    my $user    = $session->user;

    my $registrationIds = WebGUI::Registration->getAllIds( $session );

    my @managable;
    foreach my $id ( @{ $registrationIds } ) {
        my $registration    = WebGUI::Registration->new( $session, $id );

        next unless $registration->canManage( $session, $id );

        my $deleteButton    = $session->icon->delete(
            "registration=registration;func=delete;registrationId=$id",
            undef,
            'Weet u zeker dat u deze registratie wil verwijderen?',
        );

        push @managable,
            "$deleteButton <a href=\"" 
            . $session->url->page("registration=registration;func=manage;registrationId=$id") 
            . '">' . $registration->get('title') . '</a>';
    }

    return return $session->privilege->insufficient unless @managable || $user->isAdmin;

    my $output .= '<ul>' . join( '</li><li>', @managable ) . '</li></ul>';
    return adminConsole( $session, $output, 'Manage Registrations' );
}

1;
