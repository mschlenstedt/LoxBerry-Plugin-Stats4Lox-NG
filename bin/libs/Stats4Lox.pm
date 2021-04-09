
use strict;
use warnings;
use JSON;
use LoxBerry::IO;

use base 'Exporter';
our @EXPORT = qw (
	msget_value
	influx_lineprot
	loxone2telegraf
);

package Stats4Lox;

our $DEBUG = 1;
our $DUMP = 0;
if ($DEBUG) {
	require Data::Dumper;
}

#####################################################
# Miniserver REST Call to get all values of block
# Param 1: Miniserver number
# Param 2: Block's name, decription or UUID or full URL path (see Param 3)
# Param 3: Set to 1 if Param 2 is a full url path
#####################################################
sub msget_value
{
	require LWP::UserAgent;
	require Encode;

	my $msnr = shift;
	my $block = shift;
	my @response;
	my %data;
	
	my %ms = LoxBerry::System::get_miniservers();
	if (! $ms{$msnr}) {
		print STDERR "Miniserver $msnr not found or configuration not finished\n" if $DEBUG;
		return (601, undef);
	}
	
	print STDERR "Querying param: $block\n" if ($DEBUG);
	my $rawdata;
	my $status;
	if ( $block =~ m/^\/jdev\//) { # assume this is a full url
		($rawdata, $status) = LoxBerry::IO::mshttp_call2($msnr, $block); 
	} else {
		($rawdata, $status) = LoxBerry::IO::mshttp_call2($msnr, "/jdev/sps/io/" . URI::Escape::uri_escape($block) . '/all'); 
	}

	
	if ( $status->{code} ne "200" ) {
		print STDERR "Error while getting data from Miniserver: $status->{message}. Status: $status->{status}\n" if $DEBUG;
		return ($status->{code}, undef);
	}
	
	# Clean up Loxone's analoge output f*ck up (is always 0/zero if grabbed with /all...):
	my $respvalue_filtered = $rawdata;
	$respvalue_filtered =~ s/\n//g;
	$respvalue_filtered =~ s/.*\"value\": \"([-\d\.]+).*/$1/;
	#print STDERR "respvalue_filtered: $respvalue_filtered\n"; 
	no warnings "numeric";
	if($respvalue_filtered ne "" and $respvalue_filtered == 0) {
		# Search for outputs - if present, value is ok and no analogue output
		if( $rawdata !~ m/\"output0\":/ && $block !~ m/^\/jdev\// ) {
			# Not found - we require to request the value without /all
			print STDERR "Re-Querying param: $block withOUT /all due to f*cked up analoge output\n" if ($DEBUG);
			#(undef, undef, $rawdata) = LoxBerry::IO::mshttp_call($msnr, "/jdev/sps/io/" . URI::Escape::uri_escape($block)); 
			($rawdata, $status) = LoxBerry::IO::mshttp_call2($msnr, "/jdev/sps/io/" . URI::Escape::uri_escape($block)); 
		} 
	}
	
	# Clean up Loxone's json f*ck up:
        $rawdata =~ s/\"value\": ([^\"]+[a-zA-Z]+[^\"]+)\}/\"value\": \"$1\"\}/g;
	print STDERR "Received (and cleaned) raw data:\n" . $rawdata . "\n" if ($DEBUG);

	my $respjson;
	eval {
		$respjson = JSON::decode_json( "$rawdata" );
		1;
	};
	if ($@) {
		print STDERR "No valid JSON data received: $@\n" if $DEBUG;
		return (602, undef);
	}

	print STDERR "Received (and cleaned) json data:\n" . Data::Dumper::Dumper($respjson) . "\n" if ($DUMP);

	my $resp_code = $respjson->{LL}->{Code};
	if ($resp_code ne "200") {
		print STDERR "Error from Miniserver. Code: $resp_code\n" if $DEBUG;
		return ($resp_code, undef);
	}
	$resp_code = $resp_code + 0; # Convert from string

	# Default value
	my $value = $respjson->{LL}->{value};
        $value =~ s/^([-\d\.]+)\s*(.*)/$1/g; # cut of unit
	$value = $value + 0; # Convert from string
	$data{Value} = $value;
	$data{Name} = "Default";
	$data{Key} = "Default";
	$data{Unit} = $2;
	$data{Code} = $resp_code;

	push (@response, \%data);

	# Additional outputs
	my $i = 0;
	while ($respjson->{LL}->{"output$i"}) {

		my %outdata;
		my $val = $respjson->{LL}->{"output$i"}->{value};
		$outdata{Value} = $respjson->{LL}->{"output$i"}->{value};
		$outdata{Name} = $respjson->{LL}->{"output$i"}->{name};
		$outdata{Key} = "output$i";
		$outdata{Nr} = $respjson->{LL}->{"output$i"}->{nr};
		push (@response, \%outdata);

		$i++;
	}

	# Additional SpecialStates from IRR
	$i = 0;
	while ($respjson->{LL}->{"SpecialState$i"}) {

		my %ssdata;
		$ssdata{Value} = $respjson->{LL}->{"SpecialState$i"}->{value};
		$ssdata{Name} = $respjson->{LL}->{"SpecialState$i"}->{uuid};
		$ssdata{Key} = "SpecialState$i";
		$ssdata{Nr} = $respjson->{LL}->{"SpecialState$i"}->{nr};
		push (@response, \%ssdata);

		$i++;
	}

	print STDERR "Response of subroutine:\n" . Data::Dumper::Dumper(\@response) . "\n" if ($DUMP);

	return ($resp_code, \@response);
}

#####################################################
# Create InfluxDB lineformat
# Param 1: Timestamp
# Param 2: measurement
# Param 3: Hash with tags
# Param 4: Hash with fields
#####################################################
sub influx_lineprot
{
	my $timestamp = shift;
	my $measurement = shift;
	my %tags = %{$_[0]};
	my %fields = %{$_[1]};

	if (!$timestamp) {$timestamp = ""};

	if (!$measurement) {
		print STDERR "Measurement is needed." if $DEBUG;
		return (undef);
	};

	if (keys %fields == 0) {
		print STDERR "At least one field is needed." if $DEBUG;
		return (undef);
	};

	print STDERR "Submitted measurement: " . $measurement . "\n" if ($DUMP);
	print STDERR "Submitted timestamp: " . $timestamp . "\n" if ($DUMP);
	print STDERR "Submitted tags:\n" . Data::Dumper::Dumper(\%tags) . "\n" if ($DUMP);
	print STDERR "Submitted fields:\n" . Data::Dumper::Dumper(\%fields) . "\n" if ($DUMP);

	$measurement =~ s/([ ,])/\\$1/g;
	my $data;
	my $line = $measurement;
	if (keys %tags > 0) {
		foreach  my $key (keys %tags) {
			$data = "$key=$tags{$key}";
			$data =~ s/([ ,])/\\$1/g;
			$line .= ",$data";
		}
	}

	$line .= " ";

	my $i = 0;
	foreach  my $key (keys %fields) {
		#Try to figure out if field must be handled as string - maybe to complicated here - better suggestions are welcome ;-)
		my $stringtest = $fields{$key};
		$stringtest =~ s/(.*)i$/$1/g; # i as last position is integer
		if ( $stringtest =~ m/[a-zA-Z]/ ) { # still String?
			$data = "$key=\"$fields{$key}\"";
		} else {
			$data = "$key=$fields{$key}";
		}
		$data =~ s/([ ,])/\\$1/g;
		$line .= "," if $i > 0;
		$line .= "$data";
		$i++;
	}

	$line .= " $timestamp" if $timestamp;

	return ($line);
}

#####################################################
# Send Value to Telegraf
# Param 1: Timestamp
# Param 2: measurement
# Param 3: Hash with tags
# Param 4: Hash with fields
#####################################################
sub lox2telegraf
{
	my @data = @{$_[0]};
	my $nosend = $_[1];
	my @queue;

	#print Data::Dumper::Dumper @data;
	
	my $measurement = "stats4lox";

	if ( scalar @data == 0) {
		print STDERR "Array of Hashes needed. See documentation.";
		return (2, undef);
	}

	foreach my $record (@data) {
		my $timestamp;
		my %tags = ();
		my %fields = ();
		if (! $record->{uuid}) {
			print STDERR "UUID is needed. Skipping this dataset.";
			next;
		}
		$timestamp = $record->{timestamp} + 0 if ($record->{timestamp}); # Convert to num
		$tags{"name"} =	$record->{name} if ($record->{name});
		$tags{"description"} = $record->{description} if ($record->{description});
		$tags{"uuid"} = $record->{uuid} if ($record->{uuid});
		$tags{"type"} = $record->{type} if ($record->{type}) ;
		$tags{"category"} = $record->{category} if($record->{category});
		$tags{"room"} = $record->{room} if ($record->{room});
		$tags{"msno"} = $record->{msno} if ($record->{msno});
		foreach my $value ( @{$record->{values}} ) {
			my $valname = $tags{uuid} . "_" . $value->{key};
			$fields{$valname} = $value->{value};
		}

		#print Data::Dumper::Dumper \%tags;
		#print Data::Dumper::Dumper \%fields;

		my $line = Stats4Lox::influx_lineprot( $timestamp, $measurement, \%tags, \%fields );
		push (@queue, $line);
	}

	#my @outputs;
	#if( ref($results->{outputs}) eq "ARRAY" ) {
	#	@outputs = @{$results->{outputs}};
	#}

	print STDERR "Send Queue:\n" . Data::Dumper::Dumper(\@queue) if $DUMP;
	print STDERR "Elements in queue: " . scalar @queue . "\n";
	
	# If no send
	if ($nosend) {
		return (1, \@queue);
	}

	use IO::Socket;
	#use IO::Socket qw(AF_INET AF_UNIX SOCK_STREAM SHUT_WR);
	my $tryudp = 0;
	my $client;
	my $telegraf_udp_socket = "8094";
	my $telegraf_unix_socket = "/run/telegraf.sock";
	
	my $sockstr; 
	
	# Send to telegraf via Unix socket
	if (-e $telegraf_unix_socket) { 
		$sockstr = "UNIX";
		eval {
			$client = IO::Socket::UNIX->new(
				Peer =>	"$telegraf_unix_socket",
				Type => SOCK_STREAM,
				Timeout => 10,
			) or die "$sockstr Socket could not be created, failed with error: $!\n";;
		};
		if( ! $@ ) {
			print STDERR "Using $sockstr socket\n" if $DEBUG;
			
			$client->autoflush(1);
			foreach(@queue) {
				my $length_expected = length($_)+1;
				print STDERR "$sockstr Data to sent ($length_expected bytes): $_\n" if $DUMP;
				my $i = 1;
				while ($i <= 10) {
					my $sent = $client->send($_ . "\n");
					if ($sent == $length_expected) {
						print STDERR "$sockstr Try $i: Sent: $sent bytes Expected: $length_expected bytes\n" if $DUMP;
						$i = 12;
					} else {
						print STDERR "$sockstr Try $i: FAILED sending. Sent: $sent Bytes Expected: $length_expected bytes. Retry...\n" if $DEBUG;
						sleep ($i);
						$i++;
					}
					if ($i < 12) { # All retrys failed...
						$tryudp = 1;
					}
				}
			}
			$client->shutdown(SHUT_RDWR);
			if ($tryudp == 0) {
				return (0, \@queue);
			}
		} else {
			print STDERR "Could not use $sockstr socket (will fallback to udp): $@" if $DEBUG;
			$tryudp = 1;
		}
	} else {
		$tryudp = 1;
	}
	
	# Send to telegraf via UDP socket
	if ($tryudp) { 
		$sockstr = "UDP";
		eval {
			$client = IO::Socket::INET->new(
				PeerAddr    => 'localhost',
				PeerPort => $telegraf_udp_socket,
				Proto => 'udp',
				Timeout => 10,
			) or die "$sockstr Socket could not be created, failed with error: $!\n";;
		};
		if( ! $@ ) {
			print STDERR "Using $sockstr socket\n" if $DEBUG;
			$client->autoflush(1);
			my $retstatus = 0;
			foreach(@queue) {
				my $length_expected = length($_)+1;
				print STDERR "$sockstr Data to sent ($length_expected bytes): $_\n" if $DUMP;
				my $i = 1;
				while ($i <= 10) {
					my $sent = $client->send($_ . "\n");
					if ($sent == $length_expected) {
						print STDERR "$sockstr Try $i: Sent: $sent bytes Expected: $length_expected bytes\n" if $DUMP;
						$i = 12;
					} else {
						print STDERR "$sockstr Try $i: FAILED sending. Sent: $sent Bytes Expected: $length_expected bytes. Retry...\n" if $DEBUG;
						sleep ($i);
						$i++;
					}
					if ($i < 12) { # All retrys failed...
						$retstatus = 2;
					}
				}
			}
			$client->shutdown(SHUT_RDWR);
			return ($retstatus, \@queue);
		} else {
			print STDERR "Could not use $sockstr socket (giving up - data was NOT sent (but maybe partly)!): $@" if $DEBUG;
			return (2, \@queue);
		}
	}
}
#####################################################
# Finally 1; ########################################
#####################################################
1;
