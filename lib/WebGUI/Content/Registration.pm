package WebGUI::Content::Registration;

use strict;
use WebGUI::Registration;

sub handler {
    my $session = shift;
    my $output;

    my $reg = WebGUI::Registration->new( $session );

    my $method = 'www_' . ( $session->form->process( 'registration' ) || 'viewStep' );

    if ( $method =~ /^[\w_]+$/ && $reg->can( $method ) ) {
        $output = $reg->$method;
    }
    else {
        $session->errorHandler->warn("Cannot execute method [$method]");
    }

    return $output;
}

1;

