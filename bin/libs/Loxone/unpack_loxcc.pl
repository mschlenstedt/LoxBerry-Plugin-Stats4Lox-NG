#!/usr/bin/perl
#
# Unpacks a Loxone LoxCC container (sps0.LoxCC, *.LxRes, ...).
#
# Perl port of unpack_loxcc.py, so that the build step for the element
# definitions can run directly on the machine where Loxone Config is
# installed - no Python needed there.
#
# Original algorithm: Sarnau, https://github.com/sarnau/Inside-The-Loxone-Miniserver
#
# Usage: unpack_loxcc.pl <sourcefile> <destinationfile>

use strict;
use warnings;

my ($sourcefile, $destfile) = @ARGV;
if( !defined $sourcefile or !defined $destfile ) {
	print "First argument is source file\n";
	print "Second argument is destination file\n";
	exit 1;
}

open( my $in, '<:raw', $sourcefile ) or die "Could not open $sourcefile: $!\n";
local $/;
my $raw = <$in>;
close $in;

if( length($raw) < 16 ) {
	print "Could not open file\n";
	exit 1;
}

my ($header, $compressedSize, $uncompressedSize, $checksum) = unpack( 'V4', substr($raw, 0, 16) );

if( $header != 0xaabbccee ) {   # magic word of a compressed container
	print "Could not open file\n";
	exit 1;
}

my $data = substr( $raw, 16, $compressedSize );
my $len  = length($data);
my $index = 0;
my $result = '';

while( $index < $len ) {

	my $byte = ord( substr($data, $index, 1) );
	$index++;

	# Upper nibble: number of literal bytes to copy. A value of 15 means more
	# bytes follow, each adding to the count until one is not 0xff.
	my $copyBytes = $byte >> 4;
	$byte &= 0xf;
	if( $copyBytes == 15 ) {
		while( 1 ) {
			my $addByte = ord( substr($data, $index, 1) );
			$copyBytes += $addByte;
			$index++;
			last if( $addByte != 0xff );
		}
	}
	if( $copyBytes > 0 ) {
		$result .= substr( $data, $index, $copyBytes );
		$index += $copyBytes;
	}
	last if( $index >= $len );

	# Back reference into the data already produced
	my $bytesBack = unpack( 'v', substr($data, $index, 2) );
	$index += 2;

	# At least 4 bytes plus the lower nibble of the header byte
	my $bytesBackCopied = 4 + $byte;
	if( $byte == 15 ) {
		while( 1 ) {
			my $val = ord( substr($data, $index, 1) );
			$bytesBackCopied += $val;
			$index++;
			last if( $val != 0xff );
		}
	}

	# The referenced range may overlap what we are about to append, so this has
	# to be copied byte by byte - exactly like the Python original.
	while( $bytesBackCopied > 0 ) {
		if( -$bytesBack + 1 == 0 ) {
			$result .= substr( $result, -$bytesBack );
		}
		else {
			$result .= substr( $result, -$bytesBack, 1 );
		}
		$bytesBackCopied--;
	}
}

# The container carries a CRC32 and the expected size - check both, otherwise
# a silently truncated result would look like a successful unpack.
require Compress::Zlib;
my $crc = Compress::Zlib::crc32( $result );
if( $crc != $checksum ) {
	printf( "Checksum is wrong (got %u, expected %u)\n", $crc, $checksum );
	exit 1;
}
if( length($result) != $uncompressedSize ) {
	printf( "Uncompressed filesize is wrong %d != %d\n", length($result), $uncompressedSize );
	exit 1;
}

open( my $out, '>:raw', $destfile ) or die "Could not write $destfile: $!\n";
print $out $result;
close $out;

exit 0;
