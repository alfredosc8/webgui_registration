package WebGUI::Macro::RegistrationProgress;

use strict;

use WebGUI::Registration;
use WebGUI::Asset::Template;
use Data::Dumper;

sub process {
    my $session         = shift;
    my $registrationId  = shift;
    my $registration    = WebGUI::Registration->new( $session, $registrationId );

    return 'Invalid registrationId' unless $registration;

    my $status = $registration->getStepStatus;
$session->errorHandler->warn(Dumper($status));  

    my $var;
    $var->{ step_loop } = $status;

#    my $template = <<EOT;
#<tmpl_loop step_loop>
#<div class="mainstep <tmpl_if isCurrentStep>currentStep</tmpl_if>">
#    <div class="stepNumber"><tmpl_var stepNumber></div>
#    <div class="stepName"><tmpl_var stepName></div>
#    <div class="stepComplete <tmpl_if stepComplete>checked<tmpl_else>unchecked</tmpl_if>"></div>
#    <tmpl_if substep_loop><tmpl_loop substep_loop>
#    <div class="substep <tmpl_if substepComplete>checked<tmpl_else>unchecked</tmpl_if> <tmpl_if isCurrentSubstep>currentSubstep</tmpl_if>">
#        <tmpl_var substepName>
#    </div>
#    </tmpl_loop></tmpl_if>
#</div>
#</tmpl_loop>
#EOT
    my $template = <<EOT;
<ul>
<tmpl_loop step_loop>
    <li> 
        <tmpl_var stepNumber>. <tmpl_var stepName> 
        <tmpl_if isCurrentStep>(current)</tmpl_if>
        <tmpl_if stepComplete>(complete)</tmpl_if>
        <tmpl_if substep_loop>
            <ul>
            <tmpl_loop substep_loop>
                <li>
                    <tmpl_var substepName>
                    <tmpl_if substepComplete>(complete)</tmpl_if> 
                    <tmpl_if isCurrentSubstep>(current)</tmpl_if>
                </li>
            </tmpl_loop>
            </ul>
        </tmpl_if>
    </li>
</tmpl_loop>
</ul>
EOT

    return WebGUI::Asset::Template->processRaw($session, $template, $var);
}

1;

