#!/usr/bin/perl

# Sets the password of the InfluxDB user, and repairs it when it is lost.
#
# Issue #45. Until now the password was generated once during installation and
# never touched again - if it got lost, or if an upgrade left cred.json and
# InfluxDB disagreeing, there was no way back short of reinstalling.
#
# Two routes, and the script picks whichever is needed:
#
#   The stored password still works. Then a plain "SET PASSWORD FOR ..." does
#   the job while authentication stays on.
#
#   The stored password does not work any more. Then the sequence from the
#   issue: stop InfluxDB, turn authentication off, start, set the password,
#   stop, turn authentication back on, start.
#
# The second route opens the database without authentication for a few seconds.
# It only listens on localhost and only over TLS, but it is still a window, so
# it is kept as short as possible, it is written to the log, and an END block
# puts auth-enabled back even if the script dies in between. Leaving a database
# unauthenticated because a script crashed would be far worse than a failed
# password change.
#
# Changing the password is not done when the new one has been written to
# cred.json: telegraf reads it from its own env file, Grafana has it inside the
# provisioned datasource, and mqttlive reads cred.json when it starts. All three
# are brought along - otherwise the plugin would keep running with the old
# password and stop collecting data.

use warnings;
use strict;
use LoxBerry::System;
use LoxBerry::JSON;
use LoxBerry::Log;
use Getopt::Long;
use FindBin qw($Bin);
use lib "$Bin/libs";
use Globals;

if( $< ) {
	print STDERR "This script has to be run as root.\n";
	exit 1;
}

my $command = shift @ARGV // '';
my ( $password, $generate );
GetOptions(
	'password=s' => \$password,
	'generate'   => \$generate,
);

# loglevel 6 regardless of what the plugin is set to.
#
# Most installations run on level 3, which suppresses everything below ERROR -
# and this script then leaves a log holding nothing but its own header. That is
# too little for a rare, security relevant operation that stops the database and
# turns authentication off and on again: if it goes wrong, the log is all there
# is to go on. It runs by hand, so there is no flood to fear.
my $log = LoxBerry::Log->new( name => 'InfluxPass', stderr => 1, append => 1, loglevel => 6 );
LOGSTART "InfluxDB password: $command";

my $CONF = "$LoxBerry::System::lbpconfigdir/influxdb/influxdb.conf";
my $ENVFILE = "$LoxBerry::System::lbpconfigdir/telegraf/telegraf.env";

# Progress for the web interface, written the same way the backup does it: the
# page cannot watch a background process, so it reads this file. It lives in the
# ramdisk, so writing it every step costs nothing.
my $STATUSFILE = ( $Globals::stats4lox->{s4ltmp} // '/dev/shm/s4ltmp' ) . "/influxpass-status.json";

sub status
{
	my (%p) = @_;
	eval {
		require File::Path;
		require JSON;
		my $dir = $STATUSFILE;
		$dir =~ s{/[^/]+$}{};
		File::Path::make_path($dir) if( ! -d $dir );
		open( my $fh, '>', $STATUSFILE ) or die;
		print {$fh} JSON::encode_json( { %p, time => time() } );
		close $fh;
		chown( scalar getpwnam('loxberry'), scalar getgrnam('loxberry'), $STATUSFILE );
	};
	return;
}

# Set as soon as authentication has been turned off, cleared once it is back.
# The END block uses it, so a crash cannot leave the database open.
our $AUTH_IS_OFF = 0;

sub run
{
	my ($cmd) = @_;
	my $out = `$cmd 2>&1`;
	return ( $?, $out );
}

sub influx_running
{
	my ($rc) = run( "systemctl is-active --quiet influxdb" );
	return $rc == 0 ? 1 : 0;
}

# Waits for the database to answer rather than sleeping a fixed time - on a
# Raspberry it needs noticeably longer than on a PC.
sub wait_for_influx
{
	my ($secs) = @_;
	$secs //= 60;
	for ( 1 .. $secs ) {
		if( influx_running() ) {
			# is-active is true before the HTTP endpoint accepts queries
			my ($rc) = run( "curl -s -k -o /dev/null https://localhost:8086/ping" );
			return 1 if( $rc == 0 );
		}
		sleep 1;
	}
	return 0;
}

sub cred
{
	my $obj = LoxBerry::JSON->new();
	my $c = $obj->open( filename => $Globals::stats4loxcredentials );
	return ( $obj, $c );
}

# auth-enabled lives in the [http] section. Only that one line is touched, and
# only inside that section - the file has three more settings whose names
# contain "auth-enabled" (pprof-auth-enabled, ping-auth-enabled).
sub set_auth
{
	my ($enabled) = @_;
	my $want = $enabled ? 'true' : 'false';

	open( my $in, '<', $CONF ) or do { LOGERR "Cannot read $CONF: $!"; return 0 };
	local $/;
	my $c = <$in>;
	close $in;

	my $n = ( $c =~ s/^(\s*auth-enabled\s*=\s*)(?:true|false)(\s*)$/$1$want$2/m );
	if( !$n ) {
		LOGERR "Could not find auth-enabled in $CONF";
		return 0;
	}

	open( my $out, '>', "$CONF.new" ) or do { LOGERR "Cannot write $CONF.new: $!"; return 0 };
	print {$out} $c;
	close $out;
	run( "chown --reference=" . quotemeta($CONF) . " " . quotemeta("$CONF.new") );
	run( "chmod --reference=" . quotemeta($CONF) . " " . quotemeta("$CONF.new") );
	rename( "$CONF.new", $CONF ) or do { LOGERR "Could not replace $CONF: $!"; return 0 };

	LOGINF "auth-enabled set to $want";
	return 1;
}

# A query with the credentials from cred.json
sub influx_auth
{
	my ($sql) = @_;
	my $bin = "$LoxBerry::System::lbpbindir/s4linflux";
	return run( "$bin -execute " . quotemeta($sql) );
}

# A query without any credentials - only usable while auth is off
sub influx_noauth
{
	my ($sql) = @_;
	return run( "influx -ssl -unsafeSsl -execute " . quotemeta($sql) );
}

sub password_works
{
	my ($rc, $out) = influx_auth( "SHOW DATABASES" );
	return ( $rc == 0 and $out !~ /authorization failed|unauthorized/i ) ? 1 : 0;
}

sub random_password
{
	my @c = ( 'A'..'Z', 'a'..'z', 0..9 );
	return join( '', map { $c[ int rand scalar @c ] } 1 .. 20 );
}

# --- what everything else needs to know ------------------------------------

sub update_credfile
{
	my ($user, $pass) = @_;
	my ($obj, $c) = cred();
	if( !$c ) { LOGERR "Cannot open cred.json"; return 0 }
	$c->{influx}->{influxdbuser} = $user;
	$c->{influx}->{influxdbpass} = $pass;
	$obj->write();
	run( "chown loxberry:loxberry " . quotemeta($Globals::stats4loxcredentials) );
	run( "chmod 640 " . quotemeta($Globals::stats4loxcredentials) );
	LOGOK "New password stored in cred.json";
	return 1;
}

# telegraf.conf refers to ${PASS_INFLUXDB}, which comes from this env file.
sub update_telegraf_env
{
	my ($user, $pass) = @_;
	if( ! -f $ENVFILE ) { LOGWARN "$ENVFILE does not exist - telegraf not updated"; return 0 }

	open( my $in, '<', $ENVFILE ) or do { LOGERR "Cannot read $ENVFILE: $!"; return 0 };
	my @lines = <$in>;
	close $in;

	my ($fu, $fp) = (0, 0);
	foreach my $l ( @lines ) {
		if( $l =~ /^USER_INFLUXDB=/ ) { $l = "USER_INFLUXDB=\"$user\"\n"; $fu = 1 }
		if( $l =~ /^PASS_INFLUXDB=/ ) { $l = "PASS_INFLUXDB=\"$pass\"\n"; $fp = 1 }
	}
	push @lines, "USER_INFLUXDB=\"$user\"\n" if( !$fu );
	push @lines, "PASS_INFLUXDB=\"$pass\"\n" if( !$fp );

	open( my $out, '>', "$ENVFILE.new" ) or do { LOGERR "Cannot write $ENVFILE.new: $!"; return 0 };
	print {$out} @lines;
	close $out;
	rename( "$ENVFILE.new", $ENVFILE ) or do { LOGERR "Could not replace $ENVFILE: $!"; return 0 };
	# telegraf reads this file as its user, and it holds a password
	run( "chown telegraf:loxberry " . quotemeta($ENVFILE) );
	run( "chmod 660 " . quotemeta($ENVFILE) );
	LOGOK "telegraf.env updated";
	return 1;
}

sub refresh_consumers
{
	status( running => 1, message => "Restarting Telegraf, Grafana and MQTT Live" );
	LOGINF "Handing the new password to the other services";

	# Grafana: the password sits in the provisioned datasource. The script
	# rewrites it from cred.json and restarts grafana-server itself.
	my ($rc, $out) = run( "$LoxBerry::System::lbpbindir/provisioning/set_datasource_influx.pl" );
	if( $rc == 0 ) { LOGOK "Grafana datasource rewritten" }
	else           { LOGERR "Could not rewrite the Grafana datasource: $out" }

	run( "systemctl restart telegraf" );
	if( ( run("systemctl is-active --quiet telegraf") )[0] == 0 ) { LOGOK "Telegraf restarted" }
	else { LOGERR "Telegraf is not running after the restart" }

	# mqttlive reads cred.json once at start. cron.reboot starts it, so it is
	# started here as well rather than only killed.
	run( "pkill -f mqttlive.php" );
	run( "sudo -n -u loxberry $LoxBerry::System::lbpbindir/mqtt/mqttlive.php "
	     . ">> $LoxBerry::System::lbplogdir/mqttlive.log 2>&1 &" );
	LOGINF "MQTT Live restarted";
	return;
}

# --- the two routes --------------------------------------------------------

sub set_with_auth
{
	my ($user, $new) = @_;
	status( running => 1, message => "Setting the new password" );
	LOGINF "Trying to change the password with the stored credentials";
	my ($rc, $out) = influx_auth( "SET PASSWORD FOR \"$user\" = '$new'" );
	if( $rc != 0 or $out =~ /error/i ) {
		LOGINF "That did not work: " . ( $out =~ /\S/ ? $out : "no answer" );
		return 0;
	}
	LOGOK "Password changed in InfluxDB";
	return 1;
}

sub set_without_auth
{
	my ($user, $new) = @_;

	status( running => 1, message => "Stored password does not work - restarting the database without authentication" );
	LOGWARN "Falling back to the route without authentication - the stored password does not work.";
	LOGWARN "InfluxDB is briefly reachable on localhost without a password.";

	run( "systemctl stop influxdb" );
	return 0 if( !set_auth(0) );
	$AUTH_IS_OFF = 1;
	run( "systemctl start influxdb" );
	if( !wait_for_influx() ) {
		LOGERR "InfluxDB did not come up with authentication switched off";
		return 0;
	}

	# The user may be missing entirely, not just have a different password.
	my ($rc, $out) = influx_noauth( "SET PASSWORD FOR \"$user\" = '$new'" );
	if( $rc != 0 or $out =~ /user not found/i ) {
		LOGINF "User $user does not exist - creating it";
		($rc, $out) = influx_noauth( "CREATE USER \"$user\" WITH PASSWORD '$new' WITH ALL PRIVILEGES" );
	}
	my $ok = ( $rc == 0 and $out !~ /error/i ) ? 1 : 0;
	LOGERR "Could not set the password: $out" if( !$ok );

	run( "systemctl stop influxdb" );
	set_auth(1) or LOGERR "COULD NOT SWITCH AUTHENTICATION BACK ON - check $CONF";
	$AUTH_IS_OFF = 0;
	run( "systemctl start influxdb" );
	if( !wait_for_influx() ) {
		LOGERR "InfluxDB did not come up again";
		return 0;
	}
	LOGOK "Authentication is on again" if( $ok );
	return $ok;
}

# --- commands --------------------------------------------------------------

sub cmd_set
{
	status( running => 1, message => "Preparing" );
	my ($obj, $c) = cred();
	if( !$c ) { LOGERR "Cannot read cred.json"; return 1 }
	my $user = $c->{influx}->{influxdbuser} // 'stats4lox';

	my $new = $password;
	$new = random_password() if( $generate or !defined $new or $new eq '' );

	# The line protocol and InfluxQL both use the single quote as a delimiter,
	# and neither offers an escape that survives the shell in between. Refused
	# rather than mangled.
	if( $new =~ /['"\\\s]/ ) {
		LOGERR "The password must not contain quotes, backslashes or spaces";
		return 1;
	}
	if( length($new) < 8 ) {
		LOGERR "The password must be at least 8 characters long";
		return 1;
	}

	if( !influx_running() ) {
		LOGINF "InfluxDB is not running - starting it";
		run( "systemctl start influxdb" );
		wait_for_influx();
	}

	my $ok = 0;
	$ok = set_with_auth( $user, $new ) if( password_works() );
	$ok = set_without_auth( $user, $new ) if( !$ok );

	if( !$ok ) {
		status( running => 0, errors => 1, message => "The password was not changed" );
		LOGERR "The password was not changed";
		return 1;
	}

	status( running => 1, message => "Storing the new password" );
	update_credfile( $user, $new );

	# Proof rather than assumption: the new password has to work now.
	if( password_works() ) { LOGOK "The new password works" }
	else {
		status( running => 0, errors => 1, message => "The new password does not work" );
		LOGERR "The new password does not work - something is wrong";
		return 1;
	}

	update_telegraf_env( $user, $new );
	refresh_consumers();

	status( running => 0, errors => 0, message => "Password changed" );
	LOGOK "Password change finished";
	return 0;
}

my $rc = 0;
if( $command eq 'set' ) { $rc = cmd_set() }
else {
	print STDERR "Usage: $0 set [--password <new>] [--generate]\n";
	print STDERR "  Without --password a password is generated.\n";
	exit 1;
}

LOGEND;
exit $rc;

# Whatever happened above, the database must not be left without
# authentication.
END {
	if( $AUTH_IS_OFF ) {
		print STDERR "Restoring auth-enabled after an abort\n";
		set_auth(1);
		system( "systemctl restart influxdb" );
	}
}
