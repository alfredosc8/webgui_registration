package WebGUI::Registration::Step;

use strict;
use Class::InsideOut qw{ :std };
use WebGUI::HTMLForm;
use JSON;

readonly session        => my %session;
readonly stepId         => my %stepId;
readonly options        => my %options;
readonly registrationId => my %registrationId;

#-------------------------------------------------------------------
sub _buildObj {
    my $class           = shift;
    my $session         = shift;
    my $stepId          = shift;
    my $registrationId  = shift;
    my $options         = shift || {};
    my $self            = {};

    bless    $self, $class;
    register $self;

    my $id                  = id $self;
    $session        { $id } = $session;
    $stepId         { $id } = $stepId;
    $options        { $id } = $options;
    $registrationId { $id } = $registrationId;

    return $self;
}

#-------------------------------------------------------------------
sub create {
    my $class           = shift;
    my $session         = shift;
    my $registration    = shift;
    my $stepId          = $session->id->generate;
    my $namespace       = $class->definition->[0]->{ namespace };

    $session->db->write(
        'insert into RegistrationStep set stepId=?, registrationId=?, options=?, stepOrder=?, namespace=?', 
        [
            $stepId,
            $registration->registrationId,
            '{ }',
            0,
            $namespace,
        ]
    );

    my $self = _buildObj( $class, $session, $stepId, $registration->registrationId );

    return $self;
}

#-------------------------------------------------------------------
sub definition {
    my $class       = shift;
    my $session     = shift;
    my $definition  = shift || [ ];

    tie my %fields, 'Tie::IxHash', (
        title   => {
            fieldType   => 'text',
            label       => 'title',
#            label       => $i18n->echo('title'),
#            hoverHelp   => $i18n->echo('title help'),
        },
    );

    push @{ $definition }, {
        name        => 'Registration Step',
        properties  => \%fields,
        namespace   => 'WebGUI::Registration::Step',
    };

    return $definition;
}

#-------------------------------------------------------------------
sub get {
    my $self    = shift;
    my $key     = shift;

    return $self->options->{ $key } if $key;

    return { %{ $self->options->{ $key } } };
}

#-------------------------------------------------------------------
sub getEditForm {
    my $self    = shift;
    my $session = $self->session;

    my $f = WebGUI::HTMLForm->new( $session );
    $f->hidden(
        -name   => 'registration',
        -value  => 'register',
    );
    $f->hidden(
        -name   => 'func',
        -value  => 'editStepSave',
    );
    $f->hidden(
        -name   => 'stepId',
        -value  => $self->stepId,
    );
    $f->hidden(
        -name   => 'registrationId',
        -value  => $self->registrationId,
    );
    $f->dynamicForm( $self->definition, 'properties', $self );
    $f->submit;

    return $f;
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
sub getStep {
    my $class       = shift;
    my $session     = shift;
    my $stepId      = shift;

    # Figure out namespace of step
    my $namespace   = $session->db->quickScalar( 'select namespace from RegistrationStep where stepId=?', [
        $stepId,
    ]);

    # Instanciate
    my $step        = WebGUI::Pluggable::instanciate( $namespace, 'new', [
        $session,
        $stepId,
    ]);

    return $step;
}

#-------------------------------------------------------------------
sub getStepsForRegistration {
    my $class           = shift;
    my $session         = shift;
    my $registrationId  = shift;
    my @steps;

    #### TODO: Hier getStep gebruiken.
    my $sth = $session->db->read( 
        'select stepId, namespace from RegistrationStep where registrationId=? order by stepOrder',
        [
            $registrationId,
        ]
    );

    while (my $row = $sth->hashRef) {
        my $step = WebGUI::Pluggable::instanciate( $row->{ namespace }, 'new', [
            $session,
            $row->{ stepId },
        ]);

        push @steps, $step;
    }

    return \@steps;
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
    
    my $properties  = $session->db->quickHashRef( 'select * from RegistrationStep where stepId=?', [
        $stepId,
    ]);

    my $self = $class->_buildObj( $session, $stepId, $properties->{ registrationId }, decode_json( $properties->{ options } ) );

    return $self;
}

#-------------------------------------------------------------------
sub processPropertiesFromFormPost {
    my $self    = shift;
    my $session = $self->session;
    my %properties;

    foreach my $definition ( @{ $self->definition( $session ) } ) {
        foreach my $property ( keys %{ $definition->{properties} } ) {
            $properties{$property} = $session->form->process(
                $property,
                $definition->{properties}{$property}{fieldType},
                $definition->{properties}{$property}{defaultValue}
            );
        }
    }
#    $properties{title} = $fullDefinition->[0]{name} if ($properties{title} eq "" || lc($properties{title}) eq "untitled");
    $self->update(\%properties);
}

#-------------------------------------------------------------------
sub processStepFormData { 

}

#-------------------------------------------------------------------
sub view {

}

#-------------------------------------------------------------------
sub update {
    my $self        = shift;
    my $properties  = shift;
    my $session     = $self->session;

    $session->db->write('update RegistrationStep set options=? where stepId=?', [
        encode_json( $properties ),
        $self->stepId,
    ]);
}

1;

