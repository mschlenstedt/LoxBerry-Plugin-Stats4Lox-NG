use warnings;
use strict;
use LoxBerry::System;
use LoxBerry::IO;
use Carp;
use LoxBerry::Log;
use XML::LibXML;
use FindBin qw($Bin);
use lib "$Bin/..";
use Globals;
use DateTime;
require "$lbpbindir/libs/Stats4Lox.pm";

use Data::Dumper;


$LoxBerry::IO::DEBUG=1;

########################
## LOXONE::IMPORT     ##
########################

package Loxone::Import;

use base 'Exporter';
our @EXPORT = qw (
	supdate
);


our $DEBUG = 1;
our $LocalTZ = DateTime::TimeZone->new( name => 'local' );
our $http_timeout = 120;


sub new 
{
	my $class = shift;
	my $me = Globals::whoami();
	
	if (@_ % 2) {
		Carp::croak "$me Illegal parameter list has odd number of values\n" . join("\n", @_) . "\n";
	}
	
	my %p = @_;
	
	my $self = { 
		msno =>$p{msno}, 
		uuid =>$p{uuid},
		log =>$p{log}
	};

	my $log = $self->{log};
	
	$log->DEB("$me Called");
	
	if( !defined $self->{msno} ) {
		Carp::croak("$me msno paramter missing");
	}
	# if( !defined $self->{uuid} ) {
		# Carp::croak("$me uuid parameter missing");
	# }

	my %miniservers = LoxBerry::System::get_miniservers();
	if( !defined $miniservers{$self->{msno}} ) {
		Carp::croak("$me Miniserver $self->{msno} not defined");
	}
	
	bless $self, $class;
	
	if( $self->{uuid} ) {
		
		$self->getStatsjsonElement();
		if(!defined $self->{statobj}) {
			$self->{importstatus}->{error} = 1;
			$self->{importstatus}->{errortext} = "Statobj with msno=$self->{msno} and uuid=$self->{uuid} not found";
			Carp::croak("Statobj with msno=$self->{msno} and uuid=$self->{uuid} not found");
		}
		
		$self->getLoxoneLabels();
		
		$self->setMappings();
		
		if( ! $self->{mapping} ) {
			$self->{importstatus}->{error} = 1;
			$self->{importstatus}->{errortext} = "This import has no outputs selected that can be imported";
			Carp::croak($me." ".$self->{importstatus}->{errortext});
		}
	}
	
	return $self;
}

sub new_empty
{
	my $class = shift;
	my $me = Globals::whoami();
	
	if (@_ % 2) {
		Carp::croak "$me Illegal parameter list has odd number of values\n" . join("\n", @_) . "\n";
	}
	
	my %p = @_;
	
	my $self = { 
		log =>$p{log}
	};

	my $log = $self->{log};
	
	bless $self, $class;
	return $self;
	
}

sub getStatlist
{
	my $self = shift;
	my $me = Globals::whoami();
	my $log = $self->{log};
	$log->DEB("$me Called");
	
	my $msno = $self->{msno};
	my $uuid = $self->{uuid};
	
	my $resphtml;
	my $usedcachefile=0;
	
	$log->DEB("$me Checking for cached statlist of $msno");
	my $statlistcachefile = $Globals::stats4lox->{s4ltmp}."/msstatlist_ms$msno.tmp";
	if( -e $statlistcachefile ) {
		my $modtime = (stat($statlistcachefile))[9];
		if ( defined $modtime and (time()-$modtime) < 900 ) {
			$log->DEB("$me Reading cache file $statlistcachefile");
			$resphtml = LoxBerry::System::read_file($statlistcachefile);
			if( $resphtml ) {
				$usedcachefile=1;
			}
		}
	}
	
	if( !$usedcachefile ) {
		
		# Request statlist 
		my $url = "/stats";
		my $status;
		
		my $retrycount = 3;
		my $retries = 0;
		while ( $retries < $retrycount ) {
			$retries++;
			$log->DEB("$me Acquiring download lock for Miniserver $msno");
			my $mslockfh = lockMiniserver( $msno );
			
			$log->DEB("$me Requesting stat list from Miniserver $msno (Try $retries/$retrycount)");
			($resphtml, $status) = LoxBerry::IO::mshttp_call2($msno, $url, ( timeout => $http_timeout*$retries ) );
			close $mslockfh;
			if( $resphtml and $status->{code} eq "200" ) {
				last;
			}
			$log->WARN("$me Error $status->{message} - Sleeping a bit...");
			sleep(3);
		}
	
		if( !$resphtml) {
			$log->DEB("$me ERROR no response from Miniserver ($status->{status})");
			Carp::Croak("Loxone::Import->getStatlist: ERROR no response from Miniserver ($status->{status})");
		}
		$log->DEB("$me Saving response to cachefile $statlistcachefile");
		
		eval {
			open(my $fh, '>', $statlistcachefile);
			print $fh $resphtml;
			close($fh);
		}
	}
		
	my %resultsAll;
	
	$log->DEB("$me Parsing response");
	
	my @resp = split( /\n/, $resphtml );
	my $count = 0;
	foreach my $line ( @resp ) {
		if( $line =~ /<a href="(.*)\.(\d{6}).xml">/ ) {
			my $uid = $1;
			my $yearmon = $2;
			$count++;
			# print STDERR "UID: $uid  Date: $yearmon\n";
			if( !$resultsAll{$uid} ) {
				$resultsAll{$uid} = ();
			}
			push( @{$resultsAll{$uid}}, $yearmon );
			
		}
	}
	$log->INF("$me Number of lines $count");
	$log->INF("$me Number of different uuids ". keys(%resultsAll));
	
	$self->{statlistAll} = \%resultsAll;
	$log->OK("$me Finished ok");
	
	if ( defined $uuid ) {
		my $count_month_uuid = 0;
		$count_month_uuid = @{$resultsAll{$uuid}} if( defined $resultsAll{$uuid} );
		
		if( $count_month_uuid > 0 ) {
			$log->DEB("$me Responsing array ($count_month_uuid months): " . join(",", @{$resultsAll{$uuid}}) );
			return @{$resultsAll{$uuid}};
		}
		else {
			$log->DEB("$me No elements for uuid $uuid found. Responsing empty array");
			return;
		}
	}
	else {
		$log->DEB("$me Responding with hash of all results");
		return \%resultsAll;
	}
		
	
}

sub getStatsjsonElement
{
	
	my $self = shift;
	my $me = Globals::whoami();
	my $log = $self->{log};
	
	$log->DEB("$me Called");
	
	$log->DEB("$me Opening stats.json ($Globals::statsconfig)");
	
	my $statsjsonobj = new LoxBerry::JSON;
	my $statsjson = $statsjsonobj->open( filename => $Globals::statsconfig, readonly => 1 );
	if (!$statsjson) {
		$log->DEB("$me ERROR Opening stats.json (empty)");
		return;
	}
	
	$log->DEB("$me Searching for $self->{uuid} and $self->{msno}");
	
	my @result = $statsjsonobj->find( $statsjson->{loxone}, "\$_->{uuid} eq '".$self->{uuid}."' and \$_->{msno} eq '".$self->{msno}."'");
	
	if( @result ) {
		$log->DEB("$me Found ". scalar @result ." elements");
		my $statobj = $statsjson->{loxone}[$result[0]];
		$log->DEB("$me Found stat name $statobj->{name}");
		$self->{statobj} = $statobj;
	}
	else {
		$log->DEB("$me ERROR stats.json element not found");
	}
}


sub getMonthStat {
	
	my $self = shift;
	my $me = Globals::whoami();
	my $log = $self->{log};
	my $msno = $self->{msno};
	my $uuid = $self->{uuid};
	
	$log->DEB("$me Called");
		
	my %args = @_;
	my $yearmon = $args{yearmon};
	
	if(!$uuid) {
		$log->DEB("$me ERROR uuid not defined.");
		return;
	}
	if(!$yearmon) {
		$log->DEB("$me ERROR yearmon not defined.");
		return;
	}
	
	my $url = "/stats/$uuid.$yearmon.xml";
	
	
	my $retrycount = 5;
	my $retries = 0;
	my ($respxml, $status);
	my $timedata;
	
	while ( $retries <= $retrycount ) {
		$retries++;
	
		$log->DEB("$me Acquiring download lock for Miniserver $msno");
		my $mslockfh = lockMiniserver( $msno );
		
		$log->DEB("$me Querying stat for month $yearmon (Try $retries/$retrycount)");
		$log->DEB("$me url: $url");
		
		($respxml, $status) = LoxBerry::IO::mshttp_call2($msno, $url, ( timeout => ($http_timeout*$retries) ) );
		close $mslockfh;
		
		my $msg = "$me HTTP $status->{status}";
		if( $status->{code} == 200 ) {
			$log->OK($msg);
		}
		elsif ( $status->{code} == 404 ) {
			$log->WARN($msg);
		}
		elsif ( $status->{code} == 500 ) {
			$log->ERR($msg);
		}
		else {
			$log->ERR($msg);
		}
		
		if($respxml) {
			eval{
				$timedata = $self->parseStatXML_REGEX( yearmon=>$yearmon, xml=>\$respxml );
			};
			if( $@ ) {
				my $exception = $@;
				if( $retries >= $retrycount ) {
					die $exception;
				}
				$log->WARN("$me Download possibly corrupt --> $exception");
			}
			else {
				last;
			}
		}
		
		if( $status->{code} == 404 and $retries >= $retrycount ) {
			$log->WARN("$me ERROR This file really seems to not exist. Skipping this month");
			last;
		}
		
		my $sleep = 5*$retries*$retries;
		$log->WARN("$me Sleeping $sleep seconds before retry...");
		sleep($sleep);
	}
	
	if( !$respxml and $status->{code} != 404 ) {
		my $errormsg = "$me Could not get data from MS $msno / $yearmon";
		$log->ERR($errormsg);
		die $errormsg;
	}
	
	return $timedata;
	

}

##### XML variant of parseStatXML
#####

sub parseStatXML
{
	my $self = shift;
	my $me = Globals::whoami();
	my $log = $self->{log};
	my $msno = $self->{msno};
	my $uuid = $self->{uuid};
	
	my %args = @_;
	my $yearmon = $args{yearmon};
	my $respxml = $args{xml};
	
	my $parser = XML::LibXML->new();
	my $statsxml;
	$log->DEB("$me Loading XML");
	eval {
		$statsxml = XML::LibXML->load_xml( string => $respxml, no_blanks => 1);
	};
	if( $@ ) {
		$log->DEB("$me ERROR Could not load XML (month $yearmon)");
		return;
	}
	
	my %result;
	
	my $root = $statsxml->getDocumentElement;
	foreach( $root->attributes ) {
		# print STDERR "Attribute: " . $_->nodeName . " Value: " . $_->value . "\n";
		$result{StatMetadata}{$_->nodeName} = $_->value;
	}
	
	my $NumOutputs = defined $root->{NumOutputs} ? $root->{NumOutputs} : 1;
	
	my @statsnodes = $statsxml->findnodes('/Statistics/S');
	my @timedata;
	
	foreach my $node ( @statsnodes ) {
		# print STDERR "mainnode Node Name: ".$node->{T}."\n";
		my %data;
		my $data_time = createDateTime($node->{T}, 0, $log); 
		$data{T} =  $data_time->epoch;
		$data{val} = ();
		# foreach my $statattr ( $node->attributes ) {
			# next if ($statattr->nodeName eq "T" );
			# # $data{$statattr->nodeName} = $statattr->value;
			# push @{$data{val}}, \{ $statattr->nodeName => $statattr->value };
			# $result{StatMetadata}{usedLabels}{$statattr->nodeName} = 1;
		# }
		
		for( my $i = 0; $i < $NumOutputs; $i++ ) {
			my $valname = $i == 0 ? "V" : "V$i";
			push @{$data{val}}, $node->{$valname};
		}

		push @timedata, \%data;
	}
	
	$result{values} = \@timedata;
	
	$log->DEB("$me Timestamp count found " . scalar @timedata);
	
	return \%result;
	
}


#### REGEX variant of parseStatXML
sub parseStatXML_REGEX
{
	my $self = shift;
	my $me = Globals::whoami();
	my $log = $self->{log};
	my $msno = $self->{msno};
	my $uuid = $self->{uuid};
	
	my %args = @_;
	my $yearmon = $args{yearmon};
	my $respxml = ${$args{xml}};
	
	my $line;
	my %result;
	
	$log->DEB("$me Reading XML (REGEX)");
	
	# Split file to lines
	my @xml = split("\n", $respxml);
	
	# print STDERR "respxml size: " . length($respxml) . " linecount: " . scalar @xml . "\n";
	
	
	# Check XML header (line 1)
	$line = shift @xml;
	# print STDERR "Line1: $line\n";
	if( index( $line, '<?xml' ) == -1 ) {
		$log->DEB("$me ERROR Seems not to be XML (month $yearmon)");
		return;
	}
	
	# Get Statistics header (line 2)

	$line = shift @xml;
	($result{StatMetadata}{Name}) = $line =~ /<Statistics.*Name="(.*?)"/;
	($result{StatMetadata}{NumOutputs}) = $line =~ /<Statistics.*NumOutputs="(.*?)"/;
	($result{StatMetadata}{Outputs}) = $line =~ /<Statistics.*Outputs="(.*?)"/;
	$log->DEB("$me Name:$result{StatMetadata}{Name} Outputs:($result{StatMetadata}{Outputs}) NumOutputs:$result{StatMetadata}{NumOutputs}");
	my $NumOutputs = $result{StatMetadata}{NumOutputs};

	# Loop further lines (line 3+)
	
	my @timedata;
	my $bulkcount=0;
	foreach $line ( @xml ) {
		my %data;
		my ($data_time) = $line =~ /<S.*T="(.*?)"/;
		next if (!$data_time);
		$bulkcount++;
		$log->DEB("$me Readed $bulkcount records") if( $bulkcount%2000 == 0 );
		# print STDERR "data_time: $data_time\n";
		$data_time = createDateTime($data_time, 0, $log); 
		$data{T} =  $data_time->epoch;
		$data{val} = ();
		# print STDERR "Time $data{T} ";
		for( my $i = 1; $i <= $NumOutputs; $i++ ) {
			my $valname = $i == 1 ? "V" : "V$i";
			my ($val) = $line =~ /<S.*$valname="(.*?)"/;
			push @{$data{val}}, $val;
		#	print STDERR "$valname=$val ";
		}
		#print STDERR "\n";
		push @timedata, \%data;
	}
	
	$result{values} = \@timedata;
	
	$log->DEB("$me Timestamp count found " . scalar @timedata);
	
	return \%result;
	
}


sub getLoxoneLabels {
	my $self = shift;
	my $me = Globals::whoami();
	my $log = $self->{log};
	my $msno = $self->{msno};
	my $uuid = $self->{uuid};
	
	$log->INF("$me Querying MS$msno to get output labels");
	my ($code, $data) = Stats4Lox::msget_value( $msno, $uuid );
	
	if( $code ne "200" ) {
		$log->ERR("$me Could not get live response of block for labels");
		return;
	}

	$self->{LoxoneLabels} = $data;
	return 1;
	
}

sub setMappings {

	my $self = shift;
	my $me = Globals::whoami();
	my $log = $self->{log};
	my $statobj = $self->{statobj};
	my %lxlabels = map { $_->{Key} => $_->{Name} } @{$self->{LoxoneLabels}};
	
	# statlabels now contains: Default => Default, output0 => AQ,...
	my %statlabels = map { $_ => $lxlabels{$_} } @{$statobj->{outputs}};
	
	
	
	$log->DEB("$me Called");
	my $type = $statobj->{type};
	my $type_uc = uc($type);
	$log->DEB("$me Stat element type is $type");
	
	# Default mappings for known types
	
	my @mappings;
	if( defined $Globals::ImportMapping->{$type_uc} ) {
		@mappings = @{$Globals::ImportMapping->{$type_uc}};
	}
	else {
		@mappings = @{$Globals::ImportMapping->{Default}};
	}
	
	
	# Remove mappings to outputs that are not enabled in stats.json
	
	my @filtered_mappings;
	foreach my $mapping (@mappings) {
		# print Data::Dumper::Dumper($mapping) . "\n";
		my $mapkey = $mapping->{statpos};
		my $maplabel = $mapping->{lxlabel};
		# print STDERR "mapkey: $mapkey  maplabel: $maplabel\n";

		if( grep { $statlabels{$_} eq $maplabel } keys %statlabels ) {
			# Label (e.g. AQ) found in mapping
			push @filtered_mappings, $mapping;
		}
	}
	
	
	my @printmappings;
	foreach my $mapping ( @filtered_mappings ) {
		push @printmappings, "«$mapping->{statpos}»→«$mapping->{lxlabel}»";
	}
	$log->INF("$me Used mapping is: " . join(" ", @printmappings));
		
	$self->{mapping} = \@filtered_mappings;
	
}

sub submitData
{
	my $self = shift;
	my $me = Globals::whoami();
	my $log = $self->{log};
	my $statobj = $self->{statobj};
	my $mappings = $self->{mapping};
	
	my ($data) = @_;
	
	$log->DEB("$me Called");
	
	my @bulkdata;
	my $bulkcount = 0;
	my $bulkmax = $Globals::influx->{influx_bulk_blocksize};
	my $fullcount = 0;
	
	my $measurementname = $statobj->{measurementname};
	if( !defined $measurementname or $measurementname eq "" ) {
		if( defined $statobj->{description} and $statobj->{description} ne "" ) {
			$measurementname = $statobj->{description};
		} 
		else {
			$measurementname = $statobj->{name};
		}
	}
	
	# Loop all timestamps
	foreach my $record ( @{$data->{values}} ) {
		
		my %influxrecord = (
				timestamp => $record->{T}*1000000000,		# Epoch Nanoseconds
				msno => $statobj->{msno},					# Miniserver No. in LoxBerry
				uuid => $statobj->{uuid},					# Loxone UUID
				name => $statobj->{name},					# Loxone Name of the block
				description => $statobj->{description},		# Loxone Description (shown in Loxone visu)
				category => $statobj->{category},			# Loxone Category name
				room => $statobj->{room},					# Loxone Room name
				type => $statobj->{type},					# Loxone Type of control
				measurementname => $measurementname,		# User-defined name of the measurement, default is name
				source => 'import',							# Tag that this data was imported
			);
		# Values of a timestamp are distributed according to the mapping
		# so we walk through the mapping to get the correct values
		
		my @values = ();
		foreach my $mapping ( @{$mappings} ) {
			
			my $statpos = $mapping->{statpos};
			my $label = $mapping->{lxlabel};
			my $value = $record->{val}[$statpos];
			push @values, { key => $label, value => $value };
			
		}
		$influxrecord{values} = \@values;
		push @bulkdata, \%influxrecord;
		# print STDERR Data::Dumper::Dumper( $influxrecord{values} );
		$bulkcount++;
		$fullcount++;
		
		$log->DEB("$me Prepared $bulkcount records") if( $bulkcount%2000 == 0 );
		
		if( $bulkcount >= $bulkmax ) {
			
			# Bulk is full - transmit
			$log->DEB("$me Transmitting $bulkcount records");
			eval {
				Stats4Lox::lox2telegraf( \@bulkdata, undef );
			};
			if( $@ ) {
				$log->ERR("$me lox2telegraf excepted: $@");
			}
			Time::HiRes::sleep( $Globals::influx->{influx_bulk_delay_secs} );
			$bulkcount = 0;
			@bulkdata = ();
			
		}
	
	}

	# Finally, submit the rest of the bulk
	if( @bulkdata ) {
		$log->DEB("$me Transmitting $bulkcount records");
		eval {
			Stats4Lox::lox2telegraf( \@bulkdata, undef );
		};
	}
	
	# Month done
	return $fullcount;
	
}




###
### This is the original routine that fails if a Loxone statistic time is inside of a daylight saving switch timeframe
###


# sub createDateTime
# {
	# my ($timestr) = @_;
	# my $me = Globals::whoami();
	
	# if( $timestr =~ /(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2}):(\d{2})/ ) {
		# my $ye = $1;
		# my $mo = $2;
		# my $da = $3;
		# my $ho = $4;
		# my $mi = $5;
		# my $se = $6;
		
		# my $dt = DateTime->new(
			# year       => $ye,
			# month      => $mo,
			# day        => $da,
			# hour       => $ho,
			# minute     => $mi,
			# second     => $se,
			# time_zone  => $LocalTZ
		# );
	
		# return $dt;
	# }
# }



sub createDateTime
{
	my ($timestr, $retry, $log) = @_;
	my $me = Globals::whoami();
		
	if( $timestr =~ /(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2}):(\d{2})/ ) {
		my $ye = $1;
		my $mo = $2;
		my $da = $3;
		my $ho = $4;
		my $mi = $5;
		my $se = $6;
		
		my $dt;
		
		eval {
					
			$dt = DateTime->new(
				year       => $ye,
				month      => $mo,
				day        => $da,
				hour       => $ho,
				minute     => $mi,
				second     => $se,
				time_zone  => $LocalTZ
			);
		};
		
		if( $@ and !$retry) {
			$log->WARN("$me Exception on date conversion ($timestr): $@") if($log);
			# print STDERR "Trying to modify timestamp (Loxone daylight saving issue)\n";
			
			# print "Offset: -1 minute\n";
			$mi -= 1;
			if( $mi < 0 ) {
				$mi = 59;
				$ho -= 1;
			}
			if( $ho < 0 ) {
				$ho = 0;
				$mi = 0;
				$se = 0;
			}
			my $newtimestr = sprintf("%04d-%02d-%02d %02d:%02d:%02d", $ye, $mo, $da, $ho, $mi, $se);
			$log->INF("$me Trying offset -1 minute: $newtimestr...") if($log);
			$dt = createDateTime($newtimestr, 1);
		}
		elsif( $@ ) {
			$log->CRIT("$me cannot parse timestamp $timestr after retry: $@") if($log);
			die "$@";
		}
	
		return $dt;
	}
	
}




sub statusgetfile {
	
	my %p = @_;
	my $me = Globals::whoami();
	my $log = $p{log};
	my $msno = $p{msno};
	my $uuid = $p{uuid};
	
	
	# Creating state json
	$log->DEB("$me Creating status file");
	`mkdir -p $Globals::stats4lox->{importstatusdir}`;

	my $statusfilename = $Globals::stats4lox->{importstatusdir}."/import_${msno}_${uuid}.json";
	
	$main::statusobj = new LoxBerry::JSON;
	$main::status = $main::statusobj->open( filename => $statusfilename, writeonclose => 1 );
	$log->INF("$me Status file: " . $main::statusobj->filename());
	
	# Lock status file
	open($main::statusfh, ">>", $statusfilename);
	statuslock($main::statusfh);
}

sub statuslock {
    my ($fh) = @_;
	my $me = Globals::whoami();
    # flock($fh, 2) or die "Cannot lock - $!\n";
}

# supdate --> Status Update
sub supdate {

	my ($data) = @_;
	my $me = Globals::whoami();
	
	foreach( keys %{$data} ) {
		$main::status->{$_} = $data->{$_};
	}
	$main::status->{statustime} = time();
	$main::statusobj->write();
	
}

sub lockMiniserver {
	my $msno = shift;
	my $me = Globals::whoami();
	my $mslockfile = $Globals::stats4lox->{s4ltmp}."/miniserver_${msno}_download.lock";
	open my $fh, '>', $mslockfile or die "$me CRITICAL Could not open LOCK file $mslockfile: $!";
	flock $fh, 2;
	return $fh;
}

sub DESTROY {

		my $self = shift;
		my $me = Globals::whoami();
		my $log = $self->{log};
	
		$log->DEB("$me: Called");
		
}
#####################################################
# Finally 1; ########################################
#####################################################
1;
