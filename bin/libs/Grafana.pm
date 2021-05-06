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
	my $panel_ids = shift;
	
	print STDERR "panel_ids is " . ref($panel_ids) . "\n";
	if( ref($panel_ids) eq "" ) {
		$panel_ids = [ $panel_ids ];
		print STDERR "panel_ids now is " . ref($panel_ids) . "\n";
	}
	
	if( !$panel_ids ) {
		die "deletePanelFromDashboard requires a valid panel id parameter";
	}
	
	my $self = {};
	
	$self->{_dashboardobj} = new LoxBerry::JSON;
	$self->{_dashboard} = $self->{_dashboardobj}->open( filename => $dashboard_file, writeonclose => 0, lockexclusive => 1 ) or die "Could not open dashboard file\n";
	
	my $deleted = 0;
	
	
	
	foreach my $panel_id ( @{$panel_ids} ) {
		print STDERR "Deleting $panel_id\n";
		my @panelsWithId = $self->{_dashboardobj}->find($self->{_dashboard}->{panels}, "\$_->{id} eq '".$panel_id."'");
		next if( !@panelsWithId );
		foreach( @panelsWithId ) {
			$deleted++;
			splice @{$self->{_dashboard}->{panels}}, $_, 1;
			# delete $self->{_dashboard}->{panels}[$_];
		}
	}
	# if( ! $self->{_dashboard}->{panels} ) {
		# $self->{_dashboard}->{panels} = ();
	# }
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
	$self->{_dashboard} = $self->{_dashboardobj}->open( filename => $dashboard_file, writeonclose => 0, lockexclusive => 1 ) or die "Could not open dashboard file\n";
	
	$self->{_function} = "modifyDashboard";
	
	$self->{_dashboard}->{_packageGrafana} = $self;
	
	return $self->{_dashboard};
	
}


sub modifyPanel {
	my $class = shift;
	my $dashboard_file = shift;
	my $panel_id = shift;
	
	if( !$panel_id ) {
		die "modifyPanel requires a valid panel id parameter";
	}
	
	my $self = {};
	
	$self->{_dashboardobj} = new LoxBerry::JSON;
	$self->{_dashboard} = $self->{_dashboardobj}->open( filename => $dashboard_file, writeonclose => 0, lockexclusive => 1 ) or die "Could not open dashboard file\n";
	
	my @panelsWithId = $self->{_dashboardobj}->find($self->{_dashboard}->{panels}, "\$_->{id} eq '".$panel_id."'");
	
	if( !@panelsWithId ) {
		die "Panel with id $panel_id does not exist";
	}
	$self->{_panelKey} = $panelsWithId[0];
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
		if( defined $self->{_dashboard}->{panels} ) {
			$obj->{panels} = $self->{_dashboard}->{panels};
		}
		
		$self->{_dashboardobj}->{jsonobj} = $obj;
		$self->{_dashboardobj}->write();
		
		return $obj->{uid};
		
	}
	elsif ( $function eq "PanelFromTemplate" ) {
		
		my @panelsWithId;

		if( ! $obj->{id} ) {
			# The panel has no id, create one
			# We need to get the highest panel id from all existing panels
			my $highest_id = 0; 
			foreach( @{ $self->{_dashboard}->{panels} } ) {
				$highest_id = 0+$_->{id} if( 0+$_->{id} > $highest_id );
			}
			$obj->{id} = $highest_id+1;
			# print STDERR "Panel had no panel id - id $obj->{id} created";
		}
		else {
			# Panel has id, search for existing panel with that id
			@panelsWithId = $self->{_dashboardobj}->find($self->{_dashboard}->{panels}, "\$_->{id} == ".$obj->{id});
		}
	
		if( @panelsWithId ) {
			# Panel exists
			$obj->{id} = int($obj->{id});
			my $panelkey = $panelsWithId[0];
			print STDERR "Panel exists\n";
			$self->{_dashboard}->{panels}[$panelkey] = $obj;
		}
		else {
			$obj->{id} = int($obj->{id});
			print STDERR "Panel is new\n";
			push @{$self->{_dashboard}->{panels}}, $obj;
		}
		print STDERR "Calling write\n";
		$self->{_dashboardobj}->write();
		return $obj->{id};
	
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
		$obj->{id} += 0;
		$self->{_dashboard}->{panels}[$panelkey] = $obj;
		$self->{_dashboardobj}->write();
		
		return $obj->{id};
	}
		
		
	
	
	# use Data::Dumper;
	# print Data::Dumper::Dumper ( $obj );
	
	
	
	die "save() called to an unknown object";
}


#####################################################
# Finally 1; ########################################
#####################################################
1;
