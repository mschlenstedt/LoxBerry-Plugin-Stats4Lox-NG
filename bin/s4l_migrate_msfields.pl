#!/usr/bin/perl

# Takes the Miniserver number out of the field names of stats_miniserver.
#
#   msno_1_sys_cpu   ->   sys_cpu
#
# The number is already a tag on every one of those points. Having it in the
# field name as well means a query over two Miniservers gives two field names
# instead of two series, every Grafana panel has to be written per Miniserver,
# and nothing can be summed or compared without naming each machine. It was a
# mistake, and it is one of those that cannot be corrected by writing the new
# name from now on: the history would then sit under a name nobody queries.
#
# So the history is rewritten. InfluxDB 1.x cannot rename a field and cannot
# delete one, so this is the only route there is:
#
#   1. SELECT "msno_1_sys_cpu" AS "sys_cpu", ... INTO <policy>.stats_miniserver_mig
#   2. DROP MEASUREMENT stats_miniserver          (all policies at once - 1.x has
#                                                  no per-policy drop)
#   3. SELECT * INTO <policy>.stats_miniserver FROM <policy>.stats_miniserver_mig
#   4. DROP MEASUREMENT stats_miniserver_mig
#
# Every retention policy that holds the measurement is done, and a downsampled
# copy carries the aggregate in front: mean_msno_1_sys_cpu becomes mean_sys_cpu.
#
# Idempotent. Without a single msno_ field it does nothing and says so, which is
# what happens on a fresh installation and on the second run.
#
# EXISTING GRAFANA PANELS WILL BREAK. They select the field by its raw name, and
# that name changes. Michael decided that trade knowingly on 07.08.2026: a
# measurement that is wrong for good is worse than dashboards that have to be
# adjusted once.

use strict;
use warnings;
use FindBin qw($Bin);
use lib "$Bin/libs";
use LoxBerry::System;
use LoxBerry::Log;
use Globals;
use InfluxInfo;

my $MEASUREMENT = 'stats_miniserver';
my $TEMP        = 'stats_miniserver_mig';
my $DB          = $Globals::influx->{influxdatabase} // 'stats4lox';

# loglevel 6 whatever the plugin is set to. This runs once, it rewrites somebody's
# history, and the one place anybody will look afterwards is this log - at the
# configured level of 3 it would have recorded nothing but errors.
my $log = LoxBerry::Log->new(
	name     => 'Migration',
	filename => "$lbplogdir/migrate_msfields.log",
	append   => 1,
	addtime  => 1,
	stderr   => 1,
	loglevel => 6,
);
LOGSTART "Miniserver field names";

# Runs statements and reports a failure. InfluxInfo::query hands back a result
# per statement and puts the failure in its "error" key - a statement that failed
# looks exactly like one that worked unless somebody looks.
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

sub fail
{
	my ($msg) = @_;
	LOGCRIT $msg;
	LOGEND "Aborted";
	exit 1;
}

# The retention policies of the database
my ($ok, $res, $err) = influx( "SHOW RETENTION POLICIES ON \"$DB\"" );
fail( "Could not read the retention policies: " . ( $err // '?' ) ) if( !$ok );

my @policies;
foreach my $s ( @{ $res->[0]->{series} || [] } ) {
	foreach my $v ( @{ $s->{values} || [] } ) {
		push @policies, $v->[0] if( defined $v->[0] );
	}
}
fail( "No retention policy found" ) if( !@policies );
LOGINF "Policies: " . join( ", ", @policies );

# The field names to be renamed, per policy.
#
# mean_ and last_ in front are the aggregates a downsampled copy carries. They
# stay where they are - only the msno_<n>_ in the middle goes.
my %rename;   # policy => { old => new }
my $total = 0;
foreach my $p ( @policies ) {
	my ($o, $r, $e) = influx( "SHOW FIELD KEYS FROM \"$DB\".\"$p\".\"$MEASUREMENT\"" );
	next if( !$o );
	foreach my $s ( @{ $r->[0]->{series} || [] } ) {
		foreach my $v ( @{ $s->{values} || [] } ) {
			my $f = $v->[0];
			next if( !defined $f );
			next if( $f !~ /^((?:mean_|last_)?)msno_\d+_(.+)$/ );
			$rename{$p}->{$f} = $1 . $2;
			$total++;
		}
	}
	LOGINF "  $p: " . scalar( keys %{ $rename{$p} || {} } ) . " fields to rename";
}

if( !$total ) {
	LOGOK "Nothing to do - no field carries a Miniserver number.";
	LOGEND "Finished";
	exit 0;
}

# Two fields must never end up with the same new name. That would happen with
# data from two Miniservers, where msno_1_sys_cpu and msno_2_sys_cpu both want to
# be sys_cpu - which is exactly the point of the change, because they are told
# apart by their msno tag. They therefore have to be written in separate passes,
# one per Miniserver, or the second would overwrite the first at the same
# timestamp.
my %passes;   # policy => { msno => { old => new } }
foreach my $p ( keys %rename ) {
	foreach my $old ( keys %{ $rename{$p} } ) {
		my ($n) = $old =~ /msno_(\d+)_/;
		$passes{$p}->{$n}->{$old} = $rename{$p}->{$old};
	}
}

# How much there is, so the log says afterwards whether it all arrived
my %before;
foreach my $p ( keys %passes ) {
	foreach my $n ( keys %{ $passes{$p} } ) {
		my ($first) = sort keys %{ $passes{$p}->{$n} };
		my ($o, $r, $e) = influx( "SELECT count(\"$first\") FROM \"$DB\".\"$p\".\"$MEASUREMENT\"" );
		my $c = eval { $r->[0]->{series}->[0]->{values}->[0]->[1] } // 0;
		$before{$p}->{$n} = $c;
		LOGINF "  $p, Miniserver $n: $c points (counted on $first)";
	}
}

# 1. Copy every policy into a temporary measurement of the same policy, with the
#    new names. The temporary one is needed because a measurement cannot be
#    dropped per policy - and the drop has to happen before the data can come
#    back under the same name.
LOGINF "Copying to $TEMP ...";
foreach my $p ( sort keys %passes ) {
	foreach my $n ( sort keys %{ $passes{$p} } ) {
		my $map = $passes{$p}->{$n};
		my $sel = join( ", ", map { "\"$_\" AS \"$map->{$_}\"" } sort keys %$map );
		my $sql = "SELECT $sel INTO \"$DB\".\"$p\".\"$TEMP\" FROM \"$DB\".\"$p\".\"$MEASUREMENT\" GROUP BY *";
		my ($o, $r, $e) = influx( $sql );
		fail( "Copy failed ($p, Miniserver $n): " . ( $e // '?' ) ) if( !$o );
		my $written = eval { $r->[0]->{series}->[0]->{values}->[0]->[1] } // 0;
		LOGINF "  $p, Miniserver $n: $written points written";
		fail( "$p, Miniserver $n: nothing was written although there are $before{$p}->{$n} points" )
			if( $before{$p}->{$n} > 0 and $written == 0 );
	}
}

# 2. The old measurement. This is the point of no return, and it is why step 1
#    checks that its copy actually arrived.
LOGINF "Dropping $MEASUREMENT ...";
{
	my ($o, $r, $e) = influx( "DROP MEASUREMENT \"$MEASUREMENT\"" );
	fail( "Could not drop $MEASUREMENT: " . ( $e // '?' ) ) if( !$o );
}

# 3. Back under the proper name, policy by policy
LOGINF "Writing $MEASUREMENT back ...";
foreach my $p ( sort keys %passes ) {
	my $sql = "SELECT * INTO \"$DB\".\"$p\".\"$MEASUREMENT\" FROM \"$DB\".\"$p\".\"$TEMP\" GROUP BY *";
	my ($o, $r, $e) = influx( $sql );
	fail( "Writing back failed ($p): " . ( $e // '?' ) . " - the data is still in $TEMP" ) if( !$o );
	my $written = eval { $r->[0]->{series}->[0]->{values}->[0]->[1] } // 0;
	LOGINF "  $p: $written points";
}

# 4. The temporary measurement, in every policy at once
{
	my ($o, $r, $e) = influx( "DROP MEASUREMENT \"$TEMP\"" );
	LOGWARN "Could not drop $TEMP: " . ( $e // '?' ) if( !$o );
}

# Did it work? Not a formality - this ran over somebody's history.
my $leftover = 0;
foreach my $p ( @policies ) {
	my ($o, $r, $e) = influx( "SHOW FIELD KEYS FROM \"$DB\".\"$p\".\"$MEASUREMENT\"" );
	next if( !$o );
	foreach my $s ( @{ $r->[0]->{series} || [] } ) {
		foreach my $v ( @{ $s->{values} || [] } ) {
			$leftover++ if( defined $v->[0] and $v->[0] =~ /msno_\d+_/ );
		}
	}
}
if( $leftover ) {
	LOGCRIT "$leftover field names still carry a Miniserver number.";
	LOGEND "Finished with errors";
	exit 1;
}

LOGOK "Done. The Miniserver number is a tag now and no longer part of any field name.";
LOGWARN "Grafana panels that select these fields by name have to be adjusted - the names have changed.";
LOGEND "Finished";
exit 0;
