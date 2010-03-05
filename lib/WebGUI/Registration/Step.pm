package WebGUI::Registration::Step;

use strict;
use Class::InsideOut qw{ :std };
use WebGUI::HTMLForm;
use WebGUI::Registration;
use WebGUI::Registration::Admin;
use JSON;
use Carp;

use Data::Dumper;

private  registration   => my %registration;
public   data           => my %data;
readonly error          => my %error;

use base qw{ WebGUI::Crud::Dynamic };

#-------------------------------------------------------------------
sub apply {
    return;
}

#-------------------------------------------------------------------
sub changeStepDataUrl {
    my $self    = shift;

    return $self->session->url->page(
        'registration=register;func=changeStep;stepId=' . $self->getId . ';registrationId=' . $self->registration->getId
    );
}

#-------------------------------------------------------------------
sub crud_definition {
    my $class       = shift;
    my $session     = shift;
    my $definition  = $class->SUPER::crud_definition( $session );

    $definition->{ tableName    } = 'RegistrationStep';
    $definition->{ tableKey     } = 'stepId';
    $definition->{ sequenceKey  } = 'registrationId';
####    $definition->{ registrationId   } = 'registrationId';

    $definition->{ properties }->{ registrationId } = {
        fieldType       => 'guid',
        noFormPost      => 1,
    };
    $definition->{ properties }->{ title    } = {
        fieldType       => 'text',
        label           => 'title',
    };
    $definition->{ properties }->{ comment  } = {
        fieldType       => 'HTMLArea',
        label           => 'Comments',
    };

    if ( $class->hasUserInteraction ) {
        $definition->{ dynamic   }->{ countStep } = {
            fieldType       => 'yesNo',
            label           => 'Count as seperate step?',
            defaultValue    => 1,
        };
    }

    return $definition;
}

#-------------------------------------------------------------------
sub delete {
    my $self    = shift;
    my $session = $self->session;

    $session->db->write('delete from RegistrationStep_accountData where stepId=?', [
        $self->getId,
    ]);

    $self->SUPER::delete;
}

#-------------------------------------------------------------------
sub exports {
    return [];
}

#-------------------------------------------------------------------
sub getConfigurationData {
    my $self    = shift;
#    my $userId  = shift || $self->registration->user->userId;

    return $self->data;

#    my $configurationData = $self->session->db->quickScalar(
#        'select configurationData from RegistrationStep_accountData where userId=? and stepId=?',
#        [
#            $userId,
#            $self->getId,
#        ]
#    );
# 
#    return $configurationData ? decode_json($configurationData) : {};
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

    my $tabform = WebGUI::TabForm->new( $session );
    my $f = $tabform->addTab( 'properties', 'Properties' );
    $f->hidden(
        name   => 'registration',
        value  => 'step',
    );
    $f->hidden(
        name   => 'func',
        value  => 'editSave',
    );
    $f->hidden(
        name   => 'stepId',
        value  => $self->getId,
    );
    
    tie my %props, 'Tie::IxHash', (
        %{ $self->crud_getProperties( $session )        },
        %{ $self->crud_getDynamicProperties( $session ) },
    );
    foreach my $key ( keys %props ) {
        next if $props{ $key }{ noFormPost };

        $f->dynamicField(
            %{ $props{ $key } },
            name    => $key,
            value   => $self->get( $key )
        );
    };
    
    return $tabform;
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
        last if ($step->getId eq $self->getId);

        # Fetch the relevant variables from the step.
        my @stepVariables =  
            grep    { $_->{ type } eq $type }
                    @{ $step->exports}
            ;
    
        # And add to the select box options
        foreach my $variable ( @stepVariables ) {
            $options{ $step->getId . '~' . $variable->{name} }  = $step->get('title') . '::' . $variable->{label};
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
        -value  => $self->registration->getId,
    );

    return $f;
}

#-------------------------------------------------------------------
sub getStepNumber {
    my $self        = shift;
    my $steps       = $self->registration->getSteps;
    my $stepCount   = 0;

    $stepCount++ if $self->registration->get('countLoginAsStep');

    foreach my $step ( @{ $steps } ) {
        $stepCount++ if $step->get('countStep');

        last if $step->getId eq $self->getId;
    }

    # If no step has a seperate step count we still have to return 1.
    return $stepCount || 1;
}


#-------------------------------------------------------------------
sub getViewVars {
    my $self            = shift;
    my $registrationId  = $self->registration->getId;
    
    my $var;
    $var->{ category_name   } = $self->get('title');
    $var->{ step_number     } = $self->getStepNumber;
    $var->{ comment         } = $self->get('comment');
    $var->{ form_header     } =
        WebGUI::Form::formHeader($self->session)
        . WebGUI::Form::hidden($self->session, { name => 'func',            value => 'viewStepSave'         } )
        . WebGUI::Form::hidden($self->session, { name => 'registration',    value => 'register'             } ) 
        . WebGUI::Form::hidden($self->session, { name => 'registrationId',  value => $registrationId        } );
    $var->{ form_footer     } = WebGUI::Form::formFooter($self->session);
    $var->{ field_loop      } = [ ];
    $var->{ error_loop      } = [ map { {error_message => $_} } @{ $self->error } ];
    
    return $var;
}

#-------------------------------------------------------------------
sub getSummaryTemplateVars {
    return ( );
}

#-------------------------------------------------------------------
sub hasUserInteraction {
    return 1;
}

#-------------------------------------------------------------------
sub isComplete {
    return 0;
}

#-------------------------------------------------------------------
sub isInvisible {
    return 0;
}

#-------------------------------------------------------------------
sub new {
    my $class   = shift;
    my $session = shift;
    my $stepId  = shift;
    my $data    = shift || {};

    my $self    = $class->SUPER::new( $session, $stepId );
    register $self;

    my $id                  = id $self;
    $registration   { $id } = undef;
    $error          { $id } = [];
    $data           { $id } = $data;

    return $self;
}

#-------------------------------------------------------------------
sub registration {
    my $self            = shift;
    my $session         = $self->session;
    my $registration    = $registration{ id $self };
    
    if ( !$registration ) {    
        $registration = WebGUI::Registration->new( $session, $self->get('registrationId') );
        croak "Could not instanciate Registration " . $self->get('registrationId') unless $registration;
        $registration{ id $self } = $registration;
    }

    return $registration;
}

#-------------------------------------------------------------------
sub onDeleteAccount {
    my $self    = shift;
    my $doit    = shift;
    my $session = $self->session;

    # Don't do anything when we are still reviewing.
    return unless $doit;

    # Delete step data
    $session->db->write('delete from RegistrationStep_accountData where stepId=? and userId=?', [
        $self->getId,
        $self->registration->user->userId,
    ]);

    return;
}

#-------------------------------------------------------------------
sub processStepFormData { 
    return {};
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
    my $self = shift;

    my $var = $self->getViewVars;

    my $template = WebGUI::Asset::Template->new( $self->session, $self->registration->get('stepTemplateId') );
    return $template->process($var);
}

#-------------------------------------------------------------------
sub setConfigurationData {
    my $self    = shift;
    my $key     = shift;
    my $value   = shift;
#    my $userId  = shift || $self->registration->user->userId;

    $self->data( { %{$self->data}, $key => $value } );

    return;

#
#    my $configurationData = $self->getConfigurationData;
#    $configurationData->{ $key } = $value;
#
#    my $json = encode_json($configurationData);
#   
#    $self->session->db->write('delete from RegistrationStep_accountData where stepId=? and userId=?', [
#        $self->getId,
#        $userId,
#    ]);
#    $self->session->db->write('insert into RegistrationStep_accountData set configurationData=?, stepId=?, userId=?', [
#        $json,
#        $self->getId,
#        $userId,
#    ]);
}

#-------------------------------------------------------------------
sub setExportVariable {
    my $self    = shift;
    my $key     = shift;
    my $value   = shift;

    $self->setConfigurationData( $key, $value );
}

#-------------------------------------------------------------------
sub www_delete {
    my $self = shift;

#### TODO: privs
    $self->delete;

    return WebGUI::Registration::Admin::www_listSteps( $self->session, $self->get('registrationId') );
}

#-------------------------------------------------------------------
sub www_demote {
    my $self = shift;

#### TODO: privs
    $self->demote;

    return WebGUI::Registration::Admin::www_listSteps( $self->session, $self->get('registrationId') );
}

#-------------------------------------------------------------------
sub www_edit {
    my $self = shift;

#### TODO: privs
    my $f = $self->getEditForm;
    $f->submit;

    return WebGUI::Registration::Admin::adminConsole( $self->session, $f->print, 'Edit step for ' . $self->registration->get('title') );
    return $f->print;
}

#-------------------------------------------------------------------
sub www_editSave {
    my $self = shift;

#### TODO: privs
    $self->updateFromFormPost;

    return WebGUI::Registration::Admin::www_listSteps( $self->session, $self->get('registrationId') );
}

#-------------------------------------------------------------------
sub www_promote {
    my $self = shift;

#### TODO: privs
    $self->promote;

    return WebGUI::Registration::Admin::www_listSteps( $self->session, $self->get('registrationId') );
}

#-------------------------------------------------------------------
sub www_view {
    my $self = shift;

    return $self->processStyle( $self->view );
}

1;

