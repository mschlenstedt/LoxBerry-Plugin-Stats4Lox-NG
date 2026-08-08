#!/usr/bin/perl
use warnings;
use strict;
use LoxBerry::System;
use LoxBerry::Web;
use LoxBerry::Storage;
use LoxBerry::JSON;
use FindBin qw($Bin);
use lib "$Bin/../../../../bin/plugins/REPLACELBPPLUGINDIR/libs/";
use Globals;

our $htmlhead="";
$htmlhead .= js_tag( $Bin, 'system_sub_navbar.js' );

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
# For the link into the Backup logfile at the end of a run. Addressed by package
# and name rather than by path, so it keeps working although every run writes a
# new file.
$template->param( 'PLUGINDIR', $lbpplugindir );

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

# Number of archives. Wording and order follow the LoxBerry backup widget
# ("Behalte ein Backup" / "Behalte 3 Backups"), extended by "keep all".
my $keep = defined $b->{keep} ? $b->{keep} : 3;
my $keephtml = opt( 1, $L{'BACKUP.KEEP_ONE'}, $keep );
$keephtml .= opt( $_, "$L{'BACKUP.KEEP_MORE_1'} $_ $L{'BACKUP.KEEP_MORE_2'}", $keep )
	foreach ( 2 .. 10 );
$keephtml .= opt( 0, $L{'BACKUP.KEEP_ALL'}, $keep );
$template->param( 'KEEP_OPTIONS', $keephtml );

# Same order as the widget: none, 7z, zip, gzip, xz
my $comp = $b->{compression} || 'gzip';
my $comphtml = '';
$comphtml .= opt( 'none', $L{'BACKUP.COMPRESSION_NONE'}, $comp );
$comphtml .= opt( '7z',   $L{'BACKUP.COMPRESSION_7Z'},   $comp );
$comphtml .= opt( 'zip',  $L{'BACKUP.COMPRESSION_ZIP'},  $comp );
$comphtml .= opt( 'gzip', $L{'BACKUP.COMPRESSION_GZIP'}, $comp );
$comphtml .= opt( 'xz',   $L{'BACKUP.COMPRESSION_XZ'},   $comp );
$template->param( 'COMPRESSION_OPTIONS', $comphtml );

my $repeat = $s->{repeat} || 1;
my $rephtml = opt( 1, $L{'BACKUP.REPEAT_WEEK'}, $repeat );
foreach my $n ( 2 .. 8 ) {
	( my $lbl = $L{'BACKUP.REPEAT_WEEKS'} ) =~ s/__N__/$n/;
	$rephtml .= opt( $n, $lbl, $repeat );
}
$template->param( 'REPEAT_OPTIONS', $rephtml );

# Hour and minute as two lists. Minutes in five minute steps - a backup runs
# for minutes anyway, so the exact minute is not worth twelve times the options.
my ( $th, $tm ) = ( $s->{time} || '03:00' ) =~ /^(\d{1,2}):(\d{2})$/;
$th = 3  if( !defined $th or $th > 23 );
$tm = 0  if( !defined $tm or $tm > 59 );
$tm = int( $tm / 5 ) * 5;

my $hourhtml = '';
$hourhtml .= opt( sprintf("%02d",$_), sprintf("%02d",$_), sprintf("%02d",$th) ) foreach ( 0 .. 23 );
$template->param( 'HOUR_OPTIONS', $hourhtml );

my $minhtml = '';
$minhtml .= opt( sprintf("%02d",$_), sprintf("%02d",$_), sprintf("%02d",$tm) ) foreach ( grep { $_ % 5 == 0 } 0 .. 59 );
$template->param( 'MINUTE_OPTIONS', $minhtml );
$template->param( 'SCHEDULEACTIVE',
	LoxBerry::System::is_enabled( $s->{active} ) ? 'checked="checked"' : '' );

foreach my $d ( qw( mon tue wed thu fre sat sun ) ) {
	$template->param( 'CHECKED_' . uc($d),
		LoxBerry::System::is_enabled( $s->{$d} ) ? 'checked="checked"' : '' );
}

# Link into the file manager widget. Its "p" parameter is a path below the
# volume root, and the volume root is "/" (php/connector.minimal.php), so an
# absolute path can be handed over unchanged. Only offered once a storage
# location is configured - without one the link would just open "/".
if( $b->{storagepath} ) {
	require URI::Escape;
	$template->param( 'FILEMANAGER_URL',
		'/admin/system/tools/filemanager/index.cgi?p='
		. URI::Escape::uri_escape( $b->{storagepath}, "^A-Za-z0-9\-\._~/" ) );
	$template->param( 'STORAGEPATH_SET', 1 );
}

print $template->output();

LoxBerry::Web::lbfooter();

exit;
