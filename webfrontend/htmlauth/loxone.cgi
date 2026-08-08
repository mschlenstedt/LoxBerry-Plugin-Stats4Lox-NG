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
$htmlhead .= js_tag( $Bin, 'loxone.js' );

init_navbar_i18n();
LoxBerry::Web::lbheader("Stats4Lox", undef, undef);

my $template = HTML::Template->new(
    filename => "$lbptemplatedir/loxone.html",
    global_vars => 1,
    loop_context_vars => 1,
    die_on_bad_params => 0,
);

my %L = LoxBerry::System::readlanguage($template, "language.ini");

my $lang = LoxBerry::System::lblanguage();
$template->param( 'LOXONE_ELEMENTS', LoxBerry::System::read_file( "$lbptemplatedir/lang/loxelements_$lang.json" ) );

my %miniservers = LoxBerry::System::get_miniservers();
$template->param( 'LOXONE_MINISERVERS', to_json( \%miniservers ) );

# The shortest interval a statistic may be given, in minutes - the field in the
# details popup is in minutes. Set on the System tab; while it is unset this is
# one, which is what the grabber has always applied.
$template->param( 'MIN_INTERVAL_MINUTES', int( Globals::loxone_min_interval() / 60 ) );

print $template->output();

LoxBerry::Web::lbfooter();
