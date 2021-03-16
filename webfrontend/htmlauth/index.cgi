#!/usr/bin/perl
use warnings;
use strict;
use LoxBerry::System;
use LoxBerry::Web;
use JSON;
use FindBin qw($Bin);
use lib "$Bin/../../../../bin/plugins/stats4lox-ng/libs/";
use Globals;

our $htmlhead = '<script type="application/javascript" src="js/settings_loxone.js"></script>';
LoxBerry::Web::lbheader("Stats4Lox", undef, undef);

my $template = HTML::Template->new(
    filename => "$lbptemplatedir/settings_loxone.html",
    global_vars => 1,
    loop_context_vars => 1,
    die_on_bad_params => 0,
);

my %loxone_elements = LoxBerry::System::readlanguage("loxelements.ini");
$template->param( 'LOXONE_ELEMENTS', join(',', map { '"'.substr($_,9).'":"'.$loxone_elements{$_}.'"' } keys %loxone_elements) );
my %miniservers = LoxBerry::System::get_miniservers();
$template->param( 'LOXONE_MINISERVERS', to_json( \%miniservers ) );


print $template->output();

LoxBerry::Web::lbfooter();
