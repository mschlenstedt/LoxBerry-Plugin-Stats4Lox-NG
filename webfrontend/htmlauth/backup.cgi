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

our $htmlhead="";
$htmlhead .= '<script type="application/javascript" src="js/system_sub_navbar.js"></script>';

init_navbar_i18n();
LoxBerry::Web::lbheader("Stats4Lox", undef, undef);

my $template = HTML::Template->new(
    filename => "$lbptemplatedir/backup.html",
    global_vars => 1,
    loop_context_vars => 1,
    die_on_bad_params => 0,
);

my %L = LoxBerry::System::readlanguage($template, "language.ini");

# Globals has already merged stats4lox.json over the defaults, so $Globals::backup
# is complete even on an installation that has never saved this page.
my $b = $Globals::backup;
my $s = $b->{schedule} || {};

# Everything that jQuery Mobile turns into a widget is rendered with its value
# already in place. Setting it from JavaScript afterwards works, but the widget
# is built when the page is created - the user would watch it jump.
$template->param( 'STORAGE_PATH', LoxBerry::Storage::get_storage_html(
	formid       => 'storagepath',
	custom_folder=> 1,
	readwriteonly=> 1,
	show_browse  => 1,
	data_mini    => 1,
	type_all     => 1,
	currentpath  => $b->{storagepath},
) );

sub opt
{
	my ($value, $label, $current) = @_;
	my $sel = ( "$value" eq "$current" ) ? ' selected="selected"' : '';
	return "<option value=\"$value\"$sel>$label</option>";
}

# Number of archives: 1-10, plus "keep all"
my $keep = defined $b->{keep} ? $b->{keep} : 3;
my $keephtml = opt( 0, $L{'BACKUP.KEEP_ALL'}, $keep );
$keephtml .= opt( $_, $_, $keep ) foreach ( 1 .. 10 );
$template->param( 'KEEP_OPTIONS', $keephtml );

my $comp = $b->{compression} || 'gzip';
my $comphtml = '';
$comphtml .= opt( 'none', $L{'BACKUP.COMPRESSION_NONE'}, $comp );
$comphtml .= opt( 'gzip', $L{'BACKUP.COMPRESSION_GZIP'}, $comp );
$comphtml .= opt( 'xz',   $L{'BACKUP.COMPRESSION_XZ'},   $comp );
$comphtml .= opt( 'zip',  $L{'BACKUP.COMPRESSION_ZIP'},  $comp );
$comphtml .= opt( '7z',   $L{'BACKUP.COMPRESSION_7Z'},   $comp );
$template->param( 'COMPRESSION_OPTIONS', $comphtml );

my $repeat = $s->{repeat} || 1;
my $rephtml = opt( 1, $L{'BACKUP.REPEAT_WEEK'}, $repeat );
foreach my $n ( 2 .. 8 ) {
	( my $lbl = $L{'BACKUP.REPEAT_WEEKS'} ) =~ s/__N__/$n/;
	$rephtml .= opt( $n, $lbl, $repeat );
}
$template->param( 'REPEAT_OPTIONS', $rephtml );

$template->param( 'SCHEDULE_TIME', $s->{time} || '03:00' );
$template->param( 'SCHEDULEACTIVE',
	LoxBerry::System::is_enabled( $s->{active} ) ? 'checked="checked"' : '' );

foreach my $d ( qw( mon tue wed thu fre sat sun ) ) {
	$template->param( 'CHECKED_' . uc($d),
		LoxBerry::System::is_enabled( $s->{$d} ) ? 'checked="checked"' : '' );
}

print $template->output();

LoxBerry::Web::lbfooter();

exit;
