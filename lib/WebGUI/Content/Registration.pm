package WebGUI::Content::Registration;

use strict;
use WebGUI::Registration;

sub handler {
    my $session = shift;
    my $output;

    my $reg = WebGUI::Registration->new( $session );

    $output = ref $reg;

    return $output;
}

1;

