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

	# Outputs without the key/label mapping cannot become panels, and this has to
	# be caught BEFORE anything is deleted.
	#
	# The panel titles come from outputlabels, looked up by outputkeys. Without
	# them the loop below built nothing, but deletePanelFromDashboard had already
	# removed the existing panels - and then line "@outputkeys_labels{...}" died on
	# the undefined array reference, so stats.json was never written back either.
	# Result: the panels were gone from the dashboard, the configuration still
	# claimed they existed, and the caller answered with a webserver error page.
	# Reachable from ajax.cgi/updatestat, which only sets outputkeys and
	# outputlabels when its parameters are not empty.
	#
	# An element with no outputs at all is a different matter: there the panels
	# SHOULD go and none be created, so that case passes through.
	if( ref($element->{outputs}) eq 'ARRAY' and @{$element->{outputs}} ) {
		if(    ref($element->{outputkeys})   ne 'ARRAY'
		    or ref($element->{outputlabels}) ne 'ARRAY'
		    or !@{$element->{outputkeys}}
		    or scalar @{$element->{outputkeys}} != scalar @{$element->{outputlabels}} ) {
			print STDERR "provisionDashboard: " . ( $element->{name} // '?' )
			           . " has outputs but no usable outputkeys/outputlabels - dashboard left untouched\n";
			return undef;
		}
	}

	### Update the dashboard
	my $dashboard = DashboardFromTemplate Grafana( 
		"$Globals::grafana->{s4l_provisioning_dir}/dashboards/defaultDashboard.json",
		"$Globals::grafana->{s4l_provisioning_template_dir}/template_defaultDashboard.json"
	);
	$dashboard->{title} = "LoxBerry Stats4Lox";
	my $lbhostname = LoxBerry::System::lbhostname();
	if( ! $lbhostname ) {
		$lbhostname = LoxBerry::System::get_localip();
	}
	$dashboard->{links}->[0]->{url} = "http://".$lbhostname.":".LoxBerry::System::lbwebserverport()."/admin/plugins/".$LoxBerry::System::lbpplugindir."/index.cgi";
	my $dashboard_uid = Grafana->save( $dashboard );
	undef $dashboard;
	
	### Update the panels
	my %known_panel_ids;
	if( defined $element->{grafana}->{panels} ) {
		%known_panel_ids = %{$element->{grafana}->{panels}};
	}
	delete $element->{grafana}->{panels};
	# As we don't know, if outputs got added or deleted, first we clear all panels of this stat
	# use Data::Dumper;
	# $LoxBerry::JSON::DEBUG=1;
	# print STDERR Dumper( \%known_panel_uids );
	
	my @ids_to_delete = values %known_panel_ids;
	# print STDERR Dumper( \@uids_to_delete );
	deletePanelFromDashboard Grafana( 
		"$Globals::grafana->{s4l_provisioning_dir}/dashboards/defaultDashboard.json",
		\@ids_to_delete
	);
	
	# Now, we recreate the panels from selected outputs and known lables, with known panel id's
	
	my %outputkeys_labels;

	if( ref($element->{outputkeys}) eq 'ARRAY' and ref($element->{outputlabels}) eq 'ARRAY' ) {
		@outputkeys_labels{ @{$element->{outputkeys}} } = @{$element->{outputlabels}};
	}
	
	# my $panel_id = $panelcount;
	
	foreach my $output ( @{ $element->{outputs} } ) {
		my $panel_id;
		
		# Get array index of output from outputkeys 
		my $label = $outputkeys_labels{$output};
		next if(! defined $label); 
		
		if( defined $known_panel_ids{$label} ) {
			$panel_id = $known_panel_ids{$label};
		}
		my $panel = PanelFromTemplate Grafana( 
			"$Globals::grafana->{s4l_provisioning_dir}/dashboards/defaultDashboard.json",
			"$Globals::grafana->{s4l_provisioning_template_dir}/template_panel_graph.json"
		);
		
		##
		## Fill Panel data with content
		##
		
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
		$panel->{id} = $panel_id if( defined $panel_id );
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
		
		$panel_id = Grafana->save( $panel );
		$element->{grafana}->{panels}{$label} = $panel_id;
		undef $panel;
		
		
		
		
	}

		##############################
		# Sort panels in Dashboard
		##############################
		
		# LOGINF "Sorting panels";
		$dashboard = modifyDashboard Grafana( 
			"$Globals::grafana->{s4l_provisioning_dir}/dashboards/defaultDashboard.json"
		);
		if( ! defined $dashboard ) {
			# LOGERR "Dashboard is empty\n";
			return;
		}
	
		@{$dashboard->{panels}} = sort { $$a{title} cmp $$b{title} } @{ $dashboard->{panels} };
	
		my $panelcount = scalar @{$dashboard->{panels}};
		if( $panelcount > 0 ) {
			for my $panelkey ( 0 .. $panelcount-1 ) {
				$dashboard->{panels}[$panelkey]->{id} = $dashboard->{panels}[$panelkey]->{id}+0;
			}
		}
	
		# LOGOK "Saved dashboard uid: " . Grafana->save( $dashboard ) . "\n";
		Grafana->save( $dashboard );
	
}

#####################################################
# Finally 1; ########################################
#####################################################
1;
