#!/usr/bin/perl
use warnings;
use strict;
use LoxBerry::System;
use LoxBerry::Web;
use LoxBerry::IO;
use JSON;
use FindBin qw($Bin);
use lib "$Bin/../../../../bin/plugins/REPLACELBPPLUGINDIR/libs/";
use Globals;

our $htmlhead="";
$htmlhead .= js_tag( $Bin, 'datasources_sub_navbar.js' );
$htmlhead .= js_tag( $Bin, 'mqttlive_loxone.js' );

$main::navbar{20}{active} = 1;

init_navbar_i18n();
LoxBerry::Web::lbheader( Globals::page_title("Stats4Lox"), $Globals::wikiurl, undef );
my $template = HTML::Template->new(
    filename => "$lbptemplatedir/mqttlive_loxone.html",
    global_vars => 1,
    loop_context_vars => 1,
    die_on_bad_params => 0,
);

my %L = LoxBerry::System::readlanguage($template, "language.ini");

my $lang = LoxBerry::System::lblanguage();
my $mqttcred = LoxBerry::IO::mqtt_connectiondetails();

$template->param( 'MQTTLIVEDATA', LoxBerry::System::read_file( "$Globals::stats4lox->{s4ltmp}/mqttlive_uidata.json" ) );
$template->param( 'STATSJSON', LoxBerry::System::read_file( "$lbpconfigdir/stats.json" ) );
$template->param( 'MQTTGATEWAY_HOSTNAME',  lbhostname() );
$template->param( 'MQTTGATEWAY_UDPINPORT', $mqttcred->{udpinport} );

print $template->output();

LoxBerry::Web::lbfooter();
