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
	# stderr => 1,
	addtime => 1,
	# nosession => 1
);

LOGSTART "Grabber Miniserver";

# Settings
#
# Through Globals, which merges stats4lox.json over the defaults. This used to
# open the file itself and take whatever it happened to contain: a configuration
# without a miniserver section left the interval undefined and switched the
# grabber off - while the System tab, which does use the defaults, showed it as
# on and running every five minutes.
my $measurement = $Globals::miniserver->{measurement};
my $interval = $Globals::miniserver->{interval};

# Header
print "Content-type: text/ascii; charset=UTF-8\n\n";

# Skip if not enabled
if ( ! is_enabled($Globals::miniserver->{active}) ) {
	LOGINF "Miniserver Grabber is disabled. Existing.";
	exit 0;
}
  
# Next runs
my $jsonobjmem = LoxBerry::JSON->new();
my $memfile = $Globals::miniserver_memfile;
my $mem = $jsonobjmem->open(filename => $memfile, writeonclose => 1);

# What to grab. Chosen on the Data sources -> Miniserver page; the list used to
# be nineteen endpoints written out here. Without a saved selection this returns
# exactly those nineteen, so an upgrade changes nothing.
my @metrics = Globals::miniserver_metrics();

if( ! @metrics ) {
	LOGWARN "No metrics selected. Exiting.";
	exit 0;
}

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
	$tags{"source"} = "grabber";
	$tags{name} = $miniservers{$msno}{Name} if $miniservers{$msno}{Name};
	$tags{note} = $miniservers{$msno}{Note} if $miniservers{$msno}{Note};
	$tags{msno} = $msno;
	
	# Grab stat data.
	#
	# One request per URL rather than per metric - two of the endpoints answer
	# with two numbers each. There used to be a sleep(0.2) between the requests
	# here to be gentle on the Miniserver; it never slept, because the built-in
	# sleep takes whole seconds and Time::HiRes is not imported. Left out rather
	# than repaired: nineteen real fifths of a second would be four seconds, and
	# Telegraf gives this whole page five.
	my ($values, $errors) = Stats4Lox::miniserver_metric_values( $msno, \@metrics );

	# Plain field names. The Miniserver number is a tag and was in the field name
	# as well until 07.08.2026 - msno_1_sys_cpu - which meant two Miniservers gave
	# two field names instead of two series, and every panel had to be written per
	# machine. The history was rewritten with bin/s4l_migrate_msfields.pl.
	my %fields = ();
	foreach my $key ( sort keys %$values ) {
		LOGDEB "  Miniserver $msno -> $key = $values->{$key}";
		$fields{$key} = $values->{$key};
	}

	my $ms_fetchoks   = scalar keys %$values;
	my $ms_fetcherrors = scalar keys %$errors;
	foreach my $url ( sort keys %$errors ) {
		LOGWARN "  Could not grab data from Miniserver $msno: HTTP $errors->{$url} (URL $url)";
	}
	if( $ms_fetcherrors > 0 and $ms_fetchoks > 0 ) {
		LOGWARN "Miniserver $msno -> $ms_fetchoks values ok but $ms_fetcherrors endpoints not reachable - possibly user not Miniserver Admin, or this firmware does not know them?";
	}
	elsif ( $ms_fetcherrors > 0 and $ms_fetchoks == 0 ) {
		LOGWARN "Miniserver $msno -> $ms_fetcherrors errors. Miniserver not reachable?";
	}
	my $lineprot = Stats4Lox::influx_lineprot(undef, $measurement, \%tags, \%fields);
	push @data, $lineprot if( defined $lineprot );
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
