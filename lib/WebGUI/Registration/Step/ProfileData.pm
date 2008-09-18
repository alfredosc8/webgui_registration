package WebGUI::Registration::Step::ProfileData;

use strict;

use Data::Dumper;

use base qw{ WebGUI::Registration::Step };



#-------------------------------------------------------------------
sub definition {
    my $class       = shift;
    my $session     = shift;
    my $definition  = shift;

    tie my %fields, "Tie::IxHash", (
        profileOverrides    => {
            fieldType   => 'readOnly',
        },
        profileSteps => {
            fieldType   => 'readOnly',
        },
    );

    push @{ $definition }, {
        name        => 'ProfileData',
        properties  => \%fields,
        namespace   => 'WebGUI::Registration::Step::ProfileData',
    };

    return $class->SUPER::definition( $session, $definition );
}

#-------------------------------------------------------------------
sub getEditForm {
    my $self    = shift;
    my $f       = $self->SUPER::getEditForm();
 
    # Fetch and deserialize configuration data
    my $profileOverrides    = $self->get('profileOverrides');
    my $profileSteps        = $self->get('profileSteps');

    my ($availableCategories, $categoryMap);
    tie %$availableCategories, 'Tie::IxHash';
    $availableCategories->{''}  = 'None';

    # Overrides form
    $f->fieldSetStart( 'Profile overrides' );

    foreach my $category (@{ WebGUI::ProfileCategory->getCategories($self->session) }) {
        $availableCategories->{$category->getId} = $category->getLabel;
        
        # Add profile override controls for this category and its fields
        $f->readOnly(
            -value      => '<b>'.$category->getLabel.'</b>',
        );

        # Process each field within this category
        foreach my $field (@{ $category->getFields }) {
            # Create override form for this field
            my $fieldForm = WebGUI::HTMLForm->new($self->session);
            $fieldForm->checkbox(
                -name       => 'override_'.$field->getId.'_required',
                -label      => 'Required',
                -checked    => $profileOverrides->{ $field->getId }->{ required },
            );
            $fieldForm->textarea(
                -name       => 'override_'.$field->getId.'_comment',
                -label      => 'Comment',
                -value      => $profileOverrides->{ $field->getId }->{ comment },
            );
        
            # Add override form to the tab
            $f->readOnly(
                -label      => $field->getLabel,
                -value      => '<table style="width: 100%;"><tbody>'.$fieldForm->printRowsOnly.'</tbody></table>',
            );
        }
    }
    $f->fieldSetEnd;

    # Add profile step fields
    $f->fieldSetStart( 'Profile steps' );
    for my $i (1 .. 10) {
        my $profileStepForm .= WebGUI::Form::selectBox($self->session,
            -name       => "profileStep$i",
            -options    => $availableCategories,
            -value      => $profileSteps->{ "profileStep$i" } || "",
        );  
        $profileStepForm .= WebGUI::Form::textarea($self->session,
            -name       => "profileStepComment$i",
            -value      => $profileSteps->{ "profileStepComment$i" },
        );

        $f->readOnly(
            -label      => "Profile step $i",
            -value      => $profileStepForm,
        );
    }
    $f->fieldSetEnd;

    return $f; 
}

#-------------------------------------------------------------------
sub getSummaryTemplateVars {
    my $self            = shift;
    my $session         = $self->session;
    my @categoryLoop    = ();

    # Get entered profile data
    my $profileSteps = $self->get('profileSteps');
    my @categories = map    { $profileSteps->{$_} } 
                     sort 
                     grep   /^profileStep\d\d?$/, 
                            keys %$profileSteps;

    # And put into tmpl_vars
    foreach my $categoryId ( @categories ) {
        my $category = WebGUI::ProfileCategory->new($session, $categoryId);

        next unless $category->getLabel;
      
        my @fields;
        foreach my $field (@{ $category->getFields }) {
            push(@fields, {
                field_label       => $field->getLabel,
                field_value       => $field->formField(undef, 2),
            });
        }

        push( @categoryLoop, {
            field_loop          => \@fields,
            category_label      => $category->getLabel,
            category_id         => $category->getId,
#### TODO: URL goed maken.
            category_edit_url   => $session->url->page('func=getProfileCategoryData;categoryId='.$category->getId),
        });
    }

    return @categoryLoop;
}

#-------------------------------------------------------------------
sub isComplete {
    my $self = shift;
$self->session->errorHandler->warn( 'in iscomplete');

    my $completedProfileCategories  = $self->getConfigurationData->{ completedProfileCategories } || {};
    my $profileSteps                = $self->get('profileSteps');

$self->session->errorHandler->warn( Dumper( $completedProfileCategories ) );
$self->session->errorHandler->warn( Dumper( $profileSteps ) );

    foreach ( grep { /^profileStep\d+$/ } keys %{ $profileSteps } ) {
        return 0 unless $completedProfileCategories->{ $profileSteps->{$_} };
    }

    return 1;
}

#-------------------------------------------------------------------
sub processPropertiesFromFormPost {
    my $self = shift;

    $self->SUPER::processPropertiesFromFormPost;

    # Process profile overrides
    my $profileOverrides = {};
    foreach my $fieldId ( map { $_->getId } @{ WebGUI::ProfileField->getFields($self->session) } ) {
        for ( qw(comment required) ) {
            $profileOverrides->{ $fieldId }->{ $_ } = $self->session->form->process('override_'.$fieldId.'_'.$_);
        } 
    }

    # Process profile steps
    my $profileSteps = {};
    my $newCount = 1;
    for my $i (1 .. 10) {
        if ($self->session->form->process("profileStep$i")){
            $profileSteps->{ "profileStep$newCount"        } = $self->session->form->process("profileStep$i");
            $profileSteps->{ "profileStepComment$newCount" } = $self->session->form->process("profileStepComment$i"); 
            $newCount++;
        }
    }

    $self->update({
        profileSteps        => $profileSteps,
        profileOverrides    => $profileOverrides, 
    });
}


#-------------------------------------------------------------------
sub processStepFormData {
    my $self = shift;

    return $self->www_getProfileCategoryDataSave;
};

#-------------------------------------------------------------------
sub view {
    my $self = shift;

    return $self->www_getProfileCategoryData;
}


#-------------------------------------------------------------------
sub www_getProfileCategoryData {
    my $self    = shift;
    my $error   = shift || [];


    my $profileOverrides    = $self->get('profileOverrides');
    my $profileSteps        = $self->get('profileSteps');
    my $categoryId          = $self->session->scratch->get('currentCategoryId') 
                              || $self->session->form->process('categoryId') 
                              || $profileSteps->{ profileStep1 };

    # Figure out current sub step
    my $currentStep = { reverse %$profileSteps }->{ $categoryId };
    $currentStep    =~ s{^profileStep(\d+)$}{$1} || 1;

    # Setup HTMLForm 
    my $f = WebGUI::HTMLForm->new($self->session);
    $f->hidden(
        -name   => 'func',
        -value  => 'viewStepSave',
    );
    $f->hidden(
        -name   => 'registration',
        -value  => 'register',
    );
    $f->hidden(
        -name   => 'registrationId',
        -value  => $self->registrationId,
    );
    $f->hidden(
        -name   => 'categoryId',
        -value  => $categoryId,
    );

    my @fieldLoop;
    my $category = WebGUI::ProfileCategory->new($self->session, $categoryId);
    foreach my $field (@{ $category->getFields }) {
        next unless $field->get('visible');

        # Add form element to HTMLForm
        $f->raw(
            $field->formField({}, 1),
        );

        # Add form element to field loop
        push @fieldLoop, {
            field_label         => $field->getLabel,
            field_formElement   => $field->formField,
            field_subtext       => $profileOverrides->{ $field->getId }->{ comment  },
            field_isRequired    => $profileOverrides->{ $field->getId }->{ required },
        }
    }

    $f->submit( -value => 'Volgende stap' );

    # Setup tmpl_vars
    my $var;
    $var->{ category_name   } = $category->getLabel;
    $var->{ comment         } = $profileSteps->{ "profileStepComment".$currentStep };
    $var->{ form            } = $f->print;
    $var->{ field_loop      } = \@fieldLoop;
    $var->{ form_header     } = 
        WebGUI::Form::formHeader($self->session)
        . WebGUI::Form::hidden($self->session, { name => 'func',            value => 'viewStepSave'         } )
        . WebGUI::Form::hidden($self->session, { name => 'registration',    value => 'register'             } ) 
        . WebGUI::Form::hidden($self->session, { name => 'registrationId',  value => $self->registrationId  } )
        . WebGUI::Form::hidden($self->session, { name => 'categoryId',  value => $categoryId                } );
    $var->{ form_footer     } = WebGUI::Form::formFooter($self->session);
    $var->{ error_loop      } = [ map { {error_message => $_} } @$error ];

    my $template = WebGUI::Asset::Template->new($self->session, $self->getRegistration->stepTemplateId);
    return $template->process($var);
}

#-------------------------------------------------------------------
sub www_getProfileCategoryDataSave {
    my $self    = shift;
    my $session = $self->session;

    # Check priviledges
##    return $self->www_setupSite unless $self->canSetupSite;
    
    # Fetch the profile step and override data
    my $profileSteps     = $self->get('profileSteps');
    my $profileOverrides = $self->get('profileOverrides');

    # Figure out the current step. We don't use the scratch var because that doesn't protect against reloads.
    # Doing it this way the order is still enforced.
    my $categoryId  = $self->session->form->process('categoryId');
    my $currentStep = { reverse %$profileSteps }->{$categoryId};           # switch keys/values to do reverse lookup.
    $currentStep    =~ s{^profileStep(\d+)$}{$1};

    my $completedProfileCategories = $self->getConfigurationData->{ completedProfileCategories } || {};
    delete $completedProfileCategories->{ $categoryId };

    my @error;
    # Process category data
    my $category = WebGUI::ProfileCategory->new($self->session, $categoryId);
    
    foreach my $field (@{ $category->getFields }) {
        next unless $field->get('visible');

        my $profileFieldData = $field->formProcess;

        # Check for required fields.
        if ($profileOverrides->{ $field->getId }->{ required } && !$profileFieldData) {
            push (@error, $field->getLabel.' is verplicht');
        }
        else {
            # TODO: Wellicht ook iets doen als: error if (form->param('field') && !$profileFieldData)
            # TODO: Check if arrays are saved correctly
            $session->user->profileField($field->getId, $profileFieldData);
        }
    }
   
    # Return form with error messages
    if (@error) {
        # Make sure this category is not marked as complete.
        delete $completedProfileCategories->{ $categoryId };
        $self->setConfigurationData('completedProfileCategories' => $completedProfileCategories );

        ### Hoe gaan we de erreurs terugkoppelen...
        return $self->www_getProfileCategoryData(\@error);
    } else {
        # Mark this category as completed.
        $completedProfileCategories->{ $categoryId } = 1;
        $self->setConfigurationData('completedProfileCategories' => $completedProfileCategories );
    }

    # Data correct so proceed with next step
    my $nextStep = $currentStep + 1;

#### Dit moet worden verplaatst naar de logica in Reg.
    # Are we editing a complete profile? If so return to the confirmation page
##    return $self->www_confirmProfileData if $self->session->scratch->get('profileComplete');
    
    # Last step? Proceed with medical import data
    unless (exists $profileSteps->{"profileStep$nextStep"}) {
        $self->session->scratch->delete('currentProfileStep');

#        return $self->www_collectMedicalEncyclopediaImportCategories;
    }

    # Else proceed with next step
    $self->session->scratch->set('currentProfileStep', $nextStep);
    $self->session->scratch->set('currentCategoryId', $profileSteps->{"profileStep$nextStep"});
#    return $self->www_getProfileCategoryData([], $profileSteps->{"profileStep$nextStep"});
}

1;


