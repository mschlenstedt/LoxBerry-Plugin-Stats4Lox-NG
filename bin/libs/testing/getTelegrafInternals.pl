#!/usr/bin/perl

use LoxBerry::System;
use Data::Dumper;

require "$lbpbindir/libs/Stats4Lox.pm";

# Debug
$Stats4Lox::DEBUG = 0;
$Stats4Lox::DUMP = 0;

my ($resp) = Stats4Lox::telegrafinternals();

print Dumper (\$resp);
