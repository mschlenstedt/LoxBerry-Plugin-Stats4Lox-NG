#!/usr/bin/perl
use DateTime;
our $LocalTZ = DateTime::TimeZone->new( name => 'local' );


$timestr1="2000-03-01 10:00:00"; 
$timestr2="2000-05-01 10:00:00"; 

my $time1 = createDateTime( $timestr1 );
my $time2 = createDateTime( $timestr2 );


print $time1->hires_epoch()."\n";
print $time2->hires_epoch()."\n";
print $time1->hms."\n";
print $time2->hms."\n";


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