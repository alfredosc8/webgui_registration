package WebGUI::Registration::Invitation;

use strict;
use warnings;

use base 'WebGUI::Crud';

sub crud_definition {
    my $class       = shift;
    my $session     = shift;
    my $definition  = $class->SUPER::crud_definition( $session );

    $definition->{ tableName    } = 'Registration_invitationCode';
    $definition->{ tableKey     } = 'code';
    $definition->{ sequenceKey  } = 'registrationId';

    $definition->{ properties }->{ registrationId } = {
        fieldType       => 'guid',
    };
    $definition->{ properties }->{ email } = {
        fieldType       => 'email',
    };
    $definition->{ properties }->{ status } = {
        fieldType       => 'text',
    };

    return $definition;
}

sub create {
    my $class   = shift;
    my $session = shift;
    my @params  = @_;

    my $self = $class->SUPER::create( $session, @params );

    $self->update( { code => $session->id->generate } );

    return $self;
}

sub isValid {
    my $self    = shift;

    return $self->get('status') ne 'used';
}

1;

