#!/usr/bin/perl

use LoxBerry::System;
use LoxBerry::JSON;
use LoxBerry::IO;
use LoxBerry::Log;
use FindBin qw($Bin);
use lib "$Bin/../../../../../bin/plugins/REPLACELBPPLUGINDIR/libs";
use Globals;
use Stats4Lox;
use strict;
use warnings;
#use Data::Dumper;

my $starttime = time;

my $log = LoxBerry::Log->new ( 
	name => 'grabber_loxone',
	filename => "$lbplogdir/grabber_loxone.log",
	append => 1,
	# stderr => 1,
	addtime => 1,
	# nosession => 1
);

LOGSTART "Grabber Loxone";
# Plugin config
my $pcfgfile = $lbpconfigdir . "/stats4lox.json";
my $pjsonobj = LoxBerry::JSON->new();
my $pcfg = $pjsonobj->open(filename => $pcfgfile, readonly => 1);

# Header
print "Content-type: text/ascii; charset=UTF-8\n\n";

# Skip if not enabled
if ( ! is_enabled($pcfg->{loxone}->{active}) ) {
	LOGINF "Loxone Grabber is disabled. Existing.";
	exit 0;
}

# Stats Configuration
#
# locktimeout matters here. 'readonly' only changes the open mode, the file is
# locked shared either way - and without a timeout that lock is taken blocking,
# while Telegraf drops this cycle after 45 seconds. Measured with a lock held for
# 20 seconds, the cycle grew from 13.7 to 33.7 seconds.
#
# This used to name update_dashboards.pl as the writer to fear, which was wrong:
# nothing starts that script - no service, no cron, no caller - and its lock file
# has never even been created. The writers that do exist are the handlers of the
# web interface, and the longest of them was measured at 0.06 s.
#
# The timeout stays anyway. It costs nothing, and the alternative is a grabber
# cycle that can be stretched without limit by whoever holds the file. With it the
# module asks non-blocking and gives up, returning undef; two seconds cover the
# brief writes of the web interface, and the copy below is just as good. The retry
# inside the module is a busy loop, which is another reason not to wait long.
my $jsonobjcfg = LoxBerry::JSON->new();
my $cfgfile = $lbpconfigdir . "/stats.json";
my $cachefile = "/dev/shm/stats4lox_cfgcache_loxonegrabber.json";
my $cfg = $jsonobjcfg->open(filename => $cfgfile, readonly => 1, locktimeout => 2);

if( $cfg and ref($cfg->{loxone}) eq 'ARRAY' ) {
	# Keep a copy for the case below. The configuration changes rarely and this
	# is a ramdisk, so it costs nothing worth counting.
	eval {
		require File::Copy;
		File::Copy::copy( $cfgfile, "$cachefile.new" ) and rename( "$cachefile.new", $cachefile );
	};
}
else {
	# Someone is writing. Rather than lose a whole cycle of measurements, this
	# one runs on the last copy - the configuration is a minute old at worst,
	# and nothing in it changes what the Miniserver answers.
	LOGWARN "stats.json could not be read (locked by another process) - using the last copy";
	$jsonobjcfg = LoxBerry::JSON->new();
	$cfg = $jsonobjcfg->open( filename => $cachefile, readonly => 1, locktimeout => 2 );
	if( !$cfg or ref($cfg->{loxone}) ne 'ARRAY' ) {
		LOGERR "No usable configuration - this cycle is skipped";
		LOGEND;
		exit 0;
	}
}

# Next runs
my $jsonobjmem = LoxBerry::JSON->new();
my $memfile = "/dev/shm/stats4lox_mem_loxonegrabber.json";
my $mem = $jsonobjcfg->open(filename => $memfile, writeonclose => 1);

# How long this run may take.
#
# It used to parse stats4lox_loxone.conf, take Telegraf's HTTP timeout out of it
# and subtract two seconds. That worked, but it made a TOML parser part of every
# grabber run to read back a number the plugin had written itself - and the two
# ends could only agree by accident.
#
# Both come from the setting on the System tab now: Telegraf's timeout is the
# minimum interval less three seconds, this budget less five. While the setting
# is unset it is 43 seconds, exactly as before.
my ( undef, $max_runtime ) = Globals::loxone_timeouts();

# Temporary assign 'nextrun' time to measures
for my $results( @{$cfg->{loxone}} ){
	my $tag = $results->{measurementname};
	$results->{nextrun} = defined $mem->{$tag}->{nextrun} ? $mem->{$tag}->{nextrun} : 0;
}

# Sorting measures by nextrun time
@{$cfg->{loxone}} = sort { $a->{nextrun} <=> $b->{nextrun} } @{$cfg->{loxone}};

# Loop through stats
$max_runtime = 3 if( $max_runtime < 3 );
LOGOK "Starting data fetching (maximum runtime $max_runtime secs)";
my @data;
my $processed = 0;   # how many entries the loop has reached - needed to report
                     # which statistics were left out if we run out of time
my %msfailed;        # Miniservers that failed in this cycle, see below

# Status of a statistic, recorded in stats.json.
#
# Collected here and written once at the end of the cycle, not per block. The
# configuration directory is on the SD card on most installations, so a write
# per failing block would mean 21 writes a minute on a system with 21 deleted
# blocks. One write per cycle, and only when something actually changed.
my %statuschange;    # "msno|uuid" => hashref or undef (undef = clear it)

# The status stays on the entry only while there is something wrong. No error
# type and no timestamp means the statistic is fine, and that is also how an
# entry that never failed looks - nothing is written for it at all.
sub note_error
{
	my ($entry, $type) = @_;
	my $old = $entry->{status};
	my $count = ( $old and $old->{error} and $old->{error} eq $type ) ? ( $old->{count} // 0 ) : 0;
	$count++;

	# Keep the moment it started failing - the web interface shows "not
	# reachable since ..." from it. A different error type starts over.
	my $since = ( $old and $old->{error} and $old->{error} eq $type and $old->{since} )
	          ? $old->{since} : time();

	my $new = { error => $type, since => $since, count => $count };
	$statuschange{ $entry->{msno} . "|" . $entry->{uuid} } = $new;
	$entry->{status} = $new;   # so the same cycle already sees the new count
	return $new;
}

sub clear_error
{
	my ($entry) = @_;
	return if( !$entry->{status} or !$entry->{status}->{error} );
	$statuschange{ $entry->{msno} . "|" . $entry->{uuid} } = undef;
	delete $entry->{status};
	return;
}

# Ten failures are enough to stop asking. Nothing is written from then on
# either, so a permanently deleted block costs exactly ten writes and then
# nothing at all - neither requests nor log lines nor SD card writes.
use constant MAX_ERRORS => 10;

sub give_up
{
	my ($entry) = @_;
	return ( $entry->{status} and $entry->{status}->{count}
	         and $entry->{status}->{count} >= MAX_ERRORS ) ? 1 : 0;
}
for my $results( @{$cfg->{loxone}} ){
	$processed++;
	if (! $results->{uuid} || ! $results->{msno} || ! $results->{measurementname} ) {
		LOGWARN "$results->{name}: Configuration data aren't complete. Skipping...";
		next;
	}
	
	LOGINF "$results->{name} -> Interval $results->{interval} UUID $results->{uuid}";
	
	if ( ! is_enabled($results->{active}) ) {
		LOGINF "$results->{name} -> Statistic not activated - skipping";
		next;
	}

	# Given up on after MAX_ERRORS failures. Skipped without a request and
	# without a log line of its own - the summary at the end names them.
	if( give_up($results) ) {
		next;
	}

	my $tag = $results->{measurementname};
	my $now = time();
	# Checking if interval is reached
	if ($mem->{$tag}) {
		if ( defined $mem->{$tag}->{nextrun} and $now < $mem->{$tag}->{nextrun} ) {
			LOGINF "$results->{name} -> Interval not reached - skipping this time";
			next;
		}
	}
	# One unreachable Miniserver must not consume the whole cycle.
	#
	# mshttp_call2 waits 5 seconds per request by default, so with a runtime
	# budget of $max_runtime seconds only about a handful of requests fit before
	# the loop gives up. If the unreachable Miniserver holds more statistics
	# than that, the budget was spent entirely on timeouts and NOTHING was
	# recorded - not even from the Miniservers that were perfectly reachable.
	# That is issue #126 and the forum report by smooty1970 (#312).
	#
	# Once a Miniserver has failed in this cycle, its remaining statistics are
	# skipped without a request. Its cost drops from the whole budget to a
	# single timeout.
	if( $msfailed{ $results->{msno} } ) {
		LOGINF "$results->{name} -> Miniserver $results->{msno} already failed in this cycle - skipping without a request";
		my $retry = ( $results->{interval} && $results->{interval} < 60 ) ? $results->{interval} : 60;
		$mem->{$tag}->{nextrun} = $now + $retry;
		next;
	}

	# Grab data
	my ($code, $resp) = Stats4Lox::msget_value($results->{msno}, $results->{uuid});
	if ( !$resp || $code ne "200" ) {

		if( defined $code and $code eq "404" ) {
			# The block does not exist on the Miniserver any anymore - typically a
			# statistic that was deleted in Loxone Config but is still in
			# stats.json. Retrying that every minute would only fill the log,
			# so it waits for its regular slot.
			$mem->{$tag}->{nextrun} = $now + $results->{interval};
			my $st = note_error( $results, '404' );
			LOGERR "$results->{name} -> gone from the Miniserver ($st->{count}. time)"
			       . ( $st->{count} >= MAX_ERRORS
			           ? " - not asked for again. Remove it under 'Loxone and Import' or restore the block in Loxone Config."
			           : "" );
		}
		else {
			# A connection problem or a timeout. Retry soon - nextrun used to be
			# advanced BEFORE the request, so a single failed grab cost a whole
			# interval of data. And do not touch this Miniserver again in this
			# cycle, see the note above.
			LOGERR "$results->{name} -> Could not grab data from Miniserver $results->{msno}: HTTP $code";
			$msfailed{ $results->{msno} } = 1;
			my $retry = ( $results->{interval} && $results->{interval} < 60 ) ? $results->{interval} : 60;
			$mem->{$tag}->{nextrun} = $now + $retry;
		}
		next;
	}

	# Only a successful grab moves this block on to its next regular slot
	$mem->{$tag}->{nextrun} = $now + $results->{interval};

	# It works again - the status goes away. This is the only place a status can
	# clear itself for a timeout; a 404 additionally clears when the block turns
	# up in the LoxPLAN again (see Loxone/ParseXML.pm), because a block given up
	# on is never asked again and could not heal here.
	clear_error( $results );

	# Collect data and create Influx lineformat
	my $measurement = $results->{measurementname};
	my %tags = ();
	$tags{"source"} = "grabber";
	$tags{"name"} =	$results->{name} if ($results->{name});
	$tags{"description"} = $results->{description} if ($results->{description});
	$tags{"uuid"} = $results->{uuid} if ($results->{uuid});
	$tags{"type"} = $results->{type} if ($results->{type}) ;
	$tags{"category"} = $results->{category} if($results->{category});
	$tags{"room"} = $results->{room} if ($results->{room});
	$tags{"msno"} = $results->{msno} if ($results->{msno});

	my @outputs;
	if( ref($results->{outputs}) eq "ARRAY" ) {
		@outputs = @{$results->{outputs}};
	}
	if( scalar(@outputs) == 0) {
		# use all outputs
		@outputs = ();
		LOGWARN "$results->{name} -> Using ALL outputs - config is empty";
		foreach (@$resp) {
			if ($_->{"Key"}) {
				push @outputs, $_->{"Key"};
			}
		}
	}
	else {
		# LOGINF "  Using defined outputs " . join(",", @outputs);
	}
	
	my %fields = ();
	foreach ( @outputs ) {
		my $key = $_;
		foreach (@$resp) {
			if ($_->{"Key"} eq $key) {
				my $valname = $_->{"Name"};
				my $val = $_->{"Value"};
				$fields{"$valname"} = $val;
				LOGDEB "$results->{name} -> $valname: $val";
			}
		}
	}

	# undef means no field had a usable value - see influx_lineprot. Pushing it
	# would put an empty entry into the batch.
	my $lineprot = Stats4Lox::influx_lineprot(undef, $measurement, \%tags, \%fields);
	if( defined $lineprot ) {
		push @data, $lineprot;
	}
	else {
		LOGWARN "$results->{name} -> no usable value in this cycle - nothing written";
	}

	if( time() > ($starttime+$max_runtime) ) {

		# Name the consequence, do not just state the fact. Without numbers
		# nobody could tell from the log that statistics were silently left out
		# of this cycle - which is what the reports about gaps in the data
		# looked like.
		my $total = scalar @{$cfg->{loxone}};
		my @remaining = ($processed < $total) ? @{$cfg->{loxone}}[$processed .. $total-1] : ();

		# Of those, the ones whose interval had already elapsed are the ones
		# actually losing a measurement now. The others were not due anyway.
		my $tnow = time();
		# Entries that have been given up on are not due for anything - they
		# would not have been fetched in this cycle either. Counting them here
		# would also overwrite their 404 with a 'limit' and restart the counter.
		my @due = grep {
			     is_enabled($_->{active})
			 and $_->{uuid} and $_->{msno} and $_->{measurementname}
			 and !give_up($_)
			 and ( !defined $mem->{ $_->{measurementname} }->{nextrun}
			       or $tnow >= $mem->{ $_->{measurementname} }->{nextrun} )
		} @remaining;

		# Those that lose a measurement now get it recorded. They are the ones
		# the runtime budget hit, and without this the web interface could not
		# tell them apart from a statistic that is simply fine.
		note_error( $_, 'limit' ) foreach ( @due );

		if( @due ) {
			# Deliberately LOGERR, not LOGWARN.
			#
			# Losing measurements is not a warning, it is the data loss users
			# reported as gaps in their statistics. And it has to be visible at
			# the default loglevel: LoxBerry suppresses WARNING from level 3
			# (ERROR) downwards, so a LOGWARN here would never be seen by the
			# very people affected.
			my @names = map { $_->{name} // $_->{measurementname} // '?' } @due;
			my $shown = scalar(@names) > 8 ? 8 : scalar(@names);
			LOGERR "Ran out of time after $max_runtime s - " . scalar(@remaining) . " of $total statistics were not processed in this cycle";
			LOGERR scalar(@due) . " of them were already due and LOSE a measurement now: "
			       . join(", ", @names[0 .. $shown-1])
			       . (scalar(@names) > $shown ? ", ... (" . (scalar(@names)-$shown) . " more)" : "");
			LOGERR "They keep their old nextrun and are fetched first in the next cycle, so the";
			LOGERR "effective interval of these statistics is longer than configured.";
			LOGERR "Remedy: raise 'timeout' in telegraf/telegraf.d/stats4lox_loxone.conf (this limit";
			LOGERR "is timeout minus 2 s), or increase the intervals of some statistics.";
		}
		else {
			LOGWARN "Ran out of time after $max_runtime s - " . scalar(@remaining) . " of $total statistics were not processed,";
			LOGWARN "but none of them was due yet, so no measurement is lost in this cycle.";
		}

		last;
	}

	# Deliberately NO sleep here.
	#
	# There used to be a sleep(0.2) meant to "slow down". It never had any
	# effect, because Time::HiRes is not imported in this scope and the core
	# sleep() truncates 0.2 to 0 seconds. That turned out to be a blessing:
	# measured on a system with 121 active statistics a full cycle takes 16.4 s
	# of the 43 s budget (Telegraf timeout 45 s minus 2). A real 0.2 s pause per
	# block would have added 24.2 s and pushed the cycle to the very edge, which
	# would have dropped exactly those blocks at the end of the list.
	#
	# So do not "repair" this into a working sleep - it would cause the data
	# gaps it looks like it prevents.
}

#print STDERR Dumper @data;

# Write the collected status back, once per cycle and only if something
# changed.
#
# Deliberately a fresh handle on the file instead of writing back the copy this
# script has been working on: that copy carries a 'nextrun' on every entry,
# added further up for sorting, and it is a runtime value that has no business
# in the configuration. The fresh copy also picks up anything the web interface
# has changed in the meantime.
#
# locktimeout again: if the file is busy the write is simply skipped. Recording
# a status is not worth stalling the cycle for - it is retried next time, and
# the counter picks up where it left off because it is derived from what is in
# the file.
if( %statuschange ) {
	my $wobj = LoxBerry::JSON->new();
	my $wcfg = $wobj->open( filename => $cfgfile, lockexclusive => 1, locktimeout => 3 );
	if( !$wcfg or ref($wcfg->{loxone}) ne 'ARRAY' ) {
		LOGWARN "stats.json is busy - the status is recorded in the next cycle";
	}
	else {
		my $applied = 0;
		foreach my $e ( @{$wcfg->{loxone}} ) {
			next if( !$e->{uuid} or !defined $e->{msno} );
			my $key = $e->{msno} . "|" . $e->{uuid};
			next if( !exists $statuschange{$key} );
			if( defined $statuschange{$key} ) { $e->{status} = $statuschange{$key} }
			else                              { delete $e->{status} }
			$applied++;
		}
		$wobj->write();
		LOGINF "Status of $applied statistics recorded in stats.json";
	}
}

# The ones that are no longer being asked for. One line for all of them instead
# of one error per block per cycle - which is what made this log unreadable:
# measured on a system with 21 deleted blocks, 206 error lines an hour, and
# every single error line in the log was one of those.
my @givenup = grep { is_enabled($_->{active}) and give_up($_) } @{$cfg->{loxone}};

# Only when the set changes. The grabber is a fresh process every cycle and
# cannot remember by itself, so the marker goes into the memory file it keeps in
# /dev/shm anyway. Without this the line would appear once a minute for as long
# as the entry exists, which is the noise this whole change is meant to end.
my $givenup_key = join( ",", sort map { $_->{msno} . "|" . $_->{uuid} } @givenup );
if( ( $mem->{_givenup} // '' ) ne $givenup_key ) {
	$mem->{_givenup} = $givenup_key;
	if( @givenup ) {
		my @names = map { $_->{name} // $_->{measurementname} // '?' } @givenup;
		my $shown = scalar(@names) > 5 ? 5 : scalar(@names);
		# LOGERR, not LOGWARN: LoxBerry suppresses WARNING from loglevel 3
		# downwards, and 3 is what most installations run on. A statistic that
		# is no longer being fetched has to reach the person it affects.
		LOGERR scalar(@givenup) . " statistics are not being fetched any more after "
		       . MAX_ERRORS . " failures: "
		       . join( ", ", @names[0 .. $shown-1] )
		       . ( scalar(@names) > $shown ? ", ... (" . (scalar(@names)-$shown) . " more)" : "" );
		LOGERR "They are shown with their status under 'Loxone and Import' and can be removed or reset there.";
	}
	else {
		LOGOK "No statistics are being skipped any more";
	}
}

# Output
LOGOK "Returning lineprot dataset (" . scalar @data . " measures)";
foreach (@data) {
	print $_ . "\n";
	LOGDEB $_;
}

exit(0);






# Script desctructor
END {
	LOGEND if($log);
}
