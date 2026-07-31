#!/usr/bin/perl

use LoxBerry::System;
use LoxBerry::JSON;
use LoxBerry::IO;
use LoxBerry::Log;
use FindBin qw($Bin);
use lib "$Bin/../../../../../bin/plugins/stats4lox/libs";
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
my $jsonobjcfg = LoxBerry::JSON->new();
my $cfgfile = $lbpconfigdir . "/stats.json";
my $cfg = $jsonobjcfg->open(filename => $cfgfile, readonly => 1);

# Next runs
my $jsonobjmem = LoxBerry::JSON->new();
my $memfile = "/dev/shm/stats4lox_mem_loxonegrabber.json";
my $mem = $jsonobjcfg->open(filename => $memfile, writeonclose => 1);

# Telegraf HTTP timeout 
my $telegraf_http_timeout;
eval {
	use TOML::Parser;
	my $tomlparser = TOML::Parser->new;
	my $toml = $tomlparser->parse( LoxBerry::System::read_file("$lbpconfigdir/telegraf/telegraf.d/stats4lox_loxone.conf") );
	$telegraf_http_timeout = trim($toml->{inputs}->{http}[0]->{timeout});
	$telegraf_http_timeout = convert_duration_interval( $telegraf_http_timeout );
	# LOGDEB "telegraf_http_timeout: $telegraf_http_timeout";
};
if( $@ ) {
	LOGWARN "Could not parse telegraf/telegraf.d/stats4lox_loxone.conf: $@";
	LOGWARN "Using default timeout: 5s";
	$telegraf_http_timeout = 5;
}

# Temporary assign 'nextrun' time to measures
for my $results( @{$cfg->{loxone}} ){
	my $tag = $results->{measurementname};
	$results->{nextrun} = defined $mem->{$tag}->{nextrun} ? $mem->{$tag}->{nextrun} : 0;
}

# Sorting measures by nextrun time
@{$cfg->{loxone}} = sort { $a->{nextrun} <=> $b->{nextrun} } @{$cfg->{loxone}};

# Loop through stats
my $max_runtime = $telegraf_http_timeout-2;
$max_runtime = $max_runtime < 3 ? 3 : $max_runtime;
LOGOK "Starting data fetching (maximum runtime $max_runtime secs)";
my @data;
my $processed = 0;   # how many entries the loop has reached - needed to report
                     # which statistics were left out if we run out of time
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
	
	my $tag = $results->{measurementname};
	my $now = time();
	# Checking if interval is reached
	if ($mem->{$tag}) {
		if ( defined $mem->{$tag}->{nextrun} and $now < $mem->{$tag}->{nextrun} ) {
			LOGINF "$results->{name} -> Interval not reached - skipping this time";
			next;
		}
	}
	# Grab data
	my ($code, $resp) = Stats4Lox::msget_value($results->{msno}, $results->{uuid});
	if ( !$resp || $code ne "200" ) {
		LOGERR "$results->{name} -> Could not grab data from Miniserver $results->{msno}: HTTP $code";
		# Retry soon instead of waiting a full interval.
		#
		# nextrun used to be advanced BEFORE the request, so a single failed
		# grab - a brief network hiccup is enough - cost a whole interval of
		# data. With intervals of several minutes that is exactly the kind of
		# gap users kept reporting. A short backoff retries quickly without
		# hammering a Miniserver that is genuinely unreachable.
		my $retry = ( $results->{interval} && $results->{interval} < 60 ) ? $results->{interval} : 60;
		$mem->{$tag}->{nextrun} = $now + $retry;
		next;
	}

	# Only a successful grab moves this block on to its next regular slot
	$mem->{$tag}->{nextrun} = $now + $results->{interval};
	
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

	my $lineprot = Stats4Lox::influx_lineprot(undef, $measurement, \%tags, \%fields);	
	push @data, $lineprot;

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
		my @due = grep {
			     is_enabled($_->{active})
			 and $_->{uuid} and $_->{msno} and $_->{measurementname}
			 and ( !defined $mem->{ $_->{measurementname} }->{nextrun}
			       or $tnow >= $mem->{ $_->{measurementname} }->{nextrun} )
		} @remaining;

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

# Output
LOGOK "Returning lineprot dataset (" . scalar @data . " measures)";
foreach (@data) {
	print $_ . "\n";
	LOGDEB $_;
}

exit(0);


# This converts Influx intervals ("20ms", "3s",...) to seconds
# Influx intervals:
# https://github.com/influxdata/telegraf/blob/master/docs/CONFIGURATION.md#intervals

sub convert_duration_interval
{
	my $timestr = shift;
	$timestr =~ /(\d+)(\w+)/;
	my $timeval = $1;
	my $interval = $2;
	
	
	if( $interval eq "ns") { $timeval /= 1000000000; }
	elsif( $interval eq "us" or $interval eq "µs") { $timeval /= 1000000; }
	elsif( $interval eq "ms") { $timeval /= 1000; }
	elsif( $interval eq "s") {  }
	elsif( $interval eq "m") { $timeval *= 60; }
	elsif( $interval eq "h") { $timeval *= 60*60; }
	elsif( $interval ne "") { undef $timeval; }
	
	return $timeval;

}




# Script desctructor
END {
	LOGEND if($log);
}
