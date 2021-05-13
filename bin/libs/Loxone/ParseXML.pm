use LoxBerry::Log;
use LoxBerry::JSON;
use XML::LibXML;
use XML::LibXML::Common;
use warnings;
use strict;
use Encode;
use FindBin qw($Bin);
use lib "$Bin/..";
use Globals;
# require "$LoxBerry::System::lbpbindir/libs/Globals.pm";

# use open ':std', ':encoding(UTF-8)';

# Debugging
use Data::Dumper;

package Loxone::ParseXML;




#####################################################
# Read LoxPLAN XML
#####################################################

# What you get:
# - Key of the hash is UUID
# - Every key contains
	# {Title} Object name (Bezeichnung)
	# {Desc} Object description (Beschreibung). If empty--> Object name (*)
	# {StatsType} Statistics type 1..7
	# {Type} Type name of the Loxone input/output/function
	# {MSName} Name of the Miniserver
	# {MSIP} IP of the Miniserver
	# {MSNr} ID of the Miniserver in LoxBerry General Config
	# {Unit} Unit to display in the Loxone App (stripped from Loxone syntax <v.1>)
	# {Category} Name of the category
	# {Place} Name of the place (room)
	# {MinVal} Defined minimum value or string 'U' for undefined
	# {MaxVal} Defined maximum value or string 'U' for undefined


# ARGUMENTS are named parameters
# filename ... the LoxPlan XML
# log ... Log object (LoxBerry::Log - send using \$logobj)
# RETURNS
# Hashref with parsed data

sub readloxplan
{
	
	my %args = @_;
		
	my $loxconfig_path;
	my $log;
	my @loxconfig_xml;
	my %lox_miniserver;
	my %lox_category;
	my %lox_category_used;
	my %lox_room;
	my %lox_room_used;
	my %lox_elementType;
	my $start_run = time();
	my %lox_statsobject; 
	#my %cfg_mslist;

	$loxconfig_path = $args{filename};
	$log = $args{log};

	# Uniquify CONTROL_BLACKLIST and convert to hash for faster search
	my %CBLACKLIST = map { uc($_) => 1 } @main::CONTROL_BLACKLIST;


	
	# For performance, it would be possibly better to switch from XML::LibXML to XML::Twig

	# Prepare data from LoxPLAN file
	#my $parser = XML::LibXML->new();
	our $lox_xml;
	my $parser;
	eval { 
		my $xmlstr = LoxBerry::System::read_file($loxconfig_path);
		
		# LoxPLAN uses a BOM, that cannot be handled by the XML Parser
		my $UTF8_BOM = chr(0xef) . chr(0xbb) . chr(0xbf);
		if(substr( $xmlstr, 0, 3) eq $UTF8_BOM) {
			$log->INF("Removing BOM of LoxPLAN input");
			$xmlstr = substr $xmlstr, 3;
		}
		$xmlstr = Encode::encode("utf8", $xmlstr);
		
		
		#######################################
		## FIXES of invalid Loxone Loxplan XML 
		#######################################
		
		$xmlstr = correctXML_LoxAIR( $xmlstr, $log );
		
		#######################################
		## Finally, load the XML
		#######################################
		
		my %parseroptions = (
		#	recover => 1
		);
		
		$lox_xml = XML::LibXML->load_xml( string => $xmlstr, \%parseroptions );
	};
	if ($@) {
		$log->ERR( "import.cgi: Cannot parse LoxPLAN XML file: $@");
		#exit(-1);
		return;
	}

	# Get time and version of XML
	my %documentInfo;
	my ($docInfo) = $lox_xml->findnodes('//C[@Type="Document"]');
	my ($controlList) = $lox_xml->findnodes('//ControlList');
	$documentInfo{CLversion} = $controlList->{Version};
	$documentInfo{version} = $docInfo->{V};
	$documentInfo{Title} = $docInfo->{Title};
	$documentInfo{ConfigVersion} = $docInfo->{ConfigVersion};
	$documentInfo{Date} = $docInfo->{Date};
	$documentInfo{DateS} = $docInfo->{DateS};
	$documentInfo{DateEpoch} = LoxBerry::System::lox2epoch($docInfo->{DateS});
	$documentInfo{Town} = $docInfo->{Town};
	$documentInfo{Ctry} = $docInfo->{Ctry};
	$documentInfo{Latitude} = $docInfo->{Latitude};
	$documentInfo{Longitude} = $docInfo->{Longitude};
	$documentInfo{Currency} = $docInfo->{Currency};
	undef $docInfo;
	undef $controlList;
	$log->DEB( Data::Dumper::Dumper(\%documentInfo) );
	
	# Read Loxone Miniservers
	foreach my $miniserver ($lox_xml->findnodes('//C[@Type="LoxLIVE"]')) {
		$log->DEB( "Found Miniserver $miniserver->{Title} with internal address ".$miniserver->{IntAddr});
		# Use an multidimensional associative hash to save a table of necessary MS data
		# key is the Uid
		$lox_miniserver{$miniserver->{U}}{Title} = $miniserver->{Title};
		$lox_miniserver{$miniserver->{U}}{Serial} = $miniserver->{Serial};
		
		# Save full Internal Address
		$lox_miniserver{$miniserver->{U}}{IntAddr} = $miniserver->{IntAddr};
		
		# IntAddr can have a port - Split and save host and port part
		my ($msxmlip, $msxmlport) = split(/:/, $miniserver->{IntAddr}, 2);
		if( $msxmlport ) {
			$lox_miniserver{$miniserver->{U}}{Port} = $msxmlport;
		}
		else {
			$lox_miniserver{$miniserver->{U}}{Port} = 80;
		}
		
		$lox_miniserver{$miniserver->{U}}{Host} = $msxmlip;
		
		# Check if we can get an ip
		if($msxmlip=~/^(\d{1,3}).(\d{1,3}).(\d{1,3}).(\d{1,3})$/ &&(($1<=255 && $2<=255 && $3<=255 &&$4<=255 ))) { 
			# IP seems valid
			$log->DEB( "Found Miniserver $miniserver->{Title} with IP $msxmlip");
			$lox_miniserver{$miniserver->{U}}{IP} = $msxmlip;
		} elsif ((! defined $msxmlip) || ($msxmlip eq "")) {
			$log->ERR( "Miniserver $miniserver->{Title}: Internal IP is empty. This field is mandatory. Please update your Config.");
			$lox_miniserver{$miniserver->{U}}{IP} = undef;
		} else { 
			# IP seems not to be an IP - possibly we need a DNS lookup?
			$log->INF( "Found Miniserver $miniserver->{Title} possibly configured with hostname. Querying IP of $msxmlip ...");
			require Socket;
			my $dnsip = Socket::inet_ntoa(Socket::inet_aton($msxmlip));
			if ($dnsip) {
				$log->OK( " --> Found Miniserver $miniserver->{Title} and DNS lookup got IP $dnsip ...");
				$lox_miniserver{$miniserver->{U}}{IP} = $dnsip;
			} else {
				$log->WARN( " --> Could not resolve IP for Miniserver $miniserver->{Title}.");
				$lox_miniserver{$miniserver->{U}}{IP} = $msxmlip;
			}
		}
		
		# Resolve Miniserver in LoxBerry config
		my %lb_miniservers;
		%lb_miniservers = LoxBerry::System::get_miniservers();
		
		if (! %lb_miniservers) {
			$log->ERR("No Miniservers defined in LoxBerry. Cannot match any Miniserver");
		} else {
			foreach my $msno ( keys %lb_miniservers ) {
				$log->DEB( "Compare Miniserver Loxberry IPAddress field " . $lb_miniservers{$msno}{IPAddress} . " vs. XML Host " . $lox_miniserver{$miniserver->{U}}{Host});
				$log->DEB( "Compare Miniserver Loxberry IPAddress field " . $lb_miniservers{$msno}{IPAddress} . " vs. XML IP " . $lox_miniserver{$miniserver->{U}}{IP});
				next if( $lb_miniservers{$msno}{IPAddress} ne $lox_miniserver{$miniserver->{U}}{Host} and $lb_miniservers{$msno}{IPAddress} ne $lox_miniserver{$miniserver->{U}}{IP} );
				$lox_miniserver{$miniserver->{U}}{msno} = $msno;
				last;
			}
		}
	}
	
	# Read Loxone categories
	foreach my $category ($lox_xml->findnodes('//C[@Type="Category"]')) {
		# Key is the Uid
		$lox_category{$category->{U}} = $category->{Title};
	}
	# print "Test Perl associative array: ", $lox_category{"0b2c7aea-007c-0002-0d00000000000000"}, "\r\n";

	# Read Loxone rooms
	foreach my $room ($lox_xml->findnodes('//C[@Type="Place"]')) {
		# Key is the Uid
		$lox_room{$room->{U}} = $room->{Title};
	}

	# Get all objects
	
	foreach my $object ($lox_xml->findnodes('//C[@Type]')) {
		
		# Process CBLACKLIST
		if( exists $CBLACKLIST{ uc($object->{Type}) } ) {
			next;
		}
		
		# Place and Category
		my @iodata = $object->getElementsByTagName("IoData");
		if( $object->{Type} eq "Memory" and !defined $iodata[0]->{Cr} && !defined $iodata[0]->{Pr} ) {
			# Skip elements that do 
			next;
		}
		
		if( defined $iodata[0]->{Cr} ) {
			# $log->DEB( "Cat: " . $lox_category{$iodata[0]->{Cr}});
			$lox_statsobject{$object->{U}}{Category} = $lox_category{$iodata[0]->{Cr}} if ($iodata[0]->{Cr});
			$lox_category_used{$iodata[0]->{Cr}} = 1;
		}
		if( defined $iodata[0]->{Pr} ) {
			$lox_statsobject{$object->{U}}{Place} = $lox_room{$iodata[0]->{Pr}} if ($iodata[0]->{Pr});
			$lox_room_used{$iodata[0]->{Pr}} = 1;
		}
		if( defined $iodata[0]->{Visu} ) {
			$lox_statsobject{$object->{U}}{Visu} = $iodata[0]->{Visu};
		}
		
		# Get Miniserver of this object
		# Nodes may be a child or sub-child of LoxLive type, or alternatively Ref-er to the LoxLive node. 
		# Therefore, we have to distinguish between connected in some parent, or referred by in some parent.	
		my $ms_ref;
		my $parent = $object;
		do {
			$parent = $parent->parentNode;
		} while ((!$parent->{Ref}) && defined $parent->{Type} && ($parent->{Type} ne "LoxLIVE"));
		if ($parent->{Type} eq "LoxLIVE") {
			$ms_ref = $parent->{U};
		} else {
			$ms_ref = $parent->{Ref};
		}
		my $logmessage = "Object: ".$object->{Title}." (".$object->{Type}.") --> MS ".$lox_miniserver{$ms_ref}{Title};
		$logmessage .= " StatsType = ".$object->{StatsType} if ($object->{StatsType});
		# $log->DEB($logmessage);
		
		$lox_elementType{$object->{Type}} = 1;
		
		$lox_statsobject{$object->{U}}{Title} = $object->{Title};
		$lox_statsobject{$object->{U}}{Desc} = defined $object->{Desc} ? $object->{Desc} : "";
		$lox_statsobject{$object->{U}}{UID} = $object->{U};
		$lox_statsobject{$object->{U}}{StatsType} = defined $object->{StatsType} ? $object->{StatsType} : 0;
		$lox_statsobject{$object->{U}}{Analog} = LoxBerry::System::is_enabled( $object->{Analog} ) ? 1 : 0;
		$lox_statsobject{$object->{U}}{Type} = $object->{Type};
		# $lox_statsobject{$object->{U}}{MSName} = $lox_miniserver{$ms_ref}{Title};
		# $lox_statsobject{$object->{U}}{MSIP} = $lox_miniserver{$ms_ref}{IP};
		# $lox_statsobject{$object->{U}}{MSNr} = $cfg_mslist{$lox_miniserver{$ms_ref}{IP}};
		$lox_statsobject{$object->{U}}{msno} = $lox_miniserver{$ms_ref}{msno};
		
		# Unit
		my @display = $object->getElementsByTagName("Display");
		if($display[0]->{Unit}) { 
			$lox_statsobject{$object->{U}}{Unit} = $display[0]->{Unit};
			$lox_statsobject{$object->{U}}{Unit} =~ s|<.+?>||g;
			$lox_statsobject{$object->{U}}{Unit} = LoxBerry::System::trim($lox_statsobject{$object->{U}}{Unit});
			# $log->DEB( "Unit: " . $lox_statsobject{$object->{U}}{Unit});
		} else { 
			# $log->DEB( "Unit: (none detected)");
		}
		
		
		# Min/Max values
		if ($object->{Analog} and $object->{Analog} ne "true") {
			$lox_statsobject{$object->{U}}{MinVal} = 0;
			$lox_statsobject{$object->{U}}{MaxVal} = 1;
		} else {
			if ($object->{MinVal}) { 
				$lox_statsobject{$object->{U}}{MinVal} = $object->{MinVal};
			} else {
				$lox_statsobject{$object->{U}}{MinVal} = "U";
			}
			if ($object->{MaxVal}) { 
				$lox_statsobject{$object->{U}}{MaxVal} = $object->{MaxVal};
			} else {
				$lox_statsobject{$object->{U}}{MaxVal} = "U";
			}
		}
		
		# Page in the document
		# Not sure if the xpath query recursively goes up until type Page, but should
		my @page = $object->findnodes('ancestor::C[@Type="Page"]');
		$lox_statsobject{$object->{U}}{Page} = defined $page[0]->{Title} ? $page[0]->{Title} : "";
		# print STDERR "Pages: " . scalar @page . " Object $object->{Title} Page: " . $page[0]->{Title} . "\n";
		
		
		# $log->DEB( "Object Name: " . $lox_statsobject{$object->{U}}{Title});
	}
	
	# Delete empty Miniserver entries (unknown where they are from)
	delete $lox_miniserver{''};

	
	my $end_run = time();
	my $run_time = $end_run - $start_run;
	# print "Job took $run_time seconds\n";
	
	# Create sorted array from %lox_elementType, rooms_used and categories_used 
	my @lox_elementTypes = sort keys %lox_elementType;
	my @lox_roomsUsed = sort keys %lox_room_used;
	my @lox_categoriesUsed = sort keys %lox_category_used;
	
	
	
	my %combined_data;
	$combined_data{miniservers} = \%lox_miniserver;
	$combined_data{rooms} = \%lox_room;
	$combined_data{categories} = \%lox_category;
	$combined_data{controls} = \%lox_statsobject;
	$combined_data{elementTypes} = \@lox_elementTypes;
	$combined_data{rooms_used} = \@lox_roomsUsed;
	$combined_data{categories_used} = \@lox_categoriesUsed;
	
	$combined_data{documentInfo} = \%documentInfo;
	
	return \%combined_data;
}

#############################################################################
# Creates a json file from the Loxone XML
#############################################################################
# ARGUMENTS are named parameters
# filename ... the LoxPlan XML
# output ... the filename of the resulting json file
# log ... Log object (LoxBerry::Log - send using \$logobj)
# RETURNS
# - undef on error
# - !undef on ok

sub loxplan2json
{
	my %args = @_;
	my $log = $args{log};
	my $remoteTimestamp = $args{remoteTimestamp};
	
	$log->INF("loxplan2json started") if ($log);
	
	eval {
		
		my $result = readloxplan( log => $args{log}, filename => $args{filename} );
		if (!$result) {
			$log->CRIT("Error parsing XML");
			return undef;
		}
		
		$result->{documentInfo}->{LoxAPPversion3timestamp} = $remoteTimestamp if ($remoteTimestamp);
		
		unlink $args{output};
		open(my $fh, '>', $args{output});
		print $fh JSON->new->pretty(1)->encode( $result );
		close $fh;
	
	};
	if ($@) {
		print STDERR "loxplan2json: Error running procedure: $@\n";
		$log->ERR("loxplan2json: Error running procedure: $@\n") if ($log);
		return undef;
	}
	
	return 1;

}


sub correctXML_LoxAIR 
{
	
	my $xmlstr = shift;
	my $log = shift;
	
	### Loxone XML correction for Tree2Air bridge
	my $startpos = 0;

	while( ( my $foundpos = index( $xmlstr, '<C Type="LoxAIR"', $startpos ) ) != -1 ) {
		# print "Found: $foundpos Startpos $startpos Character: ". substr( $xmlstr, $foundpos, 1 ) . "\n";
		$startpos = $foundpos+1;
		# Finding closing tag >
		my $endpos = index( $xmlstr, '>', $foundpos );
		# print "Closing: $endpos Character: ". substr( $xmlstr, $endpos, 1 ) . "\n";
		# Get full tag
		my $tagstr = substr( $xmlstr, $foundpos+1, $endpos-$foundpos-1 );
		# print "Content: $tagstr\n";
		
		# my @attributes = split( /\s+=(?<=")\s+(?=")/g, $tagstr );
		
		# Split line by blank but without blanks inside of doublequotes
		my @attributes = $tagstr =~ m/((?:" [^"]* "|[^\s"]*)+)/gx;
		
		# print "Attributes: \n";
		# print join( "\n->", @attributes) . "\n";
		
		my @newattributeArray;
		my %uniquenesshash;
		my $duplicates = 0;
		foreach my $fullattribute ( @attributes ) { 
			next if (! $fullattribute);
			my ($attribute, $value) = split( "=", $fullattribute, 2);
			if( defined $uniquenesshash{$attribute} ) {
				$duplicates += 1;
				next;
			}
			$uniquenesshash{$attribute} = 1;
			push @newattributeArray, $fullattribute;
		}	
		
		if( $duplicates ) {
			my $newattribute = join( ' ', @newattributeArray );
			# print "New attribute:\n$newattribute\n";
			# Replace the old attributes by the new attributes
			substr( $xmlstr, $foundpos+1, $endpos-$foundpos-1, $newattribute );
		
			$log->WARN( "Stats4Lox corrected $duplicates duplicate attributes (non-valid Loxone XML):" ) if ($log);
			$log->WARN( "LoxAIR Original: $tagstr") if ($log);
			$log->WARN( "LoxAIR S4LFixed: $newattribute") if ($log); 
		}
	}
	
	return $xmlstr;
	
}




#####################################################
# Finally 1; ########################################
#####################################################
1;
