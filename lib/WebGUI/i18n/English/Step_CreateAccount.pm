package WebGUI::i18n::English::Step_CreateAccount;

use strict;

our $I18N = {
    'is required' => {
        message => 'is required.',
    },
   
    'username taken' => {
        message => 'The requested username is already in use by another user',
    },

    'pw doesnt match' => {
        message => 'The password you entered doesn\'t match its confirmation',
    },

    'captcha wrong' => {
        message => 'The captcha you entered does not match the image',
    },

    'account exists' => {
        message => 'An account with the username and/or emailadress already exists on this site. Click <a href="%s">here</a> to reset your password',
    },
};

1;

