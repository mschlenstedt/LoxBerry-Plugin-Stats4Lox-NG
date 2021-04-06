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
my @slots;
# Loop
while(time() < $lastchange_timestamp+$timeout) {
	
	
	
	# print STDERR "CHANGES:\n";
	
	# Search for new/changed import statusfiles
	my @changedfiles = getStatusChanges();
	# print STDERR join("\n", @changedfiles) . "\n";
	
	# Read import statusfile of changed imports into memory
	updateImportStatus( @changedfiles );

	if( @changedfiles) {
	# Keep Scheduler open as long as imports change their status
		$lastchange_timestamp = time();
	}
	
	# Run one scheduled import
	if( @slots ) {
		$lastchange_timestamp = time();
		my $task = shift @slots;
		runImport( $task ) if $task;
	}
	
	# Things to do not so often
	if( time() > $next_step_5sec ) {
		$next_step_5sec = time()+5;
		updateDeadStatus();
		@slots = getSlots();
		# Keep Scheduler open as long as tasks are running or scheduled
		$lastchange_timestamp = time() if (keys %scheduled or keys %running);
	}
	
	# Update the file for the UI
	updateSchedulerStatusfile();
	
	Time::HiRes::sleep(1);
}

sub updateImportStatus
{
	my @files = @_;
	
	
	foreach my $file ( @files ) {
		
		my $msno;
		my $uuid;
		
		# First, try to evaluate msno and uuid from filename
		my $regex = qr/import_(\d{1,2})_([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{16})/p;
		if ( $file =~ /$regex/ ) {
			$msno = $1;
			$uuid = $2;
			# print STDERR "Found: MSNO $msno  UUID $uuid\n";
		}
		
		my $filecontent;
		eval {
			$filecontent = LoxBerry::System::read_file($file);
			$filelist{$file}{status} = from_json( $filecontent );
			
		};
		if($@) {
			print STDERR "$file:\n$filecontent\n";
			if( !$msno and !$uuid ) {
				print STDERR "ERROR Could not read $file: $@\n";
				next;
			} else {
				print STDERR "WARNING Filename is used instead of content: $file\n";
				delete $filelist{$file}{status};
			}
		}
		
		# Evaluate status of import
		my $statusobj = $filelist{$file}{status};
		my $status;
		
		if( defined $filelist{$file}{status}->{msno} and defined $filelist{$file}{status}->{uuid} ) {
			$filelist{$file}{msno} = $filelist{$file}{status}->{msno};
			$filelist{$file}{uuid} = $filelist{$file}{status}->{uuid};
			$status = $statusobj->{status};
		
		} 
		elsif ( $msno and $uuid ) {
			$filelist{$file}{msno} = $msno;
			$filelist{$file}{uuid} = $uuid;
			$status = "scheduled";
		} 
		else {
			$status = "error";
		}
		
		
		if( $status eq "finished" ) {
			delete $scheduled{$file};
			$finished{$file} = 1;
			delete $running{$file};
			delete $error{$file};
			delete $dead{$file};
			delete $filelist{$file}{schedprocessed}; 
		} 
		elsif( $status eq "error" ) {
			delete $scheduled{$file};
			delete $finished{$file};
			delete $running{$file};
			$error{$file} = 1;
			delete $dead{$file};
			delete $filelist{$file}{schedprocessed};
		}
		elsif( $status eq "running" ) {
			delete $scheduled{$file};
			delete $finished{$file};
			$running{$file} = 1;
			delete $error{$file};
			delete $dead{$file};
			delete $filelist{$file}{schedprocessed};
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
			delete $filelist{$file}{schedprocessed};
		}
	}
}

sub getStatusChanges 
{

	my @changedfiles;
	
	# Read import directory
	my @importfiles = glob( $Globals::importstatusdir . '/import_*.json' );
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
			delete $filelist{$file}{schedprocessed};
			push @changedfiles, $file;
		}
		else {
			my $mtime = (stat($file))[9];
			if ( $mtime > $filelist{$file}{mtime} ) {        # and $mtime > $filelist{$file}{schedprocessed}
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
		if( $filelist{$file}{status}->{statustime} < time()-$Globals::import_time_to_dead_minutes*60 ) {
			delete $running{$file};
			$dead{$file} = 1;
		} 
	}
}

sub getSlots
{
	# Some countings
	my %scheduled_and_running = ( %scheduled, %running );
	print STDERR "Scheduled: " . scalar (keys %scheduled) . " Running: " . scalar (keys %running) . " Merged: " . scalar (keys %scheduled_and_running) . "\n";
	
	
	# Get everything that looks like running and separate it per miniserver
	my $count_running = 0;
	my %count_by_ms;
	foreach my $file ( keys %scheduled_and_running ) {
		my $msno = $filelist{$file}{msno};
		
		if( $scheduled{$file} and defined $filelist{$file}{schedprocessed} and (time()-$filelist{$file}{schedprocessed}) < 30 ) {
			# Task was started in the last 30 seconds - assume it will shortly start
			# print STDERR "Shortly started - remove from list\n";
			$count_by_ms{$msno}++;
			delete $scheduled_and_running{$file};
			$count_running++;
			next;
		} 
		elsif( $running{$file} ) {
			# Task IS running
			# print STDERR "Is running - remove from list\n";
			$count_by_ms{$msno}++;
			delete $scheduled_and_running{$file};
			$count_running++;
			next;
		} 
		my $name = defined $filelist{$file}{status}->{name} ? $filelist{$file}{status}->{name} : "";
		print STDERR "  Waiting: $filelist{$file}{uuid} " . $name . "\n";
		
	}
	
	# We can directly skip, when all slots are full
	return if( $count_running >= $Globals::import_max_parallel_processes );
	
	# Find a slot for 
	foreach my $file ( keys %scheduled_and_running ) {
		my $msno = $filelist{$file}{msno};
		if( defined $count_by_ms{$msno} and $count_by_ms{$msno} >= $Globals::import_max_parallel_per_ms ) {
			delete $scheduled_and_running{$file};
		}
	}
	
	# We now have the hash %scheduled_and_running reduced to all possible slots
	return(keys %scheduled_and_running);
}


sub runImport 
{
	my ($file) = @_;
	
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

	
	my $msno = $filelist{$file}{msno};
	my $uuid = $filelist{$file}{uuid};
	
	my $commandline = "$lbpbindir/import_loxone.pl -msno=${msno} -uuid=${uuid} >$file.log 2>&1 &";
	
	my $name = defined $filelist{$file}{status}->{name} ? $filelist{$file}{status}->{name} : "";
	print STDERR "  IMPORT: $uuid $name starting\n";
	print STDERR "Commandline: $commandline\n";
	system($commandline);
	# if( $exitcode != 0 ) {
		# print STDERR "ERROR calling import $msno / $uuid\n";
		# print STDERR "$commandline\n";
	# }
	# sleep(1);

}