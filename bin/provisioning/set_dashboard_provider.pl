#!/usr/bin/perl
use warnings;
use strict;
use LoxBerry::System;
use LoxBerry::JSON;
use FindBin qw($Bin);
use lib "$Bin/../libs";
use Globals;

my $provdir = $Globals::grafana->{s4l_provisioning_dir}.'/dashboards';

my $db = <<"EOF";
apiVersion: 1

providers:
- name: Stats4Lox
  orgId: 1
  folder: 'Stats4Lox Dynamic'
  folderUid: ''
  type: file
  disableDeletion: false
  updateIntervalSeconds: 10
  allowUiUpdates: false
  options:
    path: $provdir
EOF

my $dsfile = $Globals::grafana->{graf_provisioning_dir}.'/dashboards/stats4lox.yaml';
LoxBerry::System::write_file( $dsfile , $db );
chmod 0770, $dsfile;
chmod 0770, $Globals::grafana->{graf_provisioning_dir};
`chown loxberry:loxberry $dsfile`;
`sudo systemctl restart grafana-server`;

