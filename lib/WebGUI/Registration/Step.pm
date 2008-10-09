package WebGUI::Registration::Step;

use strict;
use Class::InsideOut qw{ :std };
use WebGUI::HTMLForm;
use JSON;

use Data::Dumper;

readonly session        => my %session;
readonly stepId         => my %stepId;
readonly options        => my %options;
readonly registration   => my %registration;
readonly error          => my %error;

#-------------------------------------------------------------------
sub _buildObj {
    my $class           = shift;
    my $session         = shift;
    my $stepId          = shift;
    my $registration    = shift;
    my $options         = shift || {};
    my $self            = {};

    bless    $self, $class;
    register $self;

    my $id                  = id $self;
    $session        { $id } = $session;
    $stepId         { $id } = $stepId;
    $options        { $id } = $options;
    $registration   { $id } = $registration;
    $error          { $id } = [];

    return $self;
}

#-------------------------------------------------------------------
sub apply {
    return;
}

#-------------------------------------------------------------------
sub changeStepDataUrl {
    my $self    = shift;

    return $self->session->url->page(
        'registration=register;func=viewStep;stepId='.$self->stepId.';registrationId='.$self->registration->registrationId
    );
}

#-------------------------------------------------------------------
sub create {
    my $class           = shift;
    my $session         = shift;
    my $registration    = shift;
    my $stepId          = $session->id->generate;
    my $namespace       = $class->definition( $session )->[0]->{ namespace };

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

    my $self = _buildObj( $class, $session, $stepId, $registration );

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
        comment => {
            fieldType   => 'HTMLArea',
            label       => 'Comments',
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
sub exportedVariables {
    my $self    = shift;
    my @exports;

    foreach ( @{ $self->definition( $self->session ) }  ) {
        my $stepExports = $_->{ exports } || [];
        push @exports, @{ $stepExports };
    }

    return \@exports;
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
    my $userId  = shift || $self->registration->user->userId;

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
sub getExportVariable {
    my $self    = shift;
    my $key     = shift;

    # $key has the format: StepID~VarName
    my ($stepId, $variable) = ($key =~ m{^([^~]+)~(.+)$});

    my $step    = $self->registration->getStep( $stepId );
    my $value   = $step->getConfigurationData->{ $variable };

    return $value;
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
        -value  => $self->registration->registrationId,
    );
    $f->dynamicForm( $self->definition( $session ), 'properties', $self );

    return $f;
}

#-------------------------------------------------------------------
sub getExportVariablesSelectBox {
    my $self    = shift;
    my $name    = shift;
    my $type    = shift;
    my $value   = shift || '';

    my $session = $self->session;
    my @steps   = @{ $self->registration->getSteps };

    tie my %options, 'Tie::IxHash';
    
    # Loop over all steps and extract relevant export variables.
    foreach my $step ( @steps ) {
        # Stop at this step, since we cannot get data from the future.
        last if ($step->stepId eq $self->stepId);

        # Fetch the relevant varaiables from the step.
        my @stepVariables =  
            grep    { $_->{ type } eq $type }
                    @{ $step->exportedVariables }
            ;
    
        # And add to the select box options
        foreach my $variable ( @stepVariables ) {
            $options{ $step->stepId . '~' . $variable->{name} }  = $step->get('title') . '::' . $variable->{label};
        }
    }

    my $formElement = WebGUI::Form::selectBox( $session, {
        name    => $name,
        options => \%options,
        value   => $value,
    });

    return $formElement;
}

#-------------------------------------------------------------------
sub getSubstepStatus {
    return [];
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
        -value  => $self->registration->registrationId,
    );

    return $f;
}

#-------------------------------------------------------------------
sub newByDynamicClassname {
    my $class           = shift;
    my $session         = shift;
    my $stepId          = shift;
    my $registration    = shift;

    # Figure out namespace of step
    my $namespace   = $session->db->quickScalar( 'select namespace from RegistrationStep where stepId=?', [
        $stepId,
    ]);

    # Instanciate
    my $step        = WebGUI::Pluggable::instanciate( $namespace, 'new', [
        $session,
        $stepId,
        $registration,
    ]);

    return $step;
}


#-------------------------------------------------------------------
sub getSummaryTemplateVars {
    return ( );
}

#-------------------------------------------------------------------
sub isComplete {
    return 'abcde';
}

#-------------------------------------------------------------------
sub new {
    my $class           = shift;
    my $session         = shift;
    my $stepId          = shift;
    my $registration    = shift;
    
    my $properties  = $session->db->quickHashRef( 'select * from RegistrationStep where stepId=?', [
        $stepId,
    ]);

    my $self = $class->_buildObj( $session, $stepId, $registration, decode_json( $properties->{ options } ) );

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
=head2 processStepApprovalData

This method is used to process all step instance data at once. Will call processStepFormData by default. If your
step does not have substeps, you won't have to override this method.

=cut

sub processStepApprovalData {
    my $self = shift;

    return $self->processStepFormData;
}

#-------------------------------------------------------------------
sub processStyle {
    my $self    = shift;
    my $content = shift;

#### TODO: deze method verwijderen. en WG::Reg::processStyle gebruiken.
    return $self->registration->processStyle( $content );
}

#-------------------------------------------------------------------
sub pushError {
    my $self            = shift;
    my $errorMessage    = shift || return;

    push @{ $error{ id $self } }, $errorMessage;
}

#-------------------------------------------------------------------
sub view {

}

#-------------------------------------------------------------------
sub setConfigurationData {
    my $self    = shift;
    my $key     = shift;
    my $value   = shift;
    my $userId  = shift || $self->registration->user->userId;

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
sub setExportVariable {
    my $self    = shift;
    my $key     = shift;
    my $value   = shift;

    $self->setConfigurationData( $key, $value );
}

#-------------------------------------------------------------------
sub update {
    my $self        = shift;
    my $properties  = shift;
    my $session     = $self->session;
    
    my $newOptions  = { %{ $self->options }, %{ $properties } };
    
    $options{ id $self } = $newOptions;

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

