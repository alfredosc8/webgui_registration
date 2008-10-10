package WebGUI::Registration::Step::Message;

use strict;

use WebGUI::Group;

use base qw{ WebGUI::Registration::Step };

#-------------------------------------------------------------------
sub definition {
    my $class       = shift;
    my $session     = shift;
    my $definition  = shift;

    push @{ $definition }, {
        name        => 'UserGroup',
        properties  => {},
        namespace   => 'WebGUI::Registration::Step::Message',
    };

    return $class->SUPER::definition( $session, $definition ); 
}

#-------------------------------------------------------------------
sub isComplete {
    my $self    = shift;

    return exists $self->getConfigurationData->{ messageSeen };
}

#-------------------------------------------------------------------
sub isInvisible {
    return 1;
}

#-------------------------------------------------------------------
sub processStepFormData {
    my $self    = shift;

    $self->setConfigurationData( 'messageSeen', 1 );
}

#-------------------------------------------------------------------
sub view {
    my $self = shift;

    my $registrationId = $self->registration->registrationId;

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
        -value  => $registrationId,
    );
    $f->submit;

    my $var;
    $var->{ category_name   } = 'Naam van uw site';
    $var->{ comment         } = $self->get('comment');
    $var->{ form_header     } =
        WebGUI::Form::formHeader($self->session)
        . WebGUI::Form::hidden($self->session, { name => 'func',            value => 'viewStepSave'         } )
        . WebGUI::Form::hidden($self->session, { name => 'registration',    value => 'register'             } ) 
        . WebGUI::Form::hidden($self->session, { name => 'registrationId',  value => $registrationId        } );

    $var->{ form_footer     } = WebGUI::Form::formFooter($self->session);

    my $template = WebGUI::Asset::Template->new( $self->session, $self->registration->get('stepTemplateId') );
    return $template->process($var);
}
1;

