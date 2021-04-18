#!/usr/bin/perl
use warnings;
use strict;
use LoxBerry::System;
use LoxBerry::JSON;
use FindBin qw($Bin);
use lib "$Bin/../libs";
use Globals;

my $stats4loxobj = LoxBerry::JSON->new();
my $stats4lox = $stats4loxobj->open(filename => $Globals::stats4loxconfig, lockexclusive => 1, writeonclose => 1 );

my $stats4loxcredentialsobj = LoxBerry::JSON->new();
my $stats4loxcredentials = $stats4loxcredentialsobj->open(filename => $Globals::stats4loxcredentials, readonly => 1 );

if( ! $stats4lox->{influx}->{grafana}->{dsuid} ) {
	$stats4lox->{influx}->{grafana}->{dsuid} = LoxBerry::System::trim(`cat /proc/sys/kernel/random/uuid`);
}


my $ds = <<"EOF";
apiVersion: 1

datasources:
- name: Stats4Lox
  type: influxdb
  access: proxy
  is_default: true
  orgId: 1
  database: $stats4lox->{influx}->{influxdatabase}
  basicAuth: true
  basicAuthUser: $stats4loxcredentials->{influx}->{influxdbuser}
  basicAuthPassword: $stats4loxcredentials->{influx}->{influxdbpass}
  url: $stats4lox->{influx}->{influxurl}
  uid: $stats4lox->{influx}->{grafana}->{dsuid}
  jsonData:
    httpMode: GET
    tlsSkipVerify: true
EOF

my $dsfile = $Globals::graf_provisioning_dir.'/datasources/stats4lox.yaml';
LoxBerry::System::write_file( $dsfile , $ds );
chmod 0770, $dsfile;
`chown loxberry:loxberry $dsfile`;
`sudo systemctl restart grafana-server`;

