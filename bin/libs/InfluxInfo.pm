#!/usr/bin/perl

# What is actually stored in the InfluxDB database.
#
# Everything the Influx page needs, kept out of ajax.cgi so it can be run and
# checked from the command line.
#
# Measured on a live installation with 141 measurements (of which 7 are
# Telegraf's own internal_* series, filtered out here):
#
#   SHOW MEASUREMENTS                        0.16 s
#   SHOW FIELD KEYS                          0.25 s
#   SHOW TAG VALUES WITH KEY = "source"      0.20 s
#   134 x first/last, batched into one query 2.2 s each
#   134 x count(*), batched                  23.5 s
#
# Hence the split: the overview is built from the cheap queries, the timestamps
# are fetched afterwards, and the value count only when it is asked for. The
# same statements sent as a regex over all measurements - SELECT last(*) FROM
# /.*/ - take 33 s instead of 2.2, so batching individual statements is not a
# detour but the fast path.

package InfluxInfo;

use strict;
use warnings;
use JSON;
use LoxBerry::System;

our $DEBUG = 0;

# Telegraf writes its own diagnostics into the same database. They are not
# statistics and have no place on this page.
our $INTERNAL_PREFIX = 'internal_';

# Where s4linflux lives.
#
# $lbpbindir is the right source and is used whenever it has a value - but
# LoxBerry derives it from the location of the calling script, so it is empty
# as soon as this module is used by something outside the plugin directory (a
# test, a cron script, a shell). The module then falls back to its own
# location: it sits in <bindir>/libs/, and s4linflux is installed alongside it,
# so the two cannot drift apart.
sub _bin
{
	return "$LoxBerry::System::lbpbindir/s4linflux"
		if( $LoxBerry::System::lbpbindir );
	require File::Basename;
	return File::Basename::dirname( File::Basename::dirname( __FILE__ ) ) . "/s4linflux";
}

sub _db
{
	require Globals;
	return $Globals::influx->{influxdatabase} // 'stats4lox';
}

#############################################################################
# Runs one or more statements and returns the list of results.
#
# The command is called through a list, never through a shell - a measurement
# name may contain spaces, quotes and umlauts, and a batch of 134 statements is
# far too long to quote by hand.
#
# The client sometimes answers with one JSON document per line instead of one
# for everything, so the output is parsed line by line and the results are
# collected.
#############################################################################

sub query
{
	my ($sql) = @_;
	return [] if( !$sql );

	my @results;
	my $pid = open( my $ph, '-|', _bin(), '-database', _db(), '-format', 'json', '-execute', $sql );
	if( !$pid ) {
		print STDERR "InfluxInfo: could not run " . _bin() . ": $!\n";
		return [];
	}
	while( my $line = <$ph> ) {
		next if( $line !~ /^\s*\{/ );
		my $doc = eval { decode_json( $line ) };
		if( $@ ) { print STDERR "InfluxInfo: unparsable answer: $@\n" if $DEBUG; next }
		push @results, @{ $doc->{results} || [] };
	}
	close $ph;
	return \@results;
}

# One statement per name, joined into a single request. Returns the results in
# the same order the names were given.
sub query_each
{
	my ($template, $names) = @_;
	return [] if( !$names or !@$names );
	my @stmts;
	foreach my $n ( @$names ) {
		( my $safe = $n ) =~ s/"/\\"/g;
		( my $s = $template ) =~ s/__NAME__/$safe/g;
		push @stmts, $s;
	}
	return query( join( "; ", @stmts ) );
}

#############################################################################
# The names of all measurements, without Telegraf's internal ones
#############################################################################

sub measurements
{
	my $res = query( "SHOW MEASUREMENTS" );
	my @out;
	foreach my $s ( @{ $res->[0]->{series} || [] } ) {
		foreach my $v ( @{ $s->{values} || [] } ) {
			next if( !defined $v->[0] );
			next if( index( $v->[0], $INTERNAL_PREFIX ) == 0 );
			push @out, $v->[0];
		}
	}
	return \@out;
}

#############################################################################
# Everything that is cheap to know: fields per measurement and where the data
# came from.
#############################################################################

sub fieldkeys
{
	my $res = query( "SHOW FIELD KEYS" );
	my %out;
	foreach my $r ( @$res ) {
		foreach my $s ( @{ $r->{series} || [] } ) {
			next if( !$s->{name} );
			$out{ $s->{name} } = [ map { $_->[0] } @{ $s->{values} || [] } ];
		}
	}
	return \%out;
}

sub sources
{
	my $res = query( 'SHOW TAG VALUES WITH KEY = "source"' );
	my %out;
	foreach my $r ( @$res ) {
		foreach my $s ( @{ $r->{series} || [] } ) {
			next if( !$s->{name} );
			$out{ $s->{name} } = [ map { $_->[1] } @{ $s->{values} || [] } ];
		}
	}
	return \%out;
}

#############################################################################
# First and last timestamp of every measurement, in nanoseconds
#
# "ORDER BY time DESC LIMIT 1" rather than "last(*)": with several fields it is
# not obvious what time a selector over all of them reports, while the explicit
# form simply returns the last row. Both cost the same, measured.
#############################################################################

sub timestamps
{
	my ($names) = @_;
	my %out;
	return \%out if( !$names or !@$names );

	my $first = query_each( 'SELECT * FROM "__NAME__" LIMIT 1', $names );
	my $last  = query_each( 'SELECT * FROM "__NAME__" ORDER BY time DESC LIMIT 1', $names );

	for( my $i = 0; $i < scalar @$names; $i++ ) {
		my $n = $names->[$i];
		$out{$n} = {
			first => _first_time( $first->[$i] ),
			last  => _first_time( $last->[$i] ),
		};
	}
	return \%out;
}

sub _first_time
{
	my ($result) = @_;
	return undef if( !$result );
	my $s = ( $result->{series} || [] )->[0];
	return undef if( !$s );
	my $v = ( $s->{values} || [] )->[0];
	return undef if( !$v );
	return $v->[0];
}

#############################################################################
# How many values a measurement holds. The expensive one - 23.5 s for 134
# measurements - so it is never part of building the page.
#############################################################################

sub valuecount
{
	my ($names) = @_;
	my %out;
	return \%out if( !$names or !@$names );

	my $res = query_each( 'SELECT count(*) FROM "__NAME__"', $names );
	for( my $i = 0; $i < scalar @$names; $i++ ) {
		my $s = ( ( $res->[$i] || {} )->{series} || [] )->[0];
		my $v = $s ? ( $s->{values} || [] )->[0] : undef;
		if( !$v ) { $out{ $names->[$i] } = 0; next }
		# One count per field, and the measurement holds as many values as its
		# fullest field - counting them all up would report a point with three
		# fields as three values.
		my $max = 0;
		for( my $c = 1; $c < scalar @$v; $c++ ) {
			my $n = $v->[$c];
			$max = $n if( defined $n and $n =~ /^\d+$/ and $n > $max );
		}
		$out{ $names->[$i] } = $max;
	}
	return \%out;
}

#############################################################################
# Removes a measurement including all its series
#############################################################################

sub drop_measurement
{
	my ($name) = @_;
	return 0 if( !defined $name or $name eq '' );
	( my $safe = $name ) =~ s/"/\\"/g;
	my $res = query( "DROP MEASUREMENT \"$safe\"" );
	foreach my $r ( @$res ) {
		return 0 if( $r->{error} );
	}
	# Asked again rather than trusting the answer - DROP reports success even
	# for a measurement that was not there.
	my $still = measurements();
	return ( grep { $_ eq $name } @$still ) ? 0 : 1;
}

#############################################################################
# The uuid tags of every measurement
#
# This is the link back to the Loxone block. A measurement whose statistic has
# been removed cannot be matched by name - only the uuid its series carry says
# which block once wrote it. Costs 0.14 s, measured.
#############################################################################

sub uuids
{
	my $res = query( 'SHOW TAG VALUES WITH KEY = "uuid"' );
	my %out;
	foreach my $r ( @$res ) {
		foreach my $s ( @{ $r->{series} || [] } ) {
			next if( !$s->{name} );
			$out{ $s->{name} } = [ map { $_->[1] } @{ $s->{values} || [] } ];
		}
	}
	return \%out;
}

#############################################################################
# Every block uuid the parsed LoxPLANs know
#
# One caveat that matters when reading the result: the blacklist keeps 276
# control types out of these files, so a block of such a type is missing here
# even though it exists on the Miniserver. "Not in this list" therefore means
# "not in the Loxone configuration as it was read in" and not "definitely gone"
# - which is how the web interface words it.
#############################################################################

sub loxplan_uuids
{
	my %out;
	require JSON;
	foreach my $f ( glob( "$LoxBerry::System::lbpdatadir/ms*.json" ) ) {
		open( my $fh, '<:raw', $f ) or next;
		local $/;
		my $p = eval { JSON::decode_json( <$fh> ) };
		close $fh;
		next if( !$p or ref($p->{controls}) ne 'HASH' );
		$out{$_} = 1 foreach ( keys %{ $p->{controls} } );
	}
	return \%out;
}

#############################################################################
# The measurements the plugin writes itself, which are not Loxone blocks
#
# stats_miniserver and stats_loxberry come from the two system grabbers. They
# carry no uuid tag, because there is no block behind them - without this they
# would end up in the "no idea what this is" bucket, and we do know.
#############################################################################

sub system_measurements
{
	require Globals;
	my %out;
	$out{ $Globals::miniserver->{measurement} } = 1 if( $Globals::miniserver->{measurement} );
	$out{ $Globals::loxberry->{measurement} }   = 1 if( $Globals::loxberry->{measurement} );
	return \%out;
}

1;
