
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
	# There used to be a retry here: when the parsed value was 0 and the response
	# carried no output0, the block was queried a second time WITHOUT /all. That
	# was a workaround for old firmware which answered 0 for an analog block on
	# /all.
	#
	# Removed, because it was measured to be obsolete and harmful at the same time.
	# On firmware 17.1.6.30, all 24 blocks whose condition could be checked safely
	# answered identically both ways - not one case where the second query brought
	# anything the first had not. Meanwhile it fired for 8 of 128 subscribed
	# statistics, three of them of a writable type: a query without /all writes on
	# those (issue #143), so a VirtualOutCmd and two Memory blocks were being
	# written to on every single grabber cycle.
	my $respjson;
	my $resp_code;

	if( ! eval { $respjson = JSON::decode_json( "$rawdata" ); 1 } ) {

		# One kind of breakage is worth repairing, because the Miniserver produces
		# it and the block is otherwise unreadable: a status block whose text
		# itself contains quotes is sent without escaping them, which ends the
		# string early and breaks the document from there on.
		#
		#   "value": "{"text": "26.5°","duration": 3,"icon": 6397}"}
		#
		# The repair escapes that content and then hands the result back to
		# decode_json - the parser is the test. If it accepts the document, the
		# repair was right; if not, we are where we were and give up. That is the
		# difference to the regular expression that used to sit here and
		# "repaired" every response before decoding: this one only runs after
		# strict parsing has already failed, and its result has to parse.
		my $repaired = repair_status_json( $rawdata );
		if( !$repaired or ! eval { $respjson = JSON::decode_json( "$repaired" ); 1 } ) {
			print STDERR "No valid JSON received from Miniserver for $block: $@\n" if $DEBUG;
			print STDERR "Raw response was: " . substr($rawdata, 0, 500) . "\n" if $DEBUG;
			return (602, undef);
		}
		print STDERR "Repaired the unescaped status text of $block\n" if $DEBUG;
	}
	print STDERR "Received json data:\n" . Data::Dumper::Dumper($respjson) . "\n" if ($DUMP);

	$resp_code = $respjson->{LL}->{Code};
	if( !defined $resp_code or $resp_code ne "200" ) {
		print STDERR "Error from Miniserver. Code: " . (defined $resp_code ? $resp_code : '<none>') . "\n" if $DEBUG;
		return ((defined $resp_code ? $resp_code : 602), undef);
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
	#
	# One block type is exempt: a status block answers with an "output" WITHOUT a
	# number, and its LL.value is then not a value at all but a memory address -
	# "-1538922352", "-1517014704", different on every block. Measured on all 66
	# status blocks of a live installation, and on none of the other 54 types.
	# Handing that on as "Default" would write nonsense into the database.
	if( ref($respjson->{LL}->{output}) eq 'HASH' and !$respjson->{LL}->{output0} ) {
		push( @response, @{ status_block_outputs( $msnr, $block, $respjson, $resp_code ) } );
	}
	else {
		my ($defvalue, $defunit) = parse_loxone_value( $respjson->{LL}->{value} );
		$data{Value} = $defvalue;
		$data{Name} = "Default";
		$data{Key} = "Default";
		$data{Unit} = $defunit;
		$data{Code} = $resp_code;

		push (@response, \%data);
	}

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
# Outputs of a status block (issue #20)
#####################################################
# A status block answers /jdev/sps/io/<uuid>/all with the rendered text of the
# state it is in, under an "output" key without a number. Its LL.value is a
# memory address, and the connector UUIDs of TQ and AQ answer 404 - the value
# output is not reachable over HTTP at all, measured on all 66 blocks of a live
# installation.
#
# The way back to a number is the state table from the LoxPLAN: match the answer
# against the configured states, and the matching state carries its index and its
# TextV. Three outputs are offered:
#
#   Text    the rendered text, always
#   State   the index of the state, when it could be identified
#   Val     the TextV of that state, when it is a constant
#
# Text is what the user always gets; State and Val appear only when the block
# allows it. On the test installation 49 of 66 blocks could be identified and 17
# not, because several of their states share the same text.
#
# The text is stored as it arrives. Some of these blocks are configured with a
# whole JSON object as their status text, to feed something outside Loxone:
#
#   {"text": "26.5°","duration": 3,"icon": 6397}
#
# That is a text somebody wrote on purpose and it is stored as one. Reading a
# number back out of it by capturing what a placeholder was replaced with was
# tried and dropped - a text can hold several placeholders and which of them would
# be "the" value is not knowable.
#####################################################

# Anything from "<v" up to ">" is a placeholder that Loxone substitutes at
# runtime. Counted in a real LoxPLAN: <v1> 45x, <v1.1> 17x, <v3.2/1000> 3x,
# <v4.1*31.5> 1x - input number, decimals, and a divisor or factor that may
# itself have decimals. Michael also named the forms v.n and v.t, which did not
# occur there. Hence the wide pattern: a narrow one would silently stop resolving
# a form nobody thought of, and the cost of being wide is only a looser
# comparison. A ">" without a "<" is not a placeholder - one configured text has
# exactly that typo and arrives unchanged.
my $PLACEHOLDER = qr/<v[^<>]*>/;

# Repairs the one breakage the Miniserver produces on its own: the text of a
# status block is put into the response without escaping the quotes it contains.
# Only the value of the "output" object is affected, and that is the last value in
# the document - the match is greedy on purpose, because the content itself may
# contain "} sequences.
#
# Returns undef when the shape does not fit, so nothing is touched that this does
# not understand.
sub repair_status_json
{
	my ($raw) = @_;
	return undef if( !defined $raw );
	return undef if( $raw !~ m{^(.*"value"\s*:\s*")(.*)("\}\s*\}\}\s*)\z}s );

	my ($head, $content, $tail) = ($1, $2, $3);
	$content =~ s/\\/\\\\/g;
	$content =~ s/"/\\"/g;
	$content =~ s/\r/\\r/g;
	$content =~ s/\n/\\n/g;
	$content =~ s/\t/\\t/g;
	return $head . $content . $tail;
}

# Does the received text match one of the configured ones?
#
# Only that - the placeholders are skipped, not read out. Taking the substituted
# value out of the text was tried and deliberately dropped: which of the inputs
# would be "the" value is not knowable, a text can hold several placeholders, and
# a status text that happens to be a JSON object is a text somebody wrote on
# purpose - not a container to be picked apart.
sub status_text_matches
{
	my ($configured, $received) = @_;
	$configured = '' if( !defined $configured );
	$received   = '' if( !defined $received );
	return 1 if( $configured eq $received );
	return 0 if( $configured !~ $PLACEHOLDER );

	# The literal parts have to match, whatever the placeholders became.
	my @literal = split( /$PLACEHOLDER/, $configured, -1 );
	my $re = join( '.*?', map { quotemeta } @literal );
	return ( $received =~ /\A$re\z/s ) ? 1 : 0;
}

my %statetexts;
my %statetexts_mtime;

sub state_texts
{
	my ($msnr) = @_;
	return undef if( !defined $msnr );

	my $dir = eval { $Globals::stats4lox->{loxplanjsondir} };
	return undef if( !$dir );

	my $file  = "$dir/ms${msnr}_statetexts.json";
	my $mtime = (stat($file))[9] || 0;

	if( !exists $statetexts{$msnr} or ($statetexts_mtime{$msnr} // -1) != $mtime ) {
		$statetexts{$msnr} = {};
		$statetexts_mtime{$msnr} = $mtime;
		if( $mtime ) {
			eval {
				open( my $fh, '<', $file ) or die "$!\n";
				local $/;
				my $content = <$fh>;
				close($fh);
				$statetexts{$msnr} = JSON::decode_json( $content );
			};
			# A broken sidecar must never take the grabber down - it only means
			# the state stays unidentified and the text is all there is.
			$statetexts{$msnr} = {} if( $@ or ref($statetexts{$msnr}) ne 'HASH' );
		}
	}
	return $statetexts{$msnr};
}

sub status_block_outputs
{
	my ($msnr, $block, $respjson, $resp_code) = @_;

	my $out  = $respjson->{LL}->{output};
	my $text = $out->{value};
	$text = '' if( !defined $text );

	my @response;
	my ($tval, $tunit) = parse_loxone_value( $text );
	push @response, {
		Value => $tval,
		Name  => "Text",
		Key   => "Text",
		Unit  => $tunit,
		Code  => $resp_code,
	};

	my $table = state_texts( $msnr );
	my $states = ( ref($table) eq 'HASH' ) ? $table->{ lc($block // '') } : undef;
	return \@response if( ref($states) ne 'ARRAY' or !@$states );

	my $icon  = defined $out->{icon}  ? $out->{icon}  : '';
	my $color = defined $out->{color} ? $out->{color} : '';

	my (@hit, @exact);
	for( my $i = 0; $i < @$states; $i++ ) {
		my $s = $states->[$i];
		my $ci = defined $s->{Icon} ? $s->{Icon} : '';
		my $cc = defined $s->{IcC}  ? $s->{IcC}  : '';
		next if( $ci ne '' and $icon ne '' and lc($ci) ne lc($icon) );
		next if( $cc ne '' and $color ne '' and $cc ne $color );
		next if( !status_text_matches( $s->{Text}, $text ) );
		push @hit, $i;
		push @exact, $i if( ( defined $s->{Text} ? $s->{Text} : '' ) eq $text );
	}

	# One candidate, or one that matches literally - in the second case the
	# placeholders turned into wildcards created the ambiguity, and the literal
	# match is the better answer. Anything else is genuinely ambiguous: several
	# states carry the same text, and no rule can tell them apart. A third rule
	# based on how specific the patterns are was tried and resolved nothing on the
	# test installation, so it is not here.
	my $winner;
	if(    scalar @hit   == 1 ) { $winner = $hit[0] }
	elsif( scalar @exact == 1 ) { $winner = $exact[0] }
	return \@response if( !defined $winner );

	push @response, {
		Value => $winner,
		Name  => "State",
		Key   => "State",
		Code  => $resp_code,
	};

	# TextV can itself be a placeholder - the value output then passes an input
	# value through and there is no constant to store. Measured: 4 of 44.
	my $textv = $states->[$winner]->{TextV};
	if( defined $textv and $textv ne '' and $textv !~ $PLACEHOLDER ) {
		my ($vval, $vunit) = parse_loxone_value( $textv );
		push @response, {
			Value => $vval,
			Name  => "Val",
			Key   => "Val",
			Unit  => $vunit,
			Code  => $resp_code,
		};
	}

	return \@response;
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
#
# The number is only taken from the START of the string, and that is deliberate.
# What arrives here for a StateV ("Virtueller Status") is not a measurement but
# its display template rendered by the Miniserver, and the template is free text
# with a <v> placeholder somewhere in it. Measured over the 43 such blocks of a
# live installation:
#
#   "31.3°C", "102074 Lux", "0.25 ppm"   35 blocks, template starts with <v>
#                                        -> number plus unit, which is wanted
#   "0", "1"                              6 blocks set to digital mode; the
#                                        Miniserver then ignores the template
#                                        entirely -> plain number, also wanted
#   "in 11 Tagen"                         2 blocks, template "in <v> Tagen"
#                                        -> stored as text, which is wanted too
#
# Taking the first number found ANYWHERE would break that last group in the wrong
# direction and, worse, would read the 2 out of a template like "Zone 2: <v> °C"
# as the measurement. If a number is ever wanted out of such a string, the
# template from the LoxPLAN is what locates it - not a guess.
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
# The Miniserver's own vital signs
# Param 1: Miniserver number
# Param 2: arrayref of entries from @Globals::MINISERVER_METRICS
# Returns: ( \%values, \%errors, \%raw )
#####################################################
# One HTTP request per URL, not per metric: /jdev/sys/heap carries the free and
# the total memory, /jdev/sys/temperature carries two temperatures. Asking twice
# for the same answer would double the requests for nothing.
#
# Not through msget_value(), for two reasons. It hands back the parsed default
# value only, which throws away the second half of exactly those answers - and it
# insists on JSON, while /jdev/sys/temperature replies in plain text:
#
#   Cpu Temperature: 53 C. STM32 Cpu Temperature: 34 C
#
# %errors is keyed by URL, so a Miniserver that does not know an endpoint is
# reported once and not once per metric behind it.
sub miniserver_metric_values
{
	my ($msno, $metrics) = @_;
	my (%values, %errors, %raw);

	my @urls;
	my %seen;
	foreach my $m ( @$metrics ) {
		push @urls, $m->{url} if( !$seen{ $m->{url} }++ );
	}

	foreach my $url ( @urls ) {
		my ($body, $status) = LoxBerry::IO::mshttp_call2( $msno, $url );
		my $code = ( ref($status) eq 'HASH' and defined $status->{code} ) ? $status->{code} : '0';
		if( $code ne "200" or !defined $body ) {
			$errors{$url} = $code;
			next;
		}

		# A JSON answer carries the payload in LL.value; the plain text ones are
		# used as they are.
		my $text = $body;
		my $j = eval { JSON::decode_json( "$body" ) };
		if( $j and ref($j->{LL}) eq 'HASH' ) {
			my $llcode = $j->{LL}->{Code};
			if( defined $llcode and $llcode ne "200" ) {
				$errors{$url} = $llcode;
				next;
			}
			$text = defined $j->{LL}->{value} ? $j->{LL}->{value} : '';
		}
		$raw{$url} = $text;
	}

	foreach my $m ( @$metrics ) {
		next if( !exists $raw{ $m->{url} } );
		my $v = miniserver_pick( $m->{pick}, $raw{ $m->{url} } );
		$values{ $m->{key} } = $v if( defined $v );
	}

	return ( \%values, \%errors, \%raw );
}

#####################################################
# One number out of one Miniserver answer
# Param 1: rule from the catalogue in Globals.pm
# Param 2: the answer (LL.value, or the plain text body)
#####################################################
# Every rule returns a number or undef. undef means "the Miniserver answered but
# not with this value" - the field is then left out instead of being written as 0,
# which would be a measurement nobody made.
sub miniserver_pick
{
	my ($rule, $text) = @_;
	return undef if( !defined $text );
	$rule = 'number' if( !defined $rule or $rule eq '' );

	# "17%", "79", "5"
	if( $rule eq 'number' ) {
		return ( $text =~ /^\s*([-+]?[0-9]*[.,]?[0-9]+)/ ) ? _num($1) : undef;
	}
	# "422388/1016404kB"
	if( $rule eq 'heapfree' ) {
		return ( $text =~ m{^\s*(\d+)\s*/} ) ? _num($1) : undef;
	}
	if( $rule eq 'heaptotal' ) {
		return ( $text =~ m{/\s*(\d+)} ) ? _num($1) : undef;
	}
	# "Cpu Temperature: 53 C. STM32 Cpu Temperature: 34 C"
	#
	# The STM32 one has to be excluded explicitly: its label ENDS in "Cpu
	# Temperature:" too, so a pattern for the first would match it just as well
	# and the two metrics would report the same number on any answer that lists
	# the STM32 first.
	if( $rule eq 'tempcpu' ) {
		return ( $text =~ /(?:^|[.;]\s*)Cpu\s+Temperature:\s*([-+]?[\d.]+)/i ) ? _num($1) : undef;
	}
	if( $rule eq 'tempstm32' ) {
		return ( $text =~ /STM32[^:]*:\s*([-+]?[\d.]+)/i ) ? _num($1) : undef;
	}
	# "Running 100/sec"
	if( $rule eq 'spsfreq' ) {
		return ( $text =~ m{(\d+)\s*/\s*sec}i ) ? _num($1) : undef;
	}
	return undef;
}

sub _num
{
	my ($n) = @_;
	$n =~ s/,/./;
	return $n + 0;
}

#####################################################
# What a LoxBerry reports about itself, from Linfo
# Param 1: URL of the Linfo JSON output
# Param 2: arrayref of entries from @Globals::LOXBERRY_METRICS
# Returns: ( \%values, $error, $hostname )
#####################################################
# One request per host. Linfo answers with the whole system in one document -
# 9 to 15 kB depending on the machine - so everything selected comes out of that
# one answer.
#
# No authentication: /system/tools/linfo/index.php is open on every LoxBerry.
# That is why a remote LoxBerry needs nothing but its address here.
sub linfo_metric_values
{
	my ($url, $metrics) = @_;
	require LWP::UserAgent;

	my $ua = LWP::UserAgent->new( timeout => 15 );
	$ua->agent( "Stats4Lox" );
	my $resp = $ua->get( $url );

	if( !$resp->is_success ) {
		# LWP reports a failure of its own - no route, name not resolved, timeout -
		# as HTTP 500 with the reason in the message. Saying "HTTP 500" there reads
		# as if the other machine had answered, which is the one thing it did not
		# do. Its own failures carry this header, so they can be told apart.
		my $internal = ( $resp->header('Client-Warning') // '' ) eq 'Internal response';
		return ( {}, ( $internal ? $resp->message
		                         : "HTTP " . $resp->code . " " . $resp->message ), undef );
	}

	my $doc = eval { JSON::decode_json( $resp->decoded_content ) };
	if( !$doc or ref($doc) ne 'HASH' ) {
		# A LoxBerry that has no Linfo answers with an HTML error page, and an
		# address that is something else entirely answers with whatever it likes.
		# Both end up here, and both mean the same to the user: no data.
		return ( {}, "No Linfo data (the answer was not JSON)", undef );
	}

	my %values;
	foreach my $m ( @$metrics ) {
		my $v = linfo_pick( $m, $doc );
		$values{ $m->{key} } = $v if( defined $v );
	}

	return ( \%values, undef, $doc->{HostName} );
}

#####################################################
# One number out of one Linfo document
# Param 1: entry from the catalogue
# Param 2: the decoded document
#####################################################
# Returns a number or undef. undef means "this machine does not report it" - the
# field is then left out instead of being written as 0, which would be a
# measurement nobody made. That is not an edge case here: Temps is empty on an
# x86 machine, and /opt/loxberry/log/ramlog only exists on a Pi.
sub linfo_pick
{
	my ($m, $doc) = @_;
	my $rule = $m->{pick} // 'path';

	if( $rule eq 'path' ) {
		return _linfo_num( _linfo_at( $doc, $m->{path} ) );
	}

	# Seconds since the boot, from the timestamp Linfo reports
	if( $rule eq 'uptime' ) {
		my $booted = _linfo_num( _linfo_at( $doc, ['UpTime','bootedTimestamp'] ) );
		return undef if( !defined $booted or $booted <= 0 );
		my $up = time() - $booted;
		return $up >= 0 ? $up : undef;
	}

	# Percentage in use, from a total and what is free. Linfo reports both, and
	# never the used part - and a total of zero (no swap) is not 100% used, it is
	# nothing to report.
	if( $rule eq 'usedpct' ) {
		my $total = _linfo_num( _linfo_at( $doc, $m->{of} ) );
		my $free  = _linfo_num( _linfo_at( $doc, $m->{free} ) );
		return undef if( !defined $total or !defined $free or $total <= 0 );
		return sprintf( "%.1f", ( $total - $free ) / $total * 100 ) + 0;
	}

	# One named mount out of the list. Mounted twice - autofs and cifs both
	# appear for a network share - the first one wins; they report the same
	# numbers.
	if( $rule eq 'mount' ) {
		return undef if( ref($doc->{Mounts}) ne 'ARRAY' );
		foreach my $mp ( @{ $doc->{Mounts} } ) {
			next if( ref($mp) ne 'HASH' or ( $mp->{mount} // '' ) ne $m->{mount} );
			return _linfo_num( $mp->{ $m->{field} } );
		}
		return undef;
	}

	# The processor temperature. Linfo returns a list of sensors whose names
	# differ per board ("cpu-thermal (thermal_zone0)" on a Pi), so the CPU one is
	# looked for by name and the first sensor is the fallback. Fahrenheit is
	# converted - the label says degrees Celsius.
	if( $rule eq 'temp' ) {
		return undef if( ref($doc->{Temps}) ne 'ARRAY' or !scalar @{ $doc->{Temps} } );
		my ($sensor) = grep { ref($_) eq 'HASH' and ( $_->{name} // '' ) =~ /cpu|thermal|soc/i } @{ $doc->{Temps} };
		$sensor = $doc->{Temps}->[0] if( !$sensor );
		my $t = _linfo_num( $sensor->{temp} );
		return undef if( !defined $t );
		$t = ( $t - 32 ) / 1.8 if( ( $sensor->{unit} // 'C' ) =~ /^F/i );
		return sprintf( "%.1f", $t ) + 0;
	}

	# Summed over every interface but the loopback. Linfo spells it "recieved".
	if( $rule eq 'net' ) {
		return undef if( ref($doc->{'Network Devices'}) ne 'HASH' );
		my $sum;
		foreach my $if ( keys %{ $doc->{'Network Devices'} } ) {
			my $d = $doc->{'Network Devices'}->{$if};
			next if( ref($d) ne 'HASH' );
			next if( $if eq 'lo' or ( $d->{type} // '' ) =~ /loopback/i );
			my $v = _linfo_num( ( $d->{ $m->{dir} } || {} )->{ $m->{field} } );
			next if( !defined $v );
			$sum = ( $sum // 0 ) + $v;
		}
		return $sum;
	}

	return undef;
}

# Walk a list of keys into the document
sub _linfo_at
{
	my ($doc, $path) = @_;
	return undef if( ref($path) ne 'ARRAY' );
	my $at = $doc;
	foreach my $k ( @$path ) {
		return undef if( ref($at) ne 'HASH' or !exists $at->{$k} );
		$at = $at->{$k};
	}
	return $at;
}

# Linfo mixes numbers and numeric strings ("0.61", 17.5, false). Anything that is
# not a number becomes undef, so a "false" never lands in the database as 0.
sub _linfo_num
{
	my ($v) = @_;
	return undef if( !defined $v or ref($v) );
	return undef if( $v !~ /^\s*[-+]?[0-9]*[.,]?[0-9]+\s*$/ );
	$v =~ s/,/./;
	return $v + 0;
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
		# A field key must have comma, equals sign and space escaped. Only the
		# comma used to be, and an output whose name holds a space - Loxone has
		# them, "Stereo LR" of the MusicPlayer - then ended the field set right
		# there and made the line invalid.
		my $fkey = $key;
		$fkey =~ s/([,= ])/\\$1/g;

		#Try to figure out if field must be handled as string - maybe to complicated here - better suggestions are welcome ;-)
		my $stringtest = $fields{$key};
		$stringtest =~ s/(.*)i$/$1/g; # i as last position is integer
		if ( $fields{$key} eq '' or $stringtest =~ m/[a-zA-Z]/ ) { # still String?
			# Inside a quoted string value only the quote and the backslash have to
			# be escaped - and they HAVE to be. A status text can contain quotes of
			# its own, and an unescaped one ends the value early and makes InfluxDB
			# reject the whole batch. The comma must NOT be escaped in here; doing
			# that put a stray backslash into the stored text.
			my $v = $fields{$key};
			$v =~ s/\\/\\\\/g;
			$v =~ s/"/\\"/g;
			$data = "$fkey=\"$v\"";
		} else {
			$data = "$fkey=$fields{$key}";
		}
		$line .= "," if $i > 0;
		$line .= "$data";
		$i++;
	}

	# Every field was skipped - the line would end after the tags and be invalid
	# line protocol, and InfluxDB rejects the WHOLE batch for one bad line. So one
	# block without a usable value would cost the data of every other block in the
	# same cycle. Reachable since status blocks became selectable: a state whose
	# text is empty and cannot be identified has nothing to write (issue #20).
	if( $i == 0 ) {
		print STDERR "No usable field for measurement '$measurement' - nothing to write\n" if $DEBUG;
		return (undef);
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
		push (@queue, $line) if( defined $line );
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
