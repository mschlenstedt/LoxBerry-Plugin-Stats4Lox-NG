#!/usr/bin/perl

use warnings;
use strict;
use LoxBerry::System;
use LoxBerry::JSON;

#### GRAFANA ####

package Grafana;

sub DashboardFromTemplate {
	my $class = shift;
	my $dashboard_file = shift;
	my $dashboardtemplate_file = shift;
	
	my $self = {};
	# bless $self, $class;
	
	$self->{_dashboardobj} = new LoxBerry::JSON;
	$self->{_dashboard} = $self->{_dashboardobj}->open( filename => $dashboard_file, writeonclose => 0, lockexclusive => 1 ) or die "Could not open dashboard file\n";
	
	$self->{_templateobj} = new LoxBerry::JSON;
	my $template = $self->{_templateobj}->open( filename => $dashboardtemplate_file, readonly => 1 ) or die "Could not open dashboard template file\n";
	
	$self->{_function} = "DashboardFromTemplate";
	
	$template->{_packageGrafana} = $self;
	
	return $template;
}

sub PanelFromTemplate {
	my $class = shift;
	my $dashboard_file = shift;
	my $paneltemplate_file = shift;
	
	my $self = {};
	# bless $self, $class;
	
	$self->{_dashboardobj} = new LoxBerry::JSON;
	$self->{_dashboard} = $self->{_dashboardobj}->open( filename => $dashboard_file, writeonclose => 0, lockexclusive => 1 ) or die "Could not open dashboard file\n";
	
	$self->{_templateobj} = new LoxBerry::JSON;
	my $template = $self->{_templateobj}->open( filename => $paneltemplate_file, readonly => 1 ) or die "Could not open panel template file\n";
	
	$self->{_function} = "PanelFromTemplate";
	
	$template->{_packageGrafana} = $self;
	
	return $template;
}

sub deletePanelFromDashboard {
	my $class = shift;
	my $dashboard_file = shift;
	my $panel_uids = shift;
	
	print STDERR "panel_uids is " . ref($panel_uids) . "\n";
	if( ref($panel_uids) eq "" ) {
		$panel_uids = [ $panel_uids ];
		print STDERR "panel_uids now is " . ref($panel_uids) . "\n";
	}
	
	if( !$panel_uids ) {
		die "deletePanelFromDashboard requires a valid uid parameter";
	}
	
	my $self = {};
	
	$self->{_dashboardobj} = new LoxBerry::JSON;
	$self->{_dashboard} = $self->{_dashboardobj}->open( filename => $dashboard_file, writeonclose => 0, lockexclusive => 1 ) or die "Could not open dashboard file\n";
	
	my $deleted = 0;
	foreach my $panel_uid ( @{$panel_uids} ) {
		print STDERR "Deleting $panel_uid\n";
		my @panelsWithUid = $self->{_dashboardobj}->find($self->{_dashboard}->{panels}, "\$_->{uid} eq '".$panel_uid."'");
		next if( !@panelsWithUid );
		foreach( @panelsWithUid ) {
			$deleted++;
			delete $self->{_dashboard}->{panels}[$_];
		}
	}
	$self->{_dashboardobj}->write();
	return $deleted;

}

sub deleteAllPanelsFromDashboard {
	my $class = shift;
	my $dashboard_file = shift;
	
	my $self = {};
	
	$self->{_dashboardobj} = new LoxBerry::JSON;
	$self->{_dashboard} = $self->{_dashboardobj}->open( filename => $dashboard_file, writeonclose => 0, lockexclusive => 1 ) or die "Could not open dashboard file\n";
	
	$self->{_dashboard}->{panels} = ();
	
	$self->{_dashboardobj}->write();
	return;
	
}

sub modifyDashboard {
	my $class = shift;
	my $dashboard_file = shift;
	
	my $self = {};
	# bless $self, $class;
	
	$self->{_dashboardobj} = new LoxBerry::JSON;
	my $dashboard = $self->{_dashboardobj}->open( filename => $dashboard_file, writeonclose => 0, lockexclusive => 1 ) or die "Could not open dashboard file\n";
	
	$self->{_function} = "modifyDashboard";
	
	$dashboard->{_packageGrafana} = $self;
	
	return $self->{_dashboard};
	
}


sub modifyPanel {
	my $class = shift;
	my $dashboard_file = shift;
	my $panel_uid = shift;
	
	if( !$panel_uid ) {
		die "modifyPanel requires a valid uid parameter";
	}
	
	my $self = {};
	
	$self->{_dashboardobj} = new LoxBerry::JSON;
	$self->{_dashboard} = $self->{_dashboardobj}->open( filename => $dashboard_file, writeonclose => 0, lockexclusive => 1 ) or die "Could not open dashboard file\n";
	
	my @panelsWithUid = $self->{_dashboardobj}->find($self->{_dashboard}->{panels}, "\$_->{uid} eq '".$panel_uid."'");
	
	if( !@panelsWithUid ) {
		die "Panel with uid $panel_uid does not exist";
	}
	$self->{_panelKey} = $panelsWithUid[0];
	my $panel = $self->{_dashboard}->{panels}[ $self->{_panelKey} ];
	
	$panel->{_packageGrafana} = $self;
	return $panel;
	
}



sub write {
	save( @_ );
}

sub save {
	my $class = shift;
	my $obj = shift;
	
	my $self = $obj->{_packageGrafana};
	
	delete $obj->{_packageGrafana};
	
	my $function = $self->{_function};
	
	if( $function eq "DashboardFromTemplate" ) {
		
		# Preserve old dashboard uid if no specific uid was given
		if( !$obj->{uid} and $self->{_dashboard}->{uid} ) {
			$obj->{uid} = $self->{_dashboard}->{uid};
		}
		
		if( ! $obj->{uid} ) {
			# The dashboard has no uid, create one
			$obj->{uid} = LoxBerry::System::trim(`cat /proc/sys/kernel/random/uuid`);
		}
		
		# Save panels from orig dashboard
		my $panels;
		if( $self->{_dashboard}->{panels} ) {
			$obj->{panels} = $self->{_dashboard}->{panels};
		}
		
		$self->{_dashboardobj}->{jsonobj} = $obj;
		$self->{_dashboardobj}->write();
		
		return $obj->{uid};
		
	}
	elsif ( $function eq "PanelFromTemplate" ) {
		
		my @panelsWithUid;
		if( ! $obj->{uid} ) {
			# The panel has no uid, create one
			$obj->{uid} = LoxBerry::System::trim(`cat /proc/sys/kernel/random/uuid`);
		}
		else {
			# Panel has uid, search for existing panel with that uid
			@panelsWithUid = $self->{_dashboardobj}->find($self->{_dashboard}->{panels}, "\$_->{uid} eq '".$obj->{uid}."'");
		}
	
		if( @panelsWithUid ) {
			# Panel exists
			my $panelkey = $panelsWithUid[0];
			print STDERR "Panel exists\n";
			$self->{_dashboard}->{panels}[$panelkey] = $obj;
		}
		else {
			print STDERR "Panel is new\n";
			push @{$self->{_dashboard}->{panels}}, $obj;
		}
		$self->{_dashboardobj}->write();
		return $obj->{uid};
	
	}
	elsif( $function eq "modifyDashboard" ) {
		
		if( ! $obj->{uid} ) {
			# The dashboard has no uid, create one
			$obj->{uid} = LoxBerry::System::trim(`cat /proc/sys/kernel/random/uuid`);
		}
		
		$self->{_dashboardobj}->{jsonobj} = $obj;
		$self->{_dashboardobj}->write();
		
		return $obj->{uid};
		
	}
	elsif( $function eq "modifyPanel" ) {
		
		my $panelkey = $self->{_panelKey};
		$self->{_dashboard}->{panels}[$panelkey] = $obj;
		$self->{_dashboardobj}->write();
		
		return $obj->{uid};
	}
		
		
	
	
	# use Data::Dumper;
	# print Data::Dumper::Dumper ( $obj );
	
	
	
	die "save() called to an unknown object";
}


#####################################################
# Finally 1; ########################################
#####################################################
1;
