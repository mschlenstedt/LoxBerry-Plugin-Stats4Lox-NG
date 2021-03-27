#!/usr/bin/perl

use LoxBerry::System;
use Data::Dumper;

require "$lbpbindir/libs/Stats4Lox.pm";

# Debug
$Stats4Lox::DEBUG = 0;

my ($code, $resp) = Stats4Lox::msget_value( 1, "a6da627a-6677-11e3-a77d9c3de0c5866d" );

print "Response Code is: $code\n\n";

my $i = "0";
foreach (@$resp) {
	print "=== $i. Dataset: ===\n";
	foreach $key ( keys %$_ ) {
		my $value = $_->{$key};
		print "Value of $key is: $value\n";
	}
	$i++;
}
