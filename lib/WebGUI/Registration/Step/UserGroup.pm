package WebGUI::Registration::Step::UserGroup;

use strict;

use WebGUI::Group;

use base qw{ WebGUI::Registration::Step };

#-------------------------------------------------------------------
sub apply {
    my $self    = shift;
    my $session = $self->session;
    my $user    = $self->registration->user;

    # Create group for user
    my $userGroup = WebGUI::Group->new($session, 'new');
    $userGroup->name( join( ' ', ($self->get('groupNamePrefix'), $user->username) ) );

    # Add user to group
    $userGroup->addUsers( [ $user->userId ] ) if ($self->get('addUserToGroup'));

    # Make user group admin
    $userGroup->userIsAdmin($user->userId, 1) if ($self->get('userIsGroupAdmin'));
    
    # Add other groups to group
    my $additionalGroups = [ split( /\n/, $self->get('additionalGroups') ) ];
    $userGroup->addGroups( $additionalGroups );

#    # Add other users to group
#    my $additionalUsers = $self->get('additionalUsers'):
#    $userGroup->addUsers( $additionalUsers );

    # Persist variable for exporting
    $self->setExportVariable( 'userGroup', $userGroup->getId );
}

#-------------------------------------------------------------------
sub crud_definition {
    my $class       = shift;
    my $session     = shift;
    my $definition  = $class->SUPER::crud_definition( $session );
    my $i18n        = WebGUI::International->new( $session, 'Registration_Step_UserGroup' );

    $definition->{ dynamic }->{ groupNamePrefix     } = {
        fieldType           => 'text',
        tab                 => 'properties',
        label               => 'Group name prefix',
    };
    $definition->{ dynamic }->{ addUserToGroup      } = {
        fieldType           => 'yesNo',
        tab                 => 'properties',
        label               => $i18n->echo('Add user to user group'),
        defaultValue        => 1,
    };
    $definition->{ dynamic }->{ userIsGroupAdmin    } = {
        fieldType           => 'yesNo',
        tab                 => 'properties',
        label               => $i18n->echo('Make user group admin'),
        defaultValue        => 0,
    };
    $definition->{ dynamic }->{ additionalGroups    } = {
        fieldType           => 'group',
        tab                 => 'properties',
        label               => $i18n->echo('Add additional groups to user group'),
        multiple            => 1,
        size                => 5,
    };

    return $definition;
}

#-------------------------------------------------------------------
sub exports {
    my $self    = shift;
    my $exports = $self->SUPER::exports;

    push @{ $exports }, {
        name    => 'userGroup',
        type    => 'groupId',
        label   => 'Created user group',
    };

    return $exports;
}

#-------------------------------------------------------------------
sub hasUserInteraction {
    return 0;
}

#-------------------------------------------------------------------
sub getSummaryTemplateVars {

}

#-------------------------------------------------------------------
sub isComplete {
    return 1;
}

#-------------------------------------------------------------------
sub isInvisible {
    return 1;
}

#-------------------------------------------------------------------
sub onDeleteAccount {
    my $self    = shift;
    my $doit    = shift;
    my $session = $self->session;
    my @deleteGroups;

    # Fetch usergroup(s) to delete
    my $groups = $self->registration->user->getGroups;
    foreach my $groupId ( @{ $groups } ) {
        my $group = WebGUI::Group->new( $session, $groupId );
        if ($group && scalar(@{ $group->getUsers }) <= 1) {
            push @deleteGroups, $group;
        }
    }
    
    # Construct removal message
    my $message = 'Groups: '. join(', ', map {$_->name} @deleteGroups);

    # Remove groups if doit
    if ($doit) {
        $_->delete for (@deleteGroups);
    }    
    
    # Clear group cache
    $session->stow->delete('isInGroup');
    $session->stow->delete('gotGroupsForUser');

    # Clean up step data
    $self->SUPER::onDeleteAccount( $doit );

    # Return notification string.
    return $message; 
}

1;

