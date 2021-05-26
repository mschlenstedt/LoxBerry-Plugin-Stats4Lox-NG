#!/usr/bin/perl
use LoxBerry::System;
use Data::Dumper;

require "$lbpbindir/libs/Globals.pm";

Globals::merge_config();

my @mainobjects = qw( stats4lox grafana influx loxberry loxone miniserver telegraf );

foreach my $mainobj ( @mainobjects ) {
	my $objvar = '$Globals::'.$mainobj;
	print "\n".uc($objvar)." ------> \n";
	eval 'print Dumper( '.$objvar. ')';
}
print "\n";
