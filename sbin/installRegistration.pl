#!/usr/bin/env perl

$|++; # disable output buffering
our ($webguiRoot, $configFile, $help, $man);

BEGIN {
    $webguiRoot = "..";
    unshift (@INC, $webguiRoot."/lib");
}

use strict;
use Pod::Usage;
use Getopt::Long;
use WebGUI::Session;
use WebGUI::Registration;
use WebGUI::Registration::Step;
use WebGUI::Registration::Instance;
use List::MoreUtils qw{ insert_after_string };

GetOptions(
    'configFile=s'  => \$configFile,
);


my $session = start( $webguiRoot, $configFile );

installRegistrationInstanceTables( $session );
installRegistrationTables( $session );
addUrlTriggerSetting( $session );
installRegistrationStepTables( $session );
addRegistrationContentHandler( $session );
addRegistrationProgressMacro( $session );
addRegistrationSteps( $session );


finish( $session );

#----------------------------------------------------------------------------
sub installRegistrationInstanceTables {
    my $session = shift || die 'no session';
    print "Installing registration instance table...";

    my $tableName = WebGUI::Registration::Instance->crud_definition( $session )->{ tableName };
    if ( grep { $_ eq $tableName } $session->db->buildArray( 'show tables' ) ) {
        print "Skipping\n";
        return;
    }

    WebGUI::Registration::Instance->crud_createTable( $session );

    print "Done\n";
}

#----------------------------------------------------------------------------
sub installRegistrationStepTables {
    my $session = shift || die 'no session';
    print "Installing registration step table...";

    my $tableName = WebGUI::Registration::Step->crud_definition( $session )->{ tableName };
    if ( grep { $_ eq $tableName } $session->db->buildArray( 'show tables' ) ) {
        print "Skipping\n";
        return;
    }
    
    WebGUI::Registration::Step->crud_createTable( $session );

    print "Done\n";
}

#----------------------------------------------------------------------------
sub addUrlTriggerSetting {
    my $session = shift;
    print "Adding setting to store trigger urls...";

    if ( defined $session->setting->get( 'registrationUrlTriggers' ) ) {
        print "Skipping\n";
        return;
    }

    $session->setting->add( 'registrationUrlTriggers', '{}' );

    print "Done\n";
}

#----------------------------------------------------------------------------
sub installRegistrationTables {
    my $session = shift || die 'no session';
    print "Installing registration tables...";

    WebGUI::Registration->crud_createTable( $session );
    
    $session->db->write(<<EO_STATUS);
    CREATE TABLE IF NOT EXISTS `Registration_status` (
        `registrationId` char(22) NOT NULL,
        `userId` char(22) NOT NULL,
        `status` char(20) NOT NULL default 'setup',
        `lastUpdate` timestamp NOT NULL default CURRENT_TIMESTAMP on update CURRENT_TIMESTAMP,
        PRIMARY KEY  (`registrationId`,`userId`)
    ) ENGINE=MyISAM DEFAULT CHARSET=utf8;
EO_STATUS
   
    $session->db->write(<<EO_ACCT_DATA);
    CREATE TABLE IF NOT EXISTS `RegistrationStep_accountData` (
        `stepId` char(22) NOT NULL,
        `userId` char(22) NOT NULL,
        `status` char(20) default NULL,
        `configurationData` text,
        PRIMARY KEY  (`stepId`,`userId`)
    ) ENGINE=MyISAM DEFAULT CHARSET=utf8;
EO_ACCT_DATA

    print "Done\n";
}

sub addRegistrationContentHandler {
    my $session = shift;
    print "Adding Registration Content Handler...";

    my @handlers = @{ $session->config->get('contentHandlers') };
    if ( !grep { $_ eq 'WebGUI::Content::Registration' } @handlers ) {
        insert_after_string 'WebGUI::Content::Shop', 'WebGUI::Content::Registration', @handlers;
        $session->config->set( 'contentHandlers', \@handlers );
    }
    
    print "Done\n";
}

sub addRegistrationProgressMacro {
    my $session = shift;
    print "Adding RegistrationProgress Macro...";

    $session->config->set('macros', { %{$session->config->get('macros')}, RegistrationProgress => 'RegistrationProgress' } );

    print "Done\n";
}

sub addRegistrationSteps {
    my $session = shift;

    print "Adding Registartion Steps to config...";
    
    my %steps = map { $_ => 1 } @{ $session->config->get( 'registrationSteps' ) || [] };
    $steps{ $_ } = 1 for (
        "WebGUI::Registration::Step::CreateAccount",
        "WebGUI::Registration::Step::ProfileData",
        "WebGUI::Registration::Step::AddUserToGroups",
        "WebGUI::Registration::Step::Homepage",
        "WebGUI::Registration::Step::Message",
        "WebGUI::Registration::Step::UserGroup",
        "WebGUI::Registration::Step::AddPosts"
    );

    $session->config->set( 'registrationSteps', [ keys %steps ] );

    print "Done\n";
        
}

#----------------------------------------------------------------------------
sub start {
    my $webguiRoot  = shift;
    my $configFile  = shift;
    my $session = WebGUI::Session->open($webguiRoot,$configFile);
    $session->user({userId=>3});
    
    ## If your script is adding or changing content you need these lines, otherwise leave them commented
    #
    # my $versionTag = WebGUI::VersionTag->getWorking($session);
    # $versionTag->set({name => 'Name Your Tag'});
    #
    ##
    
    return $session;
}

#----------------------------------------------------------------------------
sub finish {
    my $session = shift;
    
    ## If your script is adding or changing content you need these lines, otherwise leave them commented
    #
    # my $versionTag = WebGUI::VersionTag->getWorking($session);
    # $versionTag->commit;
    ##
    
    $session->var->end;
    $session->close;
}

__END__


=head1 NAME

utility - A template for WebGUI utility scripts

=head1 SYNOPSIS

 utility --configFile config.conf ...

 utility --help

=head1 DESCRIPTION

This WebGUI utility script helps you...

=head1 ARGUMENTS

=head1 OPTIONS

=over

=item B<--configFile config.conf>

The WebGUI config file to use. Only the file name needs to be specified,
since it will be looked up inside WebGUI's configuration directory.
This parameter is required.

=item B<--help>

Shows a short summary and usage

=item B<--man>

Shows this document

=back

=head1 AUTHOR

Copyright 2001-2009 Plain Black Corporation.

=cut

#vim:ft=perl
