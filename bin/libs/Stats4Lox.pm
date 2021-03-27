
use strict;
use warnings;
use JSON;
use LoxBerry::IO;

use base 'Exporter';
our @EXPORT = qw (
	msget_value
	influx_lineprot
);

package Stats4Lox;

our $DEBUG = 0;
if ($DEBUG) {
	use Data::Dumper;
}

#####################################################
# Miniserver REST Call to get all values of block
# Param 1: Miniserver number
# Param 2: Block's name, decription or UUID
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
		print STDERR "Miniserver $msnr not found or configuration not finished\n";
		return (601, undef);
	}
	
	print STDERR "Querying param: $block with /all\n" if ($DEBUG);
	#my (undef, undef, $rawdata) = LoxBerry::IO::mshttp_call($msnr, "/jdev/sps/io/" . URI::Escape::uri_escape($block) . '/all'); 
	my ($rawdata, $status) = LoxBerry::IO::mshttp_call2($msnr, "/jdev/sps/io/" . URI::Escape::uri_escape($block) . '/all'); 

	if ( $status->{code} ne "200" ) {
		print STDERR "Error while getting data from Miniserver: $status->{message}. Status: $status->{status}\n";
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
		if( $rawdata !~ m/\"output0\":/ ) {
			# Not found - we require to request the value without /all
			print STDERR "Re-Querying param: $block withOUT /all due to f*cked up analoge output\n" if ($DEBUG);
			#(undef, undef, $rawdata) = LoxBerry::IO::mshttp_call($msnr, "/jdev/sps/io/" . URI::Escape::uri_escape($block)); 
			my ($rawdata, $status) = LoxBerry::IO::mshttp_call2($msnr, "/jdev/sps/io/" . URI::Escape::uri_escape($block)); 
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
		print STDERR "No valid JSON data received: $@\n";
		return (602, undef);
	}

	print STDERR "Received (and cleaned) json data:\n" . Data::Dumper::Dumper($respjson) . "\n" if ($DEBUG);

	my $resp_code = $respjson->{LL}->{Code};
	if ($resp_code ne "200") {
		print STDERR "Error from Miniserver. Code: $resp_code\n";
		return ($resp_code, undef);
	}
	# Default value
	my $value = $respjson->{LL}->{value};
        $value =~ s/^([-\d\.]+)\s+(.*)/$1/g; # cut of unit
	$data{Value} = $value;
	$data{Name} = "Default";
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
		$ssdata{Nr} = $respjson->{LL}->{"SpecialState$i"}->{nr};
		push (@response, \%ssdata);

		$i++;
	}

	print STDERR "Response of subroutine:\n" . Data::Dumper::Dumper(\@response) . "\n" if ($DEBUG);

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
		print STDERR "Measurement is needed.";
		return (undef);
	};

	if (keys %fields == 0) {
		print STDERR "At least one field is needed.";
		return (undef);
	};

	print STDERR "Submitted measurement: " . $measurement . "\n" if ($DEBUG);
	print STDERR "Submitted timestamp: " . $timestamp . "\n" if ($DEBUG);
	print STDERR "Submitted tags:\n" . Data::Dumper::Dumper(\%tags) . "\n" if ($DEBUG);
	print STDERR "Submitted fields:\n" . Data::Dumper::Dumper(\%fields) . "\n" if ($DEBUG);

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
		#Try to figure out if field must be handled as string - maybe to compolicated here - better suggestions are welcome ;-)
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
# Finally 1; ########################################
#####################################################
1;
