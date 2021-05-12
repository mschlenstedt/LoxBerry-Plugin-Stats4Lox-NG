#!/usr/bin/perl
use warnings;
use strict;
use DateTime;
our $LocalTZ = DateTime::TimeZone->new( name => 'local' );

if( !$ARGV[1] ) {
	print "Checks a timestamp of a Loxone Statistic against the Import routine that does epoch and\ntimezone/daylight saving conversion.\n";
	
	print "Calling Syntax:\n";
	print "  $0 <date> <time> (without quotes)\n";
	print "e.g.\n";
	print "  $0 2021-03-08 10:56:14\n";
	exit(1);
}

my $timestr1 = "$ARGV[0] $ARGV[1]";

my $time1 = createDateTime( $timestr1 );


print $time1->hires_epoch()."\n";
print $time1->hms."\n";


sub createDateTime
{
	my ($timestr) = @_;
	
	if( $timestr =~ /(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2}):(\d{2})/ ) {
		my $ye = $1;
		my $mo = $2;
		my $da = $3;
		my $ho = $4;
		my $mi = $5;
		my $se = $6;
		
		my $dt = DateTime->new(
			year       => $ye,
			month      => $mo,
			day        => $da,
			hour       => $ho,
			minute     => $mi,
			second     => $se,
			time_zone  => $LocalTZ
		);

		print STDERR "Is Daylight saving: " . $dt->is_dst . "\n";
	
		return $dt;
	}
	
}