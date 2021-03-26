#!/usr/bin/perl

use LoxBerry::System;

require "$lbpbindir/libs/Stats4Lox.pm";

# Debug
$Stats4Lox::DEBUG = 0;

# Tags as hash
my %tags = (
	'tag1'  => 'This is tag 1',
	'tag 2' => 'This is tag 2 with spaces',
	'tag3'  => 'This is tag 3'
);

# Fields as hash
my %fields = (
	'field1'  => '10',
	'field 2' => '20i', # integer, field with spaces
	'field3'  => 'A String' # string
);

# Measurement
my $measurement = "Daten Measurement";

# Timestamp in nanoseconds (use undef for current timestamp)
my $timestamp = time() * 1000 * 1000;

my ($line) = Stats4Lox::influx_lineprot( $timestamp, $measurement, \%tags, \%fields );

print "This is the line to send to InfluxDB:\n";
print "$line\n";
