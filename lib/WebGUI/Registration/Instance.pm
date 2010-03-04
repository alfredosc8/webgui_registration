package WebGUI::Registration::Instance;

use strict;

use base qw{ WebGUI::Crud };

#----------------------------------------------------------------------------
sub crud_definition {
    my $class       = shift;
    my $session     = shift;
    my $definition  = shift;

    $definition->{ tableName    } = 'RegistrationInstance';
    $definition->{ tableKey     } = 'instanceId';
    $definition->{ sequenceKey  } = 'registrationId';

    $definition->{ properties }->{ registrationId } = {
        fieldType       => 'guid',
        noFormPost      => 1,
    };
    $definition->{ properties }->{ userId } = {
        fieldType       => 'guid',
        noFormPost      => 1,
    };
    $definition->{ properties }->{ status } = {
        fieldType       => 'text',
        defaultValue    => 'incomplete',
        noFormPost      => 1,
    };
    $definition->{ properties }->{ stepData } = {
        fieldType       => 'textarea',
        defaultValue    => {},
        serialize       => 1,
        noFormPost      => 1,
    };

    return $definition;
}

#----------------------------------------------------------------------------
sub newByUserId {
    my $class           = shift;
    my $session         = shift;
    my $registrationId  = shift;
    my $userId          = shift;

    my $id = $class->getAllIds( $session, {
        sequenceKeyValue    => $registrationId,
        contstraints        => [ 
            { 'userId=?'  => $userId },
        ],
    } );

    return $class->new( $session, $id->[0] ) if $id->[0];

    return;
}

#----------------------------------------------------------------------------
sub getStepData {
    my $self    = shift;
    my $stepId  = shift;

    my $data = $self->get( 'stepData' );

    return $data->{ $stepId };
}

#----------------------------------------------------------------------------
sub setStepData {
    my $self    = shift;
    my $stepId  = shift;
    my $data    = shift;

    my $stepData   = $self->get( 'stepData' );
    $stepData->{ $stepId } = $data;

    $self->update({ stepData => $stepData });

    return;
}

#----------------------------------------------------------------------------
sub user {
    my $self = shift;

    #### TODO: Caching.
    return WebGUI::User->new( $self->session, $self->get('userId') );
}

1;

