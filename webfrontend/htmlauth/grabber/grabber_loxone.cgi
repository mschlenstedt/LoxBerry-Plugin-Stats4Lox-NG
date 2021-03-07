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
my $memfile = "/dev/shm/stats4lox_mem_loxonegrabber.json";
my $mem = $jsonobjcfg->open(filename => $memfile, writeonclose => 1);

# Loop through stats
my @data;
for my $results( @{$cfg->{loxone}} ){
	#print "Grabbing " . $results->{name} . "\n";
	my $tag = $results->{name};
	my $now = time();
	# Checking if interval is reached
	if ($mem->{$tag}) {
		if ( $now < $mem->{$tag}->{nextrun} ) {
			#print "Interval not reached - skipping this time\n";
			next;
		}
	}
	# Save epoche for next run/poll
	$mem->{$tag}->{nextrun} = $now + $results->{interval};
	
	# Grab data
	my (undef, undef, $resp) = LoxBerry::IO::mshttp_call($results->{msno}, "$results->{url}");
	if ( !$resp ) {
		#print "Could not grab data from Miniserver - empty data. Wrong URL?\n";
		next;
	}
	#print $resp . "\n";
	# Convert to valid UTF8
	$resp = Encode::decode("UTF-8", $resp);
	# Convert to JSON
	my $respjson;
	eval {
		$respjson = decode_json( "$resp" );
		1;
	};
	if ($@) {
		#print "Could not grab data from Miniserver - no valid JSON data received: $@\n";
		next;
	}
	if ($respjson->{LL}->{Code} ne "200") {
		#print "Could not grab data from Miniserver - error code: $respjson->{LL}->{Code}\n";
		next;
	}
	# Collect data
	my $values;
	$values->{name} = $results->{name};
	$values->{description} = $results->{description};
	$values->{uuid} = $results->{uuid};
	$values->{type} = $results->{type};
	$values->{category} = $results->{category};
	$values->{room} = $results->{room};
	my $value = $respjson->{LL}->{value};
	$value =~ s/^([-\d\.]+).*/$1/g;
	$values->{value} = $value;
	my @outputs = split (/,/,$results->{outputs});
	foreach ( @outputs ) {
		$values->{"value_$_"} = $respjson->{LL}->{"output$_"}->{value};
		$values->{"name_$_"} = $respjson->{LL}->{"output$_"}->{name};
	}
	push (@data, $values);

	# Slow down
	sleep (0.2);
}

#print Dumper @data;

# Output
my $jsonout = to_json \@data, {ascii=>1, pretty => 1};

print "Content-type: application/json\n\n";
print $jsonout;

exit(0);
