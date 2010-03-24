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

    return !$self->registration->instance->hasAutoAccount;
    return !$self->session->user->isVisitor;
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

    if ( $requestedUser && $requestedUser->isEnabled ) {
        $self->pushError( 'The requested username is already in use by another user' );
    };
    if ( $emailUser && $emailUser->isEnabled ) {
        $self->pushError( 'The requested email address is already in use by another account.' );
    };
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
    my $var = $self->SUPER::getViewVars;
    push @{ $var->{ field_loop } }, @fields;

    return $var;
}

1;

