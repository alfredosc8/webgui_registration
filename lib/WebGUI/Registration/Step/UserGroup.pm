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
sub definition {
    my $class       = shift;
    my $session     = shift;
    my $definition  = shift;
    my $i18n        = WebGUI::International->new( $session, 'Registration_Step_UserGroup' );

    tie my %fields, 'Tie::IxHash', (
        groupNamePrefix         => {
            fieldType           => 'text',
            tab                 => 'properties',
            label               => 'Group name prefix',
        },
        addUserToGroup          => {
            fieldType           => 'yesNo',
            tab                 => 'properties',
            label               => $i18n->echo('Add user to user group'),
            defaultValue        => 1,
        },
        userIsGroupAdmin        => {
            fieldType           => 'yesNo',
            tab                 => 'properties',
            label               => $i18n->echo('Make user group admin'),
            defaultValue        => 0,
        },
        additionalGroups        => {
            fieldType           => 'group',
            tab                 => 'properties',
            label               => $i18n->echo('Add additional groups to user group'),
            multiple            => 1,
            size                => 5,
        },
    );

    my $exports = [
        {
            name    => 'userGroup',
            type    => 'groupId',
            label   => 'Created user group',
        },
    ];
 
    push @{ $definition }, {
        name        => 'UserGroup',
        properties  => \%fields,
        exports     => $exports,
        namespace   => 'WebGUI::Registration::Step::UserGroup',
    };

    return $class->SUPER::definition( $session, $definition ); 
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
        if (scalar(@{ $group->getUsers }) <= 1) {
            push @deleteGroups, $group;
        }
    }
    
    # Construct removal message
    my $message = 'Groups: '. join(', ', map {$_->name} @deleteGroups);

    # Remove groups if doit
    if ($doit) {
        $_->delete for (@deleteGroups);
    }    

    # Clean up step data
    $self->SUPER::onDeleteAccount( $doit );

    # Return notification string.
    return $message; 
}

1;

