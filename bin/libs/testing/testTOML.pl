#!/usr/bin/perl
use warnings;
use strict;
use LoxBerry::System;
use LoxBerry::Log;
use FindBin qw($Bin);
use lib "$Bin/../../libs";
use Globals;
use Data::Dumper;


#use TOML::Tiny;
# Read Telegraf Loxone HTTP grabber config
#my $toml = from_toml( LoxBerry::System::read_file("$lbpconfigdir/telegraf/telegraf.d/stats4lox_loxone.conf") );
# my $http_timeout = trim($toml->{inputs}->{http}[0]->{interval});

### TOML::Tiny is too slow --> 0,4 sec to only load the library



use TOML::Parser;
my $tomlparser = TOML::Parser->new;
my $toml = $tomlparser->parse( LoxBerry::System::read_file("$lbpconfigdir/telegraf/telegraf.d/stats4lox_loxone.conf") );
my $http_timeout = trim($toml->{inputs}->{http}[0]->{interval});

print Dumper( $toml );

$http_timeout = convert_duration_interval( $http_timeout );



sub convert_duration_interval
{
	my $timestr = shift;
	$timestr =~ /(\d+)(\w+)/;
	my $timeval = $1;
	my $interval = $2;
	
	# Influx intervals:
	# https://github.com/influxdata/telegraf/blob/master/docs/CONFIGURATION.md#intervals
	
	if( $interval eq "ns") { $timeval /= 1000000000; }
	elsif( $interval eq "us" or $interval eq "µs") { $timeval /= 1000000; }
	elsif( $interval eq "ms") { $timeval /= 1000; }
	elsif( $interval eq "s") {  }
	elsif( $interval eq "m") { $timeval *= 60; }
	elsif( $interval eq "h") { $timeval *= 60*60; }
	elsif( $interval ne "") { undef $timeval; }
	
	return $timeval;

}

print "\nTimeout: $http_timeout\n";
