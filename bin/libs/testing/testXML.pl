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

### Loxone XML correction
my $startpos = 0;

while( ( my $foundpos = index( $xmlstr, '<C Type="LoxAIR"', $startpos ) ) != -1 ) {
	# print "Found: $foundpos Startpos $startpos Character: ". substr( $xmlstr, $foundpos, 1 ) . "\n";
	$startpos = $foundpos+1;
	# Finding closing tag >
	my $endpos = index( $xmlstr, '>', $foundpos );
	# print "Closing: $endpos Character: ". substr( $xmlstr, $endpos, 1 ) . "\n";
	# Get full tag
	my $tagstr = substr( $xmlstr, $foundpos+1, $endpos-$foundpos-1 );
	# print "Content: $tagstr\n";
	
	# my @attributes = split( /\s+=(?<=")\s+(?=")/g, $tagstr );
	
	# Split line by blank but without blanks inside of doublequotes
	my @attributes = $tagstr =~ m/((?:" [^"]* "|[^\s"]*)+)/gx;
	
	# print "Attributes: \n";
	# print join( "\n->", @attributes) . "\n";
	
	my @newattributeArray;
	my %uniquenesshash;
	my $duplicates = 0;
	foreach my $fullattribute ( @attributes ) { 
		next if (! $fullattribute);
		my ($attribute, $value) = split( "=", $fullattribute, 2);
		if( defined $uniquenesshash{$attribute} ) {
			$duplicates += 1;
			next;
		}
		$uniquenesshash{$attribute} = 1;
		push @newattributeArray, $fullattribute;
	}	
	
	if( $duplicates ) {
		my $newattribute = join( ' ', @newattributeArray );
		print "New attribute:\n$newattribute\n";
		
		# Replace the old attributes by the new attributes
		substr( $xmlstr, $foundpos+1, $endpos-$foundpos-1, $newattribute );
		LOGWARN "Replaced $duplicates duplicate attributes\n";
	}
	
}





my $lox_xml;

my %parseroptions = (
	# recover => 1
);

eval {
	$lox_xml = XML::LibXML->load_xml( string => $xmlstr, \%parseroptions );
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
