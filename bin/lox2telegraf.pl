#!/usr/bin/perl
use warnings;
use strict;
use LoxBerry::System;
use LoxBerry::JSON;
use FindBin qw($Bin);
use lib "$Bin/libs";
use Globals;
use Stats4Lox;

my $args = join(" ", @ARGV);
my $dataobj;
my $data;
my $filename;

if( -e $args ) {
	print STDERR "Using data file $args\n";
	$filename = $args;
	$dataobj = LoxBerry::JSON->new();
	$data = $dataobj->open(filename => $filename, lockexclusive => 1, locktimeout => 5);
	
	use Data::Dumper;
	print Dumper( $data );

} 
else {
	eval {
		$data = from_json( $args );
	};
	if( $@ ) {
		print "ERROR: File does not exist, and parameters is not valid JSON\n\n";
		help();
	}
	if( ref($data) eq "HASH") {
		$data = [ $data ];
	}
}

# Process data

	
print STDERR "Processing data...\n";

my ($result) = Stats4Lox::lox2telegraf( $data );
print "Result of lox2telegraf: $result\n";
if( $result == 0 and $filename ) {
	unlink $filename;
}
	



exit($result);



sub help {
	print "Usage:\n";
	print "$0 jsonfilename.json        Read the json data file and process it\n";
	print "$0 { jsondata }             Deliver single json record by commandline \n";
	print "$0 [ {record1},{record2} ]  Deliver multiple json records by commandline as array\n";
	print "\n";
	exit(1);
}
