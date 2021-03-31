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
require "$lbpbindir/libs/Stats4Lox.pm";

my $log = LoxBerry::Log->new (
    name => 'Load_Stats',
	stderr => 1,
	loglevel => 7,
	addtime => 1
);
 
my $cgi = CGI->new;
my $q = $cgi->Vars;

my $msno = $q->{msno};
my $uuid = $q->{uuid};

# Status json
my $statusobj;
my $status;


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

LOGINF "Logfile: $log->{filename}";

getstatusfile();

my $import = new Loxone::Import(msno => $msno, uuid=> $uuid, log => $log);

my @statmonths = $import->getStatlist();
LOGDEB "Statlist $#statmonths elements.";
if( ! $#statmonths ) {
	LOGCRIT "Could not get Statistics list from Loxone Miniserver MS$msno";
	exit(2);
}


print Data::Dumper::Dumper( $import->{statlistAll} );

foreach my $yearmonth ( @statmonths ) {
	LOGINF "Fetching $import->{uuid} Month: $yearmonth";
	
	my $monthdata = $import->getMonthStat( yearmon => $yearmonth );
	# print STDERR Data::Dumper::Dumper( $monthdata ) . "\n";
	LOGINF "   Datasets " . scalar @{$monthdata->{values}};
	
	
	$import->submitData( $monthdata );
	
	
	
	
}


sub getstatusfile {
	
	# Creating state json
	$log->DEB("Loxone::Import->new: Creating status file");
	`mkdir -p $Globals::importstatusdir`;

	my $statusobj = new LoxBerry::JSON;
	my $status = $statusobj->open( filename => $Globals::importstatusdir."/import_${msno}_${uuid}.json", writeonclose => 1 );
	LOGINF "Status file: " . $statusobj->filename();

}
