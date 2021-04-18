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



my $ds = <<"EOF";
apiVersion: 1

deleteDatasources:
- name: Stats4Lox
  orgId: 1
EOF

my $dsfile = $Globals::graf_provisioning_dir.'/datasources/stats4lox.yaml';
LoxBerry::System::write_file( $dsfile , $ds );
chmod 0770, $dsfile;
`chown loxberry:loxberry $dsfile`;
`sudo systemctl restart grafana-server`;

