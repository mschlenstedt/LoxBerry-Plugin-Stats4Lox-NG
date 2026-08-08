#!/usr/bin/perl
use warnings;
use strict;
use LoxBerry::System;
use LoxBerry::Web;
use JSON;
use FindBin qw($Bin);
use lib "$Bin/../../../../bin/plugins/REPLACELBPPLUGINDIR/libs/";
use Globals;

our $htmlhead="";
$htmlhead = '<script type="application/javascript" src="js/vue.global.js"></script>';
$htmlhead .= js_tag( $Bin, 'datasources_sub_navbar.js' );
$htmlhead .= js_tag( $Bin, 'data_inputs.js' );
$main::navbar{20}{active} = 1;

init_navbar_i18n();
LoxBerry::Web::lbheader("MQTT Collector - LoxBerry Stats4Lox", undef, undef);

my $template = HTML::Template->new(
    filename => "$lbptemplatedir/data_inputs.html",
    global_vars => 1,
    loop_context_vars => 1,
    die_on_bad_params => 0,
);

my %L = LoxBerry::System::readlanguage($template, "language.ini");

my $lang = LoxBerry::System::lblanguage();

$template->param("FINDERAVAILABLE", -e '/dev/shm/mqttfinder.json' ? "true" : "" );

print $template->output();

LoxBerry::Web::lbfooter();
