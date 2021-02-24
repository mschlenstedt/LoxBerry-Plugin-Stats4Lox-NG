#!/usr/bin/perl

use LoxBerry::System;
use strict;
use warnings;
  
my %miniservers;
%miniservers = LoxBerry::System::get_miniservers();
  
if (! %miniservers) {
	print "No Miniservers found.\n";
	exit(1);
}
 
foreach my $ms (sort keys %miniservers) {
	print "$ms: Parsing Miniserver $miniservers{$ms}{Name} / $miniservers{$ms}{IPAddress}.\n";
	system "awk -v s=\"USER_MS$ms=\\\"$miniservers{$ms}{Admin_RAW}\\\"\" '/^USER_MS$ms=/{\$0=s;f=1} {a[++n]=\$0} END{if(!f)a[++n]=s;for(i=1;i<=n;i++)print a[i]>ARGV[1]}' $lbpconfigdir/telegraf/telegraf.env";
	system "awk -v s=\"PASS_MS$ms=\\\"$miniservers{$ms}{Pass_RAW}\\\"\" '/^PASS_MS$ms=/{\$0=s;f=1} {a[++n]=\$0} END{if(!f)a[++n]=s;for(i=1;i<=n;i++)print a[i]>ARGV[1]}' $lbpconfigdir/telegraf/telegraf.env";
}
