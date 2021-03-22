#!/usr/bin/perl
use LoxBerry::System;
use LoxBerry::Log;
use Data::Dumper;

my $log = LoxBerry::Log->new (
    name => 'Load_Stats',
	stderr => 1,
	loglevel => 7
);
 

require "../Loxone/Import.pm";

my %miniservers = LoxBerry::System::get_miniservers();

# foreach my $msno ( sort keys %miniservers ) {
	
# }

my $msno = 2;
# my $statlist = Loxone::Import::getStatlist( ms => $msno, log => $log );
# my $statlist = Loxone::Import::enrichStatlist ( ms => $msno, statlist => $statlist, log => $log );

my $statdata = Loxone::Import::getMonthStat( ms => $msno, log => $log, uuid => "154d4bb3-03cd-72ec-ffff4be94a2a77f6", yearmon => "202012" );

print Dumper( $statdata );
