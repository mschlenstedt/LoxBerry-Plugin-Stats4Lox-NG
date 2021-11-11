#!/usr/bin/perl
use warnings;
use strict;
use LoxBerry::System;
use LoxBerry::Web;
use JSON;
use FindBin qw($Bin);
use lib "$Bin/../../../../bin/plugins/stats4lox/libs/";
use Globals;

our $htmlhead="";
$htmlhead = '<script type="application/javascript" src="js/vue.global.js"></script>';
$htmlhead .= '<script type="application/javascript" src="js/inputs_outputs_sub_navbar.js"></script>';
$htmlhead .= '<script type="application/javascript" src="js/input_mqtt.js"></script>';
$main::navbar{30}{active} = 1;


LoxBerry::Web::lbheader("MQTT Collector - LoxBerry Stats4Lox", undef, undef);

my $template = HTML::Template->new(
    filename => "$lbptemplatedir/input_mqtt.html",
    global_vars => 1,
    loop_context_vars => 1,
    die_on_bad_params => 0,
);

my $lang = LoxBerry::System::lblanguage();

print $template->output();

LoxBerry::Web::lbfooter();
