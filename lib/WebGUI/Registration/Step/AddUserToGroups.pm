package WebGUI::Registration::Step::AddUserToGroups;

use strict;

use WebGUI::Group;

use base qw{ WebGUI::Registration::Step };

#-------------------------------------------------------------------
sub apply {
    my $self    = shift;
    my $session = $self->session;
    my $user    = $self->registration->instance->user;

    my @groupIds = split /\n/, $self->get('addUserToGroups');

    $user->addToGroups( \@groupIds );
}

#-------------------------------------------------------------------
sub crud_definition {
    my $class       = shift;
    my $session     = shift;
    my $definition  = $class->SUPER::crud_definition( $session );

    $definition->{ dynamic }->{ addUserToGroups } => {
        fieldType           => 'group',
        tab                 => 'properties',
        label               => 'Add user to groups',
        multiple            => 1,
        size                => 5,
    };

    return $definition;
}

#-------------------------------------------------------------------
sub hasUserInteraction {
    return 0;
}

#-------------------------------------------------------------------
sub isComplete {
    return 1;
}

#-------------------------------------------------------------------
sub isInvisible {
    return 1;
}

1;

