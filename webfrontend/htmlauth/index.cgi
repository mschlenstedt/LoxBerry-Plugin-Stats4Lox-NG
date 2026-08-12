#!/usr/bin/perl
use warnings;
use strict;
use LoxBerry::System;
use LoxBerry::Web;
use JSON;
use FindBin qw($Bin);
use lib "$Bin/../../../../bin/plugins/REPLACELBPPLUGINDIR/libs/";
use Globals;

init_navbar_i18n();
LoxBerry::Web::lbheader( Globals::page_title("Stats4Lox"), $Globals::wikiurl, undef );

my $template = HTML::Template->new(
    filename => "$lbptemplatedir/home.html",
    global_vars => 1,
    loop_context_vars => 1,
    die_on_bad_params => 0,
);

my %L = LoxBerry::System::readlanguage($template, "language.ini");

$template->param( 'GRAFANA_URL', "http://" . LoxBerry::System::get_localip() . ":" . $Globals::grafana->{port} );

print $template->output();

LoxBerry::Web::lbfooter();
