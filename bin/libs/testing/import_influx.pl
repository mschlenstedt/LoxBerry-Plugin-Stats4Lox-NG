#!/usr/bin/perl
use warnings;
use strict;
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

my $import = new Loxone::Import(msno => $msno, uuid=> $uuid, log => $log);

my @statmonths = $import->getStatlist();

print Data::Dumper::Dumper( $import->{statlistAll} );

foreach my $yearmonth ( @statmonths ) {
	print STDERR "Fetching $import->{uuid} Month: $yearmonth\n";
	
	my $monthdata = $import->getMonthStat( yearmon => $yearmonth );
	# print STDERR Data::Dumper::Dumper( $monthdata ) . "\n";
	print STDERR "   Datasets " . scalar @{$monthdata->{values}} . "\n";
	
	
}
