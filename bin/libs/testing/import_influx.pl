#!/usr/bin/perl
use warnings;
use strict;
use LoxBerry::System;
use LoxBerry::Log;
use LoxBerry::JSON;
use CGI;
use Time::HiRes;
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
our $statusobj;
our $status;
our $statusfh;

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

eval {
	Loxone::Import::statusgetfile( msno=>$msno, uuid=>$uuid, log=>$log );
};
if( $@ ) {
	LOGCRIT "Cannot lock status file - already locked";
	exit(3);
}
# Initial status file update
supdate( { 
	status => "running",
	msno => $msno,
	uuid => $uuid,
	name => undef,
	pid => $$,
	starttime => time(),
	endtime => undef,
	current => undef,
	finished => { },
} );

my $import = new Loxone::Import(msno => $msno, uuid=> $uuid, log => $log);

supdate( { name => $import->{statobj}->{name} } );

my @statmonths = $import->getStatlist();
LOGDEB "Statlist $#statmonths elements.";
if( ! $#statmonths ) {
	LOGCRIT "Could not get Statistics list from Loxone Miniserver MS$msno";
	exit(2);
}


# print Data::Dumper::Dumper( $import->{statlistAll} );

foreach my $yearmonth ( @statmonths ) {
	supdate( { current => $yearmonth } );
	my $starttime = Time::HiRes::time();
	
	LOGINF "Fetching $import->{uuid} Month: $yearmonth";
	
	my $monthdata = $import->getMonthStat( yearmon => $yearmonth );
	# print STDERR Data::Dumper::Dumper( $monthdata ) . "\n";
	LOGINF "   Datasets " . scalar @{$monthdata->{values}};
	
	
	my $fullcount = $import->submitData( $monthdata );

	my %finished = (
		duration => int((Time::HiRes::time()-$starttime)*1000)/1000,
		count => $fullcount,
		timestampcount => scalar @{$monthdata->{values}},
		endtime => time()
	);	
	
	$status->{finished}{$yearmonth} = \%finished;
	supdate( { } );  

	
}

LOGOK "All month finished.";
supdate( { status=>"finished" });

exit(0);

sub END {
	if( $statusobj ) {
		if ( $status->{status} ne "finished" ) {
			supdate( { status => "error" } );
		}
		supdate( { endtime => time() } );
	}
}