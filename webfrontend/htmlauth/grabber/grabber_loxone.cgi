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

my $log = LoxBerry::Log->new ( 
	name => 'grabber_loxone',
	filename => "$lbplogdir/grabber_logone.log",
	append => 1,
	stderr => 1,
	addtime => 1,
	nosession => 1
);

LOGSTART "Grabber Loxone";

# Plugin config
my $pcfgfile = $lbpconfigdir . "/stats4lox.json";
my $pjsonobj = LoxBerry::JSON->new();
my $pcfg = $pjsonobj->open(filename => $pcfgfile, readonly => 1);

# # Measurement name for Influx
# my $measurement = $pcfg->{loxone}->{measurement};

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

# Loop through stats
my @data;
for my $results( @{$cfg->{loxone}} ){
	if (! $results->{uuid} || ! $results->{msno} || ! $results->{measurementname} ) {
		LOGWARN "$results->{name}: Configuration data aren't complete. Skipping...";
		next;
	}
	
	LOGINF "$results->{name} -> UUID ($results->{uuid})";
	
	if ( ! is_enabled($results->{active}) ) {
		LOGINF "$results->{name} -> Statistic not activated - skipping";
		next;
	}
	
	my $tag = $results->{measurementname};
	my $now = time();
	# Checking if interval is reached
	if ($mem->{$tag}) {
		if ( $now < $mem->{$tag}->{nextrun} ) {
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

# Script desctructor
END {
	LOGEND if($log);
}
