#!/usr/bin/perl
use warnings;
use strict;
use LoxBerry::System;
use LoxBerry::Web;
use LoxBerry::Storage;
use JSON;
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

# Form preparation
$template->param( 'INFLUX_STORAGE_PATH',  LoxBerry::Storage::get_storage_html( formid => 'influxstoragepath', custom_folder => 1, readwriteonly => 1, show_browse => 1, data_mini => 1, type_all => 1 ) );

print $template->output();

LoxBerry::Web::lbfooter();

exit;

