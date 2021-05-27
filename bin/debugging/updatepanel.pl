#!/usr/bin/perl
use warnings;
use strict;
use LoxBerry::System;
use FindBin qw($Bin);
use lib "$Bin/../libs";
use Globals;
use Grafana;

my $dashboard = DashboardFromTemplate Grafana( 
	"$Globals::grafana->{s4l_provisioning_dir}/dashboards/defaultDashboard.json",
	"$Globals::grafana->{s4l_provisioning_dir}/templates/template_defaultDashboard.json"
);


$dashboard->{title} = "LoxBerry Stats4Lox " . int(rand(100));
$dashboard->{links}[0]->{url} = lbhostname();
print $dashboard->{title} . "\n";
my $dashboard_uid = Grafana->save( $dashboard );

my $panel = PanelFromTemplate Grafana( 
	"$Globals::grafana->{s4l_provisioning_dir}/dashboards/defaultDashboard.json",
	"$Globals::grafana->{s4l_provisioning_dir}/templates/template_panel_graph.json"
);

$panel->{title} = "Panel Title (Room/Category)" . int(rand(100));

my $panel_uid = Grafana->save( $panel );

print STDERR "Dashboard UID: $dashboard_uid Panel UID: $panel_uid\n";

my $delcount = deletePanelFromDashboard Grafana( 
	"$Globals::grafana->{s4l_provisioning_dir}/dashboards/defaultDashboard.json",
	$panel_uid
);

$delcount = deletePanelFromDashboard Grafana( 
	"$Globals::grafana->{s4l_provisioning_dir}/dashboards/defaultDashboard.json",
	[ $panel_uid, "aaabbb" ]
);


print STDERR "Panels deleted: $delcount\n";