#!/usr/bin/perl
use warnings;
use strict;
use LoxBerry::System;
use LoxBerry::Log;
use FindBin qw($Bin);
use lib "$Bin/../../libs";
use Loxone::Import;
use Globals;
use Data::Dumper;


my $statfile = $ARGV[0];


my $log = LoxBerry::Log->new (
    name => 'Import_Stats',
	stderr => 1,
	loglevel => 7,
	addtime => 1
);
LOGSTART "Test Import $statfile";
LOGTITLE "Local Dry Import $statfile";
LOGWARN "THIS SCRIPT DOES NO IMPORT. It only parses the Loxone Statistics file for debugging.";
LOGINF "Statfile to use: $statfile\n";


my $filecontent = LoxBerry::System::read_file($statfile);

my $import = new_empty Loxone::Import(log => $log);
my $timedata = $import->parseStatXML_REGEX( yearmon => "202105", xml => \$filecontent );

LOGDEB Dumper(\$timedata);

LOGEND;
