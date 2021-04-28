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

LoxBerry::Web::lbheader("Stats4Lox", "https://loxwiki.eu", undef);

$template->param('LOGLIST_HTML', LoxBerry::Web::loglist_html());
print $template->output();

LoxBerry::Web::lbfooter();