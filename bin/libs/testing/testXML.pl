#!/usr/bin/perl
use warnings;
use strict;
use LoxBerry::System;
use LoxBerry::Log;
use XML::LibXML;
use FindBin qw($Bin);
use lib "$Bin/../../libs";
use Loxone::ParseXML;
use Globals;
use Data::Dumper;

my $Loxplanfile = $ARGV[0];

if( !$ARGV[0] ) {
	print "Tries to load a local XML (e.g. Loxplan XML) into the XML parser.\n";
	print "It does NOT parse anything, but simply tries to load and validate the XML.\n";
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
	addtime => 1,
	nofile => 1
);

my $xmlstr = LoxBerry::System::read_file($Loxplanfile);
# LoxPLAN uses a BOM, that cannot be handled by the XML Parser
my $UTF8_BOM = chr(0xef) . chr(0xbb) . chr(0xbf);
if(substr( $xmlstr, 0, 3) eq $UTF8_BOM) {
	$log->INF("Removing BOM of LoxPLAN input");
	$xmlstr = substr $xmlstr, 3;
}
$xmlstr = Encode::encode("utf8", $xmlstr);

my $lox_xml;
eval {
	$lox_xml = XML::LibXML->load_xml( string => $xmlstr );
};
if( $@ ) {
	my $exception = $@;
	LOGERR "XML Exception:";
	LOGDEB "\n$exception";
}
else {
	LOGOK "Finished - no XML exception";
}

LOGEND;
