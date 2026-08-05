#!/usr/bin/perl
use warnings;
use strict;
use LoxBerry::System;
use LoxBerry::Web;
use LoxBerry::JSON;
use FindBin qw($Bin);
use lib "$Bin/../../../../bin/plugins/stats4lox/libs/";
use Globals;

init_navbar_i18n();
LoxBerry::Web::lbheader("Stats4Lox", undef, undef);

my $template = HTML::Template->new(
    filename => "$lbptemplatedir/influx.html",
    global_vars => 1,
    loop_context_vars => 1,
    die_on_bad_params => 0,
);

my %L = LoxBerry::System::readlanguage($template, "language.ini");

# The page is filled by JavaScript - the queries take too long to build it here.
# Only the database name is known without asking InfluxDB anything.
my $db = $Globals::influx->{influxdatabase} // 'stats4lox';
$template->param( 'INFLUXDB_NAME', $db );

( my $desc = $L{'INFLUXPAGE.DESCRIPTION'} // '' ) =~ s/__DB__/$db/g;
$template->param( 'INFLUXDB_DESCRIPTION', $desc );

print $template->output();

LoxBerry::Web::lbfooter();

exit;
