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
	my $log = $args{log};
	my $msno = $args{ms};
	
	if( ! $msno) {
		print STDERR "No Miniserver number defined.\n";
		return;
	}
	
	# Create temporary storage
	if(!$main::s4ltmp) {
		print STDERR "Missing variable s4ltmp.\n";
		return;
	}
	if( ! -e $main::s4ltmp ) {
		my $mkrc = mkdir ($main::s4ltmp, 0770);
		if( !$mkrc ) {
			print STDERR "Could not create temporary folder $main::s4ltmp.\n";
			return;
		}
	}
	
	# Get file list
	my @files = getFilelist( $msno, "prog/" );
	if( !@files ) {
		print STDERR "getFilelist: No files found.\n";
		return;
	}
	
	# Download file
	my $localfile = getFile( $msno, "prog/$files[0]" );
	if( !$localfile ) {
		print STDERR "getFile. File download not successfull.\n";
		return;
	}
	print STDERR "Local file: $localfile\n";
	
	my $LoxCCsource = "$main::s4ltmp/s4l_loxplan_ms$msno/sps0.LoxCC";
	my $Loxplansource = "$main::s4ltmp/s4l_loxplan_ms$msno/sps0.Loxone";
	my $Loxplandest = "$main::s4ltmp/s4l_loxplan_ms$msno.Loxone";
	
	# Unzip file
	$log->INF("Cleaning up old files");
	`rm -f -r "$main::s4ltmp/s4l_loxplan_ms$msno/"`;
	
	my ($name, $ext) = split(/.([^.]+)$/, $localfile);
	if( lc($ext) eq "zip" ) {
		$log->INF("Unzipping zip");
		`unzip $localfile -d "$main::s4ltmp/s4l_loxplan_ms$msno/"`;
	} 
	elsif ( lc($ext) eq "loxcc" ) {
		$log->INF("File already is a LoxCC file");
		$LoxCCsource = $localfile;
	}
	
	# Check if we already have a .Loxone file, or need to unpack LoxCC
	
	if( -e $Loxplansource ) {
		# If exists, copy to $main::s4ltmp
		print STDERR "Copying Loxplan from zip\n";
		require File::Copy;
		File::Copy::copy( $Loxplansource, $Loxplandest );
	}
	elsif( -e $LoxCCsource ) {
		# Unpack LoxCC file
		print STDERR "Calling unpack_loxcc.py\n";
		`${LoxBerry::System::lbpbindir}/libs/Loxone/unpack_loxcc.py "$LoxCCsource" "$Loxplandest"`;
	} 
	else {
		print STDERR "Could not find project file.\n";
	}
	
}

sub getFilelist
{
	my ($msno, $dir) = @_;
	
	my $query = "/dev/fslist/$dir";
	
	my (undef, undef, $fileresp) = LoxBerry::IO::mshttp_call( $msno, $query );
	if( !$fileresp ) {
		print STDERR "getFilelist: Could not get file list from MS$msno\n";
		return;
	}
	
	my @files_raw = split( "\n", $fileresp);
	my @files;
	foreach my $file_raw ( @files_raw ) {
		# print STDERR $file_raw."\n";
		my @parts = split( " ", $file_raw );
		my $filesize = $parts[1];
		my $filename = $parts[5];
		my ($name, $ext) = split(/.([^.]+)$/, $filename);
		
		# Skip entries
		next if ( $parts[0] ne "-" );
		next if ( !LoxBerry::System::begins_with( lc($filename), 'sps_' ) );
		next if ( lc($ext) ne "zip" and lc($ext) ne "loxcc" );
		push @files, $filename;
		
	}
	
	@files = sort {lc($b) cmp lc($a)} @files;
	
	return @files;
	
}

sub getFile
{
	my ($msno, $filename) = @_;
	require LWP::Simple;
	
	my %miniservers = LoxBerry::System::get_miniservers();
	my $msuri = $miniservers{$msno}{FullURI};
	if (!$msuri) {
		return;
	}
	
	my ($name, $ext) = split(/.([^.]+)$/, $filename);
	
	my $fulluri = "$msuri/dev/fsget/$filename";
	my $localfile = "$main::s4ltmp/s4l_loxplan_ms$msno.$ext";
	print STDERR "Fulluri: $fulluri Localfile: $localfile\n";
	
	my $rc = LWP::Simple::getstore( $fulluri, $localfile);
	if( LWP::Simple::is_error($rc) ) {
		return;
	}
	
	return( $localfile );
}

# Checks is the local json is up-to-date against the Miniserver
# Returns 
#	undef if current file is up-to-date
#	Raises an exception in case of any error

sub checkLoxplanUpdate
{
	my ($msno, $loxplanjson) = @_;
	
	if (! -e $loxplanjson) {
		die "checkLoxplanUpdate: Json does not exist ($loxplanjson)\n";
	}
	
	my $localTimestamp = 0;
	my $remoteTimestamp = 0;
	
	# Read local timestamp
	my $loxplanobj;
	my $loxplan;
	
	eval {
	
		$loxplanobj = LoxBerry::JSON->new();
		$loxplan = $loxplanobj->open( filename => $loxplanjson );
		$localTimestamp = defined $loxplan->{documentInfo}->{LoxAPPversion3timestamp} ? $loxplan->{documentInfo}->{LoxAPPversion3timestamp} : "0";
		print STDERR "checkLoxplanUpdate: localTimestamp : $localTimestamp\n";
	};
	if( $@ ) {
		die "checkLoxplanUpdate: Could not fetch local version info\n";
	}
	
	# Read remote timestamp
	my $respraw;
	my $respobj;
	eval {
		(undef, undef, $respraw) = LoxBerry::IO::mshttp_call( $msno, "/jdev/sps/LoxAPPversion3" );
		$respobj = JSON::decode_json( $respraw );
		$remoteTimestamp = defined $respobj->{LL}->{value} ? $respobj->{LL}->{value} : "1";
		print STDERR "checkLoxplanUpdate: remoteTimestamp: $remoteTimestamp\n";
	};
	if( $@ ) {
		die "checkLoxplanUpdate: Could not fetch remote version info\n";
	}
	
	if( $localTimestamp ne "0" and $localTimestamp eq $remoteTimestamp ) {
		print STDERR "checkLoxplanUpdate: Timestamps are equal, no need to update\n";
		return;
	}
	
	return $remoteTimestamp;
	
}





#####################################################
# Finally 1; ########################################
#####################################################
1;
