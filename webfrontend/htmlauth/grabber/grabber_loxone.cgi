#!/usr/bin/perl

use LoxBerry::System;
use LoxBerry::JSON;
use LoxBerry::IO;
use FindBin qw($Bin);
use lib "$Bin/../../../../../bin/plugins/stats4lox/libs";
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

# # Measurement name for Influx
# my $measurement = $pcfg->{loxone}->{measurement};

# Header
print "Content-type: text/ascii; charset=UTF-8\n\n";

# Skip if not enabled
if ( ! is_enabled($pcfg->{loxone}->{active}) ) {
	print STDERR "Loxone Grabber is disabled. Existing.\n" if $DEBUG;
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
		print STDERR "   Data isn't complete. Skipping...\n" if $DEBUG;
		next;
	}
	print STDERR "Grabbing " . $results->{name} . "     $results->{uuid}\n" if $DEBUG;
	my $tag = $results->{measurementname};
	my $now = time();
	# Checking if interval is reached
	if ($mem->{$tag}) {
		if ( $now < $mem->{$tag}->{nextrun} ) {
			print STDERR "   Interval not reached - skipping this time\n" if $DEBUG;
			next;
		}
	}
	# Save epoche for next run/poll
	$mem->{$tag}->{nextrun} = $now + $results->{interval};
	
	# Grab data
	my ($code, $resp) = Stats4Lox::msget_value($results->{msno}, $results->{uuid});
	if ( !$resp || $code ne "200" ) {
		print STDERR "   Could not grab data from Miniserver.\n" if $DEBUG;
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
		print STDERR "   Using ALL outputs - config is empty - \n" if $DEBUG;
		foreach (@$resp) {
			if ($_->{"Key"}) {
				push @outputs, $_->{"Key"};
			}
		}
	}
	else {
		print STDERR "   Using defined outputs " . join(",", @outputs) . "\n" if $DEBUG;
	}
	
	my %fields = ();
	foreach ( @outputs ) {
		my $key = $_;
		foreach (@$resp) {
			if ($_->{"Key"} eq $key) {
				my $valname = $_->{"Name"};
				my $val = $_->{"Value"};
				$fields{"$valname"} = $val;
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
foreach (@data) {
	print $_ . "\n";
}

exit(0);
