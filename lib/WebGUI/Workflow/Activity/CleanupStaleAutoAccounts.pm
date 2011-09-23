package WebGUI::Workflow::Activity::CleanupStaleAutoAccounts;

use strict;
use warnings;
use base 'WebGUI::Workflow::Activity';

#-------------------------------------------------------------------

sub definition {
	my $class       = shift;
	my $session     = shift;
	my $definition  = shift;

	push(@{$definition}, {
		name        => 'Cleanup stale auto accounts',
		properties  => {
			timeout => {
				fieldType       => "interval",
				label           => "Declare accounts stale after",
				defaultValue    => 24*60*60,
			},
		}
	} );

	return $class->SUPER::definition($session,$definition);
}


#-------------------------------------------------------------------

sub execute {
	my $self        = shift;
    my $object      = shift;
    my $instance    = shift;

    my $session     = $self->session;
    my ($log, $db)  = $session->quick( qw[ log db ] );

    my $now         = time;

    my $sth = $db->read( 'select userId from users where username=userId and status=? and lastUpdated  < ?', [
        'Deactivated',
        $now - $self->get( 'timeout' ),
    ] );

    while ( my $userId = $sth->array ) {
        if ( time - $now > $self->getTTL ) {
            return $self->WAITING( 1 );
        }

        my $user = WebGUI::User->new( $session, $userId );
        if ( !$user ) {
            $log->error( "Cannot instanciate auto account to delete with id [$userId]" );
            next;
        }

        $user->delete;
        $log->warn( "Deleted auto account [$userId]" );
    }

    return $self->COMPLETE;
}

1;

#vim:ft=perl
