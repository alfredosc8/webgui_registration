package WebGUI::Registration::Step::AddPosts;

use strict;

use WebGUI::Asset;
use WebGUI::Group;
use WebGUI::Asset;
use WebGUI::Keyword;

use Data::Dumper;

use base qw{ WebGUI::Registration::Step };

#-------------------------------------------------------------------
sub apply {
    my $self    = shift;
    my $session = $self->session;

    # Find the destination CS
    my $userPageRootId  = $self->getExportVariable( $self->get('csContainerRoot') );
    my $userPageRoot    = WebGUI::Asset->newByDynamicClass( $session, $userPageRootId );

    my $destinationCSIds    = WebGUI::Keyword->new( $session )->getMatchingAssets({
        startAsset  => $userPageRoot,
        keyword     => $self->get('csIdentifier'),
        isa         => 'WebGUI::Asset::Wobject::Collaboration',
    });
    my $destinationCS       = WebGUI::Asset->newByDynamicClass( $session, $destinationCSIds->[0] );

    #### TODO: Better error handling.
    # Stop if not found.
    return unless defined $destinationCS;

    # Find the source CS
    my @sourceCSs = @{ $self->getConfigurationData->{ selectedCSs } };
    return unless scalar @sourceCSs;

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
            $self->copyMedicalData($theme, $destinationCS);
        }
    }
    
    # Inherit properties from CS
    my $parentProperties    = $destinationCS->get;
    my $assetProperties     = {
        ownerUserId     => $parentProperties->{ ownerUserId },
        groupIdView     => $parentProperties->{ groupIdView },
        groupIdEdit     => $parentProperties->{ groupIdEdit },
    };

    # Set urls of deployed package
    my $updatePages = $destinationCS->getLineage( ['descendants'], {returnObjects => 1} );
    foreach my $currentAsset (@$updatePages) {
        # Figure out correct url
        $assetProperties->{url} = $currentAsset->getParent->get('url') . '/' . $currentAsset->get('menuTitle');

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
        sourceCSContainer   => {
            fieldType   => 'asset',
            tab         => 'properties',
            label       => $i18n->echo('Medical data master'),
        },
        ##### Nieuwe opties #####
#        csTreeTopLevel      => {
#            fieldType   => 'asset',  #### eg. the top level page of a deployed package
#            label       => 'Top level page of the branch containing the target CS.',
#        },
        csIdentifier        => {
            fieldType   => 'text',
            label       => 'Keyword to identify target CS within branch.',
        },
        removeIdentifier    => {
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
sub getEditForm {
    my $self = shift;

    my $f   = $self->SUPER::getEditForm;
    $f->readOnly(
        -label  => 'Search for CS below',
        -value  => $self->getExportVariablesSelectBox( 'csContainerRoot', 'assetId' ),
    );

    return $f;
}

#-------------------------------------------------------------------
sub getSourceCSs {
    my $self = shift;

    # Get all CSs within directly below the sourceCSContainer.
    my $sourceCSContainer   = WebGUI::Asset->newByDynamicClass($self->session, $self->get('sourceCSContainer'));
    my $sourceCSs           = $sourceCSContainer->getLineage(['children'], {
        returnObjects           => 1,
        includeOnlyClasses      => ['WebGUI::Asset::Wobject::Collaboration'],
    });

    # Construct and return an ( assetId => menuTitle ) hash
    tie my %availableSourceCSs, 'Tie::IxHash';
    %availableSourceCSs = 
        map     { $_->getId             => $_->get('menuTitle') } 
        sort    { $a->get('menuTitle') <=> $b->get('menuTitle') }
                @{ $sourceCSs };

    return \%availableSourceCSs;
}

#-------------------------------------------------------------------
sub getSummaryTemplateVars {
    my $self                    = shift;
    my $includeAdminControls    = shift;
    my $session                 = $self->session;
    my @fields;

    my $sourceCSs   = $self->getSourceCSs;
    my $selectedCSs = $self->getConfigurationData->{'selectedCSs'} || [];
    my $csNames     = join ', ', @{ $sourceCSs }{ @{ $selectedCSs } };

    # Preferred homepage url
    push @fields, {
        field_label         => 'Specialismen',
        field_value         => $csNames,
        field_formElement   => WebGUI::Form::selectList( $session,  {
            name    => 'addCS', 
            value   => $selectedCSs,
            options => $sourceCSs,
            height  => 5,
        }),
    };
    
    # Setup tmpl_var
    my $var = {
        field_loop          => \@fields, 
        category_label      => $self->get('title'),
        category_edit_url   => $self->changeStepDataUrl,
    };

    return ( $var );    

}

#-------------------------------------------------------------------
sub isComplete {
    my $self    = shift;

    # If there are no source CSs return that the step is complete.
    return 1 unless scalar %{ $self->getSourceCSs };

    # Step is complete if user has clicked clicked on the proceed button.
    return 1 if exists $self->getConfigurationData->{selectedCSs};

    return 0;
}

#-------------------------------------------------------------------
sub view {
    my $self            = shift;
    my $registrationId  = $self->registration->registrationId;

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
        -value  => $registrationId,
    );

    my @selectedCSs = 
        $self->session->form->process('addCS') 
        || @{ $self->getConfigurationData->{selectedCSs}  || [] };

    my $sourceCSs   = $self->getSourceCSs;

    if ( $sourceCSs ) {
        $f->selectList(
            -name       => 'addCS',
            -value      => \@selectedCSs,
            -label      => 'Kies een specialisme',
            -options    => $sourceCSs,
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
        . WebGUI::Form::hidden($self->session, { name => 'func',            value => 'viewStepSave'         } )
        . WebGUI::Form::hidden($self->session, { name => 'registration',    value => 'register'             } ) 
        . WebGUI::Form::hidden($self->session, { name => 'registrationId',  value => $registrationId        } );
    $var->{ form_footer     } = WebGUI::Form::formFooter($self->session);
    $var->{ field_loop      } = 
        [ {
            field_label         => 'Kies een specialisme',
            field_formElement   => 
                WebGUI::Form::selectList($self->session, { 
                    name    => 'addCS', 
                    value   => \@selectedCSs,
                    options => $sourceCSs,
                    height  => 5,
                }),
#            field_subtext   => 'Hier komt de subtext voor dit veld'
        } ];

    my $template = WebGUI::Asset::Template->new( $self->session, $self->registration->get('stepTemplateId') );
    return $template->process($var);
}

#-------------------------------------------------------------------
sub processPropertiesFromFormPost {
    my $self    = shift;
    my $session = $self->session;

    $self->SUPER::processPropertiesFromFormPost;

    $self->update( {
        csContainerRoot         => $session->form->process('csContainerRoot'),
    } );
}

#-------------------------------------------------------------------
sub processStepFormData {
    my $self = shift;

    # Store seletected categories
    $self->setConfigurationData('selectedCSs', [ $self->session->form->process('addCS') ] );
}

1;

