package WebGUI::Registration::Step::AddUserToGroups;

use strict;

use WebGUI::Group;

use base qw{ WebGUI::Registration::Step };

#-------------------------------------------------------------------
sub apply {
    my $self    = shift;
    my $session = $self->session;
    my $user    = $self->registration->user;

    my @groupIds = split /\n/, $self->get('addUserToGroups');

    $user->addToGroups( \@groupIds );
}

#-------------------------------------------------------------------
sub definition {
    my $class       = shift;
    my $session     = shift;
    my $definition  = shift;
    my $i18n        = WebGUI::International->new( $session, 'Registration_Step_UserGroup' );

    tie my %fields, 'Tie::IxHash', (
        addUserToGroups         => {
            fieldType           => 'group',
            tab                 => 'properties',
            label               => $i18n->echo('Add user to groups'),
            multiple            => 1,
            size                => 5,
        },
    );

    push @{ $definition }, {
        name        => 'UserGroup',
        properties  => \%fields,
        namespace   => 'WebGUI::Registration::Step::AddUserToGroups',
        noStepCount => 1,
    };

    return $class->SUPER::definition( $session, $definition ); 
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

