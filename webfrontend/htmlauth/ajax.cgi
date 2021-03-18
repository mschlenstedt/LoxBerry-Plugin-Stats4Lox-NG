#!/usr/bin/perl
use warnings;
use strict;
use LoxBerry::System;
use LoxBerry::Log;
use CGI;
use JSON;
use FindBin qw($Bin);
use lib "$Bin/../../../../bin/plugins/stats4lox-ng/libs/";
use Globals;

my $error;
my $response;
my $cgi = CGI->new;
my $q = $cgi->Vars;

my $log = LoxBerry::Log->new (
    name => 'AJAX',
	stderr => 1,
	loglevel => 7
);


if( $q->{action} eq "getloxplan" ) {
	require Loxone::GetLoxplan;
	require Loxone::ParseXML;
	
	my %miniservers = LoxBerry::System::get_miniservers();
	
	if( ! defined $miniservers{$q->{msno}} ) {
		$error = "Miniserver not defined";
	}
	else {
		my $msno = $q->{msno};
		my $Loxplanfile = "$s4ltmp/s4l_loxplan_ms$msno.Loxone";		
		my $loxplanjson = "$loxplanjsondir/ms".$msno.".json";
		my $remoteTimestamp;
		eval {
			$remoteTimestamp = Loxone::GetLoxplan::checkLoxplanUpdate( $msno, $loxplanjson );
		};
		if( $@ or $remoteTimestamp ne "" ) {
			print STDERR "Loxplan file not up-to-date. Fetching from Miniserver\n";
			Loxone::GetLoxplan::getLoxplan( 
				ms => $msno, 
				log => $log 
			);
			
			if( -e $Loxplanfile ) {
				print STDERR "Loxplan for MS$msno found, parsing now...\n";
				my $loxplan = Loxone::ParseXML::loxplan2json( 
					filename => $Loxplanfile,
					output => $loxplanjson,
					log => $log,
					remoteTimestamp => $remoteTimestamp
				);
			}
			
		} else {
			print STDERR "Loxplan file is up-to-date. Using local copy\n";
		}
		
		if( -e $loxplanjson) { 
			$response = LoxBerry::System::read_file($loxplanjson);
		} else {
			$response = '{ "error":"Could not fetch Loxone Config of MS No. '.$msno.'"}';
		}
	
	}
	
}

if( $q->{action} eq "getstatsconfig" ) {
	if ( -e $statsconfig ) {
		$response = LoxBerry::System::read_file($statsconfig);
	}
	else {
		$response = "{ }";
	}
}

if( $q->{action} eq "updatestat" ) {
	require LoxBerry::JSON;
	my $jsonobjcfg = LoxBerry::JSON->new();
	my $cfg = $jsonobjcfg->open(filename => $statsconfig);
	my @searchresult = $jsonobjcfg->find( $cfg->{loxone}, "\$_->{uuid} eq \"".$q->{uuid}."\"" );
	my $elemKey = $searchresult[0];
	my $element = $cfg->{loxone}[$elemKey] if( defined $elemKey );
	
	my @outputs;
	if ( defined $q->{outputs} ) {
		@outputs = split(",", $q->{outputs});
	}
	
	my %updatedelement = (
		name => $q->{name},
		description => $q->{description},
		uuid => $q->{uuid},
		type => $q->{type},
		category => $q->{category},
		room => $q->{room},
		interval => int($q->{interval}) ne "NaN" ? $q->{interval}*60 : 0,
		active => defined $q->{active} ? $q->{active} : "false",
		msno => $q->{msno},
		outputs => \@outputs,
		url => '/jdev/sps/io/'.$q->{uuid}.'/all'
	);
	
	# Validation
	my @errors;
	push @errors, "name must be defined" if( ! $updatedelement{name} );
	push @errors, "uuid must be defined" if( ! $updatedelement{uuid} );
	push @errors, "msno must be defined" if( ! $updatedelement{msno} );
	push @errors, "url must be defined" if( ! $updatedelement{url} );
	push @errors, "active must be defined" if( ! $updatedelement{active} );

	
	# Insert/Update element in stats array
	if( defined $element ) {
		# This is an update of an existing element
		$cfg->{loxone}[$elemKey] = \%updatedelement;
	} 
	else {
		# Add a new entry to stats.json
		push @{$cfg->{loxone}}, \%updatedelement;
	}
	
	if( ! @errors ) {
		# The changes are valid
		$jsonobjcfg->write();
		undef $jsonobjcfg;
		$response = "{ }";
	}
	else {
		# The element is invalid
		$error = "Invalid input data: " . join(". ", @errors);
	}
	
}
	
if( $q->{action} eq "lxlquery" ) {
	require LoxBerry::IO;
	require JSON;
	my $url = '/jdev/sps/io/'.$q->{uuid}.'/all';
	my (undef, $code, $resp) = LoxBerry::IO::mshttp_call($q->{msno}, $url);
	
	my $respobj;
	my $jsonerror;
	eval {
		$respobj = decode_json($resp);
	};
	if( $@ ) {
		$jsonerror = $@;
		$respobj = $resp;
	}
	
	my %response = (
		msno => $q->{msno},
		uuid => $q->{uuid},
		code => $code,
		response => $respobj,
		error => $jsonerror
	);
	$response = encode_json( \%response );
}




if( defined $response and $error eq "" ) {
	print "Status: 200 OK\r\n";
	print "Content-type: application/json\r\n\r\n";
	print $response;
}
elsif ( $error ne "" ) {
	print "Status: 500 Internal Server Error\r\n";
	print "Content-type: application/json\r\n\r\n";
	print to_json( { error => $error } );
}
else {
	print "Status: 501 Not implemented\r\n";
	print "Content-type: application/json\r\n\r\n";
	$error = "Action ".$q->{action}." unknown";
	print to_json( { error => $error } );
}
