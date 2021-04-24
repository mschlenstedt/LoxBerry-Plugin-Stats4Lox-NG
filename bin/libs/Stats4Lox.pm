
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
if ($DEBUG || $DUMP) {
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

	require "$LoxBerry::System::lbpbindir/libs/Globals.pm";

	my @data = @{$_[0]};
	my $nosend = $_[1];
	my @queue;

	#print Data::Dumper::Dumper @data;
	
	if ( scalar @data == 0) {
		print STDERR "Array of Hashes needed. See documentation.";
		return (2, undef);
	}

	foreach my $record (@data) {
		my $timestamp;
		my %tags = ();
		my %fields = ();
		#if (! $record->{uuid}) {
		#	print STDERR "UUID is needed. Skipping this dataset.";
		#	next;
		#}
		my $measurement = $record->{measurementname};
		if( !$measurement ) {
			#die "measurementname missing (mandatory data field)\n";
			print STDERR  "Measurementname missing (mandatory data field). Skipping this dataset.\n";
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
		$tags{"source"} = $record->{source} if ($record->{source});
		foreach my $value ( @{$record->{values}} ) {
			#my $valname = $tags{uuid} . "_" . $value->{key};
			my $valname = $value->{key};
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
	my $client;
	my $telegraf_udp_socket = $Globals::telegraf_udp_socket;
	my $telegraf_unix_socket = $Globals::telegraf_unix_socket;
	
	my $socketlockfh = lockTelegrafSocket();
	
	# Wait until Telegraf buffer fullness is below 75%
	foreach (@Globals::telegraf_buffer_checks) {
		my $buffer = 1;
		my $check = $_;
		while ( $buffer > $Globals::telegraf_max_buffer_fullness ) {
			my $internals = telegrafinternals();
			if (!$internals) {
				print STDERR "Cannot get Telegraf internal stats. Ommitting buffer checks\n" if $DEBUG;
				$buffer = 0;
				last;
			}
			$buffer = $internals->{write}->{$check}->{buffer_size} / $internals->{write}->{$check}->{buffer_limit};
			print STDERR "Telegraf $check buffer: " . $internals->{write}->{$check}->{buffer_size} . "/" . $internals->{write}->{$check}->{buffer_limit} if $DEBUG;
			print STDERR " --> " . $buffer * 100 . "%\n" if $DEBUG;
			sleep 1 if $buffer > $Globals::telegraf_max_buffer_fullness;
		}
	}

	# Send to telegraf via Unix socket
	eval {
		$client = IO::Socket::UNIX->new(
			Peer =>	"$telegraf_unix_socket",
			Type => SOCK_STREAM,
			Timeout => 10,
		) or die "Socket could not be created, failed with error: $!\n";;
	};
	if( ! $@ ) {
		print STDERR "Using Unix socket\n" if $DEBUG;
		$client->autoflush(1);
		foreach(@queue) {
			my $length_expected = length($_)+1;
			print STDERR "Data to sent ($length_expected bytes): $_\n" if $DUMP;
			my $i = 1;
			while ($i <= 10) {
				my $sent = $client->send($_ . "\n");
				if ($sent == $length_expected) {
					print STDERR "Try $i/10: Sent: $sent bytes Expected: $length_expected bytes\n" if $DEBUG;
					$i = 12;
				} else {
					print STDERR "Try $i/10: FAILED sending. Sent: $sent Bytes Expected: $length_expected bytes. Retry...\n" if $DEBUG;
					sleep ($i);
					$i++;
				}
			}
			if ($i < 12) { # All retrys failed...
				print STDERR "Sending to Unix Socket failed finally (giving up - data was NOT sent (but maybe partly)!)" if $DEBUG;
				return (2, \@queue);
			}
		}
		$client->shutdown(SHUT_RDWR);
		return (0, \@queue);
	} else {
		print STDERR "Could not use unix socket (giving up - data was NOT sent (but maybe partly)!): $@" if $DEBUG;
		return (2, \@queue);
	}
}

#####################################################
# Get internal statistics from Telegraf
#####################################################
sub telegrafinternals
{
	require "$LoxBerry::System::lbpbindir/libs/Globals.pm";

	my @files = glob( $Globals::telegraf_internal_files );
	@files = sort @files; # Oldest first
	my @data;
	my $result;

	foreach (@files) {
		open (F, '<', $_);
			print STDERR "Read file $_\n" if $DEBUG;
			my @lines = <F>;
		close (F);
		push (@data, @lines);
	}
	@data = reverse(@data); # Newest first
	print STDERR "Data read:\n" . Data::Dumper::Dumper(\@data) if $DUMP;

	foreach (@data) {
		my ($firstblock, $secondblock, $thirdblock) = split (/(?<!\\)\s/); # Split at 'non-escaped' spaces (look-behind)
		my ($measurement, $tags) = split (/(?<!\\),/, $firstblock, 2);
		# Inputs
		if ($measurement eq 'internal_gather') {
			$tags =~ /input=(.*),/;
			my $tag = $1;
			my $section="gather";
			if (!$result->{$section}->{$tag}) { # only first match
				$secondblock =~ /metrics_gathered=(.*?)[,i\s]/;
				$result->{$section}->{$tag}->{metrics_gathered} = $1;
				$secondblock =~ /gather_time_ns=(.*?)[,i\s]/;
				$result->{$section}->{$tag}->{gather_time_ns} = $1;
				$secondblock =~ /errors=(.*?)[,i\s]/;
				$result->{$section}->{$tag}->{errors} = $1;
				$result->{$section}->{$tag}->{timestamp} = $thirdblock;
			}
		}
		# Outputs
		if ($measurement eq 'internal_write') {
			$tags =~ /output=(.*),/;
			my $tag = $1;
			my $section="write";
			if (!$result->{$section}->{$tag}) { # only first match
				$secondblock =~ /metrics_filtered=(.*?)[,i\s]/;
				$result->{$section}->{$tag}->{metrics_filtered} = $1;
				$secondblock =~ /write_time_ns=(.*?)[,i\s]/;
				$result->{$section}->{$tag}->{write_time_ns} = $1;
				$secondblock =~ /errors=(.*?)[,i\s]/;
				$result->{$section}->{$tag}->{errors} = $1;
				$secondblock =~ /metrics_added=(.*?)[,i\s]/;
				$result->{$section}->{$tag}->{metrics_added} = $1;
				$secondblock =~ /metrics_written=(.*?)[,i\s]/;
				$result->{$section}->{$tag}->{metrics_written} = $1;
				$secondblock =~ /metrics_dropped=(.*?)[,i\s]/;
				$result->{$section}->{$tag}->{metrics_dropped} = $1;
				$secondblock =~ /buffer_size=(.*?)[,i\s]/;
				$result->{$section}->{$tag}->{buffer_size} = $1;
				$secondblock =~ /buffer_limit=(.*?)[,i\s]/;
				$result->{$section}->{$tag}->{buffer_limit} = $1;
				$result->{$section}->{$tag}->{timestamp} = $thirdblock;
			}
		}
		# Agent
		if ($measurement eq 'internal_agent') {
			my $tag = "agent";
			if (!$result->{$tag}) { # only first match
				$secondblock =~ /metrics_written=(.*?)[,i\s]/;
				$result->{$tag}->{metrics_written} = $1;
				$secondblock =~ /metrics_dropped=(.*?)[,i\s]/;
				$result->{$tag}->{metrics_dropped} = $1;
				$secondblock =~ /metrics_gathered=(.*?)[,i\s]/;
				$result->{$tag}->{metrics_gathered} = $1;
				$secondblock =~ /gather_errors=(.*?)[,i\s]/;
				$result->{$tag}->{gather_errors} = $1;
				$result->{$tag}->{timestamp} = $thirdblock;
			}
		}
		# Process
		if ($measurement eq 'internal_process') {
			my $tag = "process";
			if (!$result->{$tag}) { # only first match
				$secondblock =~ /errors=(.*?)[,i\s]/;
				$result->{$tag}->{errors} = $1;
				$result->{$tag}->{timestamp} = $thirdblock;
			}
		}
		# Memstats
		if ($measurement eq 'internal_memstats') {
			my $tag = "memstats";
			if (!$result->{$tag}) { # only first match
				$secondblock =~ /mallocs=(.*?)[,i\s]/;
				$result->{$tag}->{mallocs} = $1;
				$secondblock =~ /pointer_lookups=(.*?)[,i\s]/;
				$result->{$tag}->{pointer_lookups} = $1;
				$secondblock =~ /heap_objects=(.*?)[,i\s]/;
				$result->{$tag}->{heap_objects} = $1;
				$secondblock =~ /num_gc=(.*?)[,i\s]/;
				$result->{$tag}->{num_gc} = $1;
				$secondblock =~ /frees=(.*?)[,i\s]/;
				$result->{$tag}->{frees} = $1;
				$secondblock =~ /alloc_bytes=(.*?)[,i\s]/;
				$result->{$tag}->{alloc_bytes} = $1;
				$secondblock =~ /heap_alloc_bytes=(.*?)[,i\s]/;
				$result->{$tag}->{heap_alloc_bytes} = $1;
				$secondblock =~ /heap_released_bytes=(.*?)[,i\s]/;
				$result->{$tag}->{heap_released_bytes} = $1;
				$secondblock =~ /sys_bytes=(.*?)[,i\s]/;
				$result->{$tag}->{sys_bytes} = $1;
				$secondblock =~ /heap_sys_bytes=(.*?)[,i\s]/;
				$result->{$tag}->{heap_sys_bytes} = $1;
				$secondblock =~ /heap_idle_bytes=(.*?)[,i\s]/;
				$result->{$tag}->{heap_idle_bytes} = $1;
				$secondblock =~ /total_alloc_bytes=(.*?)[,i\s]/;
				$result->{$tag}->{total_alloc_bytes} = $1;
				$secondblock =~ /heap_in_use_bytes=(.*?)[,i\s]/;
				$result->{$tag}->{heap_in_use_bytes} = $1;
				$result->{$tag}->{timestamp} = $thirdblock;
			}
		}
	}
	print STDERR "Result:\n" . Data::Dumper::Dumper(\$result) if $DUMP;

	return ($result);
}

#####################################################
# Internal Subroutines
#####################################################

sub lockTelegrafSocket {
	my $socketlockfile = $Globals::s4ltmp."/socket_telegraf.lock";
	open my $fh, '>', $socketlockfile or die "CRITICAL Could not open LOCK file $socketlockfile: $!";
	print STDERR "Aquiring Telegraf socket LOCK...\n" if $DEBUG;
	flock $fh, 2;
	print STDERR "Telegraf socket locked\n" if $DEBUG;
	return $fh;
}

#####################################################
# Finally 1; ########################################
#####################################################
1;
