package WebGUI::Registration::Step::Homepage;

use strict;

use base qw{ WebGUI::Registration::Step };

#-------------------------------------------------------------------
sub definition {
    my $class       = shift;
    my $session     = shift;
    my $definition  = shift;

    push @{ $definition }, {
        name        => 'Homepage',
        properties  => { },
        namespace   => 'WebGUI::Registration::Step::Homepage',
    };

    return $class->SUPER::definition( $session, $definition );
}

#-------------------------------------------------------------------
sub getSummaryTemplateVars {
    my $self = shift;

    my $preferredHomepageUrl = $self->getConfigurationData->{ preferredHomepageUrl };

    my $var = {
        field_loop          => [ 
            { 
                field_label         => 'Your homepage',
                field_value         => $preferredHomepageUrl,
                field_formElement   => WebGUI::Form::text($self->session, { 
                    name    => 'preferredHomepageUrl', 
                    value   => $preferredHomepageUrl,
                }),
            } 
        ],
        category_label      => $self->get('title'),
        category_edit_url   =>
            $self->session->url->page('registration=register;func=viewStep;stepId='.$self->stepId.';registrationId='.$self->registrationId),
    };

    return ( $var );    
}

#-------------------------------------------------------------------
sub isComplete {
    my $self = shift;

    return defined $self->getConfigurationData->{'preferredHomepageUrl'};
}

#-------------------------------------------------------------------
sub processStepFormData {
    my $self = shift;
    
##    # Check priviledges
##    return $self->www_setupSite unless $self->canSetupSite;

    # Store homepage url
    $self->setConfigurationData('preferredHomepageUrl', $self->session->form->process('preferredHomepageUrl') );
   
##    # Are we editing a complete profile? If so return to the confirmation page
##    return $self->www_confirmProfileData if $self->session->scratch->get('profileComplete');
   
##    # Else proceed with the next step;
##    return $self->www_confirmProfileData;
}

#-------------------------------------------------------------------
sub view {
    my $self = shift;

##    # Check priviledges
##    return $self->www_setupSite unless $self->canSetupSite;
    
    my $preferredHomepageUrl = 
        $self->session->form->process('preferredHomepageUrl')  
        || $self->getConfigurationData->{'preferredHomepageUrl'};

    my $f = WebGUI::HTMLForm->new($self->session);
    $f->hidden(
        -name   => 'func',
        -value  => 'viewStepSave',
    );
    $f->hidden(
        -name   => 'registration',
        -value  => 'register',
    );
    $f->hidden(
        -name   => 'registrationId',
        -value  => $self->registrationId,
    );
    $f->text(
        -name   => 'preferredHomepageUrl',
        -label  => 'www.wieismijnarts.nl/',
        -value  => $preferredHomepageUrl   
    );
    $f->submit;

    my $var;
    $var->{ category_name   } = 'Naam van uw site';
    $var->{ comment         } = $self->get('homepageUrlComment');
    $var->{ form            } = $f->print;
    $var->{ form_header     } =
        WebGUI::Form::formHeader($self->session)
        . WebGUI::Form::hidden($self->session, { name => 'func',            value => 'viewStepSave'         } )
        . WebGUI::Form::hidden($self->session, { name => 'registration',    value => 'register'             } ) 
        . WebGUI::Form::hidden($self->session, { name => 'registrationId',  value => $self->registrationId  } );

    $var->{ form_footer     } = WebGUI::Form::formFooter($self->session);
    $var->{ field_loop      } = 
        [
            {
                field_label         => 'www.wieismijnarts.nl/',
                field_formElement   => 
                    WebGUI::Form::text($self->session, { 
                        name    => 'preferredHomepageUrl', 
                        value   => $preferredHomepageUrl
                    }),
#                field_subtext   => 'Hier komt de subtext voor dit veld'
            }
        ];

    my $template = WebGUI::Asset::Template->new( $self->session, $self->getRegistration->get('stepTemplateId') );
    return $template->process($var);
}


1;
