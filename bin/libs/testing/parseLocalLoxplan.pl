#!/usr/bin/perl
use warnings;
use strict;
use LoxBerry::System;
use LoxBerry::Log;
use FindBin qw($Bin);
use lib "$Bin/../../libs";
use Loxone::ParseXML;
use Globals;
use Data::Dumper;

my $Loxplanfile = $ARGV[0];

if( !$ARGV[0] ) {
	print "Parses a local Loxplan XML file and creates a json file, that is used by Stats4Lox Webinterface\n";
	print "Calling Syntax:\n";
	print " $0 myloxplan.loxone\n";
	exit(1);
}

if ( ! -e $ARGV[0] ) {
	print "File $ARGV[0] does not exist.\n";
	exit(1);
}

my $log = LoxBerry::Log->new (
    name => 'Parse_Loxplan',
	stderr => 1,
	loglevel => 7,
	addtime => 1
);
LOGSTART "Test Parsing $Loxplanfile";
LOGTITLE "Local Parsing of Loxplan $Loxplanfile";
LOGINF "Loxplan file to use: $Loxplanfile\n";

my $loxplan = Loxone::ParseXML::loxplan2json( 
			filename => $Loxplanfile,
			output => $Loxplanfile.".json",
			log => $log,
			# remoteTimestamp => $remoteTimestamp
);

LOGOK "Output is written to $Loxplanfile.json";

LOGEND;
