#!/usr/bin/perl

use LoxBerry::System;
use LoxBerry::JSON;
use LoxBerry::Log;
use FindBin qw($Bin);
use lib "$Bin/../../../../../bin/plugins/stats4lox/libs";
use Globals;
use Stats4Lox;
use strict;
use warnings;

my $log = LoxBerry::Log->new (
	name => 'grabber_loxberry',
	filename => "$lbplogdir/grabber_loxberry.log",
	append => 1,
	addtime => 1,
);

LOGSTART "Grabber LoxBerry";

# Settings, through Globals so the defaults are merged in
my $measurement = $Globals::loxberry->{measurement};
my $interval = $Globals::loxberry->{interval};

# Header
print "Content-type: text/ascii; charset=UTF-8\n\n";

# Skip if not enabled. Off by default - this source has never collected anything,
# so it is switched on deliberately or not at all.
if ( ! is_enabled($Globals::loxberry->{active}) ) {
	LOGINF "LoxBerry Grabber is disabled. Exiting.";
	exit 0;
}

my @metrics = Globals::loxberry_metrics();
if( ! @metrics ) {
	LOGWARN "No metrics selected. Exiting.";
	exit 0;
}

my @hosts = Globals::loxberry_hosts();

# Next runs, per host and on the ramdisk - after a reboot every host is simply
# due at once. Keyed by address, so adding or removing a LoxBerry does not
# disturb the schedule of the others.
my $jsonobjmem = LoxBerry::JSON->new();
my $memfile = $Globals::loxberry_memfile;
my $mem = $jsonobjmem->open(filename => $memfile, writeonclose => 1);

my @data;
foreach my $h ( @hosts ) {
	my $addr = $h->{address};
	LOGINF "Grabbing LoxBerry " . $addr;

	my $now = time();
	if( $mem->{$addr} and $now < ( $mem->{$addr}->{nextrun} // 0 ) ) {
		LOGINF "  Interval not reached - skipping this time";
		next;
	}
	$mem->{$addr}->{nextrun} = $now + $interval;

	my ($values, $err, $hostname) = Stats4Lox::linfo_metric_values( $h->{url}, \@metrics );

	if( $err ) {
		LOGWARN "  $addr: $err";
		next;
	}
	if( ! keys %$values ) {
		LOGWARN "  $addr: Linfo answered, but not one of the selected values was in it";
		next;
	}

	# The host is a TAG, and the field names carry no host in them. A query over
	# several LoxBerrys then gives one series per machine instead of one per field
	# name - which is what tags are for.
	#
	# The tag is not always the address: this LoxBerry is reached over localhost
	# and would otherwise be called that in every graph.
	my %tags = ( source => 'grabber', host => ( $h->{tag} // $addr ) );
	# The name the machine calls itself, which is not the address it was reached
	# at. Only set when Linfo reported one, so an empty tag is never written.
	$tags{name} = $hostname if( defined $hostname and $hostname =~ /\S/ );
	$tags{own} = 1 if( $h->{own} );

	LOGDEB "  $addr -> $_ = $values->{$_}" foreach ( sort keys %$values );

	my $lineprot = Stats4Lox::influx_lineprot(undef, $measurement, \%tags, $values);
	push @data, $lineprot if( defined $lineprot );
	LOGOK "  $addr: " . scalar( keys %$values ) . " values";
}

# Output
LOGOK "Returning lineprot dataset (" . scalar @data . " measures)";
foreach (@data) {
	print $_ . "\n";
	LOGDEB $_;
}

exit(0);

# Script destructor
END {
	LOGEND if($log);
}
