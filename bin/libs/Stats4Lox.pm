
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

our $DEBUG = 0;
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
	
	# Decode the response.
	#
	# There used to be a regular expression here that "repaired" Loxone's JSON
	# before decoding. A current Miniserver answers with valid JSON, and a
	# regex cannot repair JSON it does not understand - it can only corrupt it.
	# We therefore decode directly and report a failure together with the raw
	# response, instead of silently continuing with mangled data.
	#
	# The retry below is a legacy workaround: older firmware answered 0 for an
	# analog block when queried with /all. Checked against a current Miniserver
	# (Loxone Config 17) this no longer happens - LL.value carries real values
	# such as "49.6%" or "-5.126". It is kept for older firmware, but its
	# trigger is now the properly parsed number. Previously the WHOLE JSON
	# document was numified, which yields 0 for any response and fired the
	# retry far more often than intended.
	#
	# Careful with that retry: a query without /all writes on some block types.
	# That is issue #143, and the reason VIRTUALINTEXT is on the blacklist.
	my $respjson;
	my $resp_code;
	my $attempt = 0;
	while( 1 ) {
		$attempt++;

		if( ! eval { $respjson = JSON::decode_json( "$rawdata" ); 1 } ) {
			print STDERR "No valid JSON received from Miniserver for $block: $@\n" if $DEBUG;
			print STDERR "Raw response was: " . substr($rawdata, 0, 500) . "\n" if $DEBUG;
			return (602, undef);
		}
		print STDERR "Received json data:\n" . Data::Dumper::Dumper($respjson) . "\n" if ($DUMP);

		$resp_code = $respjson->{LL}->{Code};
		if( !defined $resp_code or $resp_code ne "200" ) {
			print STDERR "Error from Miniserver. Code: " . (defined $resp_code ? $resp_code : '<none>') . "\n" if $DEBUG;
			return ((defined $resp_code ? $resp_code : 602), undef);
		}

		my ($v) = parse_loxone_value( $respjson->{LL}->{value} );

		last if( $attempt >= 2 );                       # at most one retry
		last if( $respjson->{LL}->{output0} );          # precise values are in the outputs
		last if( $block =~ m{^/jdev/} );                # caller passed a full url
		last if( !defined $v or $v !~ /^-?[0-9]+(?:\.[0-9]+)?$/ or $v != 0 );

		print STDERR "Value is 0 and the block has no outputs - re-querying $block without /all\n" if ($DEBUG);
		my ($retryraw, $retrystatus) = LoxBerry::IO::mshttp_call2( $msnr, "/jdev/sps/io/" . URI::Escape::uri_escape($block) );
		last if( !$retryraw or $retrystatus->{code} ne "200" );
		$rawdata = $retryraw;
	}

	$resp_code = $resp_code + 0; # Convert from string

	# Default value
	#
	# LL.value is a string that may carry a unit ("49.6%", "82353 ml", "0.0°")
	# and may hold no number at all - text blocks answer with "" or with
	# "TextValue, not Implemented".
	#
	# The previous version ran  $value =~ m/(...)/;  $value = $1+0;  without
	# checking whether the match succeeded. On a failure $1 still held the
	# capture of the PREVIOUS block, so a text block silently reported the
	# number of whatever had been queried before it. The unit was assigned from
	# $2, which never existed because the pattern has a single group.
	my ($defvalue, $defunit) = parse_loxone_value( $respjson->{LL}->{value} );
	$data{Value} = $defvalue;
	$data{Name} = "Default";
	$data{Key} = "Default";
	$data{Unit} = $defunit;
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
		my $ssuuid = $respjson->{LL}->{"SpecialState$i"}->{uuid};
		$ssdata{Value} = $respjson->{LL}->{"SpecialState$i"}->{value};
		# Loxone does not name these outputs, it only sends their UUID. Left as
		# it was, that UUID ended up in the import dialog AND as the field name
		# in InfluxDB - see state_name().
		$ssdata{Name} = state_name( $msnr, $ssuuid, "SpecialState$i" );
		$ssdata{Uuid} = $ssuuid;
		$ssdata{Key} = "SpecialState$i";
		$ssdata{Nr} = $respjson->{LL}->{"SpecialState$i"}->{nr};
		push (@response, \%ssdata);

		$i++;
	}

	print STDERR "Response of subroutine:\n" . Data::Dumper::Dumper(\@response) . "\n" if ($DUMP);

	return ($resp_code, \@response);
}

#####################################################
# Readable name for an output that Loxone reports as a bare UUID
#####################################################
# Blocks with a variable number of outputs - EFM, Wallbox2, SpotPriceOptimizer -
# report those under SpecialState0, SpecialState1, ... and send no name for
# them, only a UUID. Measured on a live installation that is 16 of the 66
# outputs of those three blocks.
#
# The resolution comes from LoxAPP3.json and is prepared once while the Loxone
# configuration is being fetched, see Loxone::ParseXML::writeStateNames(). We
# only read the resulting sidecar file here: this function also runs in the
# grabber, once per statistic per minute, and must stay cheap.
#
# The file content is cached per process and re-read when its mtime changes, so
# a fresh configuration takes effect without a restart. If the file is missing
# the UUID is returned unchanged - exactly the previous behaviour.

my %statenames;
my %statenames_mtime;

sub state_name
{
	my ($msnr, $uuid, $fallback) = @_;

	# Never hand back a UUID. Where no name can be found - measured: 268 of 864
	# such outputs have none anywhere, neither in LoxAPP3 nor in the LoxPLAN -
	# the key is used instead. "SpecialState7" says at least which output it is,
	# stays the same across runs and is usable as a field name in InfluxDB. A
	# UUID is worse in every one of those respects.
	$fallback = $uuid if( !defined $fallback or $fallback eq '' );

	return $fallback if( !defined $uuid or $uuid eq '' or !defined $msnr );

	my $dir = eval { $Globals::stats4lox->{loxplanjsondir} };
	return $fallback if( !$dir );

	my $file  = "$dir/ms${msnr}_statenames.json";
	my $mtime = (stat($file))[9] || 0;

	if( !exists $statenames{$msnr} or ($statenames_mtime{$msnr} // -1) != $mtime ) {
		$statenames{$msnr} = {};
		$statenames_mtime{$msnr} = $mtime;
		if( $mtime ) {
			eval {
				open( my $fh, '<', $file ) or die "$!\n";
				local $/;
				my $content = <$fh>;
				close($fh);
				$statenames{$msnr} = JSON::decode_json( $content );
			};
			# A broken sidecar must never take the grabber down - it only means
			# the UUIDs stay unresolved.
			$statenames{$msnr} = {} if( $@ or ref($statenames{$msnr}) ne 'HASH' );
		}
	}

	my $name = $statenames{$msnr}->{ lc($uuid) };
	return ( defined $name and $name ne '' ) ? $name : $fallback;
}

#####################################################
# Split a Loxone value string into number and unit
#####################################################
# "49.6%"     -> (49.6, "%")
# "82353 ml"  -> (82353, "ml")
# "0.0°"      -> (0, "°")
# ""          -> (undef, undef)
# "TextValue" -> ("TextValue", undef)
#
# A value that holds no number is returned as text rather than being replaced
# by a number - the caller can tell the difference, and no value is invented.
sub parse_loxone_value
{
	my ($raw) = @_;
	return (undef, undef) if( !defined $raw );

	if( $raw =~ /^\s*([-+]?[0-9]*[.,]?[0-9]+)\s*(.*?)\s*$/ ) {
		my $num  = $1;
		my $unit = $2;
		$num =~ s/,/./;                 # some locales send a decimal comma
		return ($num + 0, ($unit ne '' ? $unit : undef));
	}

	my $text = $raw;
	$text =~ s/^\s+//;
	$text =~ s/\s+$//;
	return (($text ne '' ? $text : undef), undef);
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
		# An undefined or empty value would produce "key=", which is invalid
		# line protocol and makes InfluxDB reject the whole batch. Skip the
		# undefined ones and quote the empty ones.
		if( !defined $fields{$key} ) {
			print STDERR "Field '$key' has no value - skipped\n" if $DEBUG;
			next;
		}
		#Try to figure out if field must be handled as string - maybe to complicated here - better suggestions are welcome ;-)
		my $stringtest = $fields{$key};
		$stringtest =~ s/(.*)i$/$1/g; # i as last position is integer
		if ( $fields{$key} eq '' or $stringtest =~ m/[a-zA-Z]/ ) { # still String?
			$data = "$key=\"$fields{$key}\"";
		} else {
			$data = "$key=$fields{$key}";
		}
		$data =~ s/([,])/\\$1/g;
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
	my $telegraf_unix_socket = $Globals::telegraf->{telegraf_unix_socket};
	
	my $socketlockfh = lockTelegrafSocket();
	
	# Wait until Telegraf buffer fullness is below 75%
	foreach (@{$Globals::telegraf->{telegraf_buffer_checks}}) {
		my $buffer = 1;
		my $check = $_;
		while ( $buffer > $Globals::telegraf->{telegraf_max_buffer_fullness} ) {
			my $internals = telegrafinternals();
			if (!$internals) {
				print STDERR "Cannot get Telegraf internal stats. Ommitting buffer checks\n" if $DEBUG;
				$buffer = 0;
				last;
			}
			$buffer = $internals->{write}->{$check}->{buffer_size} / $internals->{write}->{$check}->{buffer_limit};
			print STDERR "Telegraf $check buffer: " . $internals->{write}->{$check}->{buffer_size} . "/" . $internals->{write}->{$check}->{buffer_limit} if $DEBUG;
			print STDERR " --> " . $buffer * 100 . "%\n" if $DEBUG;
			sleep 1 if $buffer > $Globals::telegraf->{telegraf_max_buffer_fullness};
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

	my @files = glob( $Globals::telegraf->{telegraf_internal_files} );
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
	my $socketlockfile = $Globals::stats4lox->{s4ltmp}."/socket_telegraf.lock";
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
