package WebGUI::Registration::Step;

use strict;
use Class::InsideOut qw{ :std };
use WebGUI::HTMLForm;
use JSON;

use Data::Dumper;

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

    my $maxStepOrder    = $session->db->quickScalar(
        'select max(stepOrder) from RegistrationStep where registrationId=?',
        [
            $registration->registrationId,
        ]
    );
    
    $maxStepOrder ||= 1;

    $session->db->write(
        'insert into RegistrationStep set stepId=?, registrationId=?, options=?, stepOrder=?, namespace=?', 
        [
            $stepId,
            $registration->registrationId,
            '{ }',
            $maxStepOrder + 1,
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
sub getConfigurationData {
    my $self    = shift;
    my $userId  = shift || $self->session->user->userId;

    my $configurationData = $self->session->db->quickScalar(
        'select configurationData from RegistrationStep_accountData where userId=? and stepId=?',
        [
            $userId,
            $self->stepId,
        ]
    );
 
    return $configurationData ? decode_json($configurationData) : {};
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

    return $f;
}

#-------------------------------------------------------------------
sub getRegistration {
    my $self = shift;
    
    my $registration = WebGUI::Pluggable::instanciate( 'WebGUI::Registration', 'new', [
        $self->session,
        $self->registrationId,
    ]);
    
    return $registration;
}

#-------------------------------------------------------------------
sub getStepForm {
    my $self    = shift;

    my $f = WebGUI::HTMLForm->new( $self->session );
    $f->hidden(
        -name   => 'registration',
        -value  => 'register',
    );
    $f->hidden(
        -name   => 'func',
        -value  => 'viewStepSave',
    );
    $f->hidden(
        -name   => 'registrationId',
        -value  => $self->registrationId,
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
    return 'abcde';
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
sub processStyle {
    my $self = shift;
    my $content = shift;

    my $styleTemplateId = $self->getRegistration->styleTemplateId;

    return $self->session->style->process( $content, $styleTemplateId );
}

#-------------------------------------------------------------------
sub view {

}

#-------------------------------------------------------------------
sub setConfigurationData {
    my $self    = shift;
    my $key     = shift;
    my $value   = shift;
    my $userId  = shift || $self->session->user->userId;

    my $configurationData = $self->getConfigurationData;
    $configurationData->{ $key } = $value;

    my $json = encode_json($configurationData);
   
    $self->session->db->write('delete from RegistrationStep_accountData where stepId=? and userId=?', [
        $self->stepId,
        $userId,
    ]);
    $self->session->db->write('insert into RegistrationStep_accountData set configurationData=?, stepId=?, userId=?', [
        $json,
        $self->stepId,
        $userId,
    ]);
}


#-------------------------------------------------------------------
sub update {
    my $self        = shift;
    my $properties  = shift;
    my $session     = $self->session;
    
    my $newOptions  = { %{ $self->options }, %{ $properties } };
    
    $options{ id $self } = $newOptions;
$session->errorHandler->warn( Dumper($newOptions) );

    $session->db->write('update RegistrationStep set options=? where stepId=?', [
        encode_json( $newOptions ),
        $self->stepId,
    ]);
}

#-------------------------------------------------------------------
sub www_edit {
    my $self = shift;

    my $f = $self->getEditForm;
    $f->submit;

    return $f->print;
}

#-------------------------------------------------------------------
sub www_view {
    my $self = shift;

    return $self->processStyle( $self->view );
}

1;

