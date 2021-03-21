#!/usr/bin/perl

use LoxBerry::System;
use LoxBerry::JSON;
use LoxBerry::IO;
use strict;
use warnings;
use Data::Dumper;
  
# Stats Configuration
my $jsonobjcfg = LoxBerry::JSON->new();
my $cfgfile = $lbpconfigdir . "/stats.json";
my $cfg = $jsonobjcfg->open(filename => $cfgfile, readonly => 1);

# Next runs
my $jsonobjmem = LoxBerry::JSON->new();
my $memfile = "/dev/shm/stats4lox_mem_miniservergrabber.json";
my $mem = $jsonobjcfg->open(filename => $memfile, writeonclose => 1);

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

# Loop through Miniservers
my @data;
for my $results( @{$cfg->{miniserver}} ){
	if ( is_disabled ($results->{active}) ) {
		next;
	}
	print STDERR "Grabbing Miniserver " . $results->{msno} . "\n";
	my $msno = $results->{msno};
	my $now = time();
	# Checking if interval is reached
	if ($mem->{$msno}) {
		if ( $now < $mem->{$msno}->{nextrun} ) {
			print STDERR "   Interval not reached - skipping this time\n";
			next;
		}
	}
	# Save epoche for next run/poll
	$mem->{$msno}->{nextrun} = $now + $results->{interval};
	
	# Collect data
	my $values;
	$values->{name} = $miniservers{$msno}{Name};
	$values->{note} = $miniservers{$msno}{Note};
	$values->{msno} = $msno;
	
	# Grab stat data
	my @results;
	foreach my $key (keys %stats2grab) {
		my $url = $stats2grab{$key};
		my (undef, undef, $resp) = LoxBerry::IO::mshttp_call($msno, "$url");
		if ( !$resp ) {
			print STDERR "   Could not grab data from Miniserver - empty data. Wrong URL?\n";
			next;
		}
		#print STDERR $resp . "\n";
		# Convert to valid UTF8
		#$resp = Encode::decode("UTF-8", $resp);
		# Convert to JSON
		my $respjson;
		eval {
			$respjson = decode_json( "$resp" );
			1;
		};
		if ($@) {
			print STDERR "   Could not grab data from Miniserver - no valid JSON data received: $@\n";
			next;
		}
		if ($respjson->{LL}->{Code} ne "200") {
			print STDERR "   Could not grab data from Miniserver - error code: $respjson->{LL}->{Code}\n";
			next;
		}
		my $value = $respjson->{LL}->{value};
		$value =~ s/^([-\d\.]+).*/$1/g;
		$value = $value + 0;
		# $values->{value} = $value;
		my %defaultresult = ( "msno_" . $msno . "_" . $key => $value );
		push @results, \%defaultresult;

		# Slow down
		sleep (0.2);
	}

	$values->{value} = \@results;
	push (@data, $values);

}

# Output
my $jsonout = to_json( \@data, {ascii => 1, pretty => 1 });
print "Content-type: application/json\n\n";
print $jsonout;

exit(0);
