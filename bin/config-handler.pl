#!/usr/bin/perl
use warnings;
use strict;
use LoxBerry::System;
use LoxBerry::JSON;
use LoxBerry::Log;
use FindBin qw($Bin);
use lib "$Bin/libs";
use Globals;
use Digest::MD5 qw(md5 md5_hex);
use Data::Dumper;

if ($<) {
  print "This script has to be run as root.\n";
  exit (1);
}

# Globals
my $command = $ARGV[0];
our $s4ljsonobj;
our $s4lcfg;
our $errors;
our $logfile;
our $chjsonobj;
our $chstatus;

#$LoxBerry::System::DEBUG = 1;

# Log
# This one keeps its log file on purpose - unlike ajax.cgi.
#
# The config handler is what actually changes the system: it moves the InfluxDB
# database, rewrites the systemd drop-ins, restarts services. When that goes
# wrong the log is the only record, and ajax.cgi starts it with
# ">/dev/null 2>&1", so stderr leads nowhere.
my $log = LoxBerry::Log->new (
	name => 'Config-Handler',
	stderr => 1,
);
$logfile = $log->filename();

LOGSTART "Config-Handler";

##########################################################
# Which config should be updated:
##########################################################

# Locking
# Locks lbupdate and immediately returns, if it cannot lock
LOGINF "Creating Lockfile and wait a maximum of 10 Minutes for the lock.";
my $lockstatus = LoxBerry::System::lock(lockfile => 'stats4lox_config-handler', wait => 600);
if ($lockstatus) {
    LOGCRIT "Could not lock for 10 Minutes now, prevented by $lockstatus";
    exit (1);
} else {
    LOGOK "Lock was successfully created.";
}

# Init status file
&initstatus();

# Influx Config
if ($command eq 'influx' || $command eq 'all') {

	LOGINF "--> Parsing INFLUX <--";
	&updatestatus("global", "current_section", "influx");
	&influxconfig();

}

# Service logging
if ($command eq 'servicelog' || $command eq 'all') {

	LOGINF "--> Parsing SERVICELOG <--";
	&updatestatus("global", "current_section", "servicelog");
	&servicelogconfig();

}

# Shortest polling interval of the Loxone statistics
if ($command eq 'grabber' || $command eq 'all') {

	LOGINF "--> Parsing GRABBER <--";
	&updatestatus("global", "current_section", "grabber");
	&grabberconfig();

}

if ($command ne 'influx' && $command ne 'servicelog' && $command ne 'grabber' && $command ne 'all') {
	print "Usage: $0 config\n";
	print "Available configs:\n";
	print "all | influx | servicelog | grabber\n";
	exit (1);
}

# Exit with error > 0 if an error happend
if ($errors) {
	exit ($errors);
} else {
	exit (0);
}


##########################################################
# Config Subs
##########################################################

# Influx
sub influxconfig {

	&updatestatus("influx", "errors", 0);
	&updatestatus("influx", "message", "Check for config changes.");

	my $checkchanges = &checkchanges("influx");

	if ( $checkchanges ) {
		LOGINF "*** Config hasn't changed. I will do nothing. ***";
		&updatestatus("influx", "message", "Finished.");
		return (0);
	}

	LOGINF "*** Config changed. Will change Influx configuration. ***";

	#
	# Move database
	#
	
	LOGINF "Checking DB storage folder...";
	my $dbtarget = $s4lcfg->{influx}->{db_storage};
	LOGDEB "Target folder is: $dbtarget";

	my $dbsource = `awk '/^  dir/{print \$NF; exit}' /etc/influxdb/influxdb.conf`;
	$dbsource =~ s/"//g; # remove ""
	$dbsource =~ s/(.*)\/.*$/$1/g; # remove last subfolder from path
	chomp($dbsource);
	LOGDEB "Source folder is: $dbsource";

	if ($dbtarget eq $dbsource || ! $dbsource) {
		LOGINF "DB storage hasn't changed. Leave it untouched.";
	} else {
		LOGINF "DB storage has changed. Moving DB to new location $dbtarget/influxdb.";
		&updatestatus("influx", "message", "Moving Database to new location.");

		my $result = &influx_movedb($dbsource, $dbtarget);
		if ($result) {
			LOGERR "Something went wrong. I haven't moved the DB to the new location.";
			$errors++;
		} else {
			LOGOK "DB was moved to the new location.";
		}
	}

	# End Influx Config
	&updatestatus("influx", "errors", $errors);
	&updatestatus("influx", "message", "Finished.");
	return ($errors);

}

# Diagnostic logging of InfluxDB, Telegraf and Grafana
#
# The drop-ins normally send the output of all three services to /dev/null, and
# for good reason: on LoxBerry the log directory sits on a ramdisk. But it also
# meant that a service failing in daily operation left no trace at all - which
# is issue #134.
#
# The switch under Settings redirects the output into
# log/plugins/stats4lox/<service>.log instead, where it shows up under Logfiles
# next to the plugin's own logs and is cleaned up by the LoxBerry core.
#
# "append:" and not "file:" - that difference decides whether this works.
# log_maint.pl empties a log file in place instead of deleting it, so that a
# daemon holding it open keeps writing into the same inode. A descriptor opened
# WITHOUT O_APPEND keeps its old offset after that and produces a sparse file:
# measured, 200 KB of holes and an apparent size that keeps growing while the
# emptying achieves nothing. With O_APPEND the next write lands at offset 0.
sub servicelogconfig {

	&updatestatus("servicelog", "errors", 0);
	&updatestatus("servicelog", "message", "Applying the service logging setting.");

	# $s4lcfg is only filled by this call. influxconfig() gets it as a side
	# effect of checkchanges(); leaving it out here meant the setting always
	# read as undefined and the switch never did anything.
	&reads4lconfig();

	require ServiceLog;

	my $enabled = LoxBerry::System::is_enabled( $s4lcfg->{stats4lox}->{servicelogging} ) ? 1 : 0;
	LOGINF "Diagnostic logging of the services is " . ( $enabled ? "ENABLED" : "disabled" )
	       . ( $enabled ? ( ServiceLog::is_manual() ? " (set in the web interface)" : " (following the debug log level)" ) : "" );

	my $logdir = ServiceLog::logdir();
	my $dropindir = $LoxBerry::System::lbpconfigdir . "/systemd";

	# service -> [ drop-in file, unix user of the service ]
	my %services;
	foreach my $svc ( keys %ServiceLog::SERVICES ) {
		my $short = ( $svc eq 'grafana-server' ) ? 'grafana' : $svc;
		$services{$svc} = [ "$dropindir/00-stats4lox-$short.conf", $ServiceLog::SERVICES{$svc} ];
	}

	# The services run as their own users, so they need to be able to create
	# their log file in a directory owned by loxberry. postroot.sh puts all
	# three into the loxberry group for exactly this kind of reason.
	#
	# Unconditionally, not only while the switch is on: Telegraf writes its own
	# log into this directory whatever the switch says, and its rotation creates
	# further files next to it.
	if( -d $logdir ) {
		chmod 0775, $logdir;
	}

	my $changed = 0;
	foreach my $svc ( sort keys %services ) {
		my ($file, $user) = @{ $services{$svc} };
		my $logfile = "$logdir/$svc.log";

		my $old = '';
		if( open( my $fh, '<', $file ) ) { local $/; $old = <$fh>; close $fh; }

		# Only the two Standard* lines may be touched. The InfluxDB drop-in also
		# carries the ExecStart override that points at startinflux.sh - writing
		# the file from scratch dropped it, and the service silently fell back
		# to the packaged start script.
		my @keep = grep { !/^\s*Standard(Output|Error)\s*=/ } split( /\n/, $old, -1 );
		pop @keep while( @keep and $keep[-1] =~ /^\s*$/ );
		push @keep, "[Service]" if( !grep { /^\s*\[Service\]\s*$/ } @keep );

		my $content = join( "\n", @keep ) . "\n";
		if( $enabled ) {
			$content .= "StandardOutput=append:$logfile\nStandardError=append:$logfile\n";
		}
		else {
			$content .= "StandardOutput=null\nStandardError=null\n";
		}

		next if( $old eq $content );

		if( !open( my $out, '>', $file ) ) {
			LOGERR "Could not write $file: $!";
			$errors++;
			next;
		}
		else {
			print {$out} $content;
			close $out;
		}
		$changed++;
		LOGOK "$svc: drop-in updated";

		# Create the file up front with the right owner. Without it systemd
		# would have to create it as the service user, and it has to stay
		# readable for loxberry so it can be shown under Logfiles.
		#
		# Also done when the switch is OFF but the file is already there: Telegraf
		# writes its own log into it either way, and a file left owned by anybody
		# else stops it from starting at all.
		next if( !$enabled and ! -e $logfile );

		if( ! -e $logfile ) {
			if( open( my $lf, '>>', $logfile ) ) { close $lf; }
		}
		my $uid = getpwnam($user);
		my $gid = getgrnam('loxberry');
		chown( $uid, $gid, $logfile ) if( defined $uid and defined $gid );
		chmod 0664, $logfile;
	}

	# And how much the three have to say in the first place.
	#
	# Redirecting the output is only half the switch: all three ship quiet, so
	# turning the logging on would have produced files with two startup lines in
	# them. The whole point of the switch is to see more than usual while looking
	# for something.
	$changed += service_verbosity( $enabled );

	if( !$changed ) {
		LOGINF "Nothing to change.";
		&updatestatus("servicelog", "errors", $errors);
		&updatestatus("servicelog", "message", "Finished.");
		return ($errors);
	}

	LOGINF "Restarting the services so the change takes effect...";
	&updatestatus("servicelog", "message", "Restarting the services.");
	system("systemctl daemon-reload > /dev/null 2>&1");
	foreach my $svc ( sort keys %services ) {
		# Only restart what is running - a service the user has deliberately
		# stopped must not be started by a logging change.
		next if( system("systemctl is-active --quiet $svc") != 0 );
		if( system("systemctl restart $svc > /dev/null 2>&1") != 0 ) {
			LOGERR "$svc could not be restarted";
			$errors++;
		}
		else {
			LOGOK "$svc restarted";
		}
	}

	&updatestatus("servicelog", "errors", $errors);
	&updatestatus("servicelog", "message", "Finished.");
	return ($errors);
}

##########################################################
# The Loxone grabber: how often Telegraf asks, and for how long
##########################################################
# Both numbers follow the shortest polling interval set on the System tab:
#
#   interval = the minimum itself      Telegraf calls the grabber that often
#   timeout  = the minimum less 3 s    it has to give up before the next round
#
# The grabber's own budget - the minimum less 5 s - is not written anywhere. It
# reads the setting itself now, through Globals::loxone_timeouts(). It used to
# parse this very file to find out, which meant the plugin read back a number it
# had written itself.
#
# While the setting is unset the file keeps the 60 s and 45 s it has always had.
# Nothing is written then, and an installation that never touches the setting
# never sees this function do anything.
sub grabberconfig {

	&updatestatus("grabber", "errors", 0);
	&updatestatus("grabber", "message", "Applying the polling interval.");

	&reads4lconfig();

	my $min = int( $s4lcfg->{loxone}->{min_interval} // 0 );
	if( $min <= 0 ) {
		LOGINF "No shortest interval configured - Telegraf keeps its current settings.";
		&updatestatus("grabber", "errors", $errors);
		&updatestatus("grabber", "message", "Finished.");
		return ($errors);
	}

	my $timeout = $min - 3;
	my $file = $LoxBerry::System::lbpconfigdir . "/telegraf/telegraf.d/stats4lox_loxone.conf";

	if( ! -f $file ) {
		LOGERR "$file not found";
		$errors++;
		&updatestatus("grabber", "errors", $errors);
		&updatestatus("grabber", "message", "Finished with errors.");
		return ($errors);
	}

	my @lines;
	if( !open( my $fh, '<', $file ) ) {
		LOGERR "Could not read $file: $!";
		$errors++;
		&updatestatus("grabber", "errors", $errors);
		&updatestatus("grabber", "message", "Finished with errors.");
		return ($errors);
	}
	else {
		@lines = <$fh>;
		close $fh;
	}

	# Written in place so the file keeps its owner - this runs as root and the
	# file belongs to loxberry.
	my $changed = 0;
	foreach my $line ( @lines ) {
		if( $line =~ /^(\s*)timeout(\s*)=(\s*)"[^"]*"/ ) {
			my $new = "$1timeout$2=$3\"${timeout}s\"\n";
			$changed = 1 if( $new ne $line );
			$line = $new;
		}
		elsif( $line =~ /^(\s*)interval(\s*)=(\s*)"[^"]*"/ ) {
			my $new = "$1interval$2=$3\"${min}s\"\n";
			$changed = 1 if( $new ne $line );
			$line = $new;
		}
	}

	if( !$changed ) {
		LOGINF "Telegraf already asks every ${min}s with a ${timeout}s timeout.";
		&updatestatus("grabber", "errors", $errors);
		&updatestatus("grabber", "message", "Finished.");
		return ($errors);
	}

	if( !open( my $out, '>', $file ) ) {
		LOGERR "Could not write $file: $!";
		$errors++;
	}
	else {
		print {$out} @lines;
		close $out;
		LOGOK "Telegraf asks every ${min}s now, timeout ${timeout}s (grabber budget "
			. ( $min - 5 ) . "s)";

		LOGINF "Restarting Telegraf so the change takes effect...";
		&updatestatus("grabber", "message", "Restarting Telegraf.");
		if( system("systemctl is-active --quiet telegraf") == 0 ) {
			if( system("systemctl restart telegraf > /dev/null 2>&1") != 0 ) {
				LOGERR "Telegraf could not be restarted";
				$errors++;
			}
			else {
				LOGOK "Telegraf restarted";
			}
		}
		else {
			LOGINF "Telegraf is not running - left alone";
		}
	}

	&updatestatus("grabber", "errors", $errors);
	&updatestatus("grabber", "message", "Finished.");
	return ($errors);
}

##########################################################
# One setting in one section of an ini-style file
##########################################################
# Param: file, section (without brackets), key, value, and whether the value is
# written in quotes. Returns 1 if the file was changed.
#
# Three files with three comment characters and the same job. The rules:
#
#   - only inside the named section. "debug" and "level" mean different things
#     in other sections of the same file
#   - an existing entry keeps its indentation, so the file still looks like the
#     one the user knows
#   - no entry but a commented default: written after it, where a reader would
#     look for it
#   - neither: after the section header, because falling back to the program's
#     own default would make the switch do nothing and say nothing
#
# Written in place. These files belong to influxdb, grafana and loxberry while
# this runs as root, and a new file moved over the old one would end up owned by
# root.
sub s4l_set_ini_value
{
	my ($file, $section, $key, $value, $quoted) = @_;

	if( ! -f $file ) {
		LOGWARN "$file not found - $section/$key unchanged";
		return 0;
	}

	my @lines;
	if( !open( my $fh, '<', $file ) ) {
		LOGERR "Could not read $file: $!";
		$errors++;
		return 0;
	}
	else {
		@lines = <$fh>;
		close $fh;
	}

	my $want = $quoted ? "\"$value\"" : $value;
	my ($in, $done, $changed) = (0, 0, 0);
	my @out;
	my $commented;   # index in @out of a commented default, to insert after

	foreach my $line ( @lines ) {
		if   ( $line =~ /^\s*\[\Q$section\E\]/ ) { $in = 1 }
		elsif( $line =~ /^\s*\[/ ) {
			# Leaving the section without having found the entry
			if( $in and !$done ) {
				my $at = defined $commented ? $commented + 1 : scalar @out;
				splice( @out, $at, 0, "  $key = $want\n" );
				$done = 1;
				$changed = 1;
			}
			$in = 0;
		}

		if( $in and !$done and $line =~ /^(\s*)\Q$key\E(\s*)=/ ) {
			my $new = "$1$key$2= $want\n";
			$changed = 1 if( $new ne $line );
			push @out, $new;
			$done = 1;
			next;
		}
		if( $in and !$done and $line =~ /^\s*[#;]\s*\Q$key\E\s*=/ ) {
			$commented = scalar @out;   # remember, the real entry may still come
		}
		push @out, $line;
	}

	# The section was the last one in the file
	if( $in and !$done ) {
		my $at = defined $commented ? $commented + 1 : scalar @out;
		splice( @out, $at, 0, "  $key = $want\n" );
		$changed = 1;
	}

	return 0 if( !$changed );

	# open() in the condition of an if would scope $out to that if - the print
	# below would then be against an undeclared variable and the whole script
	# would not compile. It did not, and the config handler silently aborted at
	# startup while everything downstream reported success.
	my $out;
	if( !open( $out, '>', $file ) ) {
		LOGERR "Could not write $file: $!";
		$errors++;
		return 0;
	}
	print {$out} @out;
	close $out;
	return 1;
}

##########################################################
# How much the three services say
##########################################################
# The switch under Settings decides WHERE the output goes - the drop-ins above.
# This decides HOW MUCH there is to go anywhere. Without it, turning the logging
# on produced a file with two startup lines in it: all three ship quiet, and
# rightly so on a machine that logs to a ramdisk.
#
#   Telegraf   [agent] debug / quiet
#   InfluxDB   [http] log-enabled      one line per HTTP request
#              [data] query-log-enabled  the queries themselves
#              [logging] level
#   Grafana    [log] level
#
# Errors are logged in both states everywhere - what is switched on here is the
# detail around them.
#
# Returns the number of files that changed, so the caller knows to restart.
sub service_verbosity
{
	my ($enabled) = @_;

	my $cfgdir = $LoxBerry::System::lbpconfigdir;
	my $changed = 0;

	# Telegraf
	my $tg = "$cfgdir/telegraf/telegraf.conf";
	my $t = 0;
	$t += s4l_set_ini_value( $tg, 'agent', 'debug', ( $enabled ? 'true'  : 'false' ), 0 );
	$t += s4l_set_ini_value( $tg, 'agent', 'quiet', ( $enabled ? 'false' : 'true'  ), 0 );
	if( $t ) {
		LOGOK "Telegraf: debug = " . ( $enabled ? 'true' : 'false' )
			. ", quiet = " . ( $enabled ? 'false' : 'true' );
		$changed++;
	}

	# InfluxDB
	#
	# The HTTP request log is one line per request and about 8600 a day on an
	# idle installation - which is why it is off by default and why it belongs
	# here rather than anywhere else. The query log is what answers "why is this
	# dashboard slow".
	my $ix = "$cfgdir/influxdb/influxdb.conf";
	my $i = 0;
	$i += s4l_set_ini_value( $ix, 'http',    'log-enabled',       ( $enabled ? 'true' : 'false' ), 0 );
	$i += s4l_set_ini_value( $ix, 'data',    'query-log-enabled', ( $enabled ? 'true' : 'false' ), 0 );
	$i += s4l_set_ini_value( $ix, 'logging', 'level',             ( $enabled ? 'debug' : 'info' ), 1 );
	if( $i ) {
		LOGOK "InfluxDB: request log and query log " . ( $enabled ? 'on' : 'off' )
			. ", level " . ( $enabled ? 'debug' : 'info' );
		$changed++;
	}

	# Grafana
	my $gf = "$cfgdir/grafana/grafana.ini";
	if( s4l_set_ini_value( $gf, 'log', 'level', ( $enabled ? 'debug' : 'info' ), 0 ) ) {
		LOGOK "Grafana: level " . ( $enabled ? 'debug' : 'info' );
		$changed++;
	}

	return $changed;
}
##########################################################
# Helper subroutines
##########################################################

# Init Config-Handler Status
sub initstatus {
	my $cfgfile = $Globals::stats4lox->{s4ltmp} . "/config-handler-status.json";
	$chjsonobj = LoxBerry::JSON->new();
	$chstatus = $chjsonobj->open(filename => $cfgfile, lockexclusive => 0, writeonclose => 1);
	$chstatus->{"global"}->{"running"} = 1;
	$chstatus->{"global"}->{"logfile"} = $logfile;
	$chjsonobj->write();
	return (0);
}
 
# Update Config-Handler Status 
sub updatestatus {
	my $section = shift;
	my $tag = shift;
	my $message = shift;
	$chstatus->{"$section"}->{"$tag"} = $message;
	$chjsonobj->write();
	return (0);
}

# Read S4L Config
# Returns zero (0) and fill global var $s4lcfg
sub reads4lconfig {
	my $cfgfile = $lbpconfigdir . "/stats4lox.json";
	$s4ljsonobj = LoxBerry::JSON->new();
	$s4lcfg = $s4ljsonobj->open(filename => $cfgfile, lockexclusive => 0, writeonclose => 1);
	return (0);
}

# Read credentials
# Returns Hash with credentials
#sub readcred {
#	my $cfgfile = $lbpplugindir."/cred.json";
#	my $jsonobj = LoxBerry::JSON->new();
#	my $cfg = $jsonobj->open(filename => $cfgfile);
#	return ($cfg);
#}

# Read S4L Hashes
# Returns Hash with MD5 checksums
sub reads4lhashes {
	my $cfgfile = $Globals::stats4lox->{s4ltmp} . "/stats4lox_json_md5.json";
	my $jsonobj = LoxBerry::JSON->new();
	my $cfg = $jsonobj->open(filename => $cfgfile);
	return ($cfg);
}

# Read S4L Hashes
# Saves config in global var and returns 0
sub writes4lhashes {
	mkdir("$Globals::stats4lox->{s4ltmp}",0777);
	my $jsonobj = LoxBerry::JSON->new();
	my $md5checksums = $jsonobj->open(filename => "$Globals::stats4lox->{s4ltmp}" . "/stats4lox_json_md5.json", writeonclose => 1);
	&reads4lconfig();
	foreach my $key (keys %{ $s4lcfg }) {
		$md5checksums->{$key} = md5_hex( Dumper( $s4lcfg->{$key} ) );
	}
	return();
}

# Check if config changed
# Returns 0 if config changed and 1 otherwise
sub checkchanges {
	my $sec = shift;
	$Data::Dumper::Sortkeys = 1;

	&reads4lconfig();

	if (!-e "$Globals::stats4lox->{s4ltmp}" . "/stats4lox_json_md5.json") {
		&writes4lhashes();
		return (0);
	}

	my $hashes = &reads4lhashes();
	my $currentmd5 = md5_hex( Dumper( $s4lcfg->{$sec} ) );
	if ($currentmd5 eq $hashes->{$sec}) {
		return (1);
	} else {
		&writes4lhashes();
		return (0);
	}
}

# Check size of given folder
# Returns dir size in kB
sub dirsize {
	my $dir = shift;
	my $size = `du -ks $dir | awk '{print \$1}'`;
	chomp($size);
	return ($size);
}

# Checks free space on target mountpoint
# Returns free space in kB
sub freespace {
	my $dir = shift;
	my %targetinfo = LoxBerry::System::diskspaceinfo($dir);
	return ($targetinfo{available});
}

# Influx: Move DB from source to target
# Returns 0 if successfull, 1 on error
sub influx_movedb {

	my $dbsource = shift;
	my $dbtarget = shift;

	my $noperms = 0;

	if ( !-e "$dbsource" ) {
		LOGERR "Source folder does not exist.";
		# Restore old db path
		$dbsource =~ s/(.*)\/influxdb$/$1/g; # remove influx subfolder from path
		$s4lcfg->{influx}->{db_storage} = "$dbsource";
		return (1);
	}

	if ( -e "$dbtarget/influxdb" ) {
		LOGERR "Target sub-folder $dbtarget/influxdb already exists.";
		# Restore old db path
		$dbsource =~ s/(.*)\/influxdb$/$1/g; # remove influx subfolder from path
		$s4lcfg->{influx}->{db_storage} = "$dbsource";
		return (1);
	}

	system ("mkdir -p $dbtarget/influxdb");
	if ($? > 0) {
		LOGERR "Target sub-folder $dbtarget/influxdb could not been created (target writable?).";
		# Restore old db path
		$dbsource =~ s/(.*)\/influxdb$/$1/g; # remove influx subfolder from path
		$s4lcfg->{influx}->{db_storage} = "$dbsource";
		return (1);
	} 
	system ("chown influxdb:loxberry $dbtarget/influxdb");
	if ($? > 0) {
		LOGINF "Cannot change owner/group of $dbtarget/influxdb. Assuming this is a filesystem wihtout permissions at all.";
		$noperms = 1;
	}

	my $sourcesize = &dirsize($dbsource);
	my $targetsize = &freespace($dbtarget);
	LOGDEB "Size of current DB is: $sourcesize kB. Free space on target mountpoint is: $targetsize kB.";
	if ( $sourcesize *1.25 > $targetsize ) {
		LOGERR "On target mountpoint is not enough free discspace available.";
		# Restore old db path
		$dbsource =~ s/(.*)\/influxdb$/$1/g; # remove influx subfolder from path
		$s4lcfg->{influx}->{db_storage} = "$dbsource";
		return (1);
	}

	# Move database to new location
	system ("systemctl stop influxdb");
	if ($noperms) {
		system ("rsync -av --no-owner --no-group --no-perms $dbsource/* $dbtarget/influxdb/ >> $logfile 2>&1");
	} else {
		system ("rsync -av $dbsource/* $dbtarget/influxdb/ >> $logfile 2>&1");
	}
	if ($? > 0) {
		LOGERR "Copying database failed.";
		system ("systemctl start influxdb");
		# Restore old db path
		$dbsource =~ s/(.*)\/influxdb$/$1/g; # remove influx subfolder from path
		$s4lcfg->{influx}->{db_storage} = "$dbsource";
		return (1);
	}

	LOGOK "Copied database successfully. Adjusting influx configuration now.";
	system("sed -i -e \"s#\\(^  dir = \\\"\\)\\(.*\\)\\(meta\\\"\$\\\)#  dir = \\\"" . $dbtarget . "/influxdb/meta" . "\\\"#g ; \
		s#\\(^  dir = \\\"\\)\\(.*\\)\\(data\\\"\$\\\)#  dir = \\\"" . $dbtarget . "/influxdb/data" . "\\\"#g ; \
		s#\\(^  wal-dir = \\\"\\)\\(.*\\)\\(wal\\\"\$\\\)#  wal-dir = \\\"" . $dbtarget . "/influxdb/wal" . "\\\"#g\" /etc/influxdb/influxdb.conf");
	system ("systemctl start influxdb");

	return (0);

}






END {
	# Finally write current hashes
	&writes4lhashes();
	# Close status file
	$chstatus->{"global"}->{"running"} = 0;
	$chstatus->{"global"}->{"current_section"} = "none";
	$chjsonobj->write();
	# Unlock
	my $unlockstatus = LoxBerry::System::unlock(lockfile => 'stats4lox_config-handler');
	# Close log
	LOGEND "End.";
}
