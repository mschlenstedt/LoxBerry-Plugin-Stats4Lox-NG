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
	filename => "$lbplogdir/grabber_logone.log",
	append => 1,
	# stderr => 1,
	addtime => 1,
	nosession => 1
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
for my $results( @{$cfg->{loxone}} ){
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
	# Save epoche for next run/poll
	$mem->{$tag}->{nextrun} = $now + $results->{interval};
	
	# Grab data
	my ($code, $resp) = Stats4Lox::msget_value($results->{msno}, $results->{uuid});
	if ( !$resp || $code ne "200" ) {
		LOGERR "$results->{name} -> Could not grab data from Miniserver $results->{msno}: HTTP $code";
		next;
	}
	
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
		LOGWARN "Early abandon fetching after reaching max_runtime";
		last;
	}

	# Slow down
	sleep (0.2);
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
