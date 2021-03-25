use warnings;
use strict;
use LoxBerry::System;
use LoxBerry::IO;
# use LoxBerry::Log;
# use Carp::Croak;
use XML::LibXML;
use FindBin qw($Bin);
use lib "$Bin/..";
use Globals;
use DateTime;

use Data::Dumper;


package Loxone::Import;

our $DEBUG = 1;
our $LocalTZ = DateTime::TimeZone->new( name => 'local' );

sub new 
{
	print STDERR "Loxone::Import->new: Called\n" if ($DEBUG);
	
	my $class = shift;
	
	if (@_ % 2) {
		print STDERR "Loxone::Import->new: ERROR Illegal parameter list has odd number of values\n";
		Carp::croak "Illegal parameter list has odd number of values\n" . join("\n", @_) . "\n";
	}
	
	my %p = @_;
	
	my $self = { 
		msno =>$p{msno}, 
		uuid =>$p{uuid},
		log =>$p{log}
	};
	
	if( !defined $self->{msno} ) {
		die "msno paramter missing";
	}
	if( !defined $self->{uuid} ) {
		die "uuid parameter missing";
	}

	# Creating state json
	print STDERR "Loxone::Import->new: Creating status file\n" if ($DEBUG);
	`mkdir -p $Globals::importstatusdir`;
	
	$self->{importstatusobj} = new LoxBerry::JSON;
	$self->{importstatus} = $self->{importstatusobj}->open( filename => $Globals::importstatusdir."/import_$self->{msno}_$self->{uuid}.json", writeonclose => 1 );
	
	my %miniservers = LoxBerry::System::get_miniservers();
	if( !defined $miniservers{$self->{msno}} ) {
		die "Miniserver $self->{msno} not defined";
	}
	
	bless $self, $class;
	
	$self->getStatsjsonElement();
	if(!defined $self->{statobj}) {
		die("Statobj with msno=$self->{msno} and uuid=$self->{uuid} not found");
	}
	
	return $self;
}

sub getStatlist
{
	print STDERR "Loxone::Import->getStatlist: Called\n" if ($DEBUG);
	my $self = shift;
	
	my $log = $self->{log};
	my $msno = $self->{msno};
	my $uuid = $self->{uuid};
	
	my $resphtml;
	my $usedcachefile=0;
	
	print STDERR "Loxone::Import->getStatlist: Checking for cached statlist of $msno\n" if ($DEBUG);
	my $statlistcachefile = $Globals::s4ltmp."/msstatlist_ms$msno.tmp";
	if( -e $statlistcachefile ) {
		my $modtime = (stat($statlistcachefile))[9];
		if ( defined $modtime and (time()-$modtime) < 900 ) {
			print STDERR "Loxone::Import->getStatlist: Reading cache file $statlistcachefile\n" if ($DEBUG);
			$resphtml = LoxBerry::System::read_file($statlistcachefile);
			if( $resphtml ) {
				$usedcachefile=1;
			}
		}
	}
	
	if( !$usedcachefile ) {
		
		# Request statlist 
		my $url = "/stats";
		my $respcode;
		print STDERR "Loxone::Import->getStatlist: Requesting stat list from Miniserver $msno ($url)\n" if ($DEBUG);
		(undef, $respcode, $resphtml) = LoxBerry::IO::mshttp_call($msno, $url);
			
		if( !$resphtml) {
			print STDERR "Loxone::Import->getStatlist: ERROR no response from Miniserver (Code $respcode)\n" if ($DEBUG);
			return undef;
		}
		print STDERR "Loxone::Import->getStatlist: Saving response to cachefile $statlistcachefile\n" if ($DEBUG);
		
		eval {
			open(my $fh, '>', $statlistcachefile);
			print $fh $resphtml;
			close($fh);
		}
	}
		
	my %resultsAll;
	
	print STDERR "Loxone::Import->getStatlist: Parsing response\n" if ($DEBUG);
	
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
	print STDERR "Loxone::Import->getStatlist: Number of lines $count\n" if ($DEBUG);
	print STDERR "Loxone::Import->getStatlist: Number of different uuids ". keys(%resultsAll) . "\n" if ($DEBUG);
	
	$self->{statlistAll} = \%resultsAll;
	print STDERR "Loxone::Import->getStatlist: Finished ok\n" if ($DEBUG);
	
	return @{$resultsAll{$uuid}};
	
}

sub getStatsjsonElement
{
	
	print STDERR "Loxone::Import->getStatsjsonElement: Called\n" if ($DEBUG);
	
	my $self = shift;
	
	print STDERR "Loxone::Import->getStatsjsonElement: Opening stats.json ($Globals::statsconfig)\n" if ($DEBUG);
	
	my $statsjsonobj = new LoxBerry::JSON;
	my $statsjson = $statsjsonobj->open( filename => $Globals::statsconfig, readonly => 1 );
	if (!$statsjson) {
		print STDERR "Loxone::Import->getStatsjsonElement: ERROR Opening stats.json (empty)\n" if ($DEBUG);
		return;
	}
	
	print STDERR "Loxone::Import->getStatsjsonElement: Searching for $self->{uuid} and $self->{msno}\n";
	
	my @result = $statsjsonobj->find( $statsjson->{loxone}, "\$_->{uuid} eq '".$self->{uuid}."' and \$_->{msno} eq '".$self->{msno}."'");
	
	if( @result ) {
		print STDERR "Loxone::Import->getStatsjsonElement: Found ". scalar @result ." elements\n" if ($DEBUG);
		my $statobj = $statsjson->{loxone}[$result[0]];
		print STDERR "Loxone::Import->getStatsjsonElement: Found stat name $statobj->{name}\n" if($DEBUG);
		$self->{statobj} = $statobj;
	}
	else {
		print STDERR "Loxone::Import->getStatsjsonElement: ERROR stats.json element not found\n" if ($DEBUG);
	}
}


sub getMonthStat {
	print STDERR "Loxone::Import->getMonthStat: Called\n" if ($DEBUG);
	
	my $self = shift;
	
	my $log = $self->{log};
	my $msno = $self->{msno};
	my $uuid = $self->{uuid};
	
	my %args = @_;
	my $yearmon = $args{yearmon};
	
	if(!$uuid) {
		print STDERR "Loxone::Import->getMonthStat: ERROR uuid not defined.\n";
		return;
	}
	if(!$yearmon) {
		print STDERR "Loxone::Import->getMonthStat: ERROR yearmon not defined.\n";
		return;
	}
	
	my $url = "/stats/$uuid.$yearmon.xml";
	
	print STDERR "Loxone::Import->getMonthStat: Querying stat for month $yearmon";
	my (undef, undef, $respxml) = LoxBerry::IO::mshttp_call($msno, $url);
	
	if( ! $respxml) {
		print STDERR "Loxone::Import->getMonthStat: ERROR No response from MS$msno ($url)\n";
		return;
	}
	my $parser = XML::LibXML->new();
	my $statsxml;
	print STDERR "Loxone::Import->getMonthStat: Loading XML";
	eval {
		$statsxml = XML::LibXML->load_xml( string => $respxml, no_blanks => 1);
	};
	if( $@ ) {
		print STDERR "Loxone::Import->getMonthStat: ERROR Could not load XML (month $yearmon)\n";
		return;
	}
	
	my %result;
	
	my $root = $statsxml->getDocumentElement;
	foreach( $root->attributes ) {
		# print STDERR "Attribute: " . $_->nodeName . " Value: " . $_->value . "\n";
		$result{StatMetadata}{$_->nodeName} = $_->value;
	}
	
	my @statsnodes = $statsxml->findnodes('/Statistics/S');
	my @timedata;
	
	foreach my $node ( @statsnodes ) {
		# print STDERR "mainnode Node Name: ".$node->{T}."\n";
		my %data;
		my $data_time = createDateTime($node->{T}); 
		$data{T} =  $data_time->epoch;
		$data{val} = ();
		foreach my $statattr ( $node->attributes ) {
			next if ($statattr->nodeName eq "T" );
			# $data{$statattr->nodeName} = $statattr->value;
			push @{$data{val}}, \{ $statattr->nodeName => $statattr->value };
		}
		push @timedata, \%data;
	}
	
	$result{values} = \@timedata;
	print STDERR "Loxone::Import->getMonthStat: Timestamp count found " . scalar @timedata ."\n";
	
	return \%result;

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
		print STDERR "Loxone::Import->END: Called\n" if ($DEBUG);
		if( $self->{importstatusobj} ) {
			print STDERR "Loxone::Import->END: importstatusobj existing\n" if ($DEBUG);
		
			$self->{importstatus}->{exitingprogram} = $?;
			if($@) {
				$self->{importstatus}->{exception} = $@;
				$self->{importstatus}->{iserror} = 1;
			} else {
				undef $self->{importstatus}->{exception};
				$self->{importstatus}->{iserror} = 0;
			}
		}
}
#####################################################
# Finally 1; ########################################
#####################################################
1;
