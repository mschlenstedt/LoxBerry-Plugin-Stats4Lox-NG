#!/usr/bin/perl

use LoxBerry::System;

require "$lbpbindir/libs/Loxone/Stats4Lox.pm";

# Debug
$Stats4Lox::DEBUG = 0;

my ($code, %resp) = Stats4Lox::msget_value( 1, "a6da627a-6677-11e3-a77d9c3de0c5866d" );

print "Response Code is: $code\n";

foreach my $key (keys %resp) {
	print "Value of $key is: $resp{$key}\n";
}
