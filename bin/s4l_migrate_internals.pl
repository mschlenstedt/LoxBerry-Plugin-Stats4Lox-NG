#!/usr/bin/perl

# Operating statistics stop filling up the database.
#
# Two of them, and they are easy to confuse:
#
#   internal_*   TELEGRAF's statistics about itself, written into the stats4lox
#                database. Three graphs on the Plugin Home dashboard draw them.
#   _internal    INFLUXDB's statistics about itself, its own database. Nothing
#                in the plugin reads it at all.
#
# Measured on a live installation on 08.08.2026, after a year of running:
#
#   internal_gather   4 224 867 points     _internal   174.6 MB
#   internal_write    2 816 578 points     stats4lox    91.7 MB
#   internal_parser   1 411 699 points
#   internal_process  1 408 289 points
#
# Nine point nine million points of Telegraf's bookkeeping, kept forever in
# autogen beside the user's measurements - and InfluxDB's own notes almost twice
# the size of the data they are about.
#
# What this does:
#
#   1. Creates the "internal" retention policy, seven days. Telegraf writes the
#      two measurements the dashboard needs into it from now on - see
#      telegraf.d/stats4lox_internal.conf.
#   2. Drops the internal_* measurements from the old place. They are Telegraf's
#      bookkeeping; there is no case for keeping a year of it, and the graphs
#      show the last 24 hours.
#   3. Drops the _internal database, which the [monitor] section of influxdb.conf
#      no longer fills.
#
# Idempotent, and every step checks its own precondition. Run it twice and it
# says there is nothing to do.
#
# THE HISTORY OF THESE STATISTICS IS GONE afterwards. The three graphs start
# empty and have their full window after a week. No measurement of the user's is
# touched: only names beginning with internal_ and the _internal database.

use strict;
use warnings;
use Getopt::Long;
use FindBin qw($Bin);
use lib "$Bin/libs";
use LoxBerry::System;
use LoxBerry::Log;
use Globals;
use InfluxInfo;

my $POLICY   = 'internal';
my $DURATION = '7d';
my $SHARD    = '1d';

my $opt_database;
GetOptions( "database=s" => \$opt_database ) or die "Unknown option\n";
$Globals::influx->{influxdatabase} = $opt_database if( $opt_database );
my $DB = $Globals::influx->{influxdatabase} // 'stats4lox';

# loglevel 6 whatever the plugin is set to: this runs once and deletes things.
my $log = LoxBerry::Log->new(
	name     => 'Migration',
	filename => "$lbplogdir/migrate_internals.log",
	append   => 1,
	addtime  => 1,
	stderr   => 1,
	loglevel => 6,
);
LOGSTART "Operating statistics";

sub influx
{
	my ($sql) = @_;
	my $res = InfluxInfo::query( $sql );
	return ( 0, [], "no answer from InfluxDB" ) if( ref($res) ne 'ARRAY' or !@$res );
	foreach my $r ( @$res ) {
		return ( 0, $res, $r->{error} ) if( $r->{error} );
	}
	return ( 1, $res, undef );
}

my $errors = 0;

#############################################################################
# 1. The retention policy for Telegraf's statistics
#############################################################################
# Not called s4l_internal. s4l_retention.pl drops every policy whose name starts
# with s4l_ and is not one of its own stages - with its data.
my %policies;
{
	my ($ok, $res, $err) = influx( "SHOW RETENTION POLICIES ON \"$DB\"" );
	if( !$ok ) {
		LOGCRIT "Could not read the retention policies: " . ( $err // '?' );
		LOGEND "Aborted";
		exit 1;
	}
	foreach my $s ( @{ $res->[0]->{series} || [] } ) {
		foreach my $v ( @{ $s->{values} || [] } ) {
			$policies{ $v->[0] } = $v->[1] if( defined $v->[0] );
		}
	}
}

if( !exists $policies{$POLICY} ) {
	my ($ok, $res, $err) = influx(
		"CREATE RETENTION POLICY \"$POLICY\" ON \"$DB\" DURATION $DURATION REPLICATION 1 SHARD DURATION $SHARD" );
	if( $ok ) { LOGOK "Retention policy $POLICY created ($DURATION, shards $SHARD)" }
	else      { LOGCRIT "Could not create the retention policy $POLICY: " . ( $err // '?' ); $errors++ }
}
else {
	# Only corrected when it says something else. Shard duration is deliberately
	# left alone here - InfluxDB applies a new one to new shards only, and
	# changing it on every run would say something happened when nothing did.
	if( ( $policies{$POLICY} // '' ) ne '168h0m0s' ) {
		my ($ok, $res, $err) = influx(
			"ALTER RETENTION POLICY \"$POLICY\" ON \"$DB\" DURATION $DURATION" );
		if( $ok ) { LOGOK "Retention policy $POLICY set to $DURATION (was $policies{$POLICY})" }
		else      { LOGWARN "Could not alter the retention policy $POLICY: " . ( $err // '?' ) }
	}
	else {
		LOGINF "Retention policy $POLICY is already there with $DURATION";
	}
}

#############################################################################
# 2. Telegraf's statistics in the old place
#############################################################################
# DROP MEASUREMENT takes it out of every retention policy at once, which is what
# is wanted here: a downsampling copy of Telegraf's bookkeeping is worth even
# less than the original.
my @found;
{
	my ($ok, $res, $err) = influx( "SHOW MEASUREMENTS ON \"$DB\"" );
	if( $ok ) {
		foreach my $s ( @{ $res->[0]->{series} || [] } ) {
			foreach my $v ( @{ $s->{values} || [] } ) {
				push @found, $v->[0] if( defined $v->[0] and $v->[0] =~ /^internal_/ );
			}
		}
	}
	else { LOGWARN "Could not read the measurements: " . ( $err // '?' ) }
}

if( !@found ) {
	LOGINF "No internal_ measurement in $DB - nothing to drop";
}
else {
	LOGINF "Dropping " . scalar(@found) . " measurements: " . join( ", ", sort @found );
	foreach my $m ( sort @found ) {
		# The guard that makes this safe to run anywhere: nothing that is not
		# called internal_ is ever passed to DROP.
		if( $m !~ /^internal_[A-Za-z0-9_]+$/ ) {
			LOGWARN "  $m does not look like a Telegraf measurement - left alone";
			next;
		}
		my ($ok, $res, $err) = influx( "DROP MEASUREMENT \"$m\"" );
		if( $ok ) { LOGOK "  $m dropped" }
		else      { LOGWARN "  $m: " . ( $err // '?' ); $errors++ }
	}
}

#############################################################################
# 3. InfluxDB's own database
#############################################################################
# Only when [monitor] store-enabled is off - otherwise InfluxDB creates it again
# within ten seconds and the drop was for nothing. postroot.sh sets that before
# InfluxDB is started, so by the time this runs the file already says so.
my $conf = "$lbpconfigdir/influxdb/influxdb.conf";
my $monitor_off = 0;
if( open( my $fh, '<', $conf ) ) {
	my $in = 0;
	while( my $line = <$fh> ) {
		$in = 1 if( $line =~ /^\s*\[monitor\]/ );
		next if( !$in );
		last if( $line =~ /^\s*\[/ and $line !~ /^\s*\[monitor\]/ );
		$monitor_off = 1 if( $line =~ /^\s*store-enabled\s*=\s*false/ );
	}
	close $fh;
}

if( !$monitor_off ) {
	LOGINF "[monitor] store-enabled is not off in influxdb.conf - _internal left alone";
}
else {
	my ($ok, $res, $err) = influx( "SHOW DATABASES" );
	my $have = 0;
	if( $ok ) {
		foreach my $s ( @{ $res->[0]->{series} || [] } ) {
			foreach my $v ( @{ $s->{values} || [] } ) {
				$have = 1 if( ( $v->[0] // '' ) eq '_internal' );
			}
		}
	}
	if( !$have ) {
		LOGINF "_internal does not exist - nothing to drop";
	}
	else {
		my ($o, $r, $e) = influx( "DROP DATABASE \"_internal\"" );
		if( $o ) { LOGOK "_internal dropped" }
		else     { LOGWARN "Could not drop _internal: " . ( $e // '?' ); $errors++ }
	}
}

if( $errors ) {
	LOGCRIT "$errors step(s) failed - see above";
	LOGEND "Finished with errors";
	exit 1;
}

LOGOK "Done. Telegraf's statistics are kept for $DURATION in the $POLICY policy, "
	. "and InfluxDB no longer writes about itself.";
LOGEND "Finished";
exit 0;
