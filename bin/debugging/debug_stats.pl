#!/usr/bin/perl
use warnings;
use strict;
use LoxBerry::System;
use LoxBerry::Log;
use LoxBerry::JSON;
use Getopt::Long;
use Time::HiRes qw(time);
use FindBin qw($Bin);
use lib "$Bin/../libs";
use Loxone::Import;
use Globals;
require "$lbpbindir/libs/Stats4Lox.pm";

use Data::Dumper;

my $me = Globals::whoami();
my $finished = 0;

my $log = LoxBerry::Log->new (
    name => 'Debug Stats',
	stderr => 1,
	loglevel => 7,
	addtime => 1
);
LOGSTART "Dump Loxone Statistics";

my %miniservers = LoxBerry::System::get_miniservers();
if( !%miniservers ) {
	my $error = "$me get_miniservers: No Miniservers defined on your LoxBerry.";
	LOGCRIT $error;
	exit(1);
}

# Store the stat data per blocktype
my %blocktypedata;

foreach my $msno ( sort keys %miniservers ) {

	# Read Loxplan json
	my $loxplanobj = LoxBerry::JSON->new();
	my $loxplan = $loxplanobj->open(filename => $loxplanjsondir."/ms$msno.json", readonly => 1);

	my $import;
	eval {
		$import = new Loxone::Import(msno => $msno, log => $log);
	};
	if( $@ ) {
		my $error = "$me new Import: msno $msno Error --> $@";
		LOGCRIT $error;
		exit(4);
	}

	my $statlist;
	eval {
		$statlist = $import->getStatlist();
		
		# print Dumper( $statlist );
		
		LOGDEB "$me Statlist " . scalar (keys %{$statlist}) . " elements.";
	};
	if( $@ or !$statlist ) {
		my $error = "$me getStatList: Could not get Statistics list from Loxone Miniserver MS$msno --> $@";
		LOGCRIT $error;
		next;
	}
	
	# Iterate statistics
	foreach my $stat ( sort keys %$statlist ) {
		my $blocktype;
		# Get blocktype of this statistic
		if( defined $loxplan->{controls}->{$stat} ) {
			$blocktype = $loxplan->{controls}->{$stat}->{Type};
			LOGOK "Statistic $stat is blocktype $blocktype";
		} else {
			LOGERR "No match found to block $stat in Loxplan. Skipping";
			next;
		}
		
		# if we already know a stat with this blocktype, we don't need it again
		if( defined $blocktypedata{$blocktype} ) {
			LOGINF "Blocktype $blocktype already captured. Skipping";
			next;
		}
		
		# Get last month of this statistic
		my $lastmonth = @{$statlist->{$stat}}[-1];
		if( !$lastmonth ) {
			LOGERR "Cannot get lastmonth";
			next;
		}
		
		LOGINF "Last month $lastmonth";
		
		$import->{msno} = $msno;
		$import->{uuid} = $stat;
		
		# Fetching statistic
		LOGINF "$me Fetching $import->{uuid} Month: $lastmonth";
		my $monthdata;
		eval {
			$monthdata = $import->getMonthStat( yearmon => $lastmonth );
		};
		if( $@ ) {
			my $error = "$me getMonthStat $lastmonth: $@";
			LOGCRIT $error;
			next;
		}
		# print STDERR Data::Dumper::Dumper( $monthdata ) . "\n";
		if ( !$monthdata ) {
			LOGWARN "$me getMonthStat $lastmonth: No data to send. Skipping";
			next;
		}
		LOGINF "$me   Datasets " . scalar @{$monthdata->{values}};
	
		# print Dumper( $monthdata );
		
		# Extruding infos 
		
		$blocktypedata{$blocktype}{StatMetadata} = $monthdata->{StatMetadata};
		# Extract 5 values from data
		my $maxvalues = scalar $monthdata->{values};
		$maxvalues = $maxvalues < 5 ? $maxvalues : 5;
		$blocktypedata{$blocktype}{values} = ();
		for( my $i=0; $i<$maxvalues; $i++) {
			# Copy Hash to blocktypedata
			push @{$blocktypedata{$blocktype}{values}}, $monthdata->{values}[$i];
		}
		
		# Get Live Data from Miniserver
		$import->getLoxoneLabels();
		
		$blocktypedata{$blocktype}{LiveData} = $import->{LoxoneLabels};
		
		
		# print Dumper( $blocktypedata{$blocktype} );
		
		LOGOK "Blocktype $blocktype finished";
	
	}
}
LOGOK "All Miniservers finished";
$finished = 1;

END {

	if( $finished != 1 ) {
		LOGERR "Some statistic or Miniserver could not be fetched.";
		LOGERR "This is a partial output";
	}
	LOGINF "Fetched data";
	LOGINF "=================";
	LOGDEB "\n\n" . to_json( \%blocktypedata, {utf8 => 0, pretty => 1} ) . "\n\n";
	LOGEND;

}