#!/usr/bin/perl

use LoxBerry::System;

require "../Stats4Lox.pm";

# Debug
$Stats4Lox::DEBUG = 1;

my @data;

my %influxrecord = (
		timestamp => '',
		msno => '1',
		uuid => '11111-11111-11111-1111',
		name => 'Das ist mein Name',
		category => 'Heizung',
		room => 'Keller',
		type => 'Output',
	);

my @values;
push @values, { key => 'output1', value => 1 };
push @values, { key => 'output2', value => 2 };
push @values, { key => 'output3', value => 3 };
push @values, { key => 'output4', value => 4 };
push @values, { key => 'output5', value => 5 };

$influxrecord{values} = \@values;

push @data, \%influxrecord;

my $nosend = "0";

my (@response) = Stats4Lox::lox2telegraf( \@data, $nosend );

