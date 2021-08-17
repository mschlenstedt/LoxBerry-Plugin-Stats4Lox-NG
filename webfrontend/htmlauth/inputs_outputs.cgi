#!/usr/bin/perl
use warnings;
use strict;
use LoxBerry::System;
use LoxBerry::Web;
use LoxBerry::Storage;
use LoxBerry::JSON;
use FindBin qw($Bin);
use lib "$Bin/../../../../bin/plugins/stats4lox/libs/";
use Globals;

LoxBerry::Web::lbheader("Stats4Lox", undef, undef);

my $template = HTML::Template->new(
    filename => "$lbptemplatedir/inputs_outputs.html",
    global_vars => 1,
    loop_context_vars => 1,
    die_on_bad_params => 0,
);

# Language
my %L;
%L = LoxBerry::System::readlanguage($template, "language.ini");

# Load config- needed until we can read preconfigured path with LoxBerry::Storage::get_storage_html via Javascript
my $cfgfile = $lbpconfigdir . "/stats4lox.json";
my $jsonobj = LoxBerry::JSON->new();
my $cfg = $jsonobj->open(filename => $cfgfile);

# Form preparation
$template->param( 'INFLUX_STORAGE_PATH',  LoxBerry::Storage::get_storage_html( formid => 'influxstoragepath', custom_folder => 1, readwriteonly => 1, show_browse => 1, data_mini => 1, type_all => 1, currentpath => $cfg->{'influx'}->{'db_storage'} ) );

print $template->output();

LoxBerry::Web::lbfooter();

exit;

