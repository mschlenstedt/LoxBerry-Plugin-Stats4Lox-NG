#!/usr/bin/perl
# Switches the diagnostic logging of the services off again after a reboot -
# unless it was switched on deliberately in the web interface.
#
# Started from cron.reboot. Runs as the loxberry user, so the drop-ins are
# written by config-handler.pl, which has the necessary rights.

use warnings;
use strict;
use LoxBerry::System;
use LoxBerry::Log;
use FindBin qw($Bin);
use lib "$Bin/libs";
use Globals;
use ServiceLog;

my $log = LoxBerry::Log->new(
	name     => 'Service Logging',
	filename => "$LoxBerry::System::lbplogdir/servicelog.log",
	append   => 1,
	addtime  => 1,
);
LOGSTART "Service logging reset after reboot";

if( !ServiceLog::is_enabled() ) {
	LOGINF "Diagnostic logging is off - nothing to do.";
	LOGEND;
	exit 0;
}

if( ServiceLog::is_manual() ) {
	LOGINF "Diagnostic logging was switched on in the web interface - left untouched.";
	LOGEND;
	exit 0;
}

LOGINF "Diagnostic logging had followed the debug log level - switching it off again.";
ServiceLog::set_enabled( 0, 0 );
system("sudo $LoxBerry::System::lbpbindir/config-handler.pl servicelog >/dev/null 2>&1");
LOGOK "Done.";
LOGEND;
exit 0;
