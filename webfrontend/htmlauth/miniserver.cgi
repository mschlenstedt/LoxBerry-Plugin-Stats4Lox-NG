#!/usr/bin/perl
use warnings;
use strict;
use LoxBerry::System;
use LoxBerry::Web;
use JSON;
use FindBin qw($Bin);
use lib "$Bin/../../../../bin/plugins/REPLACELBPPLUGINDIR/libs/";
use Globals;

our $htmlhead="";
$htmlhead .= js_tag( $Bin, 'datasources_sub_navbar.js' );

# Data sources. The Miniserver's own vital signs are a source the plugin reads
# from, the same as the MQTT Collector and MQTT Live next to it - and unlike a
# Loxone block, which is what the Loxone tab is about.
$main::navbar{20}{active} = 1;

init_navbar_i18n();
LoxBerry::Web::lbheader("Stats4Lox", undef, undef);

my $template = HTML::Template->new(
    filename => "$lbptemplatedir/miniserver.html",
    global_vars => 1,
    loop_context_vars => 1,
    die_on_bad_params => 0,
);

my %L = LoxBerry::System::readlanguage($template, "language.ini");

# Everything on this page is rendered with its value already in place. jQuery
# Mobile builds its widgets when the page is created: a flipswitch set afterwards
# is seen flipping, and a select is replaced by a button carrying the chosen
# labels - set afterwards, that button changes its text after the user has read
# it.
#
# $Globals::miniserver and not the raw file, so an installation that has never
# saved these settings shows the defaults instead of an empty form.
$template->param( 'MINISERVER_ACTIVE',
	LoxBerry::System::is_enabled( $Globals::miniserver->{active} ) ? 'checked="checked"' : '' );

my $msiv = int( $Globals::miniserver->{interval} || 300 );
my @msoffer = @Globals::GRABBER_INTERVALS;
# Whatever is configured stays selectable, even if it is not on the list. It can
# only have got there by hand, and dropping it would move the setting to some
# other value the next time this page is saved - without anybody asking.
push @msoffer, $msiv if( !grep { $_ == $msiv } @msoffer );

my $ivopts = '';
foreach my $s ( sort { $a <=> $b } @msoffer ) {
	my $lbl;
	if   ( $s == 60 )    { $lbl = $L{'MINISERVER.INTERVAL_MINUTE'} }
	elsif( $s == 3600 )  { $lbl = $L{'MINISERVER.INTERVAL_HOUR'} }
	# Braces as delimiters, so the division inside the code part does not end the
	# replacement.
	elsif( $s % 60 == 0 ){ ( $lbl = $L{'MINISERVER.INTERVAL_MINUTES'} ) =~ s{__N__}{ int( $s / 60 ) }e }
	else                 { ( $lbl = $L{'MINISERVER.INTERVAL_SECONDS'} ) =~ s{__N__}{$s} }
	$ivopts .= '<option value="' . $s . '"'
		. ( $s == $msiv ? ' selected="selected"' : '' ) . '>' . $lbl . '</option>';
}
$template->param( 'MINISERVER_INTERVALS', $ivopts );

# The selection list, grouped as the catalogue is grouped. The group headings are
# optgroups rather than separators, so the list stays readable at two dozen
# entries.
my @chosen = Globals::miniserver_metrics();
my %ischosen = map { $_->{key} => 1 } @chosen;

my $metopts = '';
my $lastgroup = '';
my @catalogue;
foreach my $m ( @Globals::MINISERVER_METRICS ) {
	my $label = $L{ 'MINISERVER.M_' . uc( $m->{key} ) } // $m->{key};

	if( $m->{group} ne $lastgroup ) {
		$metopts .= '</optgroup>' if( $lastgroup ne '' );
		$metopts .= '<optgroup label="' . ( $L{ 'MINISERVER.GROUP_' . $m->{group} } // $m->{group} ) . '">';
		$lastgroup = $m->{group};
	}
	$metopts .= '<option value="' . $m->{key} . '"'
		. ( $ischosen{ $m->{key} } ? ' selected="selected"' : '' ) . '>'
		. $label . '</option>';

	# The same catalogue for the live table, which is built in the browser.
	push @catalogue, { key => $m->{key}, url => $m->{url}, label => $label };
}
$metopts .= '</optgroup>' if( $lastgroup ne '' );
$template->param( 'MINISERVER_METRICS', $metopts );
$template->param( 'MINISERVER_CATALOGUE', JSON::to_json( \@catalogue ) );

print $template->output();

LoxBerry::Web::lbfooter();

exit;
