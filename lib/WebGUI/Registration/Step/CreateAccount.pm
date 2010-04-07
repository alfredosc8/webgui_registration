package WebGUI::Registration::Step::CreateAccount;

use strict;

use Data::Dumper;
use List::Util qw{ first };
use WebGUI::Form;

use base qw{ WebGUI::Registration::Step };

#-------------------------------------------------------------------
sub apply {
    my $self    = shift;
    my $session = $self->session;
    my $user    = $self->registration->instance->user;

    $user->enable;
    $session->user( { userId => $user->userId } );
}

#-------------------------------------------------------------------
sub crud_definition {
    my $class       = shift;
    my $session     = shift;
    my $definition  = $class->SUPER::crud_definition( $session );

    $definition->{ dynamic }->{ createAccountTemplateId } = {
        fieldType   => 'template',
        label       => 'Template',
        tab         => 'properties',
        namespace   => 'Registration/Step/CreateAccount',
    };
    $definition->{ dynamic }->{ requireEmailValidation } = {
        fieldType   => 'yesNo',
        label       => 'Always validate email?',
        tab         => 'properties',
        default     => 1,
    };
    return $definition;
}

##-------------------------------------------------------------------
#sub getEditForm {
#    my $self    = shift;
#    my $session = $self->session;
#    my $tabform = $self->SUPER::getEditForm();
#
#    return $tabform; 
#}

##-------------------------------------------------------------------
#sub getSummaryTemplateVars {
#    my $self            = shift;
#    my $session         = $self->session;
#    my $user            = $self->registration->instance->user;
#    my @categoryLoop;
#
#    return @categoryLoop;
#}

#-------------------------------------------------------------------
sub isComplete {
    my $self = shift;
    
    return 1 unless $self->session->user->isVisitor;

    return $self->getConfigurationData->{ status } eq 'complete';
    return !$self->registration->instance->hasAutoAccount;
}

##-------------------------------------------------------------------
#sub updateFromFormPost {
#    my $self = shift;
#
#    $self->SUPER::updateFromFormPost;
#
#    $self->update({
#        profileSteps        => $profileSteps,
#        profileOverrides    => $profileOverrides, 
#    });
#}


#-------------------------------------------------------------------
sub processStepFormData {
    my $self    = shift;
    my $session = $self->session;
    my $form    = $session->form;

    my @required = 
        qw{ username email identifier identifierConfirm captcha }, 
        map     { $_->getId } 
        grep    { $_->isRequired }
                @{ WebGUI::ProfileField->getRegistrationFields( $session ) }
    ;
    foreach ( @required ) {
        $self->pushError( "$_ is required" ) unless $form->get( $_ );
    }
    
    my $requestedUser   = WebGUI::User->newByUsername( $session, $form->get('username') );
    my $emailUser       = WebGUI::User->newByEmail( $session, $form->get('email') );

    if    ( !$emailUser && !$requestedUser ) {
        # ok!
    }
    elsif ( $emailUser &&  $emailUser->isEnabled && !$requestedUser ) {
        # reminder
        $self->pushError( $self->remindPassword );
    }
    elsif ( $emailUser && !$emailUser->isEnabled && !$requestedUser ) {
        # ok! newsletter/crm user
    }
    elsif ( !$emailUser && $requestedUser ) {
        # bezet
        $self->pushError( 'The requested username is already in use by another user' );
    }
    elsif ( $emailUser && $requestedUser && $emailUser->userId eq $requestedUser->userId && $requestedUser->isEnabled ) {
        # reminder
        $self->pushError( $self->remindPassword );
    }
    elsif ( $emailUser && $requestedUser && $emailUser->userId eq $requestedUser->userId && !$requestedUser->isEnabled ) {
        # deactivated
        # Wat melden we hier?
    }
    elsif ( $emailUser && $requestedUser && $emailUser->userId ne $requestedUser->userId ) {
        # reminder voor account bij email adres
        $self->pushError( $self->remindPassword );
    }
    else {
        # Onvoorzien!!!
    }


#    if ( $requestedUser && $requestedUser->isEnabled ) {
#        $self->pushError( 'The requested username is already in use by another user' );
#    }
#    if ( $emailUser && $emailUser->isEnabled ) {
#        $self->pushError( 'The requested email address is already in use by another account.' );
#    };
    if ( $form->get('identifier') ne $form->get('identifierConfirm') ) {
        $self->pushError( 'The password you entered doesn\'t match its confirmation' );
    };
    unless ( $form->captcha( 'captcha' ) ) {
        $self->pushError( 'The captcha you entered does not match the image' );
    };

    unless ( @{$self->error} ) {
        my $user = $self->registration->instance->user;

        $user->update( { 
            map {( 
                    $_->getId => $_->formField( {}, 2, $user )
                )}
                @{ WebGUI::ProfileField->getRegistrationFields( $session ) }
        } );

        if ( !$user->isEnabled ) {
            $user->username( $form->get('username') );
            $user->update( { email => $form->get('email') } );
            $user->disable;

            my $auth = WebGUI::Auth::WebGUI->new( $session );
            $auth->saveParams( $user->userId, $auth->authMethod, { 
                identifier => $auth->hashPassword( $form->get('identifier') ) 
            } );

            $self->setConfigurationData( status => 'created_temp_account' );
        }

        if ( $self->get('requireEmailValidation') ) {
            $self->sendConfirmationMail( $user );
        }
        else {
            $self->setConfigurationData( status => 'complete' );
        }

#        if ($session->user->isVisitor) {
#            $session->user( { userId => $user->getId } );
#        }
    }

    # Return no errors since there aren't any.
    return [];
};

#-------------------------------------------------------------------
sub getViewVars {
    my $self    = shift;
    my $session = $self->session;
    my $form    = $session->form;

    my $var = $self->SUPER::getViewVars;

    if ( $self->getConfigurationData->{ status } eq 'wait_for_confirm' ) {
        $var->{ comment } =
            'Er is een email gestuurd naar het doro u opgegeven emailadres ter controle. Klik op de link in het mailtje om verdre te gaan';
    }
    else {

        my @fields;
        push @fields, {
            field_label         => 'Username',
            field_formElement   => WebGUI::Form::text( $session, { name=>'username', value => $form->get('username') } ),
            field_isRequired    => 1,
        };
        push @fields, {
            field_label         => 'Password',
            field_formElement   => WebGUI::Form::password( $session, { name=>'identifier', value => $form->get('identifier') } ),
            field_isRequired    => 1,
        };
        push @fields, {
            field_label         => 'Password confirmation',
            field_formElement   => WebGUI::Form::password( $session, { name=>'identifierConfirm', value => $form->get('identifierConfirm') } ),
            field_isRequired    => 1,
        };
        push @fields, {
            field_label         => 'Email',
            field_formElement   => WebGUI::Form::email( $session, { name=>'email', value => $form->get('email') } ),
            field_isRequired    => 1,
        };

        foreach my $field ( @{ WebGUI::ProfileField->getRegistrationFields( $session ) } ) {
            next if $field->getId eq 'email';

            push @fields, {
                field_label         => $field->getLabel,
                field_formElement   => $field->formField( {}, undef, undef, undef, undef, undef, 'useFormDefault' ),
                field_isRequired    => $field->isRequired,
            };
        }

        push @fields, {
            field_label         => 'Captcha',
            field_formElement   => WebGUI::Form::captcha( $session, { name=>'captcha' } ),
            field_isRequired    => 1,
        };
        push @{ $var->{ field_loop } }, @fields;
    }

    return $var;
}

#-------------------------------------------------------------------
sub sendConfirmationMail {
    my $self = shift;
    my $user = shift;
    my $session = $self->session;

    my $code = $self->session->id->generate;
    my $confirm = $self->registration->instance->getId . $code;

    $self->setConfigurationData( code => $code );

    my $body = $session->url->getSiteURL . "?registration=step;stepId=".$self->getId.";func=confirmEmail;confirmation=$confirm";

    use Data::Dumper;
    $session->log->warn( Dumper {
        from    => 'noreply@oqapi.nl',
        to      => $user->profileField('email'),
        subject => 'Confirm',
    } );

    my $mail = WebGUI::Mail::Send->create( $session, {
        from    => 'noreply@oqapi.nl',
        to      => $user->profileField('email'),
        subject => 'Confirm',
    } );
    $mail->addText( $body );
    $mail->send;

    $self->setConfigurationData( status => 'wait_for_confirm' );

    return;
}

#-------------------------------------------------------------------
sub www_confirmEmail {
    my $self = shift;
    my ($form, $id) = $self->session->quick( 'form', 'id' );

    my $confirmation = $form->get('confirmation');
    my ($instanceId, $code) = $confirmation =~ m{^(.{22})(.{22})$};

    return "Invalid confirmation" unless $id->valid( $instanceId ) && $id->valid( $code );

    my $instance = WebGUI::Registration::Instance->new( $self->session, $instanceId );
    return "Instance expired"   unless $instance;

    $self->registration->setInstance( $instance );

    $instance->update( { sessionId => $self->session->getId } );
    my $data = $instance->getStepData( $self->getId );
    
    ####TODO: Check if status is wait_for_confirm?
    return "Invalid code"       unless $code eq $data->{ code };

    $data->{ status } = 'complete';
    $instance->setStepData( $self->getId, $data );

    return $self->registration->www_view;
}

#-------------------------------------------------------------------
sub remindPassword {
    my $self = shift;

    my $url = $self->registration->get('url');
    $self->session->scratch->set( 'redirectAfterLogin', $url );

    my $string = 
          qq{An account with the username and/or emailadress already exists on this site. }
        . qq{ Click <a href="%s">here</a> to reset your password" };

    my $output = sprintf $string, "/$url?op=auth;method=recoverPassword";

    return $output;
    return $self->processStyle( $output ); 

}

1;

