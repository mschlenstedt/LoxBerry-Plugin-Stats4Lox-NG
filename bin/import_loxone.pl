#!/usr/bin/perl
use warnings;
use strict;
use LoxBerry::System;
use LoxBerry::Log;
use LoxBerry::JSON;
use Getopt::Long;
use Time::HiRes qw(time);
use FindBin qw($Bin);
use lib "$Bin/libs";
use Loxone::Import;
require "$lbpbindir/libs/Stats4Lox.pm";

my $log = LoxBerry::Log->new (
    name => 'Import_Stats',
	stderr => 1,
	loglevel => 7,
	addtime => 1
);

LOGSTART "Import";

my $msno;
my $uuid;

GetOptions (
	"msno=i" => \$msno,
	"uuid=s" => \$uuid
);

# Status json
our $statusobj;
our $status;
our $statusfh;

# Validations
if( !defined $msno ) {
	LOGCRIT "msno parameter missing";
	exit(1);
}
if( !defined $uuid ) {
	LOGCRIT "uuid parameter missing";
	exit(1);
}

LOGTITLE "Import MS$msno / $uuid";

# Open Import status file
eval {
	Loxone::Import::statusgetfile( msno=>$msno, uuid=>$uuid, log=>$log );
};
if( $@ ) {
	my $error = "statusgetfile: Cannot lock status file - already locked --> $@";
	LOGCRIT $error;
	exit(3);
}

my %miniservers = LoxBerry::System::get_miniservers();
if( !defined $miniservers{$msno} ) {
	my $error = "get_miniservers: Miniserver no. $msno not defined on your LoxBerry.";
	LOGCRIT $error;
	supdate( {
		status => "error",
		errortext => $error,
		msno => $msno,
		uuid => $uuid,
		starttime => time(),
	} );
	exit(1);
}

LOGINF "Logfile: $log->{filename}";

# Initial status file update
supdate( { 
	status => "running",
	msno => $msno,
	uuid => $uuid,
	name => undef,
	pid => $$,
	starttime => time(),
	endtime => undef,
	current => undef,
	finished => { },
} );


my $import;
eval {
	$import = new Loxone::Import(msno => $msno, uuid=> $uuid, log => $log);
};
if( $@ ) {
	my $error = "new Import: Error --> $@";
	LOGCRIT $error;
	supdate( { 
		name => $import->{statobj}->{name},
		status => "error",
		errortext => $error
	} );
	exit(4);
}
supdate( { name => $import->{statobj}->{name} } );

my @statmonths;
eval {
	@statmonths = $import->getStatlist();
	LOGDEB "Statlist $#statmonths elements.";
};
if( $@ or !$#statmonths ) {
	my $error = "getStatList: Could not get Statistics list from Loxone Miniserver MS$msno --> $@";
	LOGCRIT $error;
	supdate( { 
		name => $import->{statobj}->{name},
		status => "error",
		errortext => $error
	} );
	exit(2);
}

my $months_count_full = scalar @statmonths;
my $months_count_finished = 0;
my $record_count = 0;
my $duration_time_secs = 0;
# print Data::Dumper::Dumper( $import->{statlistAll} );

foreach my $yearmonth ( @statmonths ) {
	supdate( { current => $yearmonth } );
	my $starttime = Time::HiRes::time();
	
	LOGINF "Fetching $import->{uuid} Month: $yearmonth";
	my $monthdata;
	eval {
		$monthdata = $import->getMonthStat( yearmon => $yearmonth );
	};
	if( $@ ) {
		my $error = "getMonthStat $yearmonth: $@";
		LOGCRIT $error;
		supdate( { 
			status => "error",
			errortext => $error
		} );
		exit(5);
	}
	# print STDERR Data::Dumper::Dumper( $monthdata ) . "\n";
	LOGINF "   Datasets " . scalar @{$monthdata->{values}};
	
	my $fullcount;
	eval {
		$fullcount = $import->submitData( $monthdata );
	};
	if( $@ ) {
		my $error = "submitData $yearmonth: $@";
		LOGCRIT $error;
		supdate( { 
			status => "error",
			errortext => $error
		} );
		exit(6);
	}

	my %finished = (
		duration => int((Time::HiRes::time()-$starttime)*1000)/1000,
		count => $fullcount,
		timestampcount => scalar @{$monthdata->{values}},
		endtime => time()
	);	
	
	$status->{finished}{$yearmonth} = \%finished;
	
	# Calculate runtime estimations 
	$record_count += $fullcount;
	$months_count_finished++;
	$duration_time_secs += $finished{duration};
	my $avg_records_per_month = ($record_count/$months_count_finished);
	my $avg_time_per_record_secs = $duration_time_secs / $record_count;
	my $estimate_records_left =  $avg_records_per_month * ($months_count_full-$months_count_finished);
	my $estimate_time_left_secs = $estimate_records_left*$avg_time_per_record_secs;
	my $estimate_time_left_time_obj = time()+$estimate_time_left_secs;
	my ($e_sec,$e_min,$e_hour,$e_mday,$e_mon,$e_year,$e_wday,$e_yday,$e_isdst) =
                                            localtime(time()+$estimate_time_left_secs);
	$e_year+=2000;
	my $estimate_time_left_time_hr = sprintf("%04d-%02d-%02d %02d:%02d:%02d", $e_year, $e_mon,$e_mday, $e_hour, $e_min, $e_sec);
	
	# my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
	# my $timenow = "$year-$mon-$mday $hour:$min:$sec";
	
	my %stats = (
		months_count_full => $months_count_full,
		months_count_finished => $months_count_finished,
		record_count_finished => $record_count,
		duration_time_secs => $duration_time_secs,
		avg_records_per_month => $avg_records_per_month,
		avg_time_per_record_secs => $avg_time_per_record_secs,
		estimate_records_left => $estimate_records_left,
		estimate_time_left_secs => $estimate_time_left_secs,
		estimate_time_left_time_hr => $estimate_time_left_time_hr,
	#	timenow => $timenow
	);
		
	
	supdate( { stats => \%stats } );  

	
}

LOGOK "All month finished.";
supdate( { status=>"finished" });

exit(0);

sub END {
	if( $statusobj ) {
		if ( $status->{status} ne "finished" ) {
			supdate( { status => "error" } );
			LOGCRIT "Import exited with error.";
		}
		supdate( { 
			endtime => time(), 
			duration =>  int((time()-$status->{starttime})*1000)/1000
		} );
	}
	eval { 
		LOGEND;
	};
}