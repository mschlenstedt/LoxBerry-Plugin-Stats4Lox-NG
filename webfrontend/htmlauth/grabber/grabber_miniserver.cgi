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
	name => 'grabber_miniserver',
	filename => "$lbplogdir/grabber_miniserver.log",
	append => 1,
	stderr => 1,
	addtime => 1,
	nosession => 1
);

LOGSTART "Grabber Miniserver";

# Plugin config
my $pcfgfile = $lbpconfigdir . "/stats4lox.json";
my $pjsonobj = LoxBerry::JSON->new();
my $pcfg = $pjsonobj->open(filename => $pcfgfile, readonly => 1);

# Settings
my $measurement = $pcfg->{miniserver}->{measurement};
my $interval = $pcfg->{miniserver}->{interval};

# Header
print "Content-type: text/ascii; charset=UTF-8\n\n";

# Skip if not enabled
if ( ! is_enabled($pcfg->{miniserver}->{active}) ) {
	LOGINF "Miniserver Grabber is disabled. Existing.";
	exit 0;
}
  
# Next runs
my $jsonobjmem = LoxBerry::JSON->new();
my $memfile = "/dev/shm/stats4lox_mem_miniservergrabber.json";
my $mem = $jsonobjmem->open(filename => $memfile, writeonclose => 1);

# Data to grab
my %stats2grab = (
	"sys_cpu" => "/jdev/sys/cpu",
	"sys_heap" => "/jdev/sys/heap",
	"bus_packetssent" => "/jdev/bus/packetssent",
	"bus_packetsreceived" => "/jdev/bus/packetsreceived",
	"bus_receiveerrors" => "/jdev/bus/receiveerrors",
	"bus_frameerrors" => "/jdev/bus/frameerrors",
	"bus_overruns" => "/jdev/bus/overruns",
	"bus_parityerrors" => "/jdev/bus/parityerrors",
	"lan_txp" => "/jdev/lan/txp",
	"lan_txe" => "/jdev/lan/txe",
	"lan_txc" => "/jdev/lan/txc",
	"lan_exh" => "/jdev/lan/exh",
	"lan_txu" => "/jdev/lan/txu",
	"lan_rxp" => "/jdev/lan/rxp",
	"lan_eof" => "/jdev/lan/eof",
	"lan_rxo" => "/jdev/lan/rxo",
	"lan_nob" => "/jdev/lan/nob",
	"sys_numtasks" => "/jdev/sys/numtasks",
	"sps_state" => "/jdev/sps/state",
);

# All Miniservers
my %miniservers = LoxBerry::System::get_miniservers();

if ( ! %miniservers ) {
	LOGINF "No Miniservers configured. Existing.";
	exit 0;
}

# Loop through Miniservers
my @data;
foreach my $msno (sort keys %miniservers) {
	LOGINF "Grabbing Miniserver " . $msno;
	my $now = time();
	# Checking if interval is reached
	if ($mem->{$msno}) {
		if ( $now < $mem->{$msno}->{nextrun} ) {
			LOGINF "  Interval not reached - skipping this time";
			next;
		}
	}
	# Save epoche for next run/poll
	$mem->{$msno}->{nextrun} = $now + $interval;
	
	# Collect data
	my %tags = ();
	$tags{name} = $miniservers{$msno}{Name} if $miniservers{$msno}{Name};
	$tags{note} = $miniservers{$msno}{Note} if $miniservers{$msno}{Note};
	$tags{msno} = $msno;
	
	# Grab stat data
	my %fields = ();
	my $ms_fetcherrors = 0;
	my $ms_fetchoks = 0;
	foreach my $key (keys %stats2grab) {
		my $url = $stats2grab{$key};
		# Grab data
		my ($code, $resp) = Stats4Lox::msget_value($msno, $url);
		if ( !$resp || $code ne "200" ) {
			LOGWARN "  Could not grab data from Miniserver $msno: HTTP $code (URL $url)";
			$ms_fetcherrors++;
			next;
		}
		$ms_fetchoks++;
		LOGDEB "  Miniserver $msno -> $key = $resp->[0]->{Value}";
		my $valname = "msno_" . $msno . "_" . $key;
		$fields{$valname} = $resp->[0]->{Value};

		# Slow down
		sleep (0.2);
	}
	if( $ms_fetcherrors > 0 and $ms_fetchoks > 0 ) {
		LOGWARN "Miniserver $msno -> $ms_fetchoks values ok but $ms_fetcherrors values not reachable - possibly user not Miniserver Admin?";
	}
	elsif ( $ms_fetcherrors > 0 and $ms_fetchoks == 0 ) {
		LOGWARN "Miniserver $msno -> $ms_fetcherrors errors. Miniserver not reachable?";
	}
	my $lineprot = Stats4Lox::influx_lineprot(undef, $measurement, \%tags, \%fields);
	push @data, $lineprot;
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
