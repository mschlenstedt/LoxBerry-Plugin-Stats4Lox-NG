#!/usr/bin/perl
use LoxBerry::System;
use LoxBerry::Log;

my $log = LoxBerry::Log->new (
    name => 'Loxplan_parsing',
	stderr => 1,
	loglevel => 7
);
 

require "../Loxone/GetLoxplan.pm";
require "../Loxone/ParseXML.pm";

my %miniservers = LoxBerry::System::get_miniservers();

foreach my $msno ( sort keys %miniservers ) {
	print STDERR "=== MS $msno =================\n";
	
	$Loxplanfile = "$s4ltmp/s4l_loxplan_ms$msno.Loxone";
	# $Loxplanjson = "${Loxone::GetLoxplan::s4ltmp}/s4l_loxplan_ms$msno.json";
	$Loxplanjson = "$lbpdatadir/ms$msno.json";
	
	my $remoteTimestamp;
	eval {
		$remoteTimestamp = Loxone::GetLoxplan::checkLoxplanUpdate( $msno, $Loxplanjson );
	};
	if( $@ or $remoteTimestamp ne "" ) {
		print STDERR "Loxplan file not up-to-date. Fetching from Miniserver\n";
		Loxone::GetLoxplan::getLoxplan( ms => $msno, log => $log );
	} else {
		print STDERR "Loxplan file is up-to-date. Using local copy\n";
	}
	
	if( -e $Loxplanfile ) {
		print STDERR "Loxplan for MS$msno found, parsing now...\n";
		my $loxplan = Loxone::ParseXML::loxplan2json( 
			filename => $Loxplanfile,
			output => $Loxplanjson,
			log => $log,
			remoteTimestamp => $remoteTimestamp
		);
	}
	else {
		print STDERR "No Loxplan for MS$msno\n";
	}
}
