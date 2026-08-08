#!/usr/bin/perl
use warnings;
use strict;
use LoxBerry::System;
use LoxBerry::Web;
use LoxBerry::Storage;
use LoxBerry::JSON;
use CGI;
use JSON;
use FindBin qw($Bin);
use lib "$Bin/../../../../bin/plugins/REPLACELBPPLUGINDIR/libs/";
use Globals;

# SecurePIN check, answered before anything else is printed.
#
# Built the same way as the LoxBerry MQTT widget (webfrontend/htmlauth/system/
# mqtt.cgi): the page arrives with its content hidden, asks for the PIN, and
# only fetches the actual data once check_securepin() has confirmed it. The
# return values come straight from the core function - 1 wrong, 3 locked after
# too many attempts, undef correct.
#
# This page needs the protection because it shows the InfluxDB password. Note
# that hiding the form would not be enough on its own: the endpoints in ajax.cgi
# that hand out and change the password check the PIN again themselves.
my $cgi = CGI->new;
if( $cgi->param("action") and $cgi->param("action") eq "checksecpin" ) {
	my $checkres = LoxBerry::System::check_securepin( $cgi->param("secpin") );
	print $cgi->header('application/json');
	print JSON::to_json( { error => int( $checkres // 0 ) } );
	exit;
}

our $htmlhead="";
$htmlhead .= js_tag( $Bin, 'system_sub_navbar.js' );

init_navbar_i18n();
LoxBerry::Web::lbheader("Stats4Lox", undef, undef);

my $template = HTML::Template->new(
    filename => "$lbptemplatedir/system.html",
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

# The flipswitch has to come out of the page already in the right position -
# jQuery Mobile builds it from the checkbox when the page is created, so setting
# it afterwards from JavaScript would show it flipping.
$template->param( 'SERVICELOGGING',
	LoxBerry::System::is_enabled( $cfg->{'stats4lox'}->{'servicelogging'} ) ? 'checked="checked"' : '' );

# Retention (issue #44).
#
# The same reason for the flipswitch, and the stage checkboxes come with it: the
# cascade is redrawn from the state of the form, so the form has to arrive in the
# right state. Everything else on that section - the dropdowns and their pruning -
# is filled by getRetention() afterwards, where a select can be refreshed without
# anything showing.
#
# $Globals::retention and not $cfg: the defaults have to be merged in, or an
# installation that has never saved these settings gets an empty table.
$template->param( 'RETENTION_DOWNSAMPLING',
	LoxBerry::System::is_enabled( $Globals::retention->{downsampling} ) ? 'checked="checked"' : '' );

my @stagerows;
for( my $i = 1; $i < scalar @{ $Globals::retention->{stages} }; $i++ ) {
	push @stagerows, {
		STAGE_NO      => $i + 1,
		STAGE_CHECKED => LoxBerry::System::is_enabled( $Globals::retention->{stages}->[$i]->{active} )
		                 ? 'checked="checked"' : '',
	};
}
$template->param( 'RETENTION_STAGES', \@stagerows );

# Shortest polling interval of the Loxone statistics.
#
# Rendered here for the same reason as everything else on this page: jQuery
# Mobile turns the select into a button carrying the chosen label, and a value
# set from JavaScript afterwards changes that label after it has been read.
#
# An installation that has never set this gets an entry of its own at the top,
# selected. It is not the same as one minute: unset means Telegraf keeps the 45
# seconds it has always had, while choosing one minute derives 57 from the
# formula. Two different things must not look like one option.
my $curmin = int( $Globals::loxone->{min_interval} // 0 );
my $minopts = '';
if( $curmin <= 0 ) {
	$minopts .= '<option value="0" selected="selected">'
		. ( $L{'MININTERVAL.OPTION_MINUTE'} // '1' ) . '</option>';
}
foreach my $s ( @Globals::LOXONE_MIN_INTERVALS ) {
	my $lbl = ( $s == 60 )
		? $L{'MININTERVAL.OPTION_MINUTE'}
		: do { ( my $t = $L{'MININTERVAL.OPTION_MINUTES'} ) =~ s{__N__}{ int( $s / 60 ) }e; $t };
	$minopts .= '<option value="' . $s . '"'
		. ( $s == $curmin ? ' selected="selected"' : '' ) . '>' . $lbl . '</option>';
}
$template->param( 'MININTERVAL_OPTIONS', $minopts );
$template->param( 'MININTERVAL_UNSET', $curmin <= 0 ? 1 : 0 );

# For the link into the Downsampling logfile, which is addressed by package and
# name rather than by path - logfile.cgi looks the newest run up in the log
# database, so the link survives every new run.
$template->param( 'PLUGINDIR', $lbpplugindir );

print $template->output();

LoxBerry::Web::lbfooter();

exit;

