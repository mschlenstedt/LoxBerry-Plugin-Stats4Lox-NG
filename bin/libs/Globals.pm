#!/usr/bin/perl
use LoxBerry::System;
use LoxBerry::JSON;

# NAVBAR definition (in scope main) - English defaults, translated by init_navbar_i18n()
#
# The Grafana entry links straight into Grafana's own web interface instead of
# going through a page of our own. That page existed, but its only live content
# was a button doing exactly this - everything else in it had been commented out
# as unfinished.
our %navbar = (
	1 => {
			Name => "Home",
			URL => "index.cgi"
	},
	10 => {
			Name => "Loxone and Import",
			URL => "loxone.cgi"
	},
	20 => {
			Name => "Data Sources",
			URL => "data_inputs.cgi"
	},
	25 => {
			Name => "InfluxDB",
			URL => "influx.cgi"
	},
	30 => {
			Name => "Grafana",
			# The real URL is set in init_navbar_i18n(): the configured port is
			# only known after merge_config(), which runs further down in this
			# file - after this definition.
			URL => "",
			# The navbar does not use the anchor's target attribute at all - its
			# click handler calls preventDefault() and then window.open(url,
			# target), taking "target" from this structure. So this property is
			# what actually opens Grafana in a new tab.
			target => "_blank"
	},
	40 => {
			Name => "System",
			URL => "system.cgi"
	},
	90 => {
			Name => "Logfiles",
			URL => "logfiles.cgi"
	}
);
my $relative_webpath = substr( $0, length($lbphtmlauthdir)+1 );
foreach( keys %navbar ) {
	if( $navbar{$_}{URL} eq $relative_webpath ) {
		$navbar{$_}{active} = 1;
		last;
	}
}

#### GLOBALS ####

package Globals;

use base 'Exporter';
our @EXPORT = qw (
	@CONTROL_BLACKLIST
	@CONTROL_MS_FALLBACK
	$statsconfig
	$stats4loxconfig
	$stats4loxcredentials
	whoami
	merge_config
	init_navbar_i18n
	js_tag
);

#####################################################
# Script tag for one of the plugin's own js files
#####################################################
# With a plain <script src="js/loxone.js"> the browser keeps the copy it already
# has. Nothing in the plugin tells it otherwise, so after an update the page runs
# old JavaScript against a new backend - and the only symptom is that a change
# "does not work". The file's mtime as a query string is enough: it changes
# exactly when the file does, and never otherwise, so the cache still does its
# job.
#####################################################

sub js_tag
{
	my ($dir, $file) = @_;
	my $v = ( stat("$dir/js/$file") )[9] || 0;
	return '<script type="application/javascript" src="js/' . $file . '?v=' . $v . '"></script>';
}

# Internal variable, if merge_config was already called
my $config_is_parsed;

# Main configuration files (not changeable in stats4lox.json)
our $statsconfig = "$LoxBerry::System::lbpconfigdir/stats.json";
our $stats4loxconfig = "$LoxBerry::System::lbpconfigdir/stats4lox.json";
our $stats4loxcredentials = "$LoxBerry::System::lbpconfigdir/cred.json";

# Default parameters

our $grafana = {
	port => 3000,
	grafanaport => 3000,
	graf_provisioning_dir => "/etc/grafana/provisioning",
	s4l_provisioning_dir => "$LoxBerry::System::lbpconfigdir/provisioning",
	s4l_provisioning_template_dir => "$LoxBerry::System::lbptemplatedir/grafana/templates",
};

our $influx = {
	influx_bulk_blocksize => 1000,
	influx_bulk_delay_secs => 1,
	influxbasicauth => "true",
	influxdatabase => "stats4lox",
	influxskiptlsverify => "true",
	influxurl => "https://localhost:8086",
};

# How long measurements are kept, and whether older ones are condensed instead of
# deleted (issue #44).
#
# Both off by default, and that is not a formality: an upgrade must never start
# deleting somebody's history. "0" means keep everything, which is what InfluxDB
# does today with autogen at DURATION 0s.
#
# The retention is applied to autogen itself and NOT to a newly created default
# policy. That was tried and measured: creating another policy and making it the
# default leaves all existing data in autogen and makes it invisible to every
# query that does not name a policy - which is every existing Grafana panel. The
# 571 MB of history on the test installation would have disappeared from all
# graphs. Renaming a policy is not possible in InfluxDB, and moving the data would
# mean rewriting the whole database. So autogen keeps its ugly name.
#
# The stages describe the downsampling. Stage 1 is always the raw data in autogen
# and cannot be switched off; the others are named policies fed by continuous
# queries. The LAST active stage always carries the total retention from
# "duration" above - the web interface shows that greyed out, because two fields
# for the same number can only contradict each other.
#
# interval is what a continuous query condenses into one point. Nothing below an
# hour is offered: measured on real data, a five minute interval on values that
# arrive every five minutes produces MORE data than it replaces, because one point
# with one field becomes one point with two.
our $retention = {
	# "0" = unbegrenzt, sonst eine InfluxDB-Dauer: 30d, 365d, 1095d, 1825d, 3650d
	duration     => "0",
	downsampling => "False",
	# Aggregate der Verdichtung. Bewusst nicht einstellbar: mean allein macht
	# Zaehlerstaende unbrauchbar, last allein verliert den Verlauf. Beide zusammen
	# decken Temperaturen und Zaehler ab und kosten nur zwei Felder.
	aggregates   => [ "mean", "last" ],
	# Drei Stufen, nicht mehr.
	#
	# Es waren fuenf, und das war zu viel - gemessen, nicht gemeint. Eine
	# InfluxDB-Aufbewahrungsstufe hat genau EINE Dauer, und die zaehlt immer ab
	# jetzt. "Behalte nur, was zwischen einem und zwei Jahren alt ist" laesst sich
	# damit nicht ausdruecken, also enthaelt jede Stufe ihr ganzes Fenster und
	# nicht ein Band. Bei vier Stufen liegt das letzte Jahr viermal in der
	# Datenbank.
	#
	# Auf der Testanlage (573 MB, Grabber stuendlich): vier Stufen sparten 56 MB,
	# zwei Stufen 392 MB. Jede zusaetzliche Stufe legt eine weitere vollstaendige
	# Kopie ihres Fensters an, und der Gewinn kommt nur aus dem aeltesten Band,
	# das nichts Feineres abdeckt. Drei ist der Punkt, an dem sich das noch lohnt.
	stages => [
		# Stufe 1: Rohdaten, immer aktiv, Policy autogen
		{ active => "True",  interval => "raw", duration => "0"  },
		{ active => "False", interval => "1h",  duration => ""   },
		{ active => "False", interval => "1d",  duration => ""   },
	],
};

# What the web interface may offer for the two fields above. Here and not in the
# JavaScript, because ajax.cgi checks against the same lists before writing - a
# list that lives in the browser is a suggestion, not a rule.
#
# Nothing below an hour, for the reason given above. The durations are the ones
# that were measured on the test installation: keeping one year frees 566 MB of
# 571, two years 425 MB, three 232 MB, five 47 MB.
our @RETENTION_INTERVALS = qw( 1h 2h 6h 12h 1d 1w );
our @RETENTION_DURATIONS = qw( 0 30d 90d 180d 365d 730d 1095d 1825d 3650d );

# What a LoxBerry knows about itself, read from Linfo - the system information
# every LoxBerry serves at /system/tools/linfo/index.php?out=json, without
# authentication.
#
# Off by default, and unlike the Miniserver that is not caution about upgrades:
# this source has never collected anything, so switching it on is the user's
# decision either way.
#
# "hosts" are the OTHER LoxBerrys. The one this plugin runs on is not in that list
# and cannot be taken out of the collection - it is always asked first and over
# localhost, so it needs neither a name nor working DNS.
our $loxberry = {
	active => "False",
	interval => 900,
	measurement => "stats_loxberry",
	metrics => [],
	hosts => [],
};

our $loxone = {
	active => "True",
	# Where the LoxPLAN comes from: "auto" fetches it from the Miniserver,
	# "manual" uses a file the user uploaded (issue #101).
	loxplansource => "auto",
	mqttlive_basetopic => "s4l/mqttlive",
	# The shortest interval a Loxone statistic may be polled with, in seconds.
	#
	# 0 means "never set", and that is not the same as 60. An installation that
	# has never touched this setting keeps the values it has always had - see
	# loxone_timeouts() - because those are written in stats4lox_loxone.conf and
	# nothing may change them behind the user's back.
	min_interval => 0,
};

# What the System tab may offer as the shortest interval, in seconds. One to five
# minutes: Telegraf asks the grabber every minute, so a minute is the floor, and
# beyond five the wait for a value gets long enough that nobody would call it a
# statistic any more.
our @LOXONE_MIN_INTERVALS = ( 60, 120, 180, 240, 300 );

# The shortest interval in force. 60 seconds while the setting is unset - that is
# what the grabber has always applied.
sub loxone_min_interval
{
	my $m = int( $Globals::loxone->{min_interval} // 0 );
	return 60 if( $m <= 0 );
	return $m;
}

# ( Telegraf request timeout, grabber time budget ), both in seconds.
#
# Derived from the interval: Telegraf has to give up before the next round is
# due, and the grabber has to be finished before Telegraf gives up. Three and
# five seconds of margin, which is what Michael settled on.
#
# UNSET is a case of its own and not "the same as 60". Until 08.08.2026 these
# were fixed at 45 and 43 in stats4lox_loxone.conf, and an upgrade must not
# silently move them: an installation whose grabber has been finishing inside 43
# seconds keeps exactly that. The formula applies from the moment somebody
# chooses a value - including 1 minute, which then means 57 and 55.
sub loxone_timeouts
{
	my $m = int( $Globals::loxone->{min_interval} // 0 );
	return ( 45, 43 ) if( $m <= 0 );
	return ( $m - 3, $m - 5 );
}

# The Miniserver's own vital signs - CPU load, memory, temperature, bus and LAN
# counters, the state of the PLC. Not a Loxone block, so nothing on the Loxone tab
# switches it; Data sources -> Miniserver does.
#
# "metrics" is the list of keys from @MINISERVER_METRICS below that are actually
# collected. Empty or missing means the default set, which is exactly what the
# grabber fetched before it could be chosen: an upgrade must not silently start or
# stop writing a series.
our $miniserver = {
	active => "True",
	interval => 300,
	measurement => "stats_miniserver",
	metrics => [],
};

# What the two data source pages may offer as a polling interval, in seconds.
# Checked again in ajax.cgi before anything is written, for the same reason as the
# retention lists above: a list that lives in the browser is a suggestion, not a
# rule.
#
# Five minutes is the shortest on offer. These are vital signs of a machine, not a
# measurement - and for the Miniserver one round is one HTTP request per selected
# value, the most expensive thing the plugin asks of it on its own initiative.
# Every value is a multiple of a minute, because Telegraf asks the grabbers once a
# minute and they decide for themselves whether the interval has come round;
# anything in between just drifts.
our @GRABBER_INTERVALS = ( 300, 600, 900, 1800, 3600 );

# Where the grabber remembers when each Miniserver is due again. On the ramdisk
# on purpose: after a reboot every Miniserver is simply due at once.
#
# Named here rather than in the grabber because the System tab deletes the file
# when the interval is saved. Without that, shortening the interval would take
# effect only after the OLD one had elapsed - up to an hour of a page saying it
# polls every minute while nothing happens.
our $miniserver_memfile = "/dev/shm/stats4lox_mem_miniservergrabber.json";
our $loxberry_memfile   = "/dev/shm/stats4lox_mem_loxberrygrabber.json";

# Everything the Miniserver will tell us about itself, measured against a live
# Miniserver (firmware 17.1.6.30) on 07.08.2026 rather than taken from a list.
#
#   key      the field name in the database. The Miniserver is a tag, not part of
#            the name - it used to be msno_<n>_<key>, see s4l_migrate_msfields.pl
#   url      the web service that answers. Several keys may share one URL - it is
#            fetched once and the values are picked out of the one answer.
#   pick     how to get the number out of that answer, see grabber_miniserver.cgi
#   group    only for the ordering of the selection list
#   default  the FALLBACK for an installation whose configuration has no metrics
#            list at all - and that is exactly what this grabber fetched before
#            the list could be chosen. It is deliberately NOT the recommended set.
#
# Two defaults, on purpose, because they answer two different questions.
#
# What a NEW installation collects is in the shipped config/stats4lox.json: the
# thirteen values Michael settled on after seeing what a Miniserver really
# answers, every fifteen minutes. That file only ever lands on a fresh install -
# an upgrade backs the old configuration up in preupgrade.sh and postroot.sh
# copies it back over the new one.
#
# What an EXISTING installation collects must not change because it was updated.
# Those have no "metrics" key - it did not exist - so they fall through to the
# flags below, and the flags therefore have to stay the nineteen from before.
#
# The bus and LAN counters are NOT documented by Loxone. They answer, they count,
# and the names are abbreviations - so their labels say what the abbreviation
# most likely stands for and the page says that Loxone does not document them.
# Guessing quietly would be worse than saying so.
#
# What was tried and does not work, so that nobody tries again:
#   /jdev/sys/ints           answers 200 with an EMPTY value, although the Loxone
#                            documentation lists it
#   /jdev/sys/uptime, sensors, errors, loglevel, mem, stat        404
#   /jdev/bus/collisions, buserrors, packetslost, breakerrors     404
#   /jdev/lan/rxe, crc, len                                       404
#   /jdev/task<n>/*          answers, but there are 79 tasks and their numbering
#                            shifts with the firmware - not a stable series
our @MINISERVER_METRICS = (
	{ key => 'sys_cpu',              url => '/jdev/sys/cpu',         pick => 'number',    group => 'SYSTEM', default => 1 },
	{ key => 'sys_heap',             url => '/jdev/sys/heap',        pick => 'heapfree',  group => 'SYSTEM', default => 1 },
	{ key => 'sys_heap_total',       url => '/jdev/sys/heap',        pick => 'heaptotal', group => 'SYSTEM', default => 0 },
	{ key => 'sys_numtasks',         url => '/jdev/sys/numtasks',    pick => 'number',    group => 'SYSTEM', default => 1 },
	{ key => 'sys_temperature',      url => '/jdev/sys/temperature', pick => 'tempcpu',   group => 'SYSTEM', default => 0 },
	{ key => 'sys_temperature_stm32',url => '/jdev/sys/temperature', pick => 'tempstm32', group => 'SYSTEM', default => 0 },
	{ key => 'sys_check',            url => '/jdev/sys/check',       pick => 'number',    group => 'SYSTEM', default => 0 },

	{ key => 'sps_state',            url => '/jdev/sps/state',       pick => 'number',    group => 'SPS',    default => 1 },
	{ key => 'sps_frequency',        url => '/jdev/sps/status',      pick => 'spsfreq',   group => 'SPS',    default => 0 },

	{ key => 'bus_packetssent',      url => '/jdev/bus/packetssent',     pick => 'number', group => 'BUS', default => 1 },
	{ key => 'bus_packetsreceived',  url => '/jdev/bus/packetsreceived', pick => 'number', group => 'BUS', default => 1 },
	{ key => 'bus_receiveerrors',    url => '/jdev/bus/receiveerrors',   pick => 'number', group => 'BUS', default => 1 },
	{ key => 'bus_frameerrors',      url => '/jdev/bus/frameerrors',     pick => 'number', group => 'BUS', default => 1 },
	{ key => 'bus_overruns',         url => '/jdev/bus/overruns',        pick => 'number', group => 'BUS', default => 1 },
	{ key => 'bus_parityerrors',     url => '/jdev/bus/parityerrors',    pick => 'number', group => 'BUS', default => 1 },

	{ key => 'lan_txp',              url => '/jdev/lan/txp',         pick => 'number',    group => 'LAN',    default => 1 },
	{ key => 'lan_txe',              url => '/jdev/lan/txe',         pick => 'number',    group => 'LAN',    default => 1 },
	{ key => 'lan_txc',              url => '/jdev/lan/txc',         pick => 'number',    group => 'LAN',    default => 1 },
	{ key => 'lan_exh',              url => '/jdev/lan/exh',         pick => 'number',    group => 'LAN',    default => 1 },
	{ key => 'lan_txu',              url => '/jdev/lan/txu',         pick => 'number',    group => 'LAN',    default => 1 },
	{ key => 'lan_rxp',              url => '/jdev/lan/rxp',         pick => 'number',    group => 'LAN',    default => 1 },
	{ key => 'lan_eof',              url => '/jdev/lan/eof',         pick => 'number',    group => 'LAN',    default => 1 },
	{ key => 'lan_rxo',              url => '/jdev/lan/rxo',         pick => 'number',    group => 'LAN',    default => 1 },
	{ key => 'lan_nob',              url => '/jdev/lan/nob',         pick => 'number',    group => 'LAN',    default => 1 },
);

# The keys that are collected: the saved selection, or the default set if nothing
# has ever been chosen.
#
# An EMPTY selection therefore means the same as none at all. That is a rule, not
# an oversight: the page refuses to save an empty list and points at the on/off
# switch instead, because "collect nothing" already has a control of its own.
sub miniserver_metrics
{
	my $sel = $Globals::miniserver->{metrics};
	my %known = map { $_->{key} => 1 } @MINISERVER_METRICS;

	my @out;
	if( ref($sel) eq 'ARRAY' and scalar @$sel ) {
		# In the order of the catalogue, not of the configuration, and without
		# anything unknown - a key that was renamed here must not survive in a
		# configuration file and go on producing a field nobody can find.
		my %want = map { $_ => 1 } grep { $known{$_} } @$sel;
		@out = grep { $want{ $_->{key} } } @MINISERVER_METRICS;
	}
	return @out if( scalar @out );
	return grep { $_->{default} } @MINISERVER_METRICS;
}

# What a LoxBerry reports about itself, out of one Linfo document.
#
#   key      the field name in the database. No host in it - the host is a tag,
#            which is what tags are for, and the Miniserver measurement was
#            corrected to the same shape (s4l_migrate_msfields.pl).
#   pick     how to get the number out of the document, see Stats4Lox
#   path     for pick "path": where the value sits, as a list of keys
#   group    only for the ordering of the selection list
#   default  collected when the source is switched on and nothing has been chosen
#
# Read against two live LoxBerrys on 07.08.2026 - an x86 VM (Debian 12, Linfo
# 14965 bytes) and a Raspberry Pi 4 (aarch64, 8991 bytes) - because half of what
# Linfo reports depends on the machine.
#
# What is deliberately NOT here:
#   Mounts as a whole    38 entries on the VM, 30 of them tmpfs/sysfs/cgroup and
#                        ten SMB shares that all report the same 7.9 TB
#   HD, Devices, CPU     partition tables, 20 PCI/USB devices, per-core Vendor and
#                        MHz - inventory, not a time series
#   OS, Kernel, Distro, phpVersion, webService, CPUArchitecture, virtualization,
#   Model, AccessedIP    text that never changes
#   Battery, Raid, Wifi  empty on both machines
#   services             Linfo reports whether Apache and SSHd are running, and
#                        "Apache is up" cannot be anything but 1 here: Linfo is a
#                        page served BY that Apache. If it were down, the whole
#                        document would be missing, not one field in it.
our @LOXBERRY_METRICS = (
	{ key => 'load_1',          pick => 'path', path => ['Load','now'],     group => 'SYSTEM', default => 1 },
	{ key => 'load_5',          pick => 'path', path => ['Load','5min'],    group => 'SYSTEM', default => 1 },
	{ key => 'load_15',         pick => 'path', path => ['Load','15min'],   group => 'SYSTEM', default => 1 },
	{ key => 'cpu_usage',       pick => 'path', path => ['cpuUsage'],       group => 'SYSTEM', default => 1 },
	# Only the Pi answers this one: Temps is an empty list on the x86 machine, and
	# a metric with no value simply writes no field.
	{ key => 'cpu_temperature', pick => 'temp',                             group => 'SYSTEM', default => 1 },
	# Seconds since the boot, not the boot timestamp: a restart is then a drop to
	# zero rather than a step in a number nobody reads as a date.
	{ key => 'uptime',          pick => 'uptime',                           group => 'SYSTEM', default => 1 },
	{ key => 'users_loggedin',  pick => 'path', path => ['numLoggedIn'],    group => 'SYSTEM', default => 0 },

	{ key => 'ram_total',        pick => 'path', path => ['RAM','total'],     group => 'RAM', default => 0 },
	{ key => 'ram_free',         pick => 'path', path => ['RAM','free'],      group => 'RAM', default => 1 },
	{ key => 'ram_used_percent', pick => 'usedpct', of => ['RAM','total'], free => ['RAM','free'], group => 'RAM', default => 1 },
	{ key => 'swap_total',        pick => 'path', path => ['RAM','swapTotal'], group => 'RAM', default => 0 },
	{ key => 'swap_free',         pick => 'path', path => ['RAM','swapFree'],  group => 'RAM', default => 0 },
	{ key => 'swap_used_percent', pick => 'usedpct', of => ['RAM','swapTotal'], free => ['RAM','swapFree'], group => 'RAM', default => 1 },

	{ key => 'proc_total',   pick => 'path', path => ['processStats','proc_total'],        group => 'PROC', default => 1 },
	{ key => 'proc_threads', pick => 'path', path => ['processStats','threads'],           group => 'PROC', default => 0 },
	{ key => 'proc_running', pick => 'path', path => ['processStats','totals','running'],  group => 'PROC', default => 0 },
	{ key => 'proc_zombie',  pick => 'path', path => ['processStats','totals','zombie'],   group => 'PROC', default => 1 },

	{ key => 'disk_root_size',         pick => 'mount', mount => '/', field => 'size',         group => 'DISK', default => 0 },
	{ key => 'disk_root_used',         pick => 'mount', mount => '/', field => 'used',         group => 'DISK', default => 0 },
	{ key => 'disk_root_used_percent', pick => 'mount', mount => '/', field => 'used_percent', group => 'DISK', default => 1 },
	# The two ramdisks a LoxBerry has, and which one carries the logs depends on
	# the machine: /var/log on the x86 installation, /opt/loxberry/log/ramlog on
	# the Pi. Both are offered; the one that does not exist writes nothing.
	{ key => 'disk_varlog_used_percent', pick => 'mount', mount => '/var/log',                 field => 'used_percent', group => 'DISK', default => 0 },
	{ key => 'disk_ramlog_used_percent', pick => 'mount', mount => '/opt/loxberry/log/ramlog', field => 'used_percent', group => 'DISK', default => 0 },
	{ key => 'disk_shm_used_percent',    pick => 'mount', mount => '/dev/shm',                 field => 'used_percent', group => 'DISK', default => 0 },

	# Summed over every interface except the loopback. Which one exists is up to
	# the machine - eth0, wlan0, enp1s0 - so a fixed catalogue cannot name them.
	{ key => 'net_bytes_received',   pick => 'net', dir => 'recieved', field => 'bytes',   group => 'NET', default => 1 },
	{ key => 'net_bytes_sent',       pick => 'net', dir => 'sent',     field => 'bytes',   group => 'NET', default => 1 },
	{ key => 'net_packets_received', pick => 'net', dir => 'recieved', field => 'packets', group => 'NET', default => 0 },
	{ key => 'net_packets_sent',     pick => 'net', dir => 'sent',     field => 'packets', group => 'NET', default => 0 },
	{ key => 'net_errors_received',  pick => 'net', dir => 'recieved', field => 'errors',  group => 'NET', default => 1 },
	{ key => 'net_errors_sent',      pick => 'net', dir => 'sent',     field => 'errors',  group => 'NET', default => 1 },
);

# "recieved" is spelled that way in Linfo's output. It is not a typo in this file.

# The same rule as miniserver_metrics(): the saved selection, or the default set
# if nothing has ever been chosen. An empty selection means the same as none at
# all, and the page refuses to save one.
sub loxberry_metrics
{
	my $sel = $Globals::loxberry->{metrics};
	my %known = map { $_->{key} => 1 } @LOXBERRY_METRICS;

	my @out;
	if( ref($sel) eq 'ARRAY' and scalar @$sel ) {
		my %want = map { $_ => 1 } grep { $known{$_} } @$sel;
		@out = grep { $want{ $_->{key} } } @LOXBERRY_METRICS;
	}
	return @out if( scalar @out );
	return grep { $_->{default} } @LOXBERRY_METRICS;
}

# Every LoxBerry to ask, the one this runs on first.
#
# That first entry is not in the configuration and cannot be removed. It is
# addressed as localhost on the configured web server port, so it works before
# anybody has set a hostname and it does not depend on DNS.
#
# Returns a list of { address, url, tag, own }, and it is the ONE place that
# decides what a LoxBerry is called - the page, the check, the live table and the
# grabber all read "tag" from here rather than working the name out again.
sub loxberry_hosts
{
	my $port = LoxBerry::System::lbwebserverport() || 80;
	my @out = ( {
		address => 'localhost',
		url     => "http://localhost:$port/system/tools/linfo/index.php?out=json",
		# Fetched over localhost, but labelled with the name the machine has.
		# "host=localhost" in a Grafana legend says nothing, and it says even less
		# once the data of several LoxBerrys sits side by side.
		tag     => ( LoxBerry::System::lbhostname() || 'localhost' ),
		own     => 1,
	} );

	my $hosts = $Globals::loxberry->{hosts};
	return @out if( ref($hosts) ne 'ARRAY' );

	foreach my $h ( @$hosts ) {
		my $a = ref($h) eq 'HASH' ? $h->{address} : $h;
		next if( !defined $a or $a !~ /\S/ );
		$a =~ s/^\s+//; $a =~ s/\s+$//;
		# A bare name or IP means port 80. Anything with a port keeps it, so a
		# LoxBerry on a different port can be reached by writing it down.
		push @out, {
			address => $a,
			url     => "http://$a/system/tools/linfo/index.php?out=json",
			tag     => $a,
			own     => 0,
		};
	}
	return @out;
}

our $stats4lox = { 
	s4ltmp => 	'/dev/shm/s4ltmp',
	loxplanjsondir => $LoxBerry::System::lbpdatadir,
	import_time_to_dead_minutes => 60,
	import_max_parallel_processes => 4,
	import_max_parallel_per_ms => 4,
	importstatusdir => $LoxBerry::System::lbpdatadir.'/import',
	mqttlive_active => "True",
	# Diagnostic logging of InfluxDB, Telegraf and Grafana. Off by default -
	# on LoxBerry the log directory is a ramdisk, see config-handler.pl.
	servicelogging => "False"
};

# Backup of configuration, Grafana and the time series database. The storage
# path stays empty on purpose: an empty path means "not configured yet", and the
# web interface then offers the LoxBerry storage picker instead of silently
# filling a directory the user never chose.
our $backup = {
	storagepath => "",
	compression => "gzip",
	keep        => 3,
	schedule    => {
		active => "False",
		repeat => 1,
		time   => "03:00",
		# Reference week for "every n weeks", set when the schedule is saved
		since  => "",
		mon    => "False",
		tue    => "False",
		wed    => "False",
		thu    => "False",
		fre    => "False",
		sat    => "False",
		sun    => "False",
	},
};

our $telegraf = {
	unixsocket => "/tmp/telegraf.sock",
	telegraf_unix_socket => "/tmp/telegraf.sock",
	telegraf_max_buffer_fullness => "0.75",
	telegraf_buffer_checks => ["influxdb"],
	telegraf_internal_files => "/tmp/telegraf_internals*.out",
	internal_statfiles => "/tmp/telegraf_internals*.out",
};


### Run merge_config ###
Globals::merge_config();


##################################################
# Translate navbar labels using readlanguage
# Must be called from CGI context before lbheader()
##################################################

sub init_navbar_i18n
{
	my %L = LoxBerry::System::readlanguage(undef, "language.ini");
	$main::navbar{1}{Name} = $L{'NAVBAR.NAV_HOME'} if $L{'NAVBAR.NAV_HOME'};
	$main::navbar{10}{Name} = $L{'NAVBAR.NAV_LOXONE_IMPORT'} if $L{'NAVBAR.NAV_LOXONE_IMPORT'};
	$main::navbar{20}{Name} = $L{'NAVBAR.NAV_DATASOURCES'} if $L{'NAVBAR.NAV_DATASOURCES'};
	$main::navbar{25}{Name} = $L{'NAVBAR.NAV_INFLUX'} if $L{'NAVBAR.NAV_INFLUX'};
	$main::navbar{30}{Name} = $L{'NAVBAR.NAV_GRAFANA'} if $L{'NAVBAR.NAV_GRAFANA'};
	$main::navbar{40}{Name} = $L{'NAVBAR.NAV_SYSTEM'} if $L{'NAVBAR.NAV_SYSTEM'};
	$main::navbar{90}{Name} = $L{'NAVBAR.NAV_LOGS'} if $L{'NAVBAR.NAV_LOGS'};

	# Grafana runs on its own port, so the link needs the host name the browser
	# is currently talking to - not a name only the LoxBerry itself can resolve.
	# Filled in here and not in the definition above because merge_config(),
	# which supplies the configured port, only runs after it.
	my $port = ( $Globals::grafana && $Globals::grafana->{port} ) ? $Globals::grafana->{port} : 3000;
	my $host = $ENV{HTTP_HOST} // '';
	$host =~ s/:\d+$//;
	$host = LoxBerry::System::get_localip() if( $host eq '' );
	$main::navbar{30}{URL} = "http://$host:$port";
}



# IMPORT MAPPINGS

# How should data columns from a Loxone stat file map to outputs
# statpos --> index in the Loxone stat file (0-based index)
# lxlabel --> label of the output to map to

# Individual mappings by control type

our $ImportMapping = {};
$ImportMapping->{ENERGY} = [ 
	{ statpos => "0", lxlabel => "Default" },
	{ statpos => "0", lxlabel => "AQ" },
	{ statpos => "1", lxlabel => "AQp" } 
];

$ImportMapping->{FRONIUS} = [ 
	{ statpos => "0", lxlabel => "Default" },
	{ statpos => "0", lxlabel => "AQp" },
	{ statpos => "1", lxlabel => "AQc" },
	{ statpos => "2", lxlabel => "AQv" },
	{ statpos => "3", lxlabel => "AQPs" },
	{ statpos => "4", lxlabel => "AQSs" },
	{ statpos => "5", lxlabel => "AQp4" },
	{ statpos => "6", lxlabel => "AQc4" },
	{ statpos => "7", lxlabel => "AQd4" },
	{ statpos => "8", lxlabel => "AQi4" }
];	

# DEFAULT MAPPING
$ImportMapping->{Default} = [
	{ statpos => "0", lxlabel => "Default" },
	{ statpos => "0", lxlabel => "AQ"}
];


# STATISTICS GROUPS - column name to output
#
# The newer meter blocks store their statistics per group, and those files name
# their own columns in the Outputs attribute. Those names are the ones the
# statistics use - they are NOT the names the same block reports live over
# /jdev/sps/io/<uuid>/all. Measured on a live installation, same moment:
#
#   Batteriespeicher (MeterAbsSt)  total = 5438.817  <->  live Mrd = 5438.817
#                                  totalNeg = 5698.273    live Mrc = 5698.273
#                                  storageLevel = 100     live Slvl = 100
#
# Without translating, an import would fill a field "total" next to the field
# "Mrd" the grabber writes every cycle - the same meter reading under two names,
# and a graph that stops where the import ended.
#
# The table maps a column to the OUTPUT of the block, not to its abbreviation:
# the abbreviation is what Loxone renames from time to time (AQ -> Ct), the
# output name is not. The abbreviation is then looked up per block type in
# loxelements_en.json, which is why one entry covers all types - and why the
# same column translates differently where the type demands it:
#
#   MeterAbsSt   total -> OMr1 -> Mrd (discharge),  totalNeg -> OMr2 -> Mrc
#   MeterAbsBi   total -> OMr1 -> Mrc (consumption), totalNeg -> OMr2 -> Mrd
#
# outputs is tried in order; the first output the type actually has wins.
# fallback is used when the element catalogue knows the output but carries no
# abbreviation for it - which is the case for OPf on every meter type, while
# the Miniserver does report it live as "Pf".
#
# Columns not listed here keep the name the file gave them. That is deliberate
# for the two EFM columns: measured on a live EFM, the Miniserver does not
# report Sc or Yt live at all, so there is nothing they could collide with.

our %StatGroupMapping = (
	actual       => { outputs => [ 'OPf', 'outPower' ],                 fallback => 'Pf' },
	total        => { outputs => [ 'OMr1', 'OMr', 'outMeterReading' ] },
	totalNeg     => { outputs => [ 'OMr2' ] },
	storageLevel => { outputs => [ 'OSlvl' ] },
	OYt          => { outputs => [ 'OYT' ] },
	# The one entry not established by comparing values: the Spot Price
	# Optimizer of the test installation records but has not written a single
	# file yet, so there is nothing to compare against. Confirmed by the user,
	# and the catalogue agrees - Uc is "Current Price", reported live as Cv.
	current      => { outputs => [ 'Uc' ] },
);



# BLACKLIST of controls not to add to controls section in json
#
# VIRTUALTEXTIN ("Virtueller Texteingang") is on this list for a reason that
# goes beyond tidiness: a virtual text input is writable, and the Loxone API
# WRITES on every read attempt. /jdev/sps/io/<uuid>/all sets the value to the
# literal string "all", and the form without a suffix sets it to an empty
# string. Offering such a block for statistics meant the grabber silently
# overwrote the user's value on every interval (issue #143). There is no safe
# read via this interface, so the block must not be selectable at all - use
# the MQTT Collector for text values instead.
#
# The entry used to read VIRTUALINTEXT, and that never matched anything: the
# type is called VirtualTextIn in the LoxPLAN. Same letters, different order, so
# the protection above was ineffective from the day it was written - text inputs
# stayed selectable and the grabber kept writing "all" into them. Measured on a
# live Miniserver, a single read left LL.value at "all". Both spellings are
# listed now; the wrong one costs nothing and guards against Loxone renaming it
# back. A blacklist entry is only ever as good as its spelling, and nothing
# checks it - the whole list is compared against type names that come from
# Loxone.

# RADIO ("Radiotasten"), EIBPUSH ("EIB-Taster") and PUSHBUTTON ("Schalter") were
# on this list and have been taken off again. All three are writable and driven by
# commands, so the worry was that /jdev/sps/io/<uuid>/all would be taken as one -
# which for a text input is exactly what happens (issue #143).
#
# Measured on a live installation with Michael's explicit go-ahead for one block of
# each type: all three answer HTTP 200 with their numbered outputs and their
# values, which is the documented READ form - a command would be acknowledged with
# a bare value and no output list. Three calls in a row per block came back byte
# for byte identical, and on the PushButton the switch-on and switch-off pulses Qon
# and Qoff stayed 0 throughout. So "all" is read, not executed.
#
# The variants stay on the list. RADIO2, PUSHBUTTON2 and PUSHBUTTONSEL do not exist
# in that configuration and could not be tested at all; PUSHBUTTON2SEL does exist
# but was not part of what was authorised. Untested is untested.

# STATE ("Statusbaustein") was on this list and has been taken off again. It
# answers with the rendered text of its active state, and the state table from
# the LoxPLAN turns that back into a state number and the configured value of the
# Val output - see Stats4Lox::status_block_outputs(). Measured on 66 blocks of a
# live installation: 44 identifiable, 17 not because several of their states share
# the same text, 5 unreadable because the Miniserver sends invalid JSON when the
# text itself contains quotes.

# Unsure
# ACTOR="Aktor (Relais)"
# AUTOJALOUSIE="Automatikjalousie"
# BRIGHTNESS="Helligkeitsregler (BETA)"
# CALLERVIRTUALIN: now on the blacklist below. These are the virtual inputs of
#   a Caller service, not blocks anyone configures - Loxone names them _0, _1,
#   _2 and so on, they have no page, no room ("Nicht zugeordnet") and StatsType
#   0. Measured on a real installation: 30 of them from two Caller services, not
#   one with a statistic on it.
# CURRENTOUT="Stromausgang (20mA)"
# DAYLIGHTCTRL="Tageslicht Steuerung (BETA)"
# DIMCURRENTIN="Strommessung (A)"
# DIMMER="Dimmerausgang"
# DOORCONTROLLER="Türsteuerung"
# FRONIUS="Energiemonitor"
# HEATCENRAL="Zentralheizung (BETA)"
# HEATCONTROL="Heizungsregelung"
# HEATCURVE="Heizkurve"
# HEATMIXER="Heizungsmischer"
# HEATMIXER2="Intelligente Temperatursteuerung"
# HOUSE="Eingehendes Paket"
# HVACController="Klima Controller"
# INTERCOM="Gegensprechanlage"
# JOINWINSENSOR="Composite-Fensterkontakt"
# LIGHTCONTROLLER="Lichtsteuerung Gen 1"
# LIGHTCONTROLLER2="Lichtsteuerung"
# LIGHTCONTROLLERH="Hotel Lichtsteuerung"
# LOX1WIREAACTOR="Analogaktor"
# LOX1WIREACTOR="Aktor"
# LOX1WIREASENSOR="Analogsensor"
# LOX1WIRESENSOR="Sensor"
# LOX232ACTOR="Aktor"
# LOX232SENSOR="Sensor"
# LOX232TEXTACTOR="Textaktor"
# LOX485ACTOR="Aktor"
# LOX485SENSOR="Sensor"
# LOX485TEXTACTOR="Textaktor"
# LOXAIRAACTOR="Analogaktor"
# LOXAIRACTOR="Aktor"
# LOXAIRASENSOR="Analogsensor"
# LOXAIRSENSOR="Sensor"
# LOXAIRTEXTACTOR="Textaktor"
# LOXAIRTEXTSENSOR="Textsensor"
# LOXDALIAACTOR="Aktor"
# LOXDALIACTOR="Relais"
# LOXDALISENSOR="Sensor"
# LOXDMXACTOR="Aktor"
# LOXDMXSENSOR="Analogsensor"
# LOXINTERCOMAACTOR="Analogaktor"
# LOXINTERCOMACTOR="Aktor"
# LOXINTERCOMASENSOR="Analogsensor"
# LOXINTERCOMSENSOR="Sensor"
# LOXOCEANAACTOR="Analogaktor"
# LOXOCEANACTOR="Aktor"
# LOXOCEANASENSOR="Analogsensor"
# LOXOCEANSENSOR="Sensor"
# MODBUSAACTOR="Analogaktor"
# MODBUSACTOR="Digitalaktor"
# MODBUSASENSOR="Analogsensor"
# MODBUSSENSOR="Digitalsensor"
# NFC="NFC-Tag"
# ONLINE="Onlinestatus"
# PING="Ping"
# POOLCONTROLLER="Poolsteuerung"
# PRESENCE="Visualisierungs-Präsenz"
# PRESENCECONTROLLER="Präsenzmelder (BETA)"
# PUMPCONTROL="Pumpenregelung"
# ROOFWINDOWCONTROLLER="Dachfenster"
# ROOMCONTROL="Raumregelung"
# SAUNA="Saunasteuerung"
# SAUNAVAPOR="Saunasteuerung Verdampfer"
# SHADEROOF="Dachfenster Rollo"
# SMOKEALARM="Brand- und Wassermeldezentrale"
# SOLARCOOLER="Solarkühler"
# SOLARPUMPCONTROL="Solarregelung"
# SOLARSTARTER="Solarstarter"
# STATEV="Virtueller Status"
# SYSTEMP="Systemtemperatur"
# TIMEMINMAX="Min Max seit Reset"
# TREEAACTOR="Analogaktor"
# TREEACTOR="Aktor"
# TREEASENSOR="Analogsensor"
# TREESENSOR="Sensor"
# TREETEXTACTOR="Textaktor"
# UARTACTOR="Aktor"
# UARTSENSOR="Sensor"
# UARTTEXTACTOR="Textaktor"
# VENT="Internorm Lüfter"
# VENTILATION="Raumlüftungssteuerung"
# VIRTUALHTTPINCMD="Virtueller HTTP Eingang Befehl"
# VIRTUALIN="Virtueller Eingang"
# VIRTUALINTEXT="Virtueller Texteingang"
# VIRTUALOUT="Virtueller Ausgang"
# VIRTUALUDPINCMD="Virtueller UDP Eingang Befehl"
# VOLTAGEIN="Spannungseingang"
# VOLTAGEOUT="Spannungsausgang"
# WEED="Viking iMow"
# WIND="Windmesser"
# WINDOWSMONITOR="Fenster- und Türüberwachung"
# ZAMBELLI="Zambelli"

# CONTROLS that get their Miniserver assigned as a fallback
#
# Some device containers - MTablet (Touch/Tablet), AudioServer, ... - are
# children of the Document instead of the LoxLIVE node. Controls below them
# find no Miniserver when walking up the tree, get no msno, and are then
# silently dropped by the frontend (loxone.js: controls.filter
# msno > 0). Statistics enabled on such a block would disappear without a
# trace.
#
# Deliberately a positive list: a general fallback would also surface a few
# hundred structural objects (PuDe, RightGroup, Permission, ...) in the
# statistics selection.
#
# APIACTOR, GENSENSOR, GENASENSOR and AUDIOOUT were on this list and have been
# removed again: they are not function blocks. In the LoxPLAN they sit below a
# device, not below a program page - GENSENSOR and GENASENSOR belong to a
# Managed Tablet and are not sensors of their own, AUDIOOUT belongs to the
# Audio Server, APIACTOR to an intercom device. They are on the blacklist now.
our @CONTROL_MS_FALLBACK = qw/
ONLINE
/;

# The first block of entries below are not function blocks at all. They are
# other LoxPLAN objects that the parser picks up along the way, and their Title
# gives them away:
#
#   DateTime "Unix Timestamp", NightTime "Nacht", Week "Woche"  system variables
#   GlobalStates "Systemvariablen"                              their container
#   PuDe "Registriertes Gerät"                                  a paired device
#   RightGroup, Permission                                      user rights
#   MTablet "FlurEG"                                            a touch device
#   LanInt, LoxTree                                             interfaces
#   WeatherCaption "Netzwerkperipherie"                         a caption
#   SwitchingTimer "Immer"                                      a switching time
#   OvertempShutdown, AudioOut, ApiActor, GenSensor, GenAsensor belong to a
#                                            device, not to a program page
#
# On the test installation that alone was 264 entries in the selection list.
#
# Note on why this is a list and not a rule: it looks as if "everything that is
# not below a Page inside Program" would do it - that is exactly where the real
# function blocks live. Measured, that rule removes 1167 of 1527 entries,
# including VirtualIn (161), DigitalIn (56), VoltageIn (21) and Online (18),
# which sit below the peripherals and are perfectly legitimate. So the list it
# is.
our @CONTROL_BLACKLIST = qw/
APIACTOR
AUDIOOUT
CALLERVIRTUALIN
DATETIME
GENASENSOR
GENSENSOR
GLOBALSTATES
LANINT
LOXTREE
MTABLET
NIGHTTIME
OVERTEMPSHUTDOWN
PERMISSION
PUDE
RIGHTGROUP
SWITCHINGTIMER
WEATHERCAPTION
WEEK
2POINT
3POINT
AALSMARTALARM
ACCESS
ACTORCAPTION
ADD
ADD4
ALARMCHAIN
ALARMCLOCK
AMEMORY
AMINMAX
AMULTICLICK
ANALOGCOMPARATOR
ANALOGDIFFTRIGGER
ANALOGINPUTCAPTION
ANALOGMULTIPLEXER
ANALOGMULTIPLEXER2
ANALOGOUTPUTCAPTION
ANALOGSCALER
ANALOGSTEPPER
ANALOGWATCHDOG
AND
APP
APPLICATION
AUTOPILOT
AUTOPILOTRULE
AVERAGE
AVERAGE4
AVG
BINDECODER
CALENDAR
CALENDARCAPTION
CALENDARENTRY
CALLER
CATEGORY
CATEGORYCAPTION
CENTRAL
CMDRECOGNITION
CODE1
CODE16
CODE4
CODE8
COMM1WIRE
COMM232
COMM485
COMMDMX
COMMIR
CONNECTIONIN
CONNECTIONOUT
CONSTANT
CONSTANTCAPTION
COUNTER
DAY
DAY2009
DAYLIGHT
DAYLIGHT2
DAYOFWEEK
DAYTIMER
DEVICEMONITOR
DIV
DOCUMENT
DOCUMENTATION
DOUBLECLICK
EDGEDETECTION
EDGEWIPINGRELAY
EIBACTORCAPTION
EIBLINE
EIBSENSORCAPTION
EIBTEXTACTOR
EIBTEXTSENSOR
EQUAL
EVENINGTWILIGHT
FAN
FIDELIOSERVER
FLIPFLOP
FORMULA
GATECONTROLLER
GATEWAY
GATEWAYCLIENT
GEIGERJALOUSIE
GLOBAL
GREATER
GREATEREQUAL
HOUR
ICONCAPTIONCAT
ICONCAPTIONPLACE
ICONCAPTIONSTATE
ICONCAT
ICONPLACE
ICONSTATE
IMPULSEDAY
IMPULSEEVENINGTWILIGHT
IMPULSEHOUR
IMPULSEMINUTE
IMPULSEMONTH
IMPULSEMORNINGTWILIGHT
IMPULSESECOND
IMPULSESUNRISE
IMPULSESUNSET
IMPULSEYEAR
INPUTCAPTION
INPUTREF
INT
IRCONTROLLER
JALOUSIEUPDOWN2
KEYCODE
KRETA
LEAF
LESS
LESSEQUAL
LIGHTGROUP
LIGHTGROUPACTOR
LIGHTSCENE
LIGHTSCENELEARN
LIGHTSCENERGB
LOGGER
LOGGEROUTCAPTION
LONGCLICK
LOX1WIREDEVICE
LOXAINEXT
LOXAIR
LOXAIRDEVICE
LOXCAPTION
LOXDALI
LOXDALIDEVICE
LOXDALIGROUPACTOR
LOXDEVICECAPTION
LOXDEVICECAPTION2
LOXDIGINEXT
LOXDIMM
LOXDMXDEVICE
LOXINTERNORM
LOXINTERNORMDEVICE
LOXIRACTOR
LOXIRRCVDEVICE
LOXIRSENSOR
LOXIRSNDDEVICE
LOXKNXEXT
LOXLIVE
LOXMORE
LOXOCEAN
LOXOCEANDEVICE
LOXOUTEXT
LOXREL
MAILER
MEDIA
MEDIACLIENT
MEDIASERVER
MEMORYCAPTION
MESSAGECENTER
MINISERVERCOMM
MINMAX
MINUTE
MOD
MODBUSDEV
MODBUSSERVER
MODE
MODECAPTION
MONOFLOP
MONTH
MORNINGTWILIGHT
MOTORCONTROL
MULT
MULTICLICK
MULTIFUNCSW
MULTIMEDIASERVER
MUSICZONE
NETWORKDEVICE
NOT
NOTEQUAL
NOTIFICATION
OFFDELAY
ONDELAY
ONOFFDELAY
ONPULSEDELAY
OR
OUTPUTCAPTION
OUTPUTREF
OUTPUTREFLM
OVERTEMP
PAGE
PI
PID
PLACE
PLACECAPTION
PLACEGROUP
PLACEGROUPCAPTION
POWER
PROGRAM
PULSEAT
PULSEBY
PULSEGEN
PUSHBUTTON2
PUSHBUTTON2SEL
PUSHBUTTONSEL
PUSHDIMMER
PWM
RADIO2
RAMP
RAND
RANDOMGEN
RC
RCKEY
REFUSER
REMOTECONTROLS
RETONDELAY
RSFLIPFLOP
SAFECURRENTOUT
SECOND
SECONDSBOOT
SENSORCAPTION
SEQUENCER
SHIFT
SONNENBATTERYDEVICE
SRFLIPFLOP
STAIRWAYLS
STARTPULSE
STEAKTHERMO
SUB
SUNALTITUDE
SUNAZIMUTH
SUNRISE
SUNSET
SWITCH
SWITCH2BUTTON
SYSVAR
TASKCAPTION
TASKSCHEDULER
TEXT
TEXTACTOR
TIME
TIMECAPTION
TOILET
TRACKER
TREE
TREEDEVICE
TREETURBODEVICE
UPDOWNCOUNTER
USER
USERCAPTION
USERGROUP
USERGROUPCAPTION
VALVEDEVICE
VIRTUALHTTPIN
VIRTUALINCAPTION
VIRTUALINTEXT
VIRTUALTEXTIN
VIRTUALOUTCAPTION
VIRTUALUDPIN
WALLMOUNTDEVICE
WEATHERDATA
WEATHERSERVER
WEBPAGE
WIPINGRELAY
XOR
YEAR
/;

##################################################
# Merge default config with stats4lox.json config
##################################################

sub merge_config 
{
	my %args = @_;
	if( ! $args{config_force_parse} ) {
		return if( $config_is_parsed );
	}

	require Hash::Merge;
	
	my $configobj = LoxBerry::JSON->new();
	my $config = $configobj->open(filename => $Globals::stats4loxconfig, readonly => 1);
	
	my $merge = Hash::Merge->new('LEFT_PRECEDENT');
	
	# print STDERR "Port (Globals) : " . $Globals::grafana->{port} . "\n";
	# print STDERR "Port (S4L.json): " . $config->{grafana}->{port} . "\n";
	
	$Globals::grafana = 	$merge->merge( $config->{grafana}, $Globals::grafana );
	$Globals::influx = 		$merge->merge( $config->{influx}, $Globals::influx );
	$Globals::loxberry = 	$merge->merge( $config->{loxberry}, $Globals::loxberry );
	$Globals::loxone = 		$merge->merge( $config->{loxone}, $Globals::loxone );
	$Globals::miniserver = 	$merge->merge( $config->{miniserver}, $Globals::miniserver );
	$Globals::stats4lox = 	$merge->merge( $config->{stats4lox}, $Globals::stats4lox );
	$Globals::telegraf = 	$merge->merge( $config->{telegraf}, $Globals::telegraf );
	$Globals::backup = 		$merge->merge( $config->{backup}, $Globals::backup );

	# Not through Hash::Merge, and that is not a preference.
	#
	# LEFT_PRECEDENT merges two ARRAYs by CONCATENATING them. The five configured
	# stages plus the five defaults would come out as ten, and everything below
	# counts stages. merge_retention() replaces the list instead.
	$Globals::retention = merge_retention( $config->{retention} );

	$config_is_parsed = 1;
}

##################################################
# Retention section of stats4lox.json over the defaults
##################################################
# Scalars from the configuration win. The stage list is taken as a whole or not
# at all: a list of a different length is a broken or half-written configuration,
# and silently running with four stages instead of five would apply a retention
# nobody asked for. The aggregates are never taken from the configuration - they
# are fixed by design, see the comment at $retention above.

sub merge_retention
{
	my ($cfg) = @_;
	my $def = $Globals::retention;
	return $def if( ref($cfg) ne 'HASH' );

	my %out = %$def;
	foreach my $k ( keys %$cfg ) {
		next if( $k eq 'stages' or $k eq 'aggregates' );
		$out{$k} = $cfg->{$k} if( defined $cfg->{$k} );
	}

	# Always exactly as many stages as the defaults have, whatever the file says.
	#
	# This used to insist on the same count and fall back to the defaults
	# otherwise. That was fine while the number never changed; when it went from
	# five to three it would have thrown away every stored setting in silence.
	# Now a longer list is cut to length and a shorter one filled from the
	# defaults - and the defaults are switched off, so filling can only ever add
	# inactive stages.
	#
	# Cutting a longer list does change what a configuration means: the LAST
	# active stage carries the total retention, so dropping stages moves that
	# role. It is visible - the preview shows the new arrangement and names any
	# stage whose data would go - which is better than silently reverting
	# everything to off.
	if( ref($cfg->{stages}) eq 'ARRAY' ) {
		my @stages;
		for( my $i = 0; $i < scalar @{$def->{stages}}; $i++ ) {
			my %s = %{ $def->{stages}->[$i] };
			my $c = $cfg->{stages}->[$i];
			if( ref($c) eq 'HASH' ) {
				foreach my $k ( keys %s ) {
					$s{$k} = $c->{$k} if( defined $c->{$k} );
				}
			}
			push @stages, \%s;
		}
		$out{stages} = \@stages;
	}

	# Stage 1 is the raw data in autogen and exists whatever the file says
	$out{stages}->[0]->{active}   = "True";
	$out{stages}->[0]->{interval} = "raw";

	$out{aggregates} = $def->{aggregates};
	return \%out;
}



# Returns the name of the current sub (for logfile)
# e.g. my $me = whoami();
# print "$me Starting import"; returns "Loxone::Import::new--> Starting import"
sub whoami { 
	return ( caller(1))[3] . '-->';
}


#####################################################
# Finally 1; ########################################
#####################################################
1;
