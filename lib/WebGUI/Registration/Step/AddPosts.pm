package WebGUI::Registration::Step::AddPosts;

use strict;

use WebGUI::Group;

use base qw{ WebGUI::Registration::Step };

#-------------------------------------------------------------------
sub apply {
    my $self    = shift;
    my $session = $self->session;

    # Find the destination CS
    my $userPageRoot    = WebGUI::Asset->newByDynamicClassname( $session, $self->get('csTreeTopLevel') );

    my $destinationCS   = $deployedTreeMaster->getLineage(['descendants'], {
        returnObjects       => 1,
        includeOnlyClasses  => ['WebGUI::Asset::Wobject::Collaboration::Slave'],
    });

    #### TODO: Better error handling.
    # Stop if not found.
    return unless defined $destinationCS->[0];

    # Find the source CS
    my @sourceCSs = @{ $self->getConfigurationData->{ sourceCSs } };
    return unless scalar @sourceCSs

    my $medicalInfoTop      = $slaveCSs->[0];
    
    # Add the posts.
    foreach my $assetId (@sourceCSs) {
        my $category = WebGUI::Asset->newByDynamicClass($session, $assetId);
        next unless $category;

        my $themes = $category->getLineage(['children'], {
            returnObjects      => 1,
            includeOnlyClasses => ['WebGUI::Asset::Post::Thread'],
        });
        next unless @$themes;
    
        foreach my $theme (@$themes) {
            $self->copyMedicalData($theme, $medicalInfoTop);
        }
    }
    

    # Set urls of deployed package
    my $updatePages = $destinationCS->getLineage( ['descendants'], {returnObjects => 1} );
    foreach my $currentAsset (@$updatePages) {
        # Figure out correct url
        $assetProperties->{url} = $currentAsset->getParent->get('url') . '/' . $currentAsset->get('menuTitle');

        if ($currentAsset->get('className') =~ m/^WebGUI::Asset::Wobject::Collaboration/ && $userGroup) {
            $assetProperties->{postGroupId} = $userGroup->getId;
            $assetProperties->{canStartThreadGroupId} = $userGroup->getId;
        }

        # Apply overrides
        $currentAsset->update({ %$assetProperties });
    }
}

#-------------------------------------------------------------------
sub copyMedicalData {
    my $self            = shift;
    my $master          = shift;
    my $deployUnder     = shift;
    my $slaveThreadId   = shift;

    # Make a copy of the master asset
    my $slave = $master->duplicate({
        skipAutoCommitWorkflows     => 1,
    });
    $slave->setParent($deployUnder);

    # Also update threadId for slave posts
    if ($slave->get('className') eq 'WebGUI::Asset::Post::Thread') {
        $slaveThreadId = $slave->getId;
    }

    # Insert the link to the master
    $slave->update({
        userDefined1    => $master->getId,
        threadId        => $slaveThreadId,
    });
 
    # Recursively walk the tree to copy all remaining master assets.
    my $children = $master->getLineage(['children'], {
        returnObjects       => 1,
        includeOnlyClasses  => ['WebGUI::Asset::Post', 'WebGUI::Asset::Post::Thread'],
    });
    
    foreach my $child (@{ $children }) {
        $self->copyMedicalData($child, $slave, $slaveThreadId);
    }
}


#-------------------------------------------------------------------
sub definition {
    my $class       = shift;
    my $session     = shift;
    my $definition  = shift;
    my $i18n        = WebGUI::International->new( $session, 'Registration_Step_UserGroup' );

    tie my %fields, 'Tie::IxHash', (
#### TODO: medicalDataMaster een betere naam geven.
        medicalDataMaster   => {
            fieldType   => 'asset',
            tab         => 'properties',
            label       => $i18n->echo('Medical data master'),
        },
        ##### Nieuwe opties #####
        csTreeTopLevel      => {
            fieldType   => 'asset',  #### eg. the top level page of a deployed package
            label       => 'Top level page of the branch containing the target CS.',
        },
        csIdentifier        => {
            fieldType   => 'text',
            label       => 'Keyword to identify target CS within branch.',
        },
        removeIdentifier    =>
            fieldType   => 'yesNo',
            label       => 'Remove identifier from target CS after adding posts?',
        },
    );

    push @{ $definition }, {
        name        => 'AddPosts',
        properties  => \%fields,
        namespace   => 'WebGUI::Registration::Step::AddPosts',
    };

    return $class->SUPER::definition( $session, $definition ); 
}

#-------------------------------------------------------------------
sub getSummaryTemplateVars {

}

#-------------------------------------------------------------------
sub isComplete {

}
`
#-------------------------------------------------------------------
sub www_collectMedicalEncyclopediaImportCategories {
    my $self = shift;

    # TODO: Handle the case with no categories.

    # Check priviledges
    return $self->www_setupSite unless $self->canSetupSite;
    
     my $f = WebGUI::HTMLForm->new($self->session);
    $f->hidden(
        -name   => 'func',
        -value  => 'collectMedicalEncyclopediaImportCategoriesSave',
    );

    my @selectedCategories = 
        $self->session->form->process('includeMedicalData') 
        || @{ $self->getConfigurationData->{ includeMedicalData } || [] };

    my $medicalInfoCategories;
    tie %$medicalInfoCategories, 'Tie::IxHash';
    $medicalInfoCategories = $self->getMedicalInfoCategories;
    if ( $medicalInfoCategories ) {
        $f->selectList(
            -name       => 'includeMedicalData',
            -value      => \@selectedCategories,
            -label      => 'Medische data toevoegen uit categorieen',
            -options    => $medicalInfoCategories,
            -height     => 5,
        );
    }
    $f->submit;

    my $var;
    $var->{ category_name   } = 'Kies een specialisme';
    $var->{ comment         } = $self->get('importCategoriesComment');
    $var->{ form            } = $f->print;
    $var->{ form_header     } =
        WebGUI::Form::formHeader($self->session)
        . WebGUI::Form::hidden($self->session, { name => 'func'     , value => 'collectMedicalEncyclopediaImportCategoriesSave' } );
    $var->{ form_footer     } = WebGUI::Form::formFooter($self->session);
    $var->{ field_loop      } = 
        [ {
            field_label         => 'Kies een specialisme',
            field_formElement   => 
                WebGUI::Form::selectList($self->session, { 
                    name    => 'includeMedicalData', 
                    value   => \@selectedCategories,
                    options => $medicalInfoCategories,
                    height  => 5,
                }),
#            field_subtext   => 'Hier komt de subtext voor dit veld'
        } ];

    my $template = WebGUI::Asset::Template->new($self->session, $self->get('getProfileCategoryTemplateId'));
    return $self->processStyle( $template->process($var) );
}

#-------------------------------------------------------------------
sub www_collectMedicalEncyclopediaImportCategoriesSave {
    my $self = shift;

    # Check priviledges
    return $self->www_setupSite unless $self->canSetupSite;

    # Store seletected categories
    $self->setConfigurationData('includeMedicalData' => [ $self->session->form->process('includeMedicalData') ] );

    # Are we editing a complete profile? If so return to the confirmation page
    return $self->www_confirmProfileData if $self->session->scratch->get('profileComplete');
 
    # Else proceed with the next step   
    return $self->www_chooseHomepageUrl;
}




1;

