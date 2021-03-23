#!/usr/bin/perl
use LoxBerry::System;
use LoxBerry::Log;
use LoxBerry::JSON;
use CGI;
use FindBin qw($Bin);
use lib "$Bin/..";
use Loxone::Import;

my $log = LoxBerry::Log->new (
    name => 'Load_Stats',
	stderr => 1,
	loglevel => 7
);
 
my $cgi = CGI->new;
my $q = $cgi->Vars;

my $msno = $q->{msno};
my $uuid = $q->{uuid};

# Validations
if( !defined $msno ) {
	LOGCRIT "msno parameter missing";
	exit(1);
}
if( !defined $uuid ) {
	LOGCRIT "uuid parameter missing";
	exit(1);
}
my %miniservers = LoxBerry::System::get_miniservers();
if( !defined $miniservers{$msno} ) {
	LOGCRIT "Miniserver $msno not defined";
	exit(1);
}

# my $statsjsonobj = new LoxBerry::JSON;
# my $statsjson = $statsjsonobj( filename => $Globals::statsconfig, readonly => 1 );
# if (!$statsjson) {
	# LOGCRIT "Could not read stats.json";
	# exit(1);
# }

my $import = new Loxone::Import(msno => $msno, uuid=> $uuid, log => $log);


my @statmonths = $import->getStatlist();
foreach my $yearmonth ( @statmonths ) {
	print STDERR "Fetching $import->{uuid} Month: $_\n";
	
	my $monthdata = $import->getMonthStat( yearmon => $yearmonth );

	print STDERR Dumper( $monthdata );
	
	
}




# my $statlist = Loxone::Import::enrichStatlist ( ms => $msno, statlist => $statlist, log => $log );

# my $statdata = Loxone::Import::getMonthStat( ms => $msno, log => $log, uuid => "154d4bb3-03cd-72ec-ffff4be94a2a77f6", yearmon => "202012" );

print Dumper( \@statmonths );
