#!/usr/bin/perl
use LoxBerry::System;
use LoxBerry::Log;
use LoxBerry::IO;
use JSON;

my $log = LoxBerry::Log->new (
    name => 'Loxplan_parsing',
	stderr => 1,
	loglevel => 7
);
 
LOGSTART "getLoxplan";

require "../Loxone/GetLoxplan.pm";
require "../Loxone/ParseXML.pm";

$log->INF("Querying Miniservers from LoxBerry");
my %miniservers = LoxBerry::System::get_miniservers();

## Get Serials of Miniservers
## Serials are used for matching of LoxBerry MSNO to "real" Miniservers in LoxPlan
my %ms_serials;
foreach my $msno ( keys %miniservers ) {
	$log->INF("Checking MS$msno");
	if( $miniservers{$msno}{UseCloudDNS} and $miniservers{$msno}{CloudURL} ) {
		# CloudDNS has serial defined in LoxBerry
		$ms_serials{$msno} = uc( $miniservers{$msno}{CloudURL} );
		$log->OK("MS $msno: Locally stored serial:  $ms_serials{$msno}");
		next;
	}
	
	# Fetch serial from Miniserver
	my ($response) = LoxBerry::IO::mshttp_call2($msno, "/jdev/cfg/mac");
	# print STDERR $response;
	eval {
		my $responseobj=JSON::from_json( $response );
		my $sn = $responseobj->{LL}->{value};
		$sn =~ tr/://d;
		$ms_serials{$msno} = uc( $sn );
	};
	if( $@ ) {
		$log->ERR("Could not aquire MAC from Miniserver $msno: $@");
		next;
	}
	$log->OK("MS$msno: Aquired serial from MS: $ms_serials{$msno}");
}


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
			remoteTimestamp => $remoteTimestamp,
			ms_serials => \%ms_serials
		);
	}
	else {
		print STDERR "No Loxplan for MS$msno\n";
	}
}
