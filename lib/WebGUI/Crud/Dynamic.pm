package WebGUI::Crud::Dynamic;

use strict;

use Carp;
use Clone qw{ clone };
use Class::InsideOut qw{ :std };

use Data::Dumper;
use base qw{ WebGUI::Crud };

private     dynamicProperties => my %dynamicProperties;

sub crud_definition {
    my $class   = shift;
    my $session = shift;

    my $definition = $class->SUPER::crud_definition( $session );

    $definition->{ properties   }->{ _dynamic   } = {
        fieldType       => 'textarea',
        defaultValue    => {},
        serialize       => 1,
        noFormPost      => 1,
    };
    $definition->{ properties   }->{ className  } = {
        fieldType       => 'hidden',
        defaultValue    => ref $class,
        noFormPost      => 1,
    };

    tie %{ $definition->{ dynamic } }, 'Tie::IxHash';

    return $definition; 
}

sub crud_getDynamicProperties {
    my $class   = shift;
    my $session = shift;

    return clone $class->crud_definition( $session )->{ dynamic };
}

sub get {
    my $self    = shift;
    my $name    = shift;

    # Return all props and options when no name is passed.
    unless ( defined $name ) {
        return {
            %{ $self->SUPER::get( $name ) },
            %{ $self->getDynamic },
        };
    }

    # Otherwise, if name is an option, return that.
    if ( $self->isDynamic( $name ) ) {
        return $self->getDynamic( $name );
    }

    # No option so it must be a property.
    return $self->SUPER::get( $name );
}

sub getDynamic {
    my $self = shift;
    my $name = shift;

    if ( defined $name ) {
        croak "Invalid dynamic property: $name" unless $self->isDynamic( $name );

        return clone $dynamicProperties{ id $self }{ $name };
    }

    return clone $dynamicProperties{ id $self };
}

sub isDynamic {
    my $self    = shift;
    my $name    = shift;

    return exists $dynamicProperties{ id $self }{ $name };
}

sub new {
    my $class   = shift;
    my $session = shift;
    my $id      = shift;

    my $self    = $class->SUPER::new( $session, $id );
    register $self;

    my $dynamic = $self->crud_getDynamicProperties( $session );
    $dynamicProperties{ id $self } = {
        ( map { $_ => $dynamic->{ $_ }->{ defaultValue } } keys %{ $dynamic } ),
        %{ $self->get( '_dynamic' ) || {} },
    };

    return $self;
}

#-------------------------------------------------------------------
sub newByDynamicClass {
    my $class   = shift;
    my $session = shift;
    my $id      = shift;

$session->log->warn( $id );
    # Figure out namespace of step
    my $table   = $class->crud_getTableName( $session );
    my $column  = $class->crud_getTableKey( $session );

    my $namespace   = $session->db->quickScalar( "select className from $table where $column=?", [
        $id,
    ]);

    # Instanciate
    my $crud        = WebGUI::Pluggable::instanciate( $namespace, 'new', [
        $session,
        $id,
    ] );

    return $crud;
}

sub update {
    my $self    = shift;
    my $data    = shift;
    my $id      = id $self;

    # Always force className
    $data->{ className } = ref $self;
    
    foreach my $key ( grep { $self->isDynamic( $_ ) } keys %{ $data } ) {
        $dynamicProperties{ $id }{ $key } = delete $data->{ $key };
    }
    
    $data->{ _dynamic } = $dynamicProperties{ $id };

    return $self->SUPER::update( $data );
}

sub updateFromFormPost {
    my $self    = shift;
    my $session = $self->session;
    my $form    = $session->form;

    my $data    = {};
    my %fields  = (
        %{ $self->crud_getProperties( $session )        },
        %{ $self->crud_getDynamicProperties( $session ) },
    );

    foreach my $fieldName ( keys %fields ) {
        next if $fields{ $fieldName }{ noFormPost };

        my @value = $form->process(
            $fieldName,
            $fields{ $fieldName }->{ fieldType },
            $fields{ $fieldName }->{ defaultValue },
        );
        my $value   = scalar @value > 1
                    ? \@value
                    : $value[ 0 ]
                    ;

        $data->{ $fieldName } = $value;
    }

$session->log->warn( Dumper $data );
    return $self->update( $data );
}

1;

