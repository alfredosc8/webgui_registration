package WebGUI::Registration::Step;

use strict;
use Class::InsideOut qw{ :std };

readonly session    => my %session;
readonly stepId     => my %stepId;

#-------------------------------------------------------------------
sub _buildObj {
    my $class       = shift;
    my $session     = shift;
    my $stepId      = shift;
    my $self        = {};

    bless    $self, $class;
    register $self;

    my $id              = id $self;
    $session{   $id }   = $session;
    $stepId{    $id }   = $stepId;

    return $self;
}

#-------------------------------------------------------------------
sub create {

}

#-------------------------------------------------------------------
sub definition {
    my $class       = shift;
    my $session     = shift;
    my $definition  = shift || [];

    tie my %fields, 'Tie::IxHash', (
        title   => {
            fieldType   => 'text',
#            label       => $i18n->echo('title'),
#            hoverHelp   => $i18n->echo('title help'),
        },
    );

    my $properties = {
        name        => 'Registration Step',
        properties  => \%fields,
    };

    push @{ $definition }, $properties;

    return $definition;
}

#-------------------------------------------------------------------
sub getEditForm {
    
}

#-------------------------------------------------------------------
sub getStepForm {
    my $self    = shift;

    my $f = WebGUI::HTMLForm->new( $self->session );
    $f->hidden(
        -name   => 'registration',
        -value  => 'viewStepSave',
    );

    return $f;
}

#-------------------------------------------------------------------
sub isComplete {
    return 0;
}

#-------------------------------------------------------------------
sub new {
    my $class   = shift;
    my $session = shift;
    my $stepId  = shift;
    
    #### TODO: Fetch instance data from db

    my $self = $class->_buildObj( $session, $stepId );

    return $self;
}

#-------------------------------------------------------------------
sub processStepFormData { 

}

#-------------------------------------------------------------------
sub view {

}

1;

