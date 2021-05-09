#!/usr/bin/perl
use warnings;
use strict;
use LoxBerry::System;
use LoxBerry::Log;
use LoxBerry::JSON;
use Time::HiRes qw(time);
use FindBin qw($Bin);
use lib "$Bin/../libs";
use Globals;
use Fcntl ':flock';

my $updatesignal_file = $Globals::s4ltmp."/update_dashboard_signal.tmp";

# Lock a file to make sure only one instance is running
my $lockfile = "/var/lock/update_dashboards.lock";
open my $lockfilefh, '>', $lockfile or die "CRITICAL Could not open LOCK file $lockfile: $!";
my $lock_success = flock $lockfilefh, LOCK_EX | LOCK_NB or die "CRITICAL $0 is already running";

my $log = LoxBerry::Log->new (
    name => 'Update_Dashboards',
	stderr => 1,
	loglevel => 7,
	addtime => 1
);

LOGSTART "Update Dashboards";

my $me = Globals::whoami();

# How long to wait for a dashboard job before terminating
my $timeout = 120; 
my $lastchange_timestamp = time();
my $delay_update = 2;

my %filelist;

while(time() < $lastchange_timestamp+$timeout) {

	# Check for a change
	my @changedfiles = getStatusChanges();
	
	# Extend time to keep the program open
	if( @changedfiles ) {
		$lastchange_timestamp = time();
	}
	
	# Set all changed files as not processed
	foreach( @changedfiles ){
		$filelist{$_}{processed} = 0;
	}
	
	# Wait until change is older than 2 seconds, and only process unprocessed files
	if( defined $filelist{$updatesignal_file}{mtime} and $filelist{$updatesignal_file}{mtime} < time()-$delay_update and $filelist{$updatesignal_file}{processed} == 0 ) {
		$filelist{$updatesignal_file}{processed} = updateDashboards();
	}
	
	sleep(1);

}

LOGEND "Finished after no work for $timeout seconds.";
exit;

sub updateDashboards
{

	require Grafana;
	# require GrafanaS4L;
	
	my $me = Globals::whoami();
	
	# Open and lock stats.json
	my $statsjsonobj = new LoxBerry::JSON;
	my $statsjson = $statsjsonobj->open( filename => $Globals::statsconfig, lockexclusive => 1, writeonclose => 0 );
	if (!$statsjson) {
		$log->DEB("$me ERROR Opening stats.json (empty)");
		return;
	}
	
	
	updateDefaultDashboard( $statsjson );
	
	
	$statsjsonobj->write();
	
	return 1;
	
}


sub updateDefaultDashboard
{
	
	my $statsjson = shift;
	
	
	###
	### Update the dashboard with the template - panels are kept by the lib function
	###
	LOGINF "Creating dashboard from dashboard template";
	my $dashboard = DashboardFromTemplate Grafana( 
		"$Globals::s4l_provisioning_dir/dashboards/defaultDashboard.json",
		"$Globals::s4l_provisioning_dir/templates/template_defaultDashboard.json"
	);
	$dashboard->{title} = "LoxBerry Stats4Lox";
	my $lbhostname = LoxBerry::System::lbhostname();
	if( ! $lbhostname ) {
		$lbhostname = LoxBerry::System::get_localip();
	}
	$dashboard->{links}->[0]->{url} = "http://".$lbhostname.":".LoxBerry::System::lbwebserverport()."/admin/plugins/".$LoxBerry::System::lbpplugindir."/index.cgi";
	my $dashboard_uid = Grafana->save( $dashboard );
	undef $dashboard;
	
	LOGOK "Dashboard created";
	
	# sleep 30;
	
	
	###
	### Loop stats.json and update the panels in the dashboard
	###
	
	foreach my $elementindex ( keys @{ $statsjson->{loxone} } ) {
		
		my $element = $statsjson->{loxone}[$elementindex];
		
		LOGINF "Processing $element->{name}";
		
		### Update the panels
		my %known_panel_ids;
		if( defined $element->{grafana}->{panels} ) {
			LOGDEB "Panels are defined - temporary store panel id's";
			%known_panel_ids = %{$element->{grafana}->{panels}};
		}
		LOGDEB "Locally deleting panels";
		delete $element->{grafana}->{panels};
		# As we don't know, if outputs got added or deleted, first we clear all panels of this stat
		# use Data::Dumper;
		# $LoxBerry::JSON::DEBUG=1;
		# print STDERR Dumper( \%known_panel_uids );
		
		my @ids_to_delete = values %known_panel_ids;
		# print STDERR Dumper( \@uids_to_delete );
		LOGDEB "Delete panels in dashboard (panel id's " . join(",", @ids_to_delete) . ")";
		deletePanelFromDashboard Grafana( 
			"$Globals::s4l_provisioning_dir/dashboards/defaultDashboard.json",
			\@ids_to_delete
		);
		LOGOK "Panels deleted from dashboard";
		
		# sleep 30;
		
		# Now, we recreate the panels from selected outputs and known lables, with known panel id's
		
		my %outputkeys_labels;
		
		@outputkeys_labels{ @{$element->{outputkeys}} } = @{$element->{outputlabels}};
		
		# my $panel_id = $panelcount;
		
		LOGINF "Recreating panels for every output";
		
		foreach my $output ( @{ $element->{outputs} } ) {
			
			my $panel_id;
			
			# Get array index of output from outputkeys 
			my $label = $outputkeys_labels{$output};
			next if(! defined $label); 
			
			if( defined $known_panel_ids{$label} ) {
				$panel_id = $known_panel_ids{$label};
			}
			
			LOGINF "Creating new panel for panelid $panel_id";
			
			my $panel = PanelFromTemplate Grafana( 
				"$Globals::s4l_provisioning_dir/dashboards/defaultDashboard.json",
				"$Globals::s4l_provisioning_dir/templates/template_panel_graph.json"
			);
			
			LOGINF "Panel template loaded";
			# sleep 30;
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
			
			LOGDEB "Panel id: $panel->{id}";
			LOGDEB "Panel title: $panel->{title}";
			
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
			
			LOGINF "Saving new panel to dashboard";
			$panel->{id} = int($panel->{id});
			$panel_id = Grafana->save( $panel );
			undef $panel;
			LOGOK "Panel saved, storing panel id to stats.json";
			$element->{grafana}->{panels}{$label} = $panel_id+0;
			
			# sleep 30;
			
			###############################
			# Save element back to statsobj
			###############################
		}
	}
	
	##############################
	# Sort panels in Dashboard
	##############################
	
	LOGINF "Sorting panels";
	$dashboard = modifyDashboard Grafana( 
		"$Globals::s4l_provisioning_dir/dashboards/defaultDashboard.json"
	);
	if( ! defined $dashboard ) {
		LOGERR "Dashboard is empty\n";
		return;
	}
	
	@{$dashboard->{panels}} = sort { $$a{title} cmp $$b{title} } @{ $dashboard->{panels} };
	
	my $panelcount = scalar @{$dashboard->{panels}};
	if( $panelcount > 0 ) {
		for my $panelkey ( 0 .. $panelcount-1 ) {
			$dashboard->{panels}[$panelkey]->{id} = $dashboard->{panels}[$panelkey]->{id}+0;
		}
	}
	LOGOK "Saved dashboard uid: " . Grafana->save( $dashboard ) . "\n";
	

return;
	
}














# Change tracking for stats.json
sub getStatusChanges 
{

	my @trackedfiles;
	my @changedfiles;
	
	# Read tracked files
	push @trackedfiles, $updatesignal_file;
	
	# Delete entries from local filelist hash that have been deleted on disk
	foreach my $file ( keys %filelist ) {
		if( !defined $filelist{$file} ) {
			delete $filelist{$file};
		}
	}
	
	# Check files for changes
	foreach my $file ( @trackedfiles ) {
		if( !defined $filelist{$file} ) {
			# New file
			$filelist{$file}{mtime} = (stat($file))[9];
			push @changedfiles, $file;
		}
		else {
			my $mtime = (stat($file))[9];
			if ( defined $mtime and $mtime > $filelist{$file}{mtime} ) {
				# Existing changed files
				$filelist{$file}{mtime} = $mtime;
				push @changedfiles, $file;
			}
		}
	}
	
	return @changedfiles;
}
