#!/usr/bin/perl
use warnings;
use strict;
use LoxBerry::System;
use LoxBerry::Log;
use LoxBerry::JSON;
use CGI;
use Time::HiRes qw(time);
use FindBin qw($Bin);
use lib "$Bin/libs";
use Globals;
use Fcntl ':flock';

my $cgi = CGI->new;
my $q = $cgi->Vars;

# Keep all imports in a big list
# To prevent looping several times, prepare special lists for scheduled, finished,...

my %filelist;
my %scheduled;
my %finished;
my %running;
my %error;
my %dead;

my $time_to_dead_min = 60;

if( defined $q->{importlist} ) {
	# Do reading stuff and respond with import overview data
	my @changedfiles = getStatusChanges();
	updateImportStatus( @changedfiles );
	updateDeadStatus();
	my $status = updateSchedulerStatusfile();
	
}





##############################
#### Scheduler processing ####
##############################

# Lock a file to make sure only one instance is running
my $lockfile = $Globals::s4ltmp."/import_scheduler.lock";
open my $fh, '>', $lockfile or die "CRITICAL Could not open LOCK file $lockfile: $!";
flock $fh, LOCK_EX | LOCK_NB or die "CRITICAL Scheduler is already running";

# How long to wait for a new job before terminating
my $timeout = 60; 
my $lastchange_timestamp = time();

# Check different things not so often
my $next_step_5sec = 0;

# Create info file for UI
my $schedulerStatusfile = $Globals::s4ltmp."/s4l_import_scheduler.json";
unlink $schedulerStatusfile;
my $schedstatusobj = new LoxBerry::JSON;
my $schedstatus = $schedstatusobj->open( filename => $schedulerStatusfile, writeonclose => 1 );

# Loop
while(time() < $lastchange_timestamp+$timeout) {
	
	
	
	print STDERR "CHANGES:\n";
	
	# Search for new/changed import statusfiles
	my @changedfiles = getStatusChanges();
	print STDERR join("\n", @changedfiles) . "\n";
	if( @changedfiles ) {
		# Keep Scheduler open as long as imports change their status
		$lastchange_timestamp = time();
	}

	# Read import statusfile of changed imports into memory
	updateImportStatus( @changedfiles );
	
	# Run one scheduled import
	my @scheduled = keys %scheduled;
	if( @scheduled ) {
		$lastchange_timestamp = time();
		runImport( $scheduled[0] );
	}
	
	
	# Things to do not so often
	if( time() > $next_step_5sec ) {
		$next_step_5sec = time()+5;
		updateDeadStatus();
	}
	
	# Update the file for the UI
	updateSchedulerStatusfile();
	
	Time::HiRes::sleep(2);
}

sub updateImportStatus
{
	my @files = @_;
	
	foreach my $file ( @files ) {
		eval {
			$filelist{$file}{status} = decode_json( LoxBerry::System::read_file($file) );
			
		};
		if($@) {
			print STDERR "ERROR could not read $file: $@\n";
			next;
		}
		
		# Evaluate status of import
		my $statusobj = $filelist{$file}{status};
		my $status = $statusobj->{status};
		
		if( !defined $filelist{$file}{status}->{msno} or !defined $filelist{$file}{status}->{uuid} ) {
			$status = "error";
		}
		
		if( $status eq "finished" ) {
			delete $scheduled{$file};
			$finished{$file} = 1;
			delete $running{$file};
			delete $error{$file};
			delete $dead{$file};
		} 
		elsif( $status eq "error" ) {
			delete $scheduled{$file};
			delete $finished{$file};
			delete $running{$file};
			$error{$file} = 1;
			delete $dead{$file};
		}
		elsif( $status eq "running" ) {
			delete $scheduled{$file};
			delete $finished{$file};
			$running{$file} = 1;
			delete $error{$file};
			delete $dead{$file};
		}
		elsif( !defined $status or $status eq "scheduled" ) {
			$scheduled{$file} = 1;
			delete $finished{$file};
			delete $running{$file};
			delete $error{$file};
			delete $dead{$file};
		}
		else {
			delete $scheduled{$file};
			delete $finished{$file};
			delete $running{$file};
			delete $error{$file};
			$dead{$file} = 1;
		}
	}
}

sub getStatusChanges 
{

	my @changedfiles;
	
	# Read import directory
	my @importfiles = glob( $Globals::importstatusdir . '/*.json' );
	my %importfileshash = map { $_ => 1 } @importfiles;
	# Delete entries from local hash that have been deleted on disk
	foreach my $file ( keys %filelist ) {
		if( !defined $importfileshash{$file} ) {
			# print STDERR "REMOVED file $file from internal store\n";
			delete $filelist{$file};
			delete $scheduled{$file};
			delete $finished{$file};
			delete $running{$file};
			delete $error{$file};
			delete $dead{$file};
		}
	}
	
	# Check files for changes
	foreach my $file ( @importfiles ) {
		if( !defined $filelist{$file} ) {
			# New file
			# print STDERR "ADDED file $file to internal store\n";
			$filelist{$file}{mtime} = (stat($file))[9];
			$filelist{$file}{schedprocessed} = 0;
			push @changedfiles, $file;
		}
		else {
			my $mtime = (stat($file))[9];
			if ( $mtime > $filelist{$file}{mtime} and $mtime > $filelist{$file}{schedprocessed}) {
				# Existing changed files
				# print STDERR "UPDATED file $file in internal store\n";
				$filelist{$file}{mtime} = $mtime;
				push @changedfiles, $file;
			}
		}
	}
	
	return @changedfiles;
}

	
sub updateSchedulerStatusfile
{
	# Update UI status file
	$schedstatus->{filelist} = \%filelist;
	$schedstatus->{states}{scheduled} = \%scheduled;
	$schedstatus->{states}{finished} = \%finished;
	$schedstatus->{states}{running} = \%running;
	$schedstatus->{states}{error} = \%error;
	$schedstatus->{states}{dead} = \%dead;
	$schedstatus->{updated_epoch} = time();
	$schedstatus->{updated_hr} = LoxBerry::System::currtime('hr');
	$schedstatusobj->write();
	return $schedstatus;
}

sub updateDeadStatus
{
	foreach my $file ( keys %running ) {
		if( $filelist{$file}{status}->{statustime} < time()-$time_to_dead_min*60 ) {
			delete $running{$file};
			$dead{$file} = 1;
		} 
	}
}

sub runImport 
{
	my ($file) = @_;
	if( $filelist{$file}{schedprocessed} > time()-30 ) {
		# Was processed in the last 30 seconds - skip for now
		return;
	}
	$filelist{$file}{schedprocessed} = time();
	
	if( defined $filelist{$file}{trycount} ) {
		$filelist{$file}{trycount}++;
	}
	else {
		$filelist{$file}{trycount} = 1;
	}
	
	if( $filelist{$file}{trycount} > 3 ) {
		# Mark as error
		delete $scheduled{$file};
		$error{$file} = 1;
	}

	
	my $msno = $filelist{$file}{status}->{msno};
	my $uuid = $filelist{$file}{status}->{uuid};
	
	my $commandline = "$lbpbindir/libs/testing/import_influx.pl msno=$msno uuid=$uuid >$file.log 2>&1 &";
	print STDERR "Calling IMPORT for $msno / $uuid\n";
	print STDERR "Commandline: $commandline\n";
	system($commandline);
	# if( $exitcode != 0 ) {
		# print STDERR "ERROR calling import $msno / $uuid\n";
		# print STDERR "$commandline\n";
	# }
	# sleep(1);

}