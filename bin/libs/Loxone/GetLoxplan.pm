use warnings;
use strict;
use LoxBerry::System;
use LoxBerry::IO;
use LoxBerry::Log;
use FindBin qw($Bin);
use lib "$Bin/..";
use Globals;
use Data::Dumper;

package Loxone::GetLoxplan;

sub getLoxplan
{
	my %args = @_;
	my $me = whoami();
	my $log = $args{log};
	my $msno = $args{ms};
	
	if (! $log) {
		$log = LoxBerry::Log->new (
			name => 'getLoxplan',
			stderr => 1,
			loglevel => 7
		);
		$log->LOGSTART("$me");
	}
	
	if( ! $msno) {
		$log->CRIT("$me No Miniserver number defined.");
		return;
	}
	
	# Create temporary storage
	if(!$Globals::stats4lox->{s4ltmp}) {
		$log->CRIT("$me Missing variable s4ltmp.");
		return;
	}
	if( ! -e $Globals::stats4lox->{s4ltmp} ) {
		$log->INF("$me Creating directory $Globals::stats4lox->{s4ltmp}");
		my $mkrc = mkdir ($Globals::stats4lox->{s4ltmp}, 0770);
		if( !$mkrc ) {
			$log->CRIT("$me Could not create temporary folder $Globals::stats4lox->{s4ltmp}.");
			return;
		}
	}
	
	# Get file list
	my @files = getFilelist( $msno, "prog/", $log );
	if( !@files ) {
		$log->CRIT("$me getFilelist: No files found.");
		return;
	}
	
	# Download file
	my $localfile = getFile( $msno, "prog/$files[0]", $log );
	if( !$localfile ) {
		$log->CRIT("$me getFile. File download not successful.");
		return;
	}
	$log->INF("$me Local file: $localfile");
	
	my $LoxCCsource = "$Globals::stats4lox->{s4ltmp}/s4l_loxplan_ms$msno/sps0.LoxCC";
	my $Loxplansource = "$Globals::stats4lox->{s4ltmp}/s4l_loxplan_ms$msno/sps0.Loxone";
	my $Loxplandest = "$Globals::stats4lox->{s4ltmp}/s4l_loxplan_ms$msno.Loxone";
	
	# Unzip file
	$log->INF("Cleaning up old files");
	`rm -f -r "$Globals::stats4lox->{s4ltmp}/s4l_loxplan_ms$msno/"`;
	
	my ($name, $ext) = split(/.([^.]+)$/, $localfile);
	if( lc($ext) eq "zip" ) {
		$log->INF("$me Unzipping zip");
		`unzip $localfile -d "$Globals::stats4lox->{s4ltmp}/s4l_loxplan_ms$msno/"`;
	} 
	elsif ( lc($ext) eq "loxcc" ) {
		$log->INF("$me File already is a LoxCC file");
		$LoxCCsource = $localfile;
	}
	
	# Check if we already have a .Loxone file, or need to unpack LoxCC
	
	if( -e $Loxplansource ) {
		# If exists, copy to $Globals::stats4lox->{s4ltmp}
		$log->INF("$me Copying Loxplan from zip");
		require File::Copy;
		File::Copy::copy( $Loxplansource, $Loxplandest );
	}
	elsif( -e $LoxCCsource ) {
		# Unpack LoxCC file
		$log->INF("$me Calling unpack_loxcc.py");
		`${LoxBerry::System::lbpbindir}/libs/Loxone/unpack_loxcc.py "$LoxCCsource" "$Loxplandest"`;
	} 
	else {
		$log->CRIT("$me Could not find project file.");
	}
	$log->OK("$me Finished");
}

sub getFilelist
{
	my ($msno, $dir, $log) = @_;
	
	my $me = whoami();
	if (! $log) {
		$log = LoxBerry::Log->new (
			name => 'getFilelist',
			stderr => 1,
			loglevel => 7
		);
		$log->LOGSTART("$me");
	}
	
	my $query = "/dev/fslist/$dir";
	
	my (undef, undef, $fileresp) = LoxBerry::IO::mshttp_call( $msno, $query );
	if( !$fileresp ) {
		$log->CRIT("$me Could not get file list from MS$msno");
		return;
	}
	
	my @files_raw = split( "\n", $fileresp);
	my @files;
	foreach my $file_raw ( @files_raw ) {
		$log->DEB("$me Checking $file_raw");
		my @parts = split( " ", $file_raw );
		my $filesize = $parts[1];
		my $filename = $parts[5];
		my ($name, $ext) = split(/.([^.]+)$/, $filename);
		
		# Skip entries
		next if ( $parts[0] ne "-" );
		next if ( ! LoxBerry::System::begins_with( lc($filename), 'sps_' ) );
		next if ( LoxBerry::System::begins_with( lc($filename), 'sps_old' ) );
		next if ( lc($ext) ne "zip" and lc($ext) ne "loxcc" );
		$log->DEB("$me $filename added to filelist");
		push @files, $filename;
		
	}
	
	@files = sort {lc($b) cmp lc($a)} @files;
	$log->OK("$me Final sorted filelist:\n" . join( "\n", @files) );
	
		
	return @files;
	
}

sub getFile
{
	my ($msno, $filename, $log) = @_;
	
	my $me = whoami();
	if (! $log) {
		$log = LoxBerry::Log->new (
			name => 'getFile',
			stderr => 1,
			loglevel => 7
		);
		$log->LOGSTART("$me");
	}
	
	require LWP::UserAgent;
	
	my %miniservers = LoxBerry::System::get_miniservers();
	my $msuri = $miniservers{$msno}{FullURI};
	if (!$msuri) {
		$log->CRIT("$me Cannot get FullURI from Miniserver $msno");
		return;
	}
	
	my ($name, $ext) = split(/.([^.]+)$/, $filename);
	
	my $uripart = "/dev/fsget/$filename";
	my $localfile = "$Globals::stats4lox->{s4ltmp}/s4l_loxplan_ms$msno.$ext";
	$log->INF("$me Uripart: $uripart Localfile: $localfile");
	
	my $ua = LWP::UserAgent->new( ssl_opts => { verify_hostname => 0} );
	my $req = HTTP::Request->new( GET => $msuri.$uripart );
	my $response = $ua->request($req);
	
	if ($response->is_success) {
		my $error = LoxBerry::System::write_file( $localfile, $response->content );
		if( $error ) {
			$log->CRIT("$me Could not write file $localfile: $error");
			unlink $localfile;
			return;
		}
		$log->OK("$me File successfully downloaded to $localfile");
		return( $localfile );
	}
	else {
		$log->CRIT("$me Download error: $response->status_line");
		unlink $localfile;
		return;
	}
	
}

# Checks is the local json is up-to-date against the Miniserver
# Returns 
#	undef if current file is up-to-date
#	Raises an exception in case of any error

sub checkLoxplanUpdate
{
	my ($msno, $loxplanjson, $log) = @_;
	my $me = whoami();
	if (! $log) {
		$log = LoxBerry::Log->new (
			name => 'checkLoxplanUpdate',
			stderr => 1,
			loglevel => 7
		);
		$log->LOGSTART("$me");
	}

	my $localTimestamp;
	my $remoteTimestamp;
	my $lastCheck = 0;
	
	# Read local timestamp
	my $loxplanobj;
	my $loxplan;
	
	eval {
	
		$loxplanobj = LoxBerry::JSON->new();
		$loxplan = $loxplanobj->open( filename => $loxplanjson, writeonclose => 1 );
		if( defined $loxplan->{documentInfo}->{LoxAPPversion3timestamp} ) {
			$localTimestamp = $loxplan->{documentInfo}->{LoxAPPversion3timestamp};
		}
		$log->DEB("$me Locally stored timestamp of last LoxPlan update : $localTimestamp");
	};
	if( $@ ) {
		$log->CRIT("$me Could not fetch local version info");
		die "checkLoxplanUpdate: Could not fetch local version info\n";
	}
	
	if( defined $loxplan->{documentInfo}->{S4L_LastChecked} ) {
		$lastCheck = $loxplan->{documentInfo}->{S4L_LastChecked};
	}

	$log->INF("$me Last check for new LoxPlan update : $lastCheck");
	
	if( $localTimestamp and $lastCheck > time()-90 ) {
		# Prevent checking for 90 seconds
		$log->INF("$me Skipping check (already done in the past 90 seconds)");
		return;
	}
	
	# Read remote timestamp
	my $respraw;
	my $respobj;
	eval {
		$log->INF("$me Checking LoxAPPversion3 on Miniserver $msno");
		(undef, undef, $respraw) = LoxBerry::IO::mshttp_call( $msno, "/jdev/sps/LoxAPPversion3" );
		$respobj = JSON::decode_json( $respraw );
		$remoteTimestamp = defined $respobj->{LL}->{value} ? $respobj->{LL}->{value} : "1";
		$log->INF("$me Current LoxPlan timestamp on Miniserver : $remoteTimestamp");
	};
	if( $@ ) {
		$log->CRIT("$me Could not fetch remote version info");
		die "checkLoxplanUpdate: Could not fetch remote version info\n";
	}
	
	$loxplan->{documentInfo}->{S4L_LastChecked} = time();
	
	if( $localTimestamp and $remoteTimestamp and $localTimestamp eq $remoteTimestamp ) {
		$log->INF("$me Local and Miniserver timestamps are equal, no need to update");
		return;
	}
	
	return $remoteTimestamp;
	
}

# Returns the name of the current sub (for logfile)
# e.g. my $me = whoami();
# print "$me Starting import"; returns "Loxone::Import::new--> Starting import"
sub whoami { 
	return ( caller(1))[3] . '-->';
}




#####################################################
# Finally 1; ########################################
#####################################################
1;
