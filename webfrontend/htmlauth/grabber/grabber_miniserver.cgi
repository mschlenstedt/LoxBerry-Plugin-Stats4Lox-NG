#!/usr/bin/perl

use LoxBerry::System;
use LoxBerry::JSON;
use LoxBerry::IO;
use FindBin qw($Bin);
use lib "$Bin/../../../../../bin/plugins/stats4lox-ng/libs";
use Globals;
use Stats4Lox;
use strict;
use warnings;
#use Data::Dumper;

#$Stats4Lox::DEBUG = 1;
my $DEBUG = 0;

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
	print STDERR "Miniserver Grabber is disabled. Existing.\n" if $DEBUG;
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
	print STDERR "No Miniservers configured. Existing.\n" if $DEBUG;
	exit 0;
}

# Loop through Miniservers
my @data;
foreach my $msno (sort keys %miniservers) {
	print STDERR "Grabbing Miniserver " . $msno . "\n" if $DEBUG;
	my $now = time();
	# Checking if interval is reached
	if ($mem->{$msno}) {
		if ( $now < $mem->{$msno}->{nextrun} ) {
			print STDERR "   Interval not reached - skipping this time\n" if $DEBUG;
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
	foreach my $key (keys %stats2grab) {
		my $url = $stats2grab{$key};
		# Grab data
		my ($code, $resp) = Stats4Lox::msget_value($msno, $url);
		if ( !$resp || $code ne "200" ) {
			print STDERR "   Could not grab data from Miniserver.\n" if $DEBUG;
			next;
		}
		print STDERR "Value of " . $key . " is " . $resp->[0]->{Value} . "\n";
		my $valname = "msno_" . $msno . "_" . $key;
		$fields{$valname} = $resp->[0]->{Value};

		# Slow down
		sleep (0.2);
	}

	my $lineprot = Stats4Lox::influx_lineprot(undef, $measurement, \%tags, \%fields);
	push @data, $lineprot;
}

#print STDERR Dumper @data;

# Output
foreach (@data) {
	print $_ . "\n";
}

exit(0);
