#!/usr/bin/perl
use warnings;
use strict;
use LoxBerry::System;
use LoxBerry::Web;
use JSON;
use FindBin qw($Bin);
use lib "$Bin/../../../../bin/plugins/stats4lox/libs/";
use Globals;

LoxBerry::Web::lbheader("Stats4Lox", undef, undef);

my $template = HTML::Template->new(
    filename => "$lbptemplatedir/home.html",
    global_vars => 1,
    loop_context_vars => 1,
    die_on_bad_params => 0,
);

$template->param( 'GRAFANA_URL', "http://" . LoxBerry::System::get_localip() . ":" . $Globals::grafanaport );

print $template->output();

LoxBerry::Web::lbfooter();
