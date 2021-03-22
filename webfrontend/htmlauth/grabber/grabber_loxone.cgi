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
	print STDERR "Grabbing " . $results->{name} . "     $results->{uuid}\n";
	my $tag = $results->{name};
	my $now = time();
	# Checking if interval is reached
	if ($mem->{$tag}) {
		if ( $now < $mem->{$tag}->{nextrun} ) {
			print STDERR "   Interval not reached - skipping this time\n";
			next;
		}
	}
	# Save epoche for next run/poll
	$mem->{$tag}->{nextrun} = $now + $results->{interval};
	
	# Grab data
	my (undef, undef, $resp) = LoxBerry::IO::mshttp_call($results->{msno}, "$results->{url}");
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
	# Collect data
	my $values;
	$values->{name} = $results->{name};
	$values->{description} = $results->{description};
	$values->{uuid} = $results->{uuid};
	$values->{type} = $results->{type};
	$values->{category} = $results->{category};
	$values->{room} = $results->{room};
	
	my @results;
	my $value = $respjson->{LL}->{value};
	$value =~ s/^([-\d\.]+).*/$1/g;
	$value = $value + 0;
	# $values->{value} = $value;
	my %defaultresult = ( $values->{uuid} . "_default" => $value );
	push @results, \%defaultresult;
	
	my @outputs;
	if( ref($results->{outputs}) eq "ARRAY" ) {
		@outputs = @{$results->{outputs}};
	}
	if( scalar(@outputs) == 0) {
		# use all putputs
		@outputs = ();
		print STDERR "   Using ALL outputs - config is empty - \n";
		foreach( sort keys %{$respjson->{LL}} ) {
			push @outputs, substr( $_, 6) if( LoxBerry::System::begins_with($_, "output") );
		}
	}
	else {
		print STDERR "   Using defined outputs " . join(",", @outputs) . "\n";
	}
	
	foreach ( @outputs ) {
		if ($_ < 0) {
			next; # Skip -1 (default value for future use)
		}
		my $valname = $respjson->{LL}->{"output$_"}->{name};
		my $valvalue = $respjson->{LL}->{"output$_"}->{value};
		my %result = ( $values->{uuid} . "_" . $valname => $valvalue );
		push @results, \%result;
	
	}
	$values->{value} = \@results;
	push (@data, $values);

	# Slow down
	sleep (0.2);
}

#print STDERR Dumper @data;

# Output
my $jsonout = to_json( \@data, {ascii => 1, pretty => 1 });
print "Content-type: application/json\n\n";
print $jsonout;

exit(0);
