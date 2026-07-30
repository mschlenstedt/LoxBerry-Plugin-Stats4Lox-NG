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
	my $ms_serials;
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
	$ms_serials = $args{ms_serials};

	# Uniquify CONTROL_BLACKLIST and convert to hash for faster search
	my %CBLACKLIST = map { uc($_) => 1 } @main::CONTROL_BLACKLIST;
	my %MSFALLBACK = map { uc($_) => 1 } @main::CONTROL_MS_FALLBACK;

	### Get Miniservers 
	$log->INF("Reading LoxBerry Miniserver list");
	my %lb_miniservers;
	%lb_miniservers = LoxBerry::System::get_miniservers();
	
	if (! %lb_miniservers) {
		$log->CRIT("No Miniservers defined in LoxBerry. Cannot match any Miniserver");
		return;
	}

	### Add ms_serials parameter to %lb_minisservers list
	foreach( sort keys %lb_miniservers ) {
		if( defined $ms_serials->{$_} ) {
			$log->DEB("MS$_: Added serial $ms_serials->{$_}");
			$lb_miniservers{$_}{serial} = $ms_serials->{$_};
		} 
			
	}
	
	# For performance, it would be possibly better to switch from XML::LibXML to XML::Twig

	# Prepare data from LoxPLAN file
	our $lox_xml;
	my $xmlstr;
	eval {
		$xmlstr = LoxBerry::System::read_file($loxconfig_path);

		# LoxPLAN uses a BOM, that cannot be handled by the XML Parser
		my $UTF8_BOM = chr(0xef) . chr(0xbb) . chr(0xbf);
		if( defined $xmlstr and substr( $xmlstr, 0, 3) eq $UTF8_BOM) {
			$log->INF("Removing BOM of LoxPLAN input");
			$xmlstr = substr $xmlstr, 3;
		}
		$xmlstr = Encode::encode("utf8", $xmlstr) if defined $xmlstr;
	};
	if( $@ or !defined $xmlstr or $xmlstr eq '' ) {
		$log->CRIT("Could not read the LoxPLAN file $loxconfig_path" . ($@ ? ": $@" : " (file is empty)"));
		return;
	}

	$lox_xml = loadLoxplanXML( $xmlstr, $loxconfig_path, $log );
	return if( !$lox_xml );

	

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
			
			my $dnsip;
			eval {
				require Socket;
				$dnsip = Socket::inet_ntoa(Socket::inet_aton($msxmlip));
			};
			if( $@ ) {
				$log->WARN("DNS Lookup error for $msxmlip: $@");
			}
			if ($dnsip) {
				$log->OK( " --> Found Miniserver $miniserver->{Title} and DNS lookup got IP $dnsip ...");
				$lox_miniserver{$miniserver->{U}}{IP} = $dnsip;
			} else {
				$log->WARN( " --> Could not resolve IP for Miniserver $miniserver->{Title}.");
				$lox_miniserver{$miniserver->{U}}{IP} = $msxmlip;
			}
		}
		
		# Mapping of LoxBerry Miniserver number (msno) to LoxPlan Miniserver
		
		foreach my $msno ( keys %lb_miniservers ) {
			
			# Compare serials (1st)
			# The "defined" guards are not cosmetic: a Miniserver without a
			# serial produced one warning per comparison, and a page load
			# flooded the webserver log with thousands of them.
			if( defined $lb_miniservers{$msno}{serial} and defined $miniserver->{Serial}
			    and $lb_miniservers{$msno}{serial} eq uc( $miniserver->{Serial} ) ) {
				$log->OK( "SERIAL match: LoxPlan-Miniserver '$miniserver->{Title}' matches LoxBerry Miniserver number $msno" );
				$lox_miniserver{$miniserver->{U}}{msno} = $msno;
				last;
			}
			
			# Fallback to hostname (2nd)
			
			if( defined $lb_miniservers{$msno}{IPAddress} and defined $lox_miniserver{$miniserver->{U}}{Host}
			    and $lb_miniservers{$msno}{IPAddress} eq $lox_miniserver{$miniserver->{U}}{Host} ) {
				$log->OK( "HOSTNAME match: LoxPlan-Miniserver '$miniserver->{Title}' matches LoxBerry Miniserver number $msno" );
				$lox_miniserver{$miniserver->{U}}{msno} = $msno;
				last;
			}
			
			# Fallback to IP (3rd)
			
			if( defined $lb_miniservers{$msno}{IPAddress} and defined $lox_miniserver{$miniserver->{U}}{IP}
			    and $lb_miniservers{$msno}{IPAddress} eq $lox_miniserver{$miniserver->{U}}{IP} ) {
				$log->OK( "IP match: LoxPlan-Miniserver '$miniserver->{Title}' matches LoxBerry Miniserver number $msno" );
				$lox_miniserver{$miniserver->{U}}{msno} = $msno;
				last;
			}
		}
		
		if( !defined $lox_miniserver{$miniserver->{U}}{msno} ) {
			# Giving up
			$log->WARN("LoxPlan-Miniserver '$miniserver->{Title}' matches NO Miniserver defined in LoxBerry");
			next;
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
		# The "$parent" guard prevents walking off the top of the document:
		# parentNode of the document node returns undef, and the next
		# iteration would then die on an unblessed reference.
		do {
			$parent = $parent->parentNode;
		} while ($parent && (!$parent->{Ref}) && defined $parent->{Type} && ($parent->{Type} ne "LoxLIVE"));
		if ($parent && defined $parent->{Type} && $parent->{Type} eq "LoxLIVE") {
			$ms_ref = $parent->{U};
		} elsif ($parent) {
			$ms_ref = $parent->{Ref};
		}

		# Controls below a device container outside of the LoxLIVE subtree
		# (MTablet, AudioServer, ...) find no Miniserver above them.
		if( !defined $ms_ref and exists $MSFALLBACK{ uc($object->{Type} // '') } ) {
			$ms_ref = findMiniserverFallback( $object, \%lox_miniserver );
			$log->DEB("Fallback: $object->{Type} '" . ($object->{Title}//'') . "' assigned to Miniserver "
			          . (defined $ms_ref ? ($lox_miniserver{$ms_ref}{Title}//$ms_ref) : '<none found>'));
		}
		my $logmessage = "Object: ".($object->{Title}//"")." (".($object->{Type}//"").") --> MS "
		                 . (defined $ms_ref && defined $lox_miniserver{$ms_ref}{Title} ? $lox_miniserver{$ms_ref}{Title} : "<none>");
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
		# Objects without a Miniserver ancestor (permissions, user devices,
		# right groups, ...) simply have no msno. The frontend filters them
		# out - see settings_loxone.js, controls.filter( msno > 0 ).
		$lox_statsobject{$object->{U}}{msno} = defined $ms_ref ? $lox_miniserver{$ms_ref}{msno} : undef;
		
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
	my $ms_serials = $args{ms_serials};
	
	$log->INF("loxplan2json started") if ($log);

	# Read the timestamps of the locally stored json.
	#
	# This MUST be guarded. On the very first run the file does not exist
	# yet, and a previously failed run may have left a truncated one behind.
	# Because this block used to sit OUTSIDE of any eval - and ajax.cgi calls
	# us without an eval as well - an exception here killed the CGI in the
	# middle of its response. The web interface then waited forever on
	# "Fetching Loxone Config from Miniservers..." without ever showing an
	# error, and reinstalling did not help because the broken file is part of
	# the plugin backup and gets restored on every upgrade.
	my $localTimestamp;
	my $lastChecked;
	eval {
		$log->INF("Reading local Loxplan json") if ($log);
		my $loxplanobj = LoxBerry::JSON->new();
		my $loxplan = $loxplanobj->open( filename => $args{output}, readonly => 1 );
		if( $loxplan ) {
			$localTimestamp = $loxplan->{documentInfo}->{LoxAPPversion3timestamp};
			$lastChecked    = $loxplan->{documentInfo}->{S4L_LastChecked};
		}
	};
	if( $@ ) {
		$log->WARN("loxplan2json: Could not read $args{output} ($@) - continuing without the local timestamps") if ($log);
	}

	# Parse the LoxPLAN.
	#
	# Note: the former "return undef" inside the eval only left the eval
	# block, not this function - a failed parse was therefore reported as
	# success to the caller.
	my $result;
	eval {
		$result = readloxplan( log => $args{log}, filename => $args{filename}, ms_serials => $ms_serials);
	};
	if( $@ ) {
		$log->CRIT("loxplan2json: Exception while parsing the LoxPLAN: $@") if ($log);
		return undef;
	}
	if( !$result ) {
		$log->CRIT("loxplan2json: Could not parse the LoxPLAN of this Miniserver") if ($log);
		return undef;
	}

	$result->{documentInfo}->{LoxAPPversion3timestamp} = $remoteTimestamp ? $remoteTimestamp : $localTimestamp;
	$result->{documentInfo}->{S4L_LastChecked} = $lastChecked;

	# Write atomically.
	#
	# The previous version deleted the target first and then wrote without
	# any error handling. Any failure in between left an empty or truncated
	# file - and from then on every further run failed while reading it.
	my $tmpfile = $args{output} . ".tmp.$$";
	eval {
		open( my $fh, '>', $tmpfile ) or die "Could not open $tmpfile: $!\n";
		print {$fh} JSON->new->pretty(1)->encode( $result ) or die "Could not write $tmpfile: $!\n";
		close($fh) or die "Could not close $tmpfile: $!\n";
		rename( $tmpfile, $args{output} ) or die "Could not rename $tmpfile to $args{output}: $!\n";
	};
	if( $@ ) {
		unlink $tmpfile;
		$log->CRIT("loxplan2json: Could not write $args{output}: $@") if ($log);
		return undef;
	}

	$log->OK("loxplan2json: $args{output} written") if ($log);
	return 1;

}

#############################################################################
# Determines the Miniserver for controls below a device container that sits
# outside of the LoxLIVE subtree
#############################################################################
# 1. an ancestor carrying a "Master" attribute with a known Miniserver serial
#    - that is how an AudioServer references its Miniserver
# 2. if the plan contains exactly one Miniserver, that one
# Returns the U of the Miniserver, or undef.

sub findMiniserverFallback
{
	my ($object, $lox_miniserver) = @_;

	my %serials;
	foreach my $u ( keys %{$lox_miniserver} ) {
		next if( !defined $lox_miniserver->{$u}->{Serial} or $lox_miniserver->{$u}->{Serial} eq '' );
		$serials{ uc($lox_miniserver->{$u}->{Serial}) } = $u;
	}

	my $parent = $object;
	for( 1..12 ) {
		$parent = $parent->parentNode;
		last if( !$parent or !$parent->can('getAttribute') );
		my $master = $parent->getAttribute('Master');
		next if( !defined $master or $master eq '' );
		return $serials{ uc($master) } if( $serials{ uc($master) } );
	}

	my @all = grep { $_ ne '' } keys %{$lox_miniserver};
	return $all[0] if( scalar(@all) == 1 );

	return;
}

#############################################################################
# Loads the LoxPLAN XML and repairs the invalid XML that Loxone Config
# produces.
#############################################################################
#
# Loxone Config has been emitting non-valid XML for years - duplicate
# attributes are the most common case (Phn on User, Title on the API
# Connector family, ...). Loxone's own software tolerates it, so it does not
# get fixed on their side, and every new generation of blocks brings new
# occurrences. Repairing only a hard coded list of element types meant that
# a single unknown element killed the entire import.
#
# Three stages, each of them logged, so that a support case can be judged
# from the logfile alone:
#   1. strict - the normal case, costs nothing
#   2. duplicate attributes removed from ALL elements
#   3. libxml2 recover mode - keeps everything that is parseable
#
# Returns the DOM, or undef if even recover mode fails.

sub loadLoxplanXML
{
	my ($xmlstr, $sourcefile, $log) = @_;

	my $dom;

	# Stage 1 - strict
	eval { $dom = XML::LibXML->load_xml( string => $xmlstr ); };
	return $dom if( $dom );
	my $error_strict = $@;

	$log->WARN("The LoxPLAN is not valid XML. Trying to repair it...") if ($log);
	logXMLerror( $error_strict, $xmlstr, $log, "WARN" );

	# Stage 2 - remove duplicate attributes everywhere
	my $fixed = correctXML_removeAttributeDuplicates_all( $xmlstr, $log );
	eval { $dom = XML::LibXML->load_xml( string => $fixed ); };
	if( $dom ) {
		$log->OK("The LoxPLAN could be repaired: duplicate attributes removed. Import continues normally.") if ($log);
		return $dom;
	}
	my $error_fixed = $@;

	# Stage 3 - recover mode
	#
	# Careful: recover mode also "succeeds" on a document where it had to
	# throw almost everything away. A DOM with no Miniserver in it is
	# useless to us and would only produce an empty statistics selection
	# without any error - exactly the kind of silent failure we are getting
	# rid of. So the result is checked before it is accepted.
	eval { $dom = XML::LibXML->load_xml( string => $fixed, recover => 2 ); };
	if( $dom ) {
		my @recovered = $dom->findnodes('//C[@Type]');
		my @live      = $dom->findnodes('//C[@Type="LoxLIVE"]');
		my $expected  = () = $fixed =~ /<C\s[^>]*?Type="/g;

		if( @live ) {
			$log->WARN("The LoxPLAN could only be read in recover mode.") if ($log);
			$log->WARN(sprintf("Recovered %d of %d elements - %d blocks are MISSING and will not be offered for statistics.",
				scalar(@recovered), $expected, $expected - scalar(@recovered))) if ($log and $expected > scalar(@recovered));
			logXMLerror( $error_fixed, $fixed, $log, "WARN" );
			return $dom;
		}

		$log->CRIT(sprintf("Recover mode only salvaged %d of %d elements and not a single Miniserver - the result is unusable.",
			scalar(@recovered), $expected)) if ($log);
		undef $dom;
	}

	# Give up - but leave behind something that can actually be acted upon
	$log->CRIT("Cannot parse the LoxPLAN of this Miniserver, not even in recover mode.") if ($log);
	logXMLerror( ($@ ? $@ : $error_fixed), $fixed, $log, "CRIT" );

	if( $sourcefile and $LoxBerry::System::lbpdatadir ) {
		my $keep = "$LoxBerry::System::lbpdatadir/loxplan_parse_failed.xml";
		eval {
			require File::Copy;
			File::Copy::copy( $sourcefile, $keep );
		};
		$log->CRIT("A copy of the file was saved as $keep - please attach it to a bug report.") if ($log and -e $keep);
	}

	return;
}

#############################################################################
# Turns a libxml2 error message into something actionable
#############################################################################
# libxml2 only reports line and column. That alone told neither the user nor
# us WHICH block is broken, which is why bug reports were never conclusive.
# We additionally resolve the element type and title from the source line.

sub logXMLerror
{
	my ($error, $xmlstr, $log, $level) = @_;
	$level = "CRIT" if( !$level );
	return if( !$error or !$log );

	my @errors;
	my %seen;
	foreach my $line ( split(/\n/, "$error") ) {
		next if( $line !~ /:(\d+):\s*(?:parser\s+|namespace\s+)?(?:error|warning)\s*:\s*(.+?)\s*$/i );
		my ($lineno, $msg) = ($1, $2);
		next if( $seen{"$lineno|$msg"}++ );
		push @errors, [ $lineno, $msg ];
	}

	if( !@errors ) {
		my $flat = "$error"; $flat =~ s/\s+/ /g;
		xmllog( $log, $level, "XML parser reported: " . substr($flat, 0, 500) );
		return;
	}

	my @src = split(/\n/, $xmlstr);
	my $shown = 0;
	foreach my $e ( @errors ) {
		my ($lineno, $msg) = @{$e};
		last if( $shown >= 10 );
		$shown++;

		# The element may start on an earlier line than the reported one
		my ($type, $title);
		for( my $i = $lineno-1; $i >= 0 && $i > $lineno-25; $i-- ) {
			next if( !defined $src[$i] );
			if( $src[$i] =~ /<C\s[^>]*?Type="([^"]*)"/ ) {
				$type = $1;
				($title) = $src[$i] =~ /<C\s[^>]*?Title="([^"]*)"/;
				last;
			}
		}

		my $srcline = defined $src[$lineno-1] ? $src[$lineno-1] : '';
		$srcline =~ s/^\s+//;
		$srcline = substr($srcline, 0, 300) . ' ...' if( length($srcline) > 300 );

		xmllog( $log, $level, sprintf('LoxPLAN line %d: %s', $lineno, $msg) );
		xmllog( $log, $level, sprintf('   affected block: Type="%s" Title="%s"',
			(defined $type ? $type : '?'), (defined $title ? $title : '?')) );
		xmllog( $log, $level, '   source line   : ' . $srcline );
	}

	if( scalar(@errors) > $shown ) {
		xmllog( $log, $level, sprintf('... and %d further XML errors (not listed)', scalar(@errors) - $shown) );
	}
}

sub xmllog
{
	my ($log, $level, $text) = @_;
	return if( !$log );
	if   ( $level eq "WARN" ) { $log->WARN($text) }
	elsif( $level eq "INF" )  { $log->INF($text) }
	else                      { $log->CRIT($text) }
}

### Loxone XML: Removes duplicate attributes in ALL elements
# Previously only a hard coded list of types (LoxAIR, LoxAIRDevice, User) was
# repaired, so every new Loxone block with the same defect broke the import
# again - most recently the Fronius "API Connector" family.
# Params: 1. full xml 2. $log object
# Returns: corrected xml
sub correctXML_removeAttributeDuplicates_all
{
	my ($xmlstr, $log) = @_;

	my %types;
	while( $xmlstr =~ /<C\s[^>]*?Type="([^"]*)"/g ) {
		$types{$1} = 1;
	}
	$log->INF("Checking " . scalar(keys %types) . " element types for duplicate attributes") if ($log);

	foreach my $type ( sort keys %types ) {
		$xmlstr = correctXML_removeAttributeDuplicates( $xmlstr, $type, $log );
	}
	return $xmlstr;
}

### Loxone XML: Corrects invalid duplicate attributes in XML element
# Params: 1. full xml 2. Type (e.g. LoxAIR) 3. $log object
# Returns: Corrected xml
sub correctXML_removeAttributeDuplicates
{
	
	my $xmlstr = shift;
	my $elemType = shift;
	my $log = shift;
	
	my $startpos = 0;

	while( ( my $foundpos = index( $xmlstr, '<C Type="'.$elemType.'"', $startpos ) ) != -1 ) {
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
			$log->WARN( "$elemType Original: $tagstr") if ($log);
			$log->WARN( "$elemType S4LFixed: $newattribute") if ($log); 
		}
	}
	
	return $xmlstr;
	
}




#####################################################
# Finally 1; ########################################
#####################################################
1;
