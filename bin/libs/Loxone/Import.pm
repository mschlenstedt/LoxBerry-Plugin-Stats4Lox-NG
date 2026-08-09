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


# Was permanently enabled and dumped every HTTP response of every month of
# every block to stderr, which ends up in the webserver error log.
$LoxBerry::IO::DEBUG=0;

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

		# Do NOT abort here any more.
		#
		# The newer blocks store their data in statistics groups whose columns
		# are named by the file itself, so they need no mapping at all. Dying
		# here made those blocks unimportable even though their data was
		# available all along.
		if( ! $self->{mapping} or ! @{$self->{mapping}} ) {
			$self->{nomapping} = 1;
			$log->WARN("$me No known output mapping for type '"
			           . ($self->{statobj}->{type} // '?')
			           . "'. Classic statistics of this block cannot be imported;"
			           . " statistics groups are unaffected.");
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
			# Note: Carp::Croak (capital C) does not exist and would have died
			# with "Undefined subroutine" instead of this message.
			Carp::croak("Loxone::Import->getStatlist: ERROR no response from Miniserver ($status->{status})");
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

# Returns the statistics series of this control as a list of hashrefs:
#   { statkey => "<uuid>" or "<uuid>_<group>", group => undef|N, months => [...] }
#
# Since Loxone Config 16/17 the new meter blocks (Meter*, EFM, Wallbox, ...)
# do not store their statistics under the plain control uuid any more, but per
# statistics group as "<uuid>_<group>" - a block can have several of them, and
# a group can hold several values per timestamp.
#
# Looking only for the plain uuid was the reason those blocks reported
#   "No Loxone Statistics available for ... Finished by doing nothing ;-)"
# while the Miniserver held years of data for them (forum #609, #759).
sub getStatSeries
{
	my $self = shift;
	my $me = Globals::whoami();
	my $log = $self->{log};
	my $uuid = $self->{uuid};

	$self->getStatlist() if( !$self->{statlistAll} );
	my $all = $self->{statlistAll} || {};

	my @series;

	# The classic case: one file per control
	if( defined $all->{$uuid} and ref($all->{$uuid}) eq 'ARRAY' and @{$all->{$uuid}} ) {
		push @series, { statkey => $uuid, group => undef, months => [ sort @{$all->{$uuid}} ] };
	}

	# Statistics groups of the newer blocks
	foreach my $key ( sort keys %{$all} ) {
		next if( $key !~ /^\Q$uuid\E_(\d+)$/ );
		next if( ref($all->{$key}) ne 'ARRAY' or !@{$all->{$key}} );
		push @series, { statkey => $key, group => $1, months => [ sort @{$all->{$key}} ] };
	}

	if( !@series ) {
		$log->WARN("$me No statistics found on the Miniserver for $uuid");
		return;
	}

	foreach my $s ( @series ) {
		$log->OK( sprintf("%s Series '%s'%s: %d months (%s - %s)", $me, $s->{statkey},
			(defined $s->{group} ? " (statistics group $s->{group})" : ""),
			scalar @{$s->{months}}, $s->{months}[0], $s->{months}[-1]) );
	}

	return @series;
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

	# statkey is the plain uuid for classic statistics, or "<uuid>_<group>"
	# for the statistics groups of the newer blocks.
	my $statkey = defined $args{statkey} ? $args{statkey} : $uuid;

	if(!$uuid) {
		$log->DEB("$me ERROR uuid not defined.");
		return;
	}
	if(!$yearmon) {
		$log->DEB("$me ERROR yearmon not defined.");
		return;
	}

	my $url = "/stats/$statkey.$yearmon.xml";
	
	
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
		if( !$data_time ) {
			$log->WARN("$me Skipping record with unusable timestamp '" . ($node->{T} // '') . "'");
			next;
		}
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
	# Only present in the statistics groups of the newer blocks
	($result{StatMetadata}{StatsGroup}) = $line =~ /<Statistics.*StatsGroup="(.*?)"/;

	# The Outputs attribute names the columns of this file, in order. For the
	# newer blocks these are already technical identifiers (actual, total,
	# totalNeg, OYt, ...) and can be used as field names directly.
	if( defined $result{StatMetadata}{Outputs} and $result{StatMetadata}{Outputs} ne '' ) {
		$result{StatMetadata}{OutputNames} = [ split(/,/, $result{StatMetadata}{Outputs}) ];
	}

	$log->DEB("$me Name:".($result{StatMetadata}{Name}//'')
	          ." Outputs:(".($result{StatMetadata}{Outputs}//'').")"
	          ." NumOutputs:".($result{StatMetadata}{NumOutputs}//'')
	          .(defined $result{StatMetadata}{StatsGroup} ? " StatsGroup:$result{StatMetadata}{StatsGroup}" : ''));
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
		my $orig_time = $data_time;
		$data_time = createDateTime($data_time, 0, $log);
		if( !$data_time ) {
			# Skip the single record instead of killing the whole month
			$log->WARN("$me Skipping record with unusable timestamp '$orig_time'");
			next;
		}
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

# Output name -> abbreviation, for one block type, from the element catalogue.
#
# The catalogue holds both: name is the output as the LoxPLAN names it (AQ, OMr1),
# shortname the abbreviation a current Miniserver reports live (Ct, Mrd). Entries
# without an abbreviation are kept in the hash with their empty value - the
# callers decide what to do with them, and they differ: deriveMapping() falls
# back to the output name, translateGroupOutputs() to a value from the table.
#
# Cached per type, because a single import calls this once per month file.
sub outputShortnames
{
	my ($self, $type) = @_;
	return {} if( !defined $type or $type eq '' );

	$self->{_shortnames} = {} if( ref($self->{_shortnames}) ne 'HASH' );
	return $self->{_shortnames}->{ uc($type) }
		if( defined $self->{_shortnames}->{ uc($type) } );

	my %byname;
	eval {
		my $elemfile = "$LoxBerry::System::lbptemplatedir/lang/loxelements_en.json";
		my $obj = LoxBerry::JSON->new();
		my $elems = $obj->open( filename => $elemfile, readonly => 1 );
		my $e = $elems ? $elems->{ uc($type) } : undef;
		foreach my $o ( @{ $e->{outputs} || [] } ) {
			next if( !defined $o->{name} );
			$byname{ $o->{name} } = $o->{shortname};
		}
	};
	$self->{_shortnames}->{ uc($type) } = \%byname;
	return \%byname;
}

# Column names of a statistics group file -> the field names the live grabber
# writes for the same outputs.
#
# A group file names its own columns (actual, total, totalNeg, storageLevel),
# and those names are not the ones the block reports live. Importing them
# unchanged puts the history into a field of its own, right next to the field
# the grabber fills every cycle with the very same meter reading.
#
# %Globals::StatGroupMapping says which OUTPUT a column belongs to; the
# abbreviation for that output comes from the element catalogue of this block
# type. A column nobody listed keeps its own name.
sub translateGroupOutputs
{
	my ($self, $columns) = @_;
	my $me = Globals::whoami();
	my $log = $self->{log};

	my $type = $self->{statobj} ? $self->{statobj}->{type} : undef;
	my $short = $self->outputShortnames( $type );

	my @fields;
	foreach my $col ( @{$columns} ) {

		my $rule = $Globals::StatGroupMapping{$col};
		my $field;

		foreach my $out ( @{ $rule->{outputs} || [] } ) {
			# The first output this type actually has decides. That is what
			# makes one table work for all of them - MeterAbsSt has OMr1 and
			# OMr2, MeterPUni only OMr, a Wallbox neither.
			next if( !exists $short->{$out} );
			my $sn = $short->{$out};
			$field = ( defined $sn and $sn ne '' ) ? $sn : $rule->{fallback};
			last if( defined $field );
		}

		if( !defined $field ) {
			$log->WARN("$me Column '$col' has no live counterpart on type '"
			           . ($type // '?') . "' - imported under its own name");
			push @fields, $col;
			next;
		}

		$log->INF("$me Column '$col' -> field '$field'") if( $field ne $col );
		push @fields, $field;
	}

	return \@fields;
}

# LoxAPP3.json of one Miniserver, cached
#####################################################
# 285 kB and a quarter of a second on the test installation, and everything that
# wants to know something about statistics needs it: the import once per block,
# the detail view of the web interface on every open. Cached like the statistics
# list next to it, in the same ramdisk and with the same lifetime.
#
# A stale cache costs nothing worth fearing: it describes which outputs a block
# records, and that changes when somebody edits the Loxone configuration - never
# between two clicks.
#####################################################
sub loxapp3
{
	my ($msno, $log) = @_;
	my $me = Globals::whoami();

	my $cachefile = $Globals::stats4lox->{s4ltmp} . "/msloxapp3_ms$msno.tmp";
	my $raw;

	if( -e $cachefile ) {
		my $modtime = (stat($cachefile))[9];
		if( defined $modtime and (time()-$modtime) < 900 ) {
			$raw = LoxBerry::System::read_file($cachefile);
		}
	}

	if( !$raw ) {
		require LoxBerry::IO;
		my $status;
		($raw, $status) = LoxBerry::IO::mshttp_call2( $msno, "/data/LoxAPP3.json" );
		if( !$raw ) {
			$log->WARN("$me MS$msno: Could not read LoxAPP3.json ("
			           . ($status->{code} // '?') . ")") if( $log );
			return;
		}
		eval {
			open( my $fh, '>', $cachefile );
			print $fh $raw;
			close $fh;
		};
	}

	my $app;
	eval { require JSON; $app = JSON::decode_json( $raw ); };
	if( $@ or !$app ) {
		$log->WARN("$me MS$msno: LoxAPP3.json could not be parsed: $@") if( $log );
		# A broken cache file must not survive the request that found it broken.
		unlink $cachefile;
		return;
	}
	return $app;
}


# Which fields would an import write for this block?
#####################################################
# For the web interface, which until now built this out of $Globals::ImportMapping
# - a table holding ENERGY, FRONIUS and a Default entry that matches the output
# called "Default" on EVERY block. So the block list promised an import for every
# block in the house, including those where no statistics are switched on in the
# Miniserver at all (issue #74).
#
# The answer belongs here, next to the code that performs the import, so that the
# two cannot drift apart again - which is exactly how the display got wrong.
#
# Takes msno and uuid, no entry in stats.json required: the detail view is open
# before a block is added. Returns a hashref:
#
#   { statistics   => 0|1,      an import knows what to write for this block
#     recording    => 0|1,      the LoxPLAN says statistics are switched on
#     borrowedfrom => "name",   set when the mapping comes from another block
#     fields       => [ ... ] } the field names an import would write
#
# The two flags disagree in a case that really occurs: on the test installation
# two Energy blocks carry StatsType 11 and have 48 months of files on the
# Miniserver, while LoxAPP3 holds neither statistic nor statisticV2 for them.
# Those are answered from a block of the same kind - see referenceMapping().
# recording without statistics is what is left: it records, and not even a
# neighbour could say what.
#####################################################
sub importFields
{
	my %p = @_;
	my $me = Globals::whoami();
	my ($msno, $uuid, $log) = ( $p{msno}, $p{uuid}, $p{log} );

	# The caller may pass the live output names it has just fetched anyway -
	# see default_only_mapping(), which needs them and which this must apply
	# too, or the list would name a field the import does not write.
	my $livenames = ( ref($p{livenames}) eq 'ARRAY' ) ? $p{livenames} : undef;

	my $result = { statistics => 0, recording => 0, fields => [] };
	return $result if( !defined $msno or !defined $uuid );

	# The block from our parsed LoxPLAN - for its type and its connectors
	my ($ctrl, $ctype);
	eval {
		my $obj = LoxBerry::JSON->new();
		my $plan = $obj->open(
			filename => $Globals::stats4lox->{loxplanjsondir} . "/ms$msno.json",
			readonly => 1 );
		if( $plan ) {
			$ctrl  = $plan->{controls}->{$uuid};
			$ctype = $ctrl->{Type} if( $ctrl );
		}
	};
	return $result if( !$ctrl );
	$result->{recording} = ( $ctrl->{StatsType} and $ctrl->{StatsType} ne '0' ) ? 1 : 0;

	my $app = loxapp3( $msno, $log ) or return $result;

	# LoxAPP3 keys are the control uuids, but not necessarily in the same case
	my $stat;
	foreach my $k ( keys %{ $app->{controls} || {} } ) {
		next if( lc($k) ne lc($uuid) );
		$stat = $app->{controls}->{$k};
		last;
	}
	# translateGroupOutputs, outputShortnames and referenceMapping work on an
	# object; msno, uuid and the type are all they take from it.
	my $self = Loxone::Import->new_empty( log => $log );
	$self->{statobj} = { type => $ctype };
	$self->{msno} = $msno;
	$self->{uuid} = $uuid;
	my $short = $self->outputShortnames( $ctype );

	# No definition of its own - the same fallback the import uses, so that the
	# list shows what an import would really do.
	if( !$stat or ( !$stat->{statistic} and !$stat->{statisticV2} ) ) {
		return $result if( !$result->{recording} );
		my $ref = $self->referenceMapping( $app );
		return $result if( !$ref or !@{$ref} );
		$ref = default_only_mapping( $ref, $livenames, $log );
		$result->{statistics} = 1;
		$result->{borrowedfrom} = $self->{refname};
		$result->{fields} = [ map { $_->{lxlabel} } @{$ref} ];
		return $result;
	}
	$result->{statistics} = 1;

	my @fields;

	# Classic statistics: the column names its output by connector uuid
	if( ref($stat->{statistic}->{outputs}) eq 'ARRAY' ) {
		my @classic;
		foreach my $o ( @{ $stat->{statistic}->{outputs} } ) {
			my $key = defined $o->{uuid} ? $ctrl->{connectors}->{ lc($o->{uuid}) } : undef;
			next if( !defined $key );
			my $sn = $short->{$key};
			push @classic, { statpos => ($o->{id} // 0),
			                 lxlabel => ( defined $sn and $sn ne '' ) ? $sn : $key };
		}
		push @fields, map { $_->{lxlabel} }
		              @{ default_only_mapping( \@classic, $livenames, $log ) } if( @classic );
	}

	# Statistics groups: the column names itself, and the name is translated
	my @cols;
	foreach my $g ( @{ $stat->{statisticV2}->{groups} || [] } ) {
		foreach my $dp ( @{ $g->{dataPoints} || [] } ) {
			push @cols, $dp->{output} if( defined $dp->{output} );
		}
	}
	push @fields, @{ $self->translateGroupOutputs( \@cols ) } if( @cols );

	# Same field from two groups would make two identical marks in the table
	my %seen;
	$result->{fields} = [ grep { !$seen{$_}++ } @fields ];

	return $result;
}


# Derives the import mapping from the Miniserver instead of a hard coded table.
#
# LoxAPP3.json describes for every block with statistics which column holds
# which output:
#   statistic: { outputs: [ { id: 0, name: "Gesamtverbrauch", uuid: "...3893" },
#                           { id: 1, name: "Leistung",        uuid: "...3894" } ] }
# The uuid is the output connector; its key comes from ms<n>.json, which
# readloxplan fills for blocks with statistics. id is the column index.
#
# This is what the hard coded $ImportMapping table always was - a manual
# transcription of information the Miniserver supplies per block instance.
# Derived from the instance it also covers blocks nobody entered into the
# table, and it survives Loxone renaming its output labels (AQ -> Ct).
#
# Returns an arrayref like $ImportMapping, or undef.
sub deriveMapping
{
	my $self = shift;
	my $me = Globals::whoami();
	my $log = $self->{log};
	my $msno = $self->{msno};
	my $uuid = $self->{uuid};

	# Connector uuid -> key, and the block type, from our parsed LoxPLAN
	my $connectors;
	my $ctype;
	eval {
		my $loxplanjson = $Globals::stats4lox->{loxplanjsondir} . "/ms" . $msno . ".json";
		my $obj = LoxBerry::JSON->new();
		my $plan = $obj->open( filename => $loxplanjson, readonly => 1 );
		if( $plan ) {
			$connectors = $plan->{controls}->{$uuid}->{connectors};
			$ctype      = $plan->{controls}->{$uuid}->{Type};
		}
	};
	if( $@ or !$connectors or !%{$connectors} ) {
		$log->DEB("$me No connector keys for $uuid in ms$msno.json - cannot derive a mapping");
		return;
	}

	# Connector key -> the label the Miniserver reports today.
	#
	# The connector in the LoxPLAN is still called "AQ", while a current
	# Miniserver reports "Ct" for the same output - and the live grabber writes
	# its field under that current name. Without translating, imported history
	# and live data would end up in two different fields of the same
	# measurement. The element definitions hold both: Name is the old label,
	# ShortName the current one.
	my $short = $self->outputShortnames( $ctype );
	my %tolive = map { $_ => $short->{$_} }
	             grep { defined $short->{$_} and $short->{$_} ne '' } keys %{$short};
	$log->DEB("$me Label translation for " . ($ctype // '?') . ": "
	          . scalar(keys %tolive) . " outputs") if( defined $ctype );

	# Statistics definition from the Miniserver
	my $app = loxapp3( $msno, $log );
	if( !$app ) {
		$log->WARN("$me Could not read LoxAPP3.json from MS$msno");
		return;
	}

	# Reading only "statistic" and not "statisticV2" is deliberate, even though
	# on a current installation 20 of 23 blocks with statistics carry only the V2
	# key. Measured, not assumed:
	#
	#   3 blocks   statistic     -> classic file <uuid>.<YYYYMM>.xml, needs this
	#                               mapping to name its columns
	#  20 blocks   statisticV2   -> only group files <uuid>_<n>.<YYYYMM>.xml,
	#                               which name their own columns in the Outputs
	#                               attribute, so no mapping is needed - see
	#                               submitData()
	#   0 blocks   statisticV2 WITH a classic file - the only combination that
	#                               would need a V2 mapping does not occur
	#
	# Should Loxone ever ship that combination, this is the place to extend -
	# but not by reading statisticV2. Measured on a live Miniserver, a group
	# there carries nothing but the same column name the file already holds:
	#
	#   groups: [ { dataPoints: [ { output: "actual" } ] },
	#             { dataPoints: [ { output: "total" }, { output: "totalNeg" } ] } ]
	#
	# No uuid, no connector - so LoxAPP3 offers no way from a group column to an
	# output of the block. %Globals::StatGroupMapping is that way, and
	# translateGroupOutputs() would be the place to reuse.
	#
	# LoxAPP3 keys are the control uuids, but not necessarily in the same case
	my $stat;
	foreach my $k ( keys %{ $app->{controls} || {} } ) {
		next if( lc($k) ne lc($uuid) );
		$stat = $app->{controls}->{$k}->{statistic};
		last;
	}
	if( !$stat or ref($stat->{outputs}) ne 'ARRAY' ) {
		$log->INF("$me LoxAPP3.json has no statistics definition for $uuid"
		          . " - looking for a block of the same kind that has one");
		return $self->referenceMapping( $app );
	}

	my @mapping;
	foreach my $o ( @{ $stat->{outputs} } ) {
		next if( !defined $o->{id} );
		my $key = defined $o->{uuid} ? $connectors->{ lc($o->{uuid}) } : undef;
		if( !defined $key ) {
			$log->WARN("$me Column $o->{id} ('" . ($o->{name}//'?') . "') could not be resolved to an output - skipped");
			next;
		}
		# Use the label the Miniserver reports today, so that the imported
		# history lands in the same field as the live values.
		my $label = defined $tolive{$key} ? $tolive{$key} : $key;
		$log->DEB("$me Column $o->{id}: connector '$key' -> field '$label'")
			if( $label ne $key );
		push @mapping, { statpos => $o->{id}, lxlabel => $label };
	}

	if( !@mapping ) {
		$log->DEB("$me Could not derive any mapping for $uuid");
		return;
	}

	@mapping = @{ default_only_mapping( \@mapping,
	               [ map { $_->{Name} } @{ $self->{LoxoneLabels} || [] } ], $log ) };

	$log->OK("$me Mapping derived from the Miniserver: "
	         . join("  ", map { "«$_->{statpos}»→«$_->{lxlabel}»" } @mapping));
	return \@mapping;
}

# A block that answers with nothing but its LL.value
#####################################################
# Some types have no numbered outputs at all - a StateV ("Virtueller Status") is
# the common one, 43 of them on the test installation. The Miniserver answers
# such a block with LL.value only, and msget_value calls that "Default". Its
# statistics, meanwhile, hang on the connector the catalogue calls AQ.
#
# So the import would write a field AQ that the grabber never fills, right next
# to the Default it fills every cycle - the same value under two names, which is
# the very split this whole translation exists to avoid.
#
# The condition is deliberately narrow: exactly one statistics column, and live
# nothing but Default. Then there is only one way to read it. Measured on
# "P: Alkalinität": statistics 47.248, live Default 47 - the same reading, the
# catalogue giving this type exactly one output.
#####################################################
sub default_only_mapping
{
	my ($mapping, $livenames, $log) = @_;
	my $me = Globals::whoami();

	return $mapping if( ref($mapping) ne 'ARRAY' or scalar @{$mapping} != 1 );
	return $mapping if( ref($livenames) ne 'ARRAY' or !@{$livenames} );
	foreach my $n ( @{$livenames} ) {
		return $mapping if( defined $n and $n ne 'Default' );
	}

	return $mapping if( $mapping->[0]->{lxlabel} eq 'Default' );

	$log->INF("$me Block answers with a single Default output - its statistics"
	          . " column '$mapping->[0]->{lxlabel}' is that output") if( $log );
	return [ { statpos => $mapping->[0]->{statpos}, lxlabel => 'Default' } ];
}


# The mapping of a block of the same kind, when this one has none of its own
#####################################################
# A Miniserver can record a block for years and still not describe it in
# LoxAPP3. Measured on a live installation: two Energy blocks with StatsType 11
# and 48 months of files each, and no statistics definition for either. Nothing
# could import them - the hard coded ENERGY mapping names AQ and AQp while the
# same outputs are called Ct and Pf today, so it filtered down to nothing, and
# deriveMapping() gave up right here.
#
# But the neighbours know. Two more Energy blocks of the same StatsType sit in
# the same configuration, they DO have a definition, and every one of the four
# files carries the identical header:
#
#   <Statistics Name="..." NumOutputs="2" Outputs="Gesamtverbrauch,Leistung">
#
# Type plus StatsType decides the structure - checked across all 13 type/StatsType
# combinations of that installation, every one of them with exactly one file
# signature. So the mapping of a neighbour is this block's mapping.
#
# Not a guess that stays unchecked: the column names of the reference are kept in
# $self->{refcolumns}, and submitData() compares them against what the file it is
# about to import actually declares. If they differ, nothing is written.
#####################################################
sub referenceMapping
{
	my ($self, $app) = @_;
	my $me = Globals::whoami();
	my $log = $self->{log};
	my $msno = $self->{msno};
	my $uuid = $self->{uuid};

	# Type and StatsType of this block, and of every candidate, come from the
	# LoxPLAN - LoxAPP3 uses a coarser naming ("Meter" covers Energy as well).
	my ($plan, $me_ctrl);
	eval {
		my $obj = LoxBerry::JSON->new();
		$plan = $obj->open(
			filename => $Globals::stats4lox->{loxplanjsondir} . "/ms$msno.json",
			readonly => 1 );
		$me_ctrl = $plan->{controls}->{$uuid} if( $plan );
	};
	if( !$me_ctrl or !$me_ctrl->{Type} ) {
		$log->DEB("$me $uuid is not in ms$msno.json - no reference possible");
		return;
	}
	my $type  = $me_ctrl->{Type};
	my $stype = $me_ctrl->{StatsType} // '';

	my %appc = map { lc($_) => $app->{controls}->{$_} } keys %{ $app->{controls} || {} };

	foreach my $cand ( sort keys %{ $plan->{controls} } ) {
		next if( lc($cand) eq lc($uuid) );
		my $c = $plan->{controls}->{$cand};
		next if( ($c->{Type} // '') ne $type );
		next if( ($c->{StatsType} // '') ne $stype );
		next if( !$c->{connectors} );

		my $cstat = $appc{ lc($cand) } ? $appc{ lc($cand) }->{statistic} : undef;
		next if( !$cstat or ref($cstat->{outputs}) ne 'ARRAY' or !@{$cstat->{outputs}} );

		# Build the mapping from the reference, exactly as it would be built for
		# the block itself - through its own connectors.
		my $short = $self->outputShortnames( $type );
		my (@mapping, @columns, $incomplete);
		foreach my $o ( sort { ($a->{id}//0) <=> ($b->{id}//0) } @{ $cstat->{outputs} } ) {
			next if( !defined $o->{id} );
			my $key = defined $o->{uuid} ? $c->{connectors}->{ lc($o->{uuid}) } : undef;
			if( !defined $key ) { $incomplete = 1; last; }
			my $sn = $short->{$key};
			push @mapping, { statpos => $o->{id},
			                 lxlabel => ( defined $sn and $sn ne '' ) ? $sn : $key };
			push @columns, ( $o->{name} // '' );
		}
		next if( $incomplete or !@mapping );

		$self->{refcolumns} = \@columns;
		$self->{refname}    = $c->{Title};
		$log->OK("$me Mapping taken from '" . ($c->{Title} // $cand) . "' (same $type,"
		         . " StatsType $stype): "
		         . join("  ", map { "«$_->{statpos}»→«$_->{lxlabel}»" } @mapping));
		$log->INF("$me Its columns are '" . join(",", @columns)
		          . "' - the file to import has to declare the same");
		return \@mapping;
	}

	$log->WARN("$me No other $type with StatsType $stype has a statistics"
	           . " definition - this block cannot be mapped");
	return;
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
	
	
	# If nothing survived the filter, this block cannot be imported with the
	# hard coded table - that is the case Loxone created by renaming its output
	# labels (AQ -> Ct) and by adding blocks nobody entered into the table.
	#
	# Only then do we fall back to the derivation from the Miniserver. Doing it
	# the other way round would rename the fields of measurements that work
	# today, and break the dashboards built on them.
	if( !@filtered_mappings ) {
		$log->INF("$me No hard coded mapping matches - deriving it from the Miniserver");
		my $derived = $self->deriveMapping();
		if( $derived and @{$derived} ) {
			my @dfiltered;
			foreach my $mapping ( @{$derived} ) {
				push @dfiltered, $mapping
					if( grep { defined $statlabels{$_} and $statlabels{$_} eq $mapping->{lxlabel} } keys %statlabels );
			}
			# The outputs the user selected win; if none of them matches, the
			# derived mapping is still better than importing nothing at all.
			@filtered_mappings = @dfiltered ? @dfiltered : @{$derived};
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

	# Where do the field names come from?
	#
	# For a statistics group there is no hard coded mapping and none is needed:
	# the file names its own columns in the Outputs attribute. Those names are
	# translated to the abbreviations the live grabber uses for the same
	# outputs, so that history and live values share one field instead of
	# ending up as two adjacent curves - see translateGroupOutputs().
	#
	# The classic path keeps using the mapping, which does the same job through
	# deriveMapping().
	my @fileoutputs;
	if( defined $data->{StatMetadata}->{OutputNames} ) {
		@fileoutputs = @{ $data->{StatMetadata}->{OutputNames} };
	}
	# A mapping borrowed from another block is only valid while the file agrees.
	# referenceMapping() concluded from type and StatsType that the two record
	# the same thing; here the file says what it really holds, so this is the
	# place to insist. Writing the wrong column into a field would be worse than
	# importing nothing.
	if( $self->{refcolumns} and !$self->{usefileoutputs} and @fileoutputs ) {
		my $want = join( ",", @{ $self->{refcolumns} } );
		my $got  = join( ",", @fileoutputs );
		if( $want ne $got ) {
			$log->ERR("$me Columns of this file are '$got', but the mapping borrowed"
			          . " from '" . ($self->{refname} // '?') . "' expects '$want'"
			          . " - nothing imported for this month");
			return 0;
		}
	}

	my $usefileoutputs = ( $self->{usefileoutputs} and @fileoutputs ) ? 1 : 0;
	if( $usefileoutputs ) {
		# Translated once per set of columns: submitData runs per month file,
		# and every month of a series carries the same header.
		my $cachekey = join( ",", @fileoutputs );
		$self->{_grouptrans} = {} if( ref($self->{_grouptrans}) ne 'HASH' );
		if( !$self->{_grouptrans}->{$cachekey} ) {
			$log->INF("$me Columns of the statistics file: $cachekey");
			$self->{_grouptrans}->{$cachekey} = $self->translateGroupOutputs( \@fileoutputs );
			$log->INF("$me Importing into the fields: " . join(", ", @{ $self->{_grouptrans}->{$cachekey} }));
		}
		@fileoutputs = @{ $self->{_grouptrans}->{$cachekey} };
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
		if( $usefileoutputs ) {
			for( my $i = 0; $i <= $#fileoutputs; $i++ ) {
				next if( !defined $record->{val}[$i] );
				push @values, { key => $fileoutputs[$i], value => $record->{val}[$i] };
			}
		}
		else {
			foreach my $mapping ( @{$mappings} ) {

				my $statpos = $mapping->{statpos};
				my $label = $mapping->{lxlabel};
				my $value = $record->{val}[$statpos];
				push @values, { key => $label, value => $value };

			}
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

	return if( !defined $timestr );
	if( $timestr !~ /(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2}):(\d{2})/ ) {
		$log->WARN("$me Unparseable timestamp '$timestr'") if($log);
		return;
	}
	my ($ye, $mo, $da, $ho, $mi, $se) = ($1, $2, $3, $4, $5, $6);

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
	return $dt if( $dt );

	# The local time does not exist: on the day the clock jumps forward, an
	# hour is missing. Loxone stores local times, and a statistics record
	# inside that gap used to abort the import of the entire month with
	# "Invalid local time for date in time zone: ...".
	#
	# The former workaround subtracted one minute and retried once. Measured
	# against Europe/Berlin, that only ever helped for exactly 02:00:00 -
	# anything later in the gap, 02:30:00 for instance, is still invalid and
	# the import died (issue #136).
	#
	# Time::Local::timelocal never fails and yields the same instant as
	# shifting forward by the DST offset: 02:30 becomes 03:30 local time, which
	# is the sensible reading of a clock that jumped.
	my $epoch;
	eval {
		require Time::Local;
		$epoch = Time::Local::timelocal( $se, $mi, $ho, $da, $mo - 1, $ye );
	};
	if( defined $epoch ) {
		my $fixed = DateTime->from_epoch( epoch => $epoch, time_zone => $LocalTZ );
		$log->WARN("$me '$timestr' does not exist in this timezone (daylight saving change) - using "
		           . $fixed->strftime('%Y-%m-%d %H:%M:%S')) if($log);
		return $fixed;
	}

	$log->CRIT("$me Cannot convert timestamp '$timestr': $@") if($log);
	return;
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
