package WebGUI::Registration::Step::Homepage;

use strict;

use base qw{ WebGUI::Registration::Step };

#-------------------------------------------------------------------
sub apply {

}

#-------------------------------------------------------------------
sub definition {
    my $class       = shift;
    my $session     = shift;
    my $definition  = shift;
    my $i18n        = WebGUI::International->new( $session, 'Registration_Step_Homepage' );

    tie my %profileFields, 'Tie::IxHash', 
        map { $_->getId => $_->getCategory->getLabel . '::' . $_->getLabel }
            @{ WebGUI::ProfileField->getFields($session) };

    tie my %fields, 'Tie::IxHash', (
        userPageContainer       => {
            fieldType           => 'asset',
            tab                 => 'properties',
            label               => $i18n->echo('Put user pages on'),
        },
        packageContainer        => {
            fieldType           => 'asset',
            tab                 => 'properties',
            label               => $i18n->echo('Fetch packages from'),
        },
        makeUserPageOwner       => {
            fieldType           => 'yesNo',
            tab                 => 'properties',
            label               => $i18n->echo('Make user owner of his pages'),
        },
        urlStorageField         => {
            fieldType       => 'selectBox',
            label           => 'Store homepage url in field',
            options         => \%profileFields,
        }
    );

    push @{ $definition }, {
        name        => 'Homepage',
        properties  => \%fields,
        namespace   => 'WebGUI::Registration::Step::Homepage',
    };

    return $class->SUPER::definition( $session, $definition );
}

#-------------------------------------------------------------------
sub getSummaryTemplateVars {
    my $self                    = shift;
    my $includeAdminControls    = shift;
    my $session                 = $self->session;
    my @fields;

    # Fetch preferred homepage url
    my $preferredHomepageUrl = $self->getConfigurationData->{ preferredHomepageUrl };

    # Fetch available packages
    my $packageContainer = WebGUI::Asset->newByDynamicClass($self->session, $self->get('packageContainer'));
    my %packageList = map { $_->getId => $_->get('title') } @{ $packageContainer->getLineage(['children'], {
        returnObjects   => 1,
        whereClause     => 'assetData.isPackage = 1',
    })};

    # Preferred homepage url
    push @fields, {
        field_label         => 'Your homepage',
        field_value         => $preferredHomepageUrl,
        field_formElement   => WebGUI::Form::text( $session, { 
            name    => 'preferredHomepageUrl', 
            value   => $preferredHomepageUrl,
        }),
    };
    # Package to deploy
    push @fields, {
        field_label         => 'Choose package',
        field_value         => $session->form->process('packageId'),
        field_formElement   => WebGUI::Form::selectBox( $session, {
            name    => 'packageId',
            value   => $session->form->process('packageId'),
            options => \%packageList,
        }),
    } if $includeAdminControls;

    # Setup tmpl_var
    my $var = {
        field_loop          => \@fields, 
        category_label      => $self->get('title'),
        category_edit_url   =>
            $self->session->url->page('registration=register;func=viewStep;stepId='.$self->stepId.';registrationId='.$self->registration->registrationId),
    };

    return ( $var );    
}

#-------------------------------------------------------------------
sub installUserPage {
    my $self        = shift;
    my $parameters  = shift;

    my $user        = $self->registration->user;
    my $session     = $self->session;
    my $i18n        = WebGUI::International->new($session, 'MijnArts');

    my $userGroup;

    # Deploy package under a seperate version tag.
    my $currentVersionTag   = WebGUI::VersionTag->getWorking($session, 1);
    my $tempVersionTag      = WebGUI::VersionTag->create($session, {
        name    => 'Installation of user pages for '.$user->username,
    });
    $tempVersionTag->setWorking;

    #### TODO: Check if a user object has been instanciated.

    # Deploy package
    my $userPageRoot = WebGUI::Asset->newByDynamicClass( $session, $self->get('userPageContainer') );

    #### TODO: Complain if $userPageRoot does not exist.
   
    my $packageMasterAsset  = WebGUI::Asset->newByDynamicClass( $session, $parameters->{packageId} );
    my $masterLineage       = $packageMasterAsset->get("lineage");

    if (defined $packageMasterAsset && $self->get("lineage") !~ /^$masterLineage/) {
        my $assetProperties = {};
        # Set privileges of deployed package;
        if ($self->get('makeUserPageOwner')) {
            $assetProperties->{ownerUserId} = $user->userId;
#            $assetProperties->{groupIdView} = $groupIdView;
#            $assetProperties->{groupIdEdit} = $userGroup->getId if ($userGroup);
        }

        #### NOTE: $fullName is used to replace the title and menuTitle of the root of the deployed asset.
        ####       This is hardcoded for now. Therefore the first, middle and lastName must be entered.
        my $fullName = join(' ', (
            $user->profileField('firstName'),
            $user->profileField('middleName'),
            $user->profileField('lastName')
        ));

        # Figure out the root url of the deployed package.
        my $deployedPackageRootUrl = 
               $session->form->process('rootUrlOverride') 
            || '/' . $user->profileField('firstName') . $user->profileField('middleName') . $user->profileField('lastName');
            
        # Deploy package under userPageRoot
		my $deployedTreeMaster = $packageMasterAsset->duplicateBranch;
		$deployedTreeMaster->setParent($userPageRoot);
		$deployedTreeMaster->update({ 
            isPackage   => 0, 
            url         => $deployedPackageRootUrl, 
            title       => $fullName,
            menuTitle   => $fullName,

            %$assetProperties,
        }); #, styleTemplateId=>$self->get("styleTemplateId")});

        # Store the root url in the user profile
        $user->profileField($self->get('urlStorageField'), $deployedTreeMaster->getUrl);

        # Set urls of deployed package
        my $updatePages = $deployedTreeMaster->getLineage( ['descendants'], {returnObjects => 1} );
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
 
    # Commit the tag and return the user to their previous tag
    $tempVersionTag->commit;
    $currentVersionTag->setWorking if (defined $currentVersionTag);
}


#-------------------------------------------------------------------
sub isComplete {
    my $self = shift;

    return defined $self->getConfigurationData->{'preferredHomepageUrl'};
}

#-------------------------------------------------------------------
sub processStepFormData {
    my $self    = shift;
    my $session = $self->session;

    #### TODO: privs ??????
    my $url     = $session->form->process('preferredHomepageUrl');
    unless ( $url ) {
        $self->pushError( "De url is verplicht." );
    }
    if ( WebGUI::Asset->urlExists($session, $url) ) {
        $self->pushError( "De url $url is al bezet" );
    }

    # Store homepage url
    $self->setConfigurationData('preferredHomepageUrl', $url );
}

#-------------------------------------------------------------------
sub view {
    my $self = shift;


    #### TODO: privs
    my $registrationId = $self->registration->registrationId;
    my $preferredHomepageUrl = 
        $self->session->form->process('preferredHomepageUrl')  
        || $self->getConfigurationData->{'preferredHomepageUrl'};

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
    $f->text(
        -name   => 'preferredHomepageUrl',
        -label  => 'www.wieismijnarts.nl/',
        -value  => $preferredHomepageUrl   
    );
    $f->submit;

    my $var;
    $var->{ category_name   } = 'Naam van uw site';
    $var->{ comment         } = $self->get('homepageUrlComment');
    $var->{ form            } = $f->print;
    $var->{ form_header     } =
        WebGUI::Form::formHeader($self->session)
        . WebGUI::Form::hidden($self->session, { name => 'func',            value => 'viewStepSave'         } )
        . WebGUI::Form::hidden($self->session, { name => 'registration',    value => 'register'             } ) 
        . WebGUI::Form::hidden($self->session, { name => 'registrationId',  value => $registrationId        } );

    $var->{ form_footer     } = WebGUI::Form::formFooter($self->session);
    $var->{ field_loop      } = 
        [
            {
                field_label         => 'www.wieismijnarts.nl/',
                field_formElement   => 
                    WebGUI::Form::text($self->session, { 
                        name    => 'preferredHomepageUrl', 
                        value   => $preferredHomepageUrl
                    }),
#                field_subtext   => 'Hier komt de subtext voor dit veld'
            }
        ];

    my $template = WebGUI::Asset::Template->new( $self->session, $self->registration->get('stepTemplateId') );
    return $template->process($var);
}


1;
