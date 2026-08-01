#!/usr/bin/perl
use warnings;
use strict;
use LoxBerry::Web;
require "$lbpbindir/libs/Globals.pm";

my $template = HTML::Template->new(
	filename => "$lbptemplatedir/logs.html",
	global_vars => 1,
	loop_context_vars => 1,
	die_on_bad_params => 0,
);

my %L = LoxBerry::System::readlanguage($template, "language.ini");

our $htmlhead="";
$htmlhead .= '<script type="application/javascript" src="js/s4l_navbar.js"></script>';

init_navbar_i18n();
# The help link pointed at https://loxwiki.eu, which Loxone has retired. This
# was the only page passing a help url at all - every other page passes undef,
# so no dead link is shown anywhere now (issue #144).
LoxBerry::Web::lbheader("Stats4Lox", undef, undef);

$template->param('LOGLIST_HTML', LoxBerry::Web::loglist_html());
print $template->output();

LoxBerry::Web::lbfooter();