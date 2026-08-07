#!/usr/bin/perl
use warnings;
use strict;
use LoxBerry::System;
use LoxBerry::Web;
use JSON;
use FindBin qw($Bin);
use lib "$Bin/../../../../bin/plugins/stats4lox/libs/";
use Globals;

our $htmlhead="";
$htmlhead .= js_tag( $Bin, 'datasources_sub_navbar.js' );

# Data sources, next to the Miniserver: a LoxBerry is a machine the plugin reads
# from, and none of this belongs to a Loxone block.
$main::navbar{20}{active} = 1;

init_navbar_i18n();
LoxBerry::Web::lbheader("Stats4Lox", undef, undef);

my $template = HTML::Template->new(
    filename => "$lbptemplatedir/loxberry.html",
    global_vars => 1,
    loop_context_vars => 1,
    die_on_bad_params => 0,
);

my %L = LoxBerry::System::readlanguage($template, "language.ini");

# Everything is rendered with its value already in place - jQuery Mobile builds
# its widgets when the page is created, and one that is filled afterwards is seen
# changing.
$template->param( 'LOXBERRY_ACTIVE',
	LoxBerry::System::is_enabled( $Globals::loxberry->{active} ) ? 'checked="checked"' : '' );

my $iv = int( $Globals::loxberry->{interval} || 900 );
my @offer = @Globals::GRABBER_INTERVALS;
# Whatever is configured stays selectable even if it is not on the list - it can
# only have got there by hand, and a save should not move it somewhere else.
push @offer, $iv if( !grep { $_ == $iv } @offer );

my $ivopts = '';
foreach my $s ( sort { $a <=> $b } @offer ) {
	my $lbl;
	if   ( $s == 60 )    { $lbl = $L{'LOXBERRYSRC.INTERVAL_MINUTE'} }
	elsif( $s == 3600 )  { $lbl = $L{'LOXBERRYSRC.INTERVAL_HOUR'} }
	# Braces as delimiters, so the division inside the code part does not end the
	# replacement.
	elsif( $s % 60 == 0 ){ ( $lbl = $L{'LOXBERRYSRC.INTERVAL_MINUTES'} ) =~ s{__N__}{ int( $s / 60 ) }e }
	else                 { ( $lbl = $L{'LOXBERRYSRC.INTERVAL_SECONDS'} ) =~ s{__N__}{$s} }
	$ivopts .= '<option value="' . $s . '"'
		. ( $s == $iv ? ' selected="selected"' : '' ) . '>' . $lbl . '</option>';
}
$template->param( 'LOXBERRY_INTERVALS', $ivopts );

# The selection list, grouped as the catalogue is grouped.
my @chosen = Globals::loxberry_metrics();
my %ischosen = map { $_->{key} => 1 } @chosen;

my $metopts = '';
my $lastgroup = '';
my @catalogue;
foreach my $m ( @Globals::LOXBERRY_METRICS ) {
	my $label = $L{ 'LOXBERRYSRC.M_' . uc( $m->{key} ) } // $m->{key};

	if( $m->{group} ne $lastgroup ) {
		$metopts .= '</optgroup>' if( $lastgroup ne '' );
		$metopts .= '<optgroup label="' . ( $L{ 'LOXBERRYSRC.GROUP_' . $m->{group} } // $m->{group} ) . '">';
		$lastgroup = $m->{group};
	}
	$metopts .= '<option value="' . $m->{key} . '"'
		. ( $ischosen{ $m->{key} } ? ' selected="selected"' : '' ) . '>'
		. $label . '</option>';

	push @catalogue, { key => $m->{key}, label => $label };
}
$metopts .= '</optgroup>' if( $lastgroup ne '' );
$template->param( 'LOXBERRY_METRICS', $metopts );
$template->param( 'LOXBERRY_CATALOGUE', JSON::to_json( \@catalogue ) );

# The list of machines. The first one is this LoxBerry and is not in the
# configuration - it is shown with its own name and cannot be removed.
my @hosts = Globals::loxberry_hosts();
my @rows;
foreach my $h ( @hosts ) {
	push @rows, {
		ADDRESS => $h->{address},
		OWN     => $h->{own} ? 1 : 0,
		# What it is called - decided in Globals::loxberry_hosts(), so the page,
		# the database tag and the live table cannot disagree.
		LABEL   => $h->{tag},
	};
}
$template->param( 'LOXBERRY_HOSTS', \@rows );

print $template->output();

LoxBerry::Web::lbfooter();

exit;
