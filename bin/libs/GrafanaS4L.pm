#!/usr/bin/perl

use warnings;
use strict;
use LoxBerry::System;

#### GRAFANA Stats4Lox Provisioning ####
## This module fills in conrete details to dashboards and panels, including the Grafana queries for Stats4Lox
## The other module, Grafana.pm, is a generic Grafana Provisioning module to create/modify Grafana Dashboards and Templates


package GrafanaS4L;


###########################
#### Provisioning Grafana
###########################
sub provisionDashboard {
	require Grafana;
	my $element = shift;
	
	### Update the dashboard
	my $dashboard = DashboardFromTemplate Grafana( 
		"$Globals::s4l_provisioning_dir/dashboards/defaultDashboard.json",
		"$Globals::s4l_provisioning_dir/templates/template_defaultDashboard.json"
	);
	$dashboard->{title} = "LoxBerry Stats4Lox";
	my $dashboard_uid = Grafana->save( $dashboard );
	
	# Get number of panels
	my $panelcount = scalar @{ $dashboard->{panels} };
	
	undef $dashboard;
	
	### Update the panels
	my %known_panel_uids;
	if( defined $element->{grafana}->{panels} ) {
		%known_panel_uids = %{$element->{grafana}->{panels}};
	}
	delete $element->{grafana}->{panels};
	# As we don't know, if outputs got added or deleted, first we clear all panels of this stat
	# use Data::Dumper;
	# $LoxBerry::JSON::DEBUG=1;
	# print STDERR Dumper( \%known_panel_uids );
	
	my @uids_to_delete = values %known_panel_uids;
	# print STDERR Dumper( \@uids_to_delete );
	deletePanelFromDashboard Grafana( 
		"$Globals::s4l_provisioning_dir/dashboards/defaultDashboard.json",
		\@uids_to_delete
	);
	
	# Now, we recreate the panels from selected outputs and known lables, with known panel uid's
	
	my %outputkeys_labels;
	
	@outputkeys_labels{ @{$element->{outputkeys}} } = @{$element->{outputlabels}};
	
	my $panel_id = $panelcount;
	
	foreach my $output ( @{ $element->{outputs} } ) {
		my $panel_uid;
		
		# Get index of output from outputkeys 
		my $label = $outputkeys_labels{$output};
		next if(!$label); 
		
		if( defined $known_panel_uids{$label} ) {
			$panel_uid = $known_panel_uids{$label};
		}
		my $panel = PanelFromTemplate Grafana( 
			"$Globals::s4l_provisioning_dir/dashboards/defaultDashboard.json",
			"$Globals::s4l_provisioning_dir/templates/template_panel_graph.json"
		);
		
		##
		## Fill Panel data with content
		##
		
		$panel->{uid} = $panel_uid if($panel_uid);
		$panel_id++;
		$panel->{id} = $panel_id;
		
		my $paneltitle = $element->{description} ? $element->{description} : $element->{name};
		$paneltitle .= " $label";
	
		if( $element->{room} or $element->{category} ) {
			$paneltitle .= ' (';
			$paneltitle .= $element->{room} if $element->{room};
			$paneltitle .= ' / ' if( $element->{room} and $element->{category} );
			$paneltitle .= $element->{category} if $element->{category};
			$paneltitle .= ')';
		}	
		$panel->{title} = $paneltitle;
		
		$panel->{description} = defined $element->{type} ? $element->{type} : "";
		
		
		
		# 
		# target array
		#
		
		my $target = $panel->{targets}->[0];
		
		$target->{measurement} = $element->{measurementname};
		$target->{refId} = LoxBerry::System::trim($paneltitle);
		@{ $target->{select}[0][0]->{params} } = ( $label );
		
		
		
		#################
		# Save the panel
		#################
		
		$panel_uid = Grafana->save( $panel );
		$element->{grafana}->{panels}{$label} = $panel_uid;
		
	}
	
}

#####################################################
# Finally 1; ########################################
#####################################################
1;
