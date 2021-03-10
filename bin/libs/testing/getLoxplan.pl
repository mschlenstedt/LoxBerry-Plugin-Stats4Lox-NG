#!/usr/bin/perl
use LoxBerry::System;
use LoxBerry::Log;

my $log = LoxBerry::Log->new (
    name => 'Loxplan_parsing',
	stderr => 1
);
 

require "../Loxone/GetLoxplan.pm";
require "../Loxone/ParseXML.pm";

my %miniservers = LoxBerry::System::get_miniservers();

foreach my $msno ( sort keys %miniservers ) {
	print STDERR "=== MS $msno =================\n";
	Loxone::GetLoxplan::getLoxplan( ms => $msno, log => $log );
	$Loxplanfile = "${Loxone::GetLoxplan::s4ltmp}/s4l_loxplan_ms$msno.Loxone";
	$Loxplanjson = "${Loxone::GetLoxplan::s4ltmp}/s4l_loxplan_ms$msno.json";
	if( -e $Loxplanfile ) {
		print STDERR "Loxplan for MS$msno found, parsing now...\n";
		my $loxplan = Loxone::ParseXML::loxplan2json( 
			filename => $Loxplanfile,
			output => $Loxplanjson,
			log => $log
		);
	}
	else {
		print STDERR "No Loxplan for MS$msno\n";
	}
}
