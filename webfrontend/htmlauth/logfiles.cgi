#!/usr/bin/perl
use warnings;
use strict;
use LoxBerry::Web;
use POSIX qw(strftime);
use URI::Escape;
require "$lbpbindir/libs/Globals.pm";
require "$lbpbindir/libs/ServiceLog.pm";

my $template = HTML::Template->new(
	filename => "$lbptemplatedir/logfiles.html",
	global_vars => 1,
	loop_context_vars => 1,
	die_on_bad_params => 0,
);

my %L = LoxBerry::System::readlanguage($template, "language.ini");

# This page loads Globals with require rather than use, so the exported name
# is not imported into main - the call needs its package name.
Globals::init_navbar_i18n();
# The help link pointed at https://loxwiki.eu, which Loxone has retired. This
# was the only page passing a help url at all - every other page passes undef,
# so no dead link is shown anywhere now (issue #144).
LoxBerry::Web::lbheader("Stats4Lox", undef, undef);

$template->param('LOGLIST_HTML', LoxBerry::Web::loglist_html());

# The logs of InfluxDB, Telegraf and Grafana are written by systemd, not through
# LoxBerry's logging library. They are therefore not in the log database and do
# not turn up in loglist_html() - they are added here in the same style the MQTT
# gateway uses for the Mosquitto log.
#
# Shown only when the file exists, which is exactly while the switch under
# Settings is on. The paths come from ServiceLog, never written out literally:
# the plugin folder is defined in plugin.cfg and is not fixed.
my @rows;
foreach my $svc ( sort keys %ServiceLog::SERVICES ) {
	my $file = ServiceLog::logfile($svc);
	next if( ! -e $file );
	my $mtime = ( stat($file) )[9];
	push @rows, {
		TITLE => $ServiceLog::TITLES{$svc} // $svc,
		DATE  => POSIX::strftime( "%d.%m.%Y %H:%M", localtime($mtime) ),
		SIZE  => LoxBerry::System::bytes_humanreadable( -s $file, "B" ),
		URL   => "/admin/system/tools/logfile.cgi?logfile=" . URI::Escape::uri_escape($file)
		         . "&header=html&format=template&only=once",
	};
}
if( @rows ) {
	$template->param('SERVICELOGS_EXIST', 1);
	$template->param('SERVICELOGS', \@rows);
}

print $template->output();

LoxBerry::Web::lbfooter();