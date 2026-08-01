use strict;
use warnings;
use LoxBerry::System;

package ServiceLog;

# Everything about the diagnostic logging of InfluxDB, Telegraf and Grafana in
# one place - the switch under Settings, the automatic switch-on at debug log
# level, the reset on reboot and the display under Logfiles all need the same
# service list and the same paths.
#
# No path is ever written out literally here. The plugin folder is not fixed -
# it comes from plugin.cfg - so log and config directories are always taken from
# LoxBerry::System.

# service unit -> unix user it runs as
our %SERVICES = (
	'influxdb'       => 'influxdb',
	'telegraf'       => 'telegraf',
	'grafana-server' => 'grafana',
);

# Human readable names for the Logfiles page
our %TITLES = (
	'influxdb'       => 'InfluxDB',
	'telegraf'       => 'Telegraf',
	'grafana-server' => 'Grafana',
);

sub logdir  { return $LoxBerry::System::lbplogdir; }
sub logfile { my ($svc) = @_; return logdir() . "/$svc.log"; }

# Marks that the switch was set deliberately in the web interface.
#
# Without it we could not tell the two cases apart on reboot: a user who turned
# logging on to look at something, and logging that switched itself on because
# the plugin log level was set to debug. The first has to survive a reboot, the
# second must not - otherwise a log level nobody remembers keeps the services
# writing forever.
sub flagfile { return $LoxBerry::System::lbpconfigdir . "/servicelogging_manual.flag"; }

sub set_manual
{
	my ($manual) = @_;
	my $f = flagfile();
	if( $manual ) {
		if( open( my $fh, '>', $f ) ) { close $fh; }
	}
	else {
		unlink $f;
	}
	return;
}

sub is_manual { return -e flagfile() ? 1 : 0; }

# Current setting from stats4lox.json
sub is_enabled
{
	my $cfg = _readconfig();
	return LoxBerry::System::is_enabled( $cfg->{stats4lox}->{servicelogging} ) ? 1 : 0;
}

# Writes the setting. Does NOT touch the drop-ins - that needs root and is done
# by config-handler.pl.
sub set_enabled
{
	my ($enabled, $manual) = @_;
	require LoxBerry::JSON;
	my $obj = LoxBerry::JSON->new();
	my $cfg = $obj->open( filename => $LoxBerry::System::lbpconfigdir . "/stats4lox.json" );
	return 0 if( !$cfg );
	$cfg->{stats4lox}->{servicelogging} = $enabled ? "True" : "False";
	$obj->write();
	set_manual( $enabled && $manual );
	return 1;
}

sub _readconfig
{
	require LoxBerry::JSON;
	my $obj = LoxBerry::JSON->new();
	my $cfg = $obj->open( filename => $LoxBerry::System::lbpconfigdir . "/stats4lox.json", readonly => 1 );
	return $cfg || {};
}

# Turns logging on when the plugin log level is set to debug.
#
# Called when a service is started from the web interface: whoever raises the
# log level to debug and then restarts a service wants to see what it says, and
# should not have to find a second switch for it. Returns 1 when something was
# changed.
sub follow_loglevel
{
	my $level = LoxBerry::System::pluginloglevel();
	return 0 if( !defined $level or $level < 7 );
	return 0 if( is_enabled() );
	set_enabled( 1, 0 );      # not manual - the reboot resets it again
	return 1;
}

1;
