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
$htmlhead .= '<script type="application/javascript" src="js/loxone_sub_navbar.js"></script>';
$htmlhead .= '<script type="application/javascript" src="js/mqttlive_loxone.js"></script>';

$main::navbar{10}{active} = 1;


LoxBerry::Web::lbheader("Stats4Lox", undef, undef);
my $template = HTML::Template->new(
    filename => "$lbptemplatedir/mqttlive_loxone.html",
    global_vars => 1,
    loop_context_vars => 1,
    die_on_bad_params => 0,
);

my $lang = LoxBerry::System::lblanguage();
$template->param( 'MQTTLIVEDATA', LoxBerry::System::read_file( "$s4ltmp/mqttlive_uidata.json" ) );
$template->param( 'STATSJSON', LoxBerry::System::read_file( "$lbpconfigdir/stats.json" ) );


print $template->output();

LoxBerry::Web::lbfooter();
