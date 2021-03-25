
use strict;
use warnings;
use JSON;
use LoxBerry::IO;
use base 'Exporter';
our @EXPORT = qw (
	msget_value
);

package LoxBerry::Stats4Lox;

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
	my %response;
	
	my %ms = LoxBerry::System::get_miniservers();
	if (! $ms{$msnr}) {
		print STDERR "Miniserver $msnr not found or configuration not finished\n";
		return (601, undef);
	}
	
	print STDERR "Querying param: $block with /all\n" if ($DEBUG);
	my (undef, undef, $rawdata) = LoxBerry::IO::mshttp_call($msnr, "/jdev/sps/io/" . URI::Escape::uri_escape($block) . '/all'); 

	if ( ! $rawdata ) {
		print STDERR "No data from subroutine LoxBerry::IO::mshttp_call.\n";
		return (600, undef);
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
			(undef, undef, $rawdata) = LoxBerry::IO::mshttp_call($msnr, "/jdev/sps/io/" . URI::Escape::uri_escape($block)); 
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
        $value =~ s/^([-\d\.]+).*/$1/g; # cut of unit
	$response{Default} = $value;
	# Additional outputs
	my $i = 0;
	while ($respjson->{LL}->{"output$i"}) {
		my $valname = $respjson->{LL}->{"output$i"}->{name};
		my $val = $respjson->{LL}->{"output$i"}->{value};
		$response{$valname} = $val;
		$i++;
	}
	# Additional SpecialStates from IRR
	$i = 0;
	while ($respjson->{LL}->{"SpecialState$i"}) {
		my $valname = $respjson->{LL}->{"SpecialState$i"}->{uuid};
		my $val = $respjson->{LL}->{"SpecialState$i"}->{value};
		$response{$valname} = $val;
		$i++;
	}

	print STDERR "Response of subroutine:\n" . Data::Dumper::Dumper(%response) . "\n" if ($DEBUG);
	return ($resp_code, %response);
}

#####################################################
# mshttp_get
# https://www.loxwiki.eu/x/UwE_Ag
#####################################################
sub mshttp_get
{
	my $msnr = shift;
	
	my @params = @_;
	my %response;
	
	require URI::Escape;
	
	for (my $pidx = 0; $pidx < @params; $pidx++) {
		print STDERR "Querying param: $params[$pidx]\n" if ($DEBUG);
		my ($respvalue, $respcode, $rawdata) = mshttp_call($msnr, "/dev/sps/io/" . URI::Escape::uri_escape($params[$pidx]) . '/all'); 
		if($respcode == 200) {
			# We got a valid response
			# Workaround for analogue outputs always return 0
			my $respvalue_filtered = $respvalue =~ /(\d+(?:\.\d+)?)/;
			$respvalue_filtered = $1;
			# print STDERR "respvalue         : $respvalue\n"; 
			# print STDERR "respvalue_filtered: $respvalue_filtered\n"; 
			no warnings "numeric";
			if($respvalue_filtered ne "" and $respvalue_filtered == 0) {
				# Search for outputs - if present, value is ok
				if( index( $rawdata, '<output name="' ) == -1 ) {
					# Not found - we require to request the value without /all
					($respvalue, $respcode, $rawdata) = mshttp_call($msnr, "/dev/sps/io/" . URI::Escape::uri_escape($params[$pidx]) ); 
				} 
			}
			$response{$params[$pidx]} = $respvalue;
		} else {
			$response{$params[$pidx]} = undef;
		}
	}
	return %response if (@params > 1);
	return $response{$params[0]} if (@params == 1);
}
#####################################################
# Finally 1; ########################################
#####################################################
1;
