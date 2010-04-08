package WebGUI::Content::Registration;

use strict;
use WebGUI::Registration;
use WebGUI::Registration::Admin;
use WebGUI::Utility;
use JSON;

sub handler {
    my $session = shift;
    my $output;

    my $system  = $session->form->process( 'registration' );
    $system     = 'register' if $system eq 'registration';

    return unless $system;

    my $registrationId  = $session->form->process( 'registrationId' );
    my $triggerUrls     = decode_json( $session->setting->get( 'registrationUrlTriggers' ) || '{}' );

    if ( isIn( $session->url->getRequestedUrl, keys %{ $triggerUrls } ) && !$system ) {
        $system         = 'register';
        $registrationId = $triggerUrls->{ $session->url->getRequestedUrl };
    }
    else {
        my $asset = eval { WebGUI::Asset->newByUrl( $session, $session->url->getRequestedUrl ) };
        unless ($@) {
            $session->asset( $asset );
        };
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

sub www_instance {
    my $session = shift;
    my $form    = $session->form;
    my $output;

    my $method = 'www_' . ( $session->form->process( 'func' ) || 'edit' );

    my $instance = WebGUI::Registration::Instance->new( $session, $form->get('instanceId') );

    if ( $method =~ /^www_[\w_]+$/ && $instance->can( $method ) ) {
        $output = $instance->$method;
    }
    else {
        $session->errorHandler->warn("Cannot execute method [$method]");
    }

    return $output;
}

sub www_step {
    my $session = shift;
    my $form    = $session->form;
    my $output;

    my $method = 'www_' . ( $session->form->process( 'func' ) || 'edit' );

    my $step = WebGUI::Registration::Step->newByDynamicClass( $session, $form->get('stepId') );

    if ( $method =~ /^www_[\w_]+$/ && $step->can( $method ) ) {
        $output = $step->$method;
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

