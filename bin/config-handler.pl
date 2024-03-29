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

# Everything else give help
} else {
	print "Usage: $0 config\n";
	print "Available configs:\n";
	print "all | influx\n";
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
