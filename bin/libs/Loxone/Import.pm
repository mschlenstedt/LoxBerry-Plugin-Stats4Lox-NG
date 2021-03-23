use warnings;
use strict;
use LoxBerry::System;
use LoxBerry::IO;
# use LoxBerry::Log;
# use Carp::Croak;
use XML::LibXML;
use Time::Piece;
use FindBin qw($Bin);
use lib "$Bin/..";
use Globals;
use Data::Dumper;

package Loxone::Import;

our $DEBUG = 1;

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
	my %miniservers = LoxBerry::System::get_miniservers();
	if( !defined $miniservers{$self->{msno}} ) {
		die "Miniserver $self->{msno} not defined";
	}
	
	bless $self, $class;
	
	$self->getStatlist();
	
	return $self;
}

sub getStatlist
{
	my $self = shift;
	
	my $log = $self->{log};
	my $msno = $self->{msno};
	my $uuid = $self->{uuid};
	
	# Request statlist 
	my $url = "/stats";
	my (undef, undef, $resphtml) = LoxBerry::IO::mshttp_call($msno, $url);
		
	if( !$resphtml) {
		return undef;
	}
	
	my %resultsAll;
	
	my @resp = split( /\n/, $resphtml );
	foreach my $line ( @resp ) {
		if( $line =~ /<a href="(.*)\.(\d{6}).xml">/ ) {
			my $uid = $1;
			my $yearmon = $2;
			# print STDERR "UID: $uid  Date: $yearmon\n";
			if( !$resultsAll{$uid} ) {
				$resultsAll{$uid} = ();
			}
			push( @{$resultsAll{$uid}}, $yearmon );
			
		}
	}
	
	$self->{statlistAll} = \%resultsAll;
	return @{$resultsAll{$uuid}};
	
}

# sub enrichStatlist
# {
	# my %args = @_;
	# my $log = $args{log};
	# my $msno = $args{ms};
	# my $statlist = $args{statlist};
	
	# if( ! $msno) {
		# print STDERR "No Miniserver number defined.\n";
		# return;
	# }
	# if( ! $statlist) {
		# print STDERR "Statlist is empty.\n";
		# return;
	# }
	
	# my $statsjsonobj = new LoxBerry::JSON;
	# my $statsjson = $statsjsonobj( filename => $Globals::statsconfig, readonly => 1 );
	# if (!$statsjson) {
		# return;
	# }
	
	# # Convert stats.json data to hash
	# # Filter data to match msno
	# my %statsjsonhash;
	# foreach( @{$statsjson->{loxone} ) {
		# $statsjsonhash{$_->{uuid}} = $_ if( $_->{msno} eq $msno );
	# }
	# my %enrichedstats;
	
	# foreach my $statkey ( keys %$statlist ) {
		# if( defined $statsjsonhash{$statkey} ) {
			# # We found a Loxone stat that matches a stats.json entry
			# $enrichedstats{statcfg} = $statsjsonhash{$statkey};
			# $enrichedstats{
		
	
	
	# }
	
	
	
	
	
# }


sub getMonthStat {
	
	my $self = shift;
	
	my $log = $self->{log};
	my $msno = $self->{msno};
	my $uuid = $self->{uuid};
	
	my %args = @_;
	my $yearmon = $args{yearmon};
	
	if(!$uuid) {
		print STDERR "uuid not defined.\n";
		return;
	}
	if(!$yearmon) {
		print STDERR "yearmon not defined.\n";
		return;
	}
	
	
	my $url = "/stats/$uuid.$yearmon.xml";
	my (undef, undef, $respxml) = LoxBerry::IO::mshttp_call($msno, $url);
	
	if( ! $respxml) {
		print STDERR "No response from MS$msno $url\n";
		return;
	}
	
	my $parser = XML::LibXML->new();
	my $statsxml;
	eval {
		$statsxml = XML::LibXML->load_xml( string => $respxml, no_blanks => 1);
	};
	if( $@ ) {
		print STDERR "Could not parse response XML\n";
		return;
	}
	
	my %result;
	
	my $root = $statsxml->getDocumentElement;
	foreach( $root->attributes ) {
		print STDERR "Attribute: " . $_->nodeName . " Value: " . $_->value . "\n";
		$result{StatMetadata}{$_->nodeName} = $_->value;
	}
	
	my @statsnodes = $statsxml->findnodes('/Statistics/S');
	my @timedata;
	
	foreach my $node ( @statsnodes ) {
		# print STDERR "mainnode Node Name: ".$node->{T}."\n";
		my %data;
		my $data_time = Time::Piece->strptime ($node->{T}, "%Y-%m-%d %H:%M:%S"); 
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
	
	return \%result;

}







#####################################################
# Finally 1; ########################################
#####################################################
1;
