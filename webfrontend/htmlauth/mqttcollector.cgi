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
$htmlhead .= js_tag( $Bin, 'mqttcollector.js' );
$main::navbar{20}{active} = 1;

init_navbar_i18n();
LoxBerry::Web::lbheader( Globals::page_title("MQTT Collector - LoxBerry Stats4Lox"), $Globals::wikiurl, undef );

my $template = HTML::Template->new(
    filename => "$lbptemplatedir/mqttcollector.html",
    global_vars => 1,
    loop_context_vars => 1,
    die_on_bad_params => 0,
);

my %L = LoxBerry::System::readlanguage($template, "language.ini");

my $lang = LoxBerry::System::lblanguage();

# FINDERAVAILABLE used to decide whether to offer a button into the MQTT
# Gateway's finder page. The topics are shown on this page now, and whether the
# finder has data is answered when they are fetched - a page that was opened
# before the finder started would otherwise keep claiming there is nothing.

print $template->output();

LoxBerry::Web::lbfooter();
