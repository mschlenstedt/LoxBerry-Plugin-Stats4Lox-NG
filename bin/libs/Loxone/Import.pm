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

package Loxone::Import;

our $DEBUG = 1;
our $LocalTZ = DateTime::TimeZone->new( name => 'local' );
our $http_timeout = 30;


sub new 
{
	my $class = shift;
	
	if (@_ % 2) {
		Carp::croak "Loxone::Import->new: Illegal parameter list has odd number of values\n" . join("\n", @_) . "\n";
	}
	
	my %p = @_;
	
	my $self = { 
		msno =>$p{msno}, 
		uuid =>$p{uuid},
		log =>$p{log}
	};

	my $log = $self->{log};
	
	$log->DEB("Loxone::Import->new: Called");
	
	if( !defined $self->{msno} ) {
		Carp::croak("msno paramter missing");
	}
	if( !defined $self->{uuid} ) {
		Carp::croak("uuid parameter missing");
	}

	my %miniservers = LoxBerry::System::get_miniservers();
	if( !defined $miniservers{$self->{msno}} ) {
		Carp::croak("Miniserver $self->{msno} not defined");
	}
	
	bless $self, $class;
	
	$self->getStatsjsonElement();
	if(!defined $self->{statobj}) {
		$self->{importstatus}->{error} = 1;
		$self->{importstatus}->{errortext} = "Statobj with msno=$self->{msno} and uuid=$self->{uuid} not found";
		Carp::croak("Statobj with msno=$self->{msno} and uuid=$self->{uuid} not found");
	}
	
	$self->getLoxoneLabels();
	
	$self->setMappings();
	
	
	return $self;
}

sub getStatlist
{
	my $self = shift;
	my $log = $self->{log};
	$log->DEB("Loxone::Import->getStatlist: Called");
	
	my $msno = $self->{msno};
	my $uuid = $self->{uuid};
	
	my $resphtml;
	my $usedcachefile=0;
	
	$log->DEB("Loxone::Import->getStatlist: Checking for cached statlist of $msno");
	my $statlistcachefile = $Globals::s4ltmp."/msstatlist_ms$msno.tmp";
	if( -e $statlistcachefile ) {
		my $modtime = (stat($statlistcachefile))[9];
		if ( defined $modtime and (time()-$modtime) < 900 ) {
			$log->DEB("Loxone::Import->getStatlist: Reading cache file $statlistcachefile");
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
			$log->DEB("Loxone::Import->getStatlist: Requesting stat list from Miniserver $msno (Try $retries/$retrycount)");
		
			($resphtml, $status) = LoxBerry::IO::mshttp_call2($msno, $url, ( timeout => $http_timeout*$retries ) );
			if( $resphtml and $status->{code} eq "200" ) {
				last;
			}
			$log->WARN("Loxone::Import->getStatlist: Error $status->{message} - Sleeping a bit...");
			sleep(3);
		}
	
		if( !$resphtml) {
			$log->DEB("Loxone::Import->getStatlist: ERROR no response from Miniserver ($status->{status})");
			return;
		}
		$log->DEB("Loxone::Import->getStatlist: Saving response to cachefile $statlistcachefile");
		
		eval {
			open(my $fh, '>', $statlistcachefile);
			print $fh $resphtml;
			close($fh);
		}
	}
		
	my %resultsAll;
	
	$log->DEB("Loxone::Import->getStatlist: Parsing response");
	
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
	$log->DEB("Loxone::Import->getStatlist: Number of lines $count");
	$log->DEB("Loxone::Import->getStatlist: Number of different uuids ". keys(%resultsAll));
	
	$self->{statlistAll} = \%resultsAll;
	$log->DEB("Loxone::Import->getStatlist: Finished ok");
	
	return @{$resultsAll{$uuid}};
	
}

sub getStatsjsonElement
{
	
	my $self = shift;
	my $log = $self->{log};
	
	$log->DEB("Loxone::Import->getStatsjsonElement: Called");
	
	$log->DEB("Loxone::Import->getStatsjsonElement: Opening stats.json ($Globals::statsconfig)");
	
	my $statsjsonobj = new LoxBerry::JSON;
	my $statsjson = $statsjsonobj->open( filename => $Globals::statsconfig, readonly => 1 );
	if (!$statsjson) {
		$log->DEB("Loxone::Import->getStatsjsonElement: ERROR Opening stats.json (empty)");
		return;
	}
	
	$log->DEB("Loxone::Import->getStatsjsonElement: Searching for $self->{uuid} and $self->{msno}");
	
	my @result = $statsjsonobj->find( $statsjson->{loxone}, "\$_->{uuid} eq '".$self->{uuid}."' and \$_->{msno} eq '".$self->{msno}."'");
	
	if( @result ) {
		$log->DEB("Loxone::Import->getStatsjsonElement: Found ". scalar @result ." elements");
		my $statobj = $statsjson->{loxone}[$result[0]];
		$log->DEB("Loxone::Import->getStatsjsonElement: Found stat name $statobj->{name}");
		$self->{statobj} = $statobj;
	}
	else {
		$log->DEB("Loxone::Import->getStatsjsonElement: ERROR stats.json element not found");
	}
}


sub getMonthStat {
	
	my $self = shift;
	my $log = $self->{log};
	my $msno = $self->{msno};
	my $uuid = $self->{uuid};
	
	$log->DEB("Loxone::Import->getMonthStat: Called");
		
	my %args = @_;
	my $yearmon = $args{yearmon};
	
	if(!$uuid) {
		$log->DEB("Loxone::Import->getMonthStat: ERROR uuid not defined.");
		return;
	}
	if(!$yearmon) {
		$log->DEB("Loxone::Import->getMonthStat: ERROR yearmon not defined.");
		return;
	}
	
	my $url = "/stats/$uuid.$yearmon.xml";
	
	
	my $retrycount = 3;
	my $retries = 0;
	my ($respxml, $status);
	
	while ( $retries < $retrycount ) {
		$retries++;
	
		$log->DEB("Loxone::Import->getMonthStat: Querying stat for month $yearmon (Try $retries/$retrycount)");
		($respxml, $status) = LoxBerry::IO::mshttp_call2($msno, $url, ( timeout => ($http_timeout*$retries) ) );
		
		if($respxml) {		
			last;
		}
		
		$log->WARN("Loxone::Import->getMonthStat: ERROR No response from MS$msno ($url)");
		$log->WARN("Loxone::Import->getMonthStat: Sleeping a bit...");
		sleep(3);
	}
	
	if( !$respxml ) {
		log->ERR("Loxone::Import->getMonthStat: Could not get data from MS$msno / $yearmon");
		return;
	}
	
	
	my $parser = XML::LibXML->new();
	my $statsxml;
	$log->DEB("Loxone::Import->getMonthStat: Loading XML");
	eval {
		$statsxml = XML::LibXML->load_xml( string => $respxml, no_blanks => 1);
	};
	if( $@ ) {
		$log->DEB("Loxone::Import->getMonthStat: ERROR Could not load XML (month $yearmon)");
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
		my $data_time = createDateTime($node->{T}); 
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
	
	$log->DEB("Loxone::Import->getMonthStat: Timestamp count found " . scalar @timedata);
	
	return \%result;

}

sub getLoxoneLabels {
	my $self = shift;
	my $log = $self->{log};
	my $msno = $self->{msno};
	my $uuid = $self->{uuid};
	
	$log->INF("Querying MS$msno to get output labels");
	my ($code, $data) = Stats4Lox::msget_value( $msno, $uuid );
	
	if( $code ne "200" ) {
		$log->ERR("Could not get live response of block for labels");
		return;
	}

	$self->{LoxoneLabels} = $data;
	return 1;
	
}

#
## This sub manages known mappings and default mappings for element types
#
# The result is a hash with index => livelabel  
# Index is the index of the value array, starting with 0, so 0 is always the first value
# e.g. 
#	Energy block
#	{ 
#		"0" => "AQ",
#		"1" => "AQp"
#	}




sub setMappings {

	my $self = shift;
	my $log = $self->{log};
	my $statobj = $self->{statobj};
	my %lxlabels = map { $_->{Key} => $_->{Name} } @{$self->{LoxoneLabels}};
	
	$log->DEB("Loxone::Import->setMappings: Called");
	my $type = $statobj->{type};
	my $type_uc = uc($type);
	$log->DEB("Loxone::Import->setMappings: Stat element type is $type");
	
	# Default mappings for known types
	
	my %mapping;
	
	if( $type_uc eq "ENERGY" ) {
		%mapping = ( "0" => "AQ", "1" => "AQp" );
	}
	# elsif( $type_uc eq "" ) {
		# %mapping = ( );
	# }
	else {
		
		# DEFAULT MAPPING
		
		if ( grep( /^output0$/, @{$statobj->{outputs}} ) and $lxlabels{output0} eq "AQ" ) {
			%mapping = ( "0" => "AQ" );
		}
		else {
			%mapping = ( "0" => "Default" );
		}
	}
	
	
	my $printmapping = "";
	foreach( sort keys %mapping ) {
		$printmapping .= "$_->$mapping{$_} ";
	}
	$log->INF("Loxone::Import->setMappings: Used mapping is: $printmapping");
		

	
}


sub createDateTime
{
	my ($timestr) = @_;
	
	if( $timestr =~ /(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2}):(\d{2})/ ) {
		my $ye = $1;
		my $mo = $2;
		my $da = $3;
		my $ho = $4;
		my $mi = $5;
		my $se = $6;
		
		my $dt = DateTime->new(
			year       => $ye,
			month      => $mo,
			day        => $da,
			hour       => $ho,
			minute     => $mi,
			second     => $se,
			time_zone  => $LocalTZ
		);
	
		return $dt;
	}
}

sub DESTROY {

		my $self = shift;
		my $log = $self->{log};
	
		$log->DEB("Loxone::Import->END: Called");
		
}
#####################################################
# Finally 1; ########################################
#####################################################
1;
