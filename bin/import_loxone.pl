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
use Globals;
require "$lbpbindir/libs/Stats4Lox.pm";

my $me = Globals::whoami();

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
	LOGCRIT "$me msno parameter missing";
	exit(1);
}
if( !defined $uuid ) {
	LOGCRIT "$me uuid parameter missing";
	exit(1);
}

LOGTITLE "Import MS$msno / $uuid";

# Lock file
my $lockfile = "/var/lock/import_${msno}_${uuid}.lock";
open my $lockfilefh, '>', $lockfile or die "$me CRITICAL Could not open LOCK file $lockfile: $!";
my $lock_success = flock $lockfilefh, 2+4; #LOCK_EX+LOCK_NB
if( !$lock_success) {
	LOGCRIT "$me CRITICAL Lockfile is already locked - another instance running.";
	exit(2);
}
print $lockfilefh $$;

# Open Import status file
eval {
	Loxone::Import::statusgetfile( msno=>$msno, uuid=>$uuid, log=>$log );
};
if( $@ ) {
	my $error = "$me statusgetfile: Cannot lock status file - already locked --> $@";
	LOGCRIT $error;
	exit(3);
}

my %miniservers = LoxBerry::System::get_miniservers();
if( !defined $miniservers{$msno} ) {
	my $error = "$me get_miniservers: Miniserver no. $msno not defined on your LoxBerry.";
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

LOGINF "$me Logfile: $log->{filename}";

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
	my $error = "$me new Import: Error --> $@";
	LOGCRIT $error;
	# $import is undef when the constructor died - do not dereference it
	supdate( {
		name => ($import && $import->{statobj}) ? $import->{statobj}->{name} : undef,
		status => "error",
		errortext => $error
	} );
	exit(4);
}
supdate( { name => $import->{statobj}->{name} } );

# A control can have several statistics series: the classic file under its own
# uuid, and/or one file per statistics group ("<uuid>_<group>") as the newer
# meter blocks use them.
my @series;
my $months_count_full = 0;

eval {
	@series = $import->getStatSeries();
	$months_count_full += scalar @{$_->{months}} foreach (@series);
	LOGDEB "$me " . scalar(@series) . " series, $months_count_full month files in total.";
};
if( $@ ) {
	my $error = "$me getStatSeries: Could not get Statistics list from Loxone Miniserver MS$msno --> $@";
	LOGCRIT $error;
	supdate( {
		name => $import->{statobj}->{name},
		status => "error",
		errortext => $error
	} );
	exit(2);
}
if( !$months_count_full ) {
	my $error = "No Loxone Statistics available for $import->{statobj}->{name}. Finished by doing nothing ;-)";
	LOGOK $error;
	supdate( {
		name => $import->{statobj}->{name},
		status => "finished",
		errortext => $error,
		record_count_finished => 0
	} );
	exit(0);
}

my $months_count_finished = 0;
my $record_count = 0;
my $duration_time_secs = 0;
# print Data::Dumper::Dumper( $import->{statlistAll} );

foreach my $serie ( @series ) {

my $statkey = $serie->{statkey};

# The classic series needs a known output mapping; a statistics group names its
# own columns and is imported regardless.
if( !defined $serie->{group} and $import->{nomapping} ) {
	LOGWARN "$me Skipping the classic statistics of $statkey - no known output mapping for this block type.";
	next;
}
$import->{usefileoutputs} = defined $serie->{group} ? 1 : 0;

LOGINF "$me === Series $statkey"
       . (defined $serie->{group} ? " (statistics group $serie->{group})" : "")
       . ", " . scalar @{$serie->{months}} . " months";

foreach my $yearmonth ( @{$serie->{months}} ) {
	supdate( { current => (defined $serie->{group} ? "$yearmonth (group $serie->{group})" : $yearmonth) } );
	my $starttime = Time::HiRes::time();

	LOGINF "$me Fetching $statkey Month: $yearmonth";
	my $monthdata;
	eval {
		$monthdata = $import->getMonthStat( yearmon => $yearmonth, statkey => $statkey );
	};
	if( $@ ) {
		my $error = "$me getMonthStat $statkey/$yearmonth: $@";
		LOGCRIT $error;
		supdate( {
			status => "error",
			errortext => $error
		} );
		exit(5);
	}
	# print STDERR Data::Dumper::Dumper( $monthdata ) . "\n";
	if ( !$monthdata ) {
		LOGWARN "$me getMonthStat $statkey/$yearmonth: No data to send. Skipping";
		next;
	}
	LOGINF "$me   Datasets " . scalar @{$monthdata->{values}};

	my $fullcount;
	eval {
		$fullcount = $import->submitData( $monthdata );
	};
	if( $@ ) {
		my $error = "$me submitData $statkey/$yearmonth: $@";
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
	
	# Key by series as well, otherwise the months of several statistics groups
	# would overwrite each other in the status file.
	$status->{finished}{ defined $serie->{group} ? "$yearmonth-g$serie->{group}" : $yearmonth } = \%finished;

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
}   # end of the series loop

LOGOK "$me All series and months finished.";
supdate( { status=>"finished" });

exit(0);

sub END {
	my $me = Globals::whoami();
	if( $statusobj ) {
		if ( $status->{status} ne "finished" ) {
			supdate( { status => "error" } );
			LOGCRIT "$me Import exited with error.";
		}
		supdate( { 
			endtime => time(), 
			duration =>  int((time()-$status->{starttime})*1000)/1000
		} );
	}
	eval { 
		LOGEND;
	};
	if( $lock_success ) {	
		close $lockfilefh;
		unlink $lockfile;
	}
}