package WebGUI::Registration::Step::ProfileData;

use strict;

use Data::Dumper;
use List::Util qw{ first };

use base qw{ WebGUI::Registration::Step };

#-------------------------------------------------------------------
sub apply {
    my $self    = shift;
    my $session = $self->session;
    my $user    = $self->registration->user;

    # Get entered profile data
    my $profileSteps = $self->get('profileSteps');
    my @categories = map    { $profileSteps->{$_} } 
                     sort 
                     grep   /^profileStep\d\d?$/, 
                            keys %$profileSteps;
    
    my $configurationData = $self->getConfigurationData;

    foreach my $categoryId ( @categories ) {
        my $category = WebGUI::ProfileCategory->new( $session, $categoryId );
   
        my $fieldData = $configurationData->{ $categoryId };
        foreach my $fieldId ( keys %{ $fieldData } ) {
            $user->profileField( $fieldId, $fieldData->{ $fieldId });
        }
    }
}

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
                -value      => 1,
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
sub getSubstepStatus {
    my $self    = shift;
    my $session = $self->session;
    my @substepStatus;

    my $profileSteps    = $self->get('profileSteps');
    my @categories      = map    { $profileSteps->{$_} } 
                          sort 
                          grep   /^profileStep\d\d?$/, 
                                keys %$profileSteps;

    my $completedCategories     = $self->getConfigurationData->{ completedProfileCategories } || {};
    my $overrideCategoryId      = $session->form->process('overrideCategoryId');
    my $currentCategory         = $overrideCategoryId || first { !exists $completedCategories->{ $_ } } @categories;

    # And put into tmpl_vars
    foreach my $categoryId ( @categories ) {
        my $category = WebGUI::ProfileCategory->new($session, $categoryId);

        push @substepStatus, {
            substepName         => $category->getLabel,
            substepComplete     => exists $completedCategories->{ $categoryId },
            isCurrentSubstep    => $currentCategory eq $categoryId,
        }
    }

    return \@substepStatus;
}

#-------------------------------------------------------------------
sub getSummaryTemplateVars {
    my $self            = shift;
    my $session         = $self->session;
    my $user            = $self->registration->user;

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

        my $fieldData = $self->getConfigurationData->{ $categoryId };
        my @fields;
        foreach my $field (@{ $category->getFields }) {
            push(@fields, {
                field_label         => $field->getLabel,
                field_value         => $field->formField(undef, 2, $user, 0, $fieldData->{ $field->getId }),
                field_formElement   => $field->formField(undef, 0, $user, 0, $fieldData->{ $field->getId }),
            });
        }

        push( @categoryLoop, {
            field_loop          => \@fields,
            category_label      => $category->getLabel,
            category_id         => $category->getId,
            category_edit_url   => $session->url->append( $self->changeStepDataUrl, 'overrideCategoryId='.$category->getId ),
        });
    }

    return @categoryLoop;
}

#-------------------------------------------------------------------
sub isComplete {
    my $self = shift;

    my $completedProfileCategories  = $self->getConfigurationData->{ completedProfileCategories } || {};
    my $profileSteps                = $self->get('profileSteps');

    foreach ( grep { /^profileStep\d+$/ } keys %{ $profileSteps } ) {
        return 0 unless $completedProfileCategories->{ $profileSteps->{$_} };
    }

    return 1;
}

#-------------------------------------------------------------------
=head2 processCategoryDataFromFormPost ( categoryId )

Processes the category with id categoryId using posted form data.

Returns an array ref containing error messages, if errors occurred.

=cut

sub processCategoryDataFromFormPost {
    my $self        = shift;
    my $categoryId  = shift;
    my $user        = shift || $self->registration->user;
    my $session     = $self->session;

    #### TODO: Throw exception on categoryId.

    my $profileOverrides = $self->get('profileOverrides');
    my $profileData      = $self->getConfigurationData->{ $categoryId } || {};
 
    # Instanciate category.
    my $category = WebGUI::ProfileCategory->new( $session, $categoryId );
    
    foreach my $field (@{ $category->getFields }) {
        next unless $field->get('visible');

        my $profileFieldData = $field->formProcess;

        # Check for required fields.
        if ($profileOverrides->{ $field->getId }->{ required } && !$profileFieldData) {
            $self->pushError( $field->getLabel.' is verplicht' );
        }
        else {
            # TODO: Wellicht ook iets doen als: error if (form->param('field') && !$profileFieldData)
            # TODO: Check if arrays are saved correctly
            $profileData->{ $field->getId } = $profileFieldData;
#            $user->profileField($field->getId, $profileFieldData);
        }
    }

    $self->setConfigurationData( $categoryId, $profileData );
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
    my $self    = shift;
    my $session = $self->session;

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

    $self->processCategoryDataFromFormPost( $categoryId );

    # Return form with error messages
    if ( @{ $self->error } ) {
        # Make sure this category is not marked as complete.
        delete $completedProfileCategories->{ $categoryId };
        $self->setConfigurationData('completedProfileCategories' => $completedProfileCategories );

#### TODO: Is deze nog wel nodig?
        return $self->error;
    }

    # Mark this category as completed.
    $completedProfileCategories->{ $categoryId } = 1;
    $self->setConfigurationData('completedProfileCategories' => $completedProfileCategories );
   
    # Proceed with next step
    my $nextStep = $currentStep + 1;
    $self->session->scratch->set('currentProfileStep', $nextStep);
    $self->session->scratch->set('currentCategoryId', $profileSteps->{"profileStep$nextStep"});

    # Return no errors since there aren't any.
    return [];
};

#-------------------------------------------------------------------
sub getCurrentCategoryId {
    my $self    = shift;

    my $profileSteps    = $self->get('profileSteps') || {};
    my @categories      = 
        map    { $profileSteps->{$_} } 
        sort 
        grep    /^profileStep\d\d?$/,
                keys %{ $profileSteps };
    
    my $completed = $self->getConfigurationData->{ completedProfileCategories } || {};

    foreach my $categoryId (@categories) {
        return $categoryId unless exists $completed->{ $categoryId };
    }

    return undef;
}

#-------------------------------------------------------------------
sub processStepApprovalData {
    my $self = shift;

    my $profileSteps    = $self->get('profileSteps');
    my @categories      = 
        map    { $profileSteps->{$_} } 
        sort 
        grep   /^profileStep\d\d?$/, 
               keys %$profileSteps;
      
    foreach my $categoryId ( @categories ) {
        $self->processCategoryDataFromFormPost( $categoryId );
    }
}

#-------------------------------------------------------------------
sub getViewVars {
    my $self    = shift;
    my $user    = shift || $self->registration->user;

    my $registrationId      = $self->registration->registrationId;
    my $profileOverrides    = $self->get('profileOverrides');
    my $profileSteps        = $self->get('profileSteps');

    # Figure out categoryId from form post
    my $categoryId          = $self->session->form->process('overrideCategoryId');

    # Only allow categoryId overrides by form post if that categoryId has been completed before.
    unless ($self->getConfigurationData->{ completedProfileCategories }->{ $categoryId }) {
        $categoryId = $self->getCurrentCategoryId || $profileSteps->{ profileStep1 };
    }

    # Figure out current sub step
    my $currentStep = { reverse %$profileSteps }->{ $categoryId };
    $currentStep    =~ s{^profileStep(\d+)$}{$1} || 1;

    my $var = $self->SUPER::getViewVars;

    my $category    = WebGUI::ProfileCategory->new($self->session, $categoryId);
    my $fieldData   = $self->getConfigurationData->{ $categoryId };
    foreach my $field (@{ $category->getFields }) {
        next unless $field->get('visible');

        # Add form element to field loop
        push @{ $var->{ field_loop } }, {
            field_label         => $field->getLabel,
            field_formElement   => $field->formField( {}, 0, $user, 0, $fieldData->{ $field->getId } ),
            field_subtext       => $profileOverrides->{ $field->getId }->{ comment  },
            field_isRequired    => $profileOverrides->{ $field->getId }->{ required },
        }
    }

    # Setup tmpl_vars
    $var->{ category_name   } = $category->getLabel;
    $var->{ comment         } = $profileSteps->{ "profileStepComment".$currentStep };
    $var->{ form_header     } .= 
        WebGUI::Form::hidden($self->session, { name => 'categoryId',  value => $categoryId } );

    return $var;
}

1;

