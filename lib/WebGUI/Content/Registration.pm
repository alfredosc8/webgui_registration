package WebGUI::Content::Registration;

use strict;
use WebGUI::Registration;
use WebGUI::Registration::Admin;
use WebGUI::Utility;
use JSON;

sub handler {
    my $session = shift;
    my $registrationId;
    my $output;

    my $system = $session->form->process( 'registration' );

    my $triggerUrls = decode_json( $session->setting->get( 'registrationUrlTriggers' ) || '{}' );

    if ( isIn( $session->url->getRequestedUrl, keys %{ $triggerUrls } ) && !$system ) {
        $system         = 'register';
        $registrationId = $triggerUrls->{ $session->url->getRequestedUrl };
    }

    $system = 'www_'.$system;

    if ( $system =~ /^[\w_]+$/ && ( my $sub = __PACKAGE__->can( $system ) ) ) {
        $output = $sub->( $session, $registrationId );
    }
    else {
        $session->errorHandler->warn("Invalid system [$system]");
    }

    return $output;
}

sub www_admin {
    my $session = shift;
    my $output;

    my $method = 'www_' . ( $session->form->process( 'func' ) || 'view' );

    if ( $method =~ /^www_[\w_]+$/ && (my $sub = WebGUI::Registration::Admin->can( $method ) ) ) {
        $output = $sub->( $session );
    }
    else {
        $session->errorHandler->warn("Cannot execute method [$method]");
    }

    return $output;
}

sub www_register {
    my $session = shift;
    my $regId   = shift || $session->form->process('registrationId');
    my $output;

    my $reg = WebGUI::Registration->new( $session, $regId );

    my $method = 'www_' . ( $session->form->process( 'func' ) || 'viewStep' );

    if ( $method =~ /^www_[\w_]+$/ && $reg->can( $method ) ) {
        $output = $reg->$method;
    }
    else {
        $session->errorHandler->warn("Cannot execute method [$method]");
    }

    return $output;
}
1;

