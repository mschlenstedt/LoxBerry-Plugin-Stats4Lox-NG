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
#   1. SELECT "msno_1_sys_cpu" AS "sys_cpu", ... INTO stats_miniserver_mig
#   2. DROP MEASUREMENT stats_miniserver
#   3. SELECT * INTO stats_miniserver FROM stats_miniserver_mig
#   4. DROP MEASUREMENT stats_miniserver_mig
#
# AUTOGEN ONLY. An installation whose fields still carry a Miniserver number is
# older than the downsampling, which arrived with 1.9 - so autogen is the only
# retention policy it has. The check at the end looks at all of them anyway and
# says so if that ever turns out to be wrong; migrating a policy that cannot
# exist would be code nobody can test.
#
# Note that step 2 takes the measurement out of EVERY policy at once, because
# 1.x has no per-policy drop. That is another reason not to pretend this handles
# more than one: it would have to copy them all out first.
#
# Idempotent. Without a single msno_ field it does nothing and says so, which is
# what happens on a fresh installation and on the second run.
#
# EXISTING GRAFANA PANELS WILL BREAK. They select the field by its raw name, and
# that name changes. Michael decided that trade knowingly on 07.08.2026: a
# measurement that is wrong for good is worse than dashboards that have to be
# adjusted once.
#
#   --database <name>   work on another database. For testing: the measurement
#                       name is fixed, so a rehearsal needs a database of its own.

use strict;
use warnings;
use Getopt::Long;
use FindBin qw($Bin);
use lib "$Bin/libs";
use LoxBerry::System;
use LoxBerry::Log;
use Globals;
use InfluxInfo;

my $MEASUREMENT = 'stats_miniserver';
my $TEMP        = 'stats_miniserver_mig';
my $POLICY      = 'autogen';

my $opt_database;
GetOptions( "database=s" => \$opt_database ) or die "Unknown option\n";
# InfluxInfo reads the database out of $Globals::influx on every call
$Globals::influx->{influxdatabase} = $opt_database if( $opt_database );
my $DB = $Globals::influx->{influxdatabase} // 'stats4lox';

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

# Which policies exist. Only for the check at the end - the migration itself is
# autogen, see the note at the top.
my ($ok, $res, $err) = influx( "SHOW RETENTION POLICIES ON \"$DB\"" );
fail( "Could not read the retention policies: " . ( $err // '?' ) ) if( !$ok );

my @policies;
foreach my $s ( @{ $res->[0]->{series} || [] } ) {
	foreach my $v ( @{ $s->{values} || [] } ) {
		push @policies, $v->[0] if( defined $v->[0] );
	}
}
fail( "No retention policy found" ) if( !@policies );

# The field names to be renamed
my %rename;   # old => new
{
	my ($o, $r, $e) = influx( "SHOW FIELD KEYS FROM \"$DB\".\"$POLICY\".\"$MEASUREMENT\"" );
	fail( "Could not read the field names: " . ( $e // '?' ) ) if( !$o );
	foreach my $s ( @{ $r->[0]->{series} || [] } ) {
		foreach my $v ( @{ $s->{values} || [] } ) {
			my $f = $v->[0];
			next if( !defined $f );
			next if( $f !~ /^msno_\d+_(.+)$/ );
			$rename{$f} = $1;
		}
	}
}

if( !keys %rename ) {
	LOGOK "Nothing to do - no field in $POLICY carries a Miniserver number.";
	LOGEND "Finished";
	exit 0;
}
LOGINF "$POLICY: " . scalar( keys %rename ) . " fields to rename";

# Two fields must never end up with the same new name. That would happen with
# data from two Miniservers, where msno_1_sys_cpu and msno_2_sys_cpu both want to
# be sys_cpu - which is exactly the point of the change, because they are told
# apart by their msno tag. They therefore have to be written in separate passes,
# one per Miniserver, or the second would overwrite the first at the same
# timestamp.
my %passes;   # msno => { old => new }
foreach my $old ( keys %rename ) {
	my ($n) = $old =~ /msno_(\d+)_/;
	$passes{$n}->{$old} = $rename{$old};
}
LOGINF "Miniservers in the data: " . join( ", ", sort { $a <=> $b } keys %passes );

# How much there is, so the log says afterwards whether it all arrived
my %before;
foreach my $n ( keys %passes ) {
	my ($first) = sort keys %{ $passes{$n} };
	my ($o, $r, $e) = influx( "SELECT count(\"$first\") FROM \"$DB\".\"$POLICY\".\"$MEASUREMENT\"" );
	my $c = eval { $r->[0]->{series}->[0]->{values}->[0]->[1] } // 0;
	$before{$n} = $c;
	LOGINF "  Miniserver $n: $c points (counted on $first)";
}

# 1. Copy into a temporary measurement with the new names. The temporary one is
#    needed because the old name cannot be freed any other way - and the drop has
#    to happen before the data can come back under it.
LOGINF "Copying to $TEMP ...";
foreach my $n ( sort keys %passes ) {
	my $map = $passes{$n};
	my $sel = join( ", ", map { "\"$_\" AS \"$map->{$_}\"" } sort keys %$map );
	my $sql = "SELECT $sel INTO \"$DB\".\"$POLICY\".\"$TEMP\" FROM \"$DB\".\"$POLICY\".\"$MEASUREMENT\" GROUP BY *";
	my ($o, $r, $e) = influx( $sql );
	fail( "Copy failed (Miniserver $n): " . ( $e // '?' ) ) if( !$o );
	my $written = eval { $r->[0]->{series}->[0]->{values}->[0]->[1] } // 0;
	LOGINF "  Miniserver $n: $written points written";
	fail( "Miniserver $n: nothing was written although there are $before{$n} points" )
		if( $before{$n} > 0 and $written == 0 );
}

# 2. The old measurement. This is the point of no return, and it is why step 1
#    checks that its copy actually arrived.
LOGINF "Dropping $MEASUREMENT ...";
{
	my ($o, $r, $e) = influx( "DROP MEASUREMENT \"$MEASUREMENT\"" );
	fail( "Could not drop $MEASUREMENT: " . ( $e // '?' ) ) if( !$o );
}

# 3. Back under the proper name
LOGINF "Writing $MEASUREMENT back ...";
{
	my $sql = "SELECT * INTO \"$DB\".\"$POLICY\".\"$MEASUREMENT\" FROM \"$DB\".\"$POLICY\".\"$TEMP\" GROUP BY *";
	my ($o, $r, $e) = influx( $sql );
	fail( "Writing back failed: " . ( $e // '?' ) . " - the data is still in $TEMP" ) if( !$o );
	my $written = eval { $r->[0]->{series}->[0]->{values}->[0]->[1] } // 0;
	LOGINF "  $written points";
}

# 4. The temporary measurement
{
	my ($o, $r, $e) = influx( "DROP MEASUREMENT \"$TEMP\"" );
	LOGWARN "Could not drop $TEMP: " . ( $e // '?' ) if( !$o );
}

# Did it work? Not a formality - this ran over somebody's history.
#
# Every policy is looked at, not just autogen. Another one cannot hold these
# names on an installation this migration applies to - but if that assumption is
# ever wrong, it should say so rather than leave it lying there unmentioned.
my $leftover = 0;
foreach my $p ( @policies ) {
	my ($o, $r, $e) = influx( "SHOW FIELD KEYS FROM \"$DB\".\"$p\".\"$MEASUREMENT\"" );
	next if( !$o );
	my $n = 0;
	foreach my $s ( @{ $r->[0]->{series} || [] } ) {
		foreach my $v ( @{ $s->{values} || [] } ) {
			$n++ if( defined $v->[0] and $v->[0] =~ /msno_\d+_/ );
		}
	}
	next if( !$n );
	if( $p eq $POLICY ) {
		LOGCRIT "$n field names in $p still carry a Miniserver number.";
		$leftover += $n;
	}
	else {
		LOGWARN "$n field names in the retention policy $p still carry a Miniserver "
			. "number. That policy was not migrated - it should not have existed on an "
			. "installation with these names. Fix it by hand or drop it.";
	}
}
if( $leftover ) {
	LOGEND "Finished with errors";
	exit 1;
}

LOGOK "Done. The Miniserver number is a tag now and no longer part of a field name.";
LOGWARN "Grafana panels that select these fields by name have to be adjusted - the names have changed.";
LOGEND "Finished";
exit 0;
