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
$htmlhead .= js_tag( $Bin, 'loxone_sub_navbar.js' );
$htmlhead .= js_tag( $Bin, 'loxone_import_report.js' );

$main::navbar{10}{active} = 1;

init_navbar_i18n();
LoxBerry::Web::lbheader("Import Report - LoxBerry Stats4Lox", undef, undef);

my $template = HTML::Template->new(
    filename => "$lbptemplatedir/loxone_import_report.html",
    global_vars => 1,
    loop_context_vars => 1,
    die_on_bad_params => 0,
);

my %L = LoxBerry::System::readlanguage($template, "language.ini");

my $lang = LoxBerry::System::lblanguage();

my %miniservers = LoxBerry::System::get_miniservers();
$template->param( 'LOXONE_MINISERVERS', to_json( \%miniservers ) );

print $template->output();

LoxBerry::Web::lbfooter();
