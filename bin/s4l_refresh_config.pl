#!/usr/bin/perl

# Keeps stats.json in step with the Loxone configuration (issue #33).
#
# Until now, a block renamed or moved in Loxone Config kept its old name, room
# and category here forever - stats.json was only ever written when somebody
# opened the detail view of that block and saved it. The same went for the
# Grafana panels, whose titles are built from exactly those fields.
#
# Two jobs, on two schedules, because they cost very different amounts:
#
#   --plan     daily.  Asks each Miniserver for the timestamp of its LoxPLAN and
#              fetches it only when it changed, then copies title, description,
#              room, category and type into stats.json. One HTTP request per
#              Miniserver when nothing changed.
#
#   --outputs  weekly. Refreshes outputkeys/outputlabels, which do NOT come from
#              the LoxPLAN but from the block itself - the Miniserver reports the
#              name of every output live. Those names age: on a live installation
#              a MeterAbsSt still listed "AC" where the Miniserver has reported
#              "Slvl" for a while, because the list is a snapshot of the day the
#              block was added.
#
# Why --outputs only touches ACTIVE entries:
#
#   /jdev/sps/io/<uuid>/all is not a pure read on a writable block - Loxone reads
#   the path element behind the uuid as a command, and a virtual text input takes
#   it as its new value (issue #143). The grabber queries every active entry with
#   that very call every few minutes anyway, so refreshing those adds no request
#   that would not happen regardless. Inactive entries are left alone, which is
#   the safe answer without maintaining a list of writable types.

use warnings;
use strict;
use LoxBerry::System;
use LoxBerry::Log;
use LoxBerry::JSON;
use JSON;
use Getopt::Long;
use FindBin qw($Bin);
use lib "$Bin/libs";
use Globals;
require "$lbpbindir/libs/Stats4Lox.pm";

my $me = Globals::whoami();

my $do_plan = 0;
my $do_outputs = 0;
GetOptions (
	"plan"    => \$do_plan,
	"outputs" => \$do_outputs
);
# Called without a switch it does the cheap half - that is what a manual run
# almost always wants.
$do_plan = 1 if( !$do_plan and !$do_outputs );

# loglevel 6 whatever the plugin is set to. This runs unattended and renames
# things in somebody's configuration; its log is the only place where that is
# visible afterwards. At the default level 3 not even the orphan warnings would
# be written - measured, the first run produced an empty log while it was
# updating eleven statistics.
#
# stderr stays off on purpose. The cron wrapper redirects it to a file of its
# own, so that only what breaks BEFORE this log exists - a compile error, a
# missing module - ends up there. With stderr on, every line would be written
# twice, onto a ramdisk.
my $log = LoxBerry::Log->new (
	name => 'Refresh_Config',
	stderr => 0,
	loglevel => 6,
	addtime => 1
);

LOGSTART "Refresh configuration";

# Only one of these at a time, and never next to itself from the other schedule:
# both halves write stats.json.
my $lockfile = "/var/lock/s4l_refresh_config.lock";
open my $lockfh, '>', $lockfile or die "$me CRITICAL Could not open LOCK file $lockfile: $!";
if( !flock( $lockfh, 2+4 ) ) { #LOCK_EX+LOCK_NB
	LOGWARN "$me Another instance is running - nothing to do";
	LOGEND;
	exit(0);
}
print $lockfh $$;

my %miniservers = LoxBerry::System::get_miniservers();
if( !%miniservers ) {
	LOGCRIT "$me No Miniservers defined on this LoxBerry";
	LOGEND;
	exit(1);
}

refresh_loxplan() if( $do_plan );

# Both halves change entries of stats.json, so they share one read-modify-write.
# The changes themselves are collected first, without the file open - see
# apply_changes().
my @changes;
push @changes, @{ collect_plan_changes() }    if( $do_plan );
push @changes, @{ collect_output_changes() }  if( $do_outputs );

apply_changes( \@changes );

LOGEND;
exit(0);


#####################################################
# Fetch the LoxPLAN of every Miniserver, if it changed
#####################################################
# Deliberately a copy of what ajax.cgi/getloxplan does and not a call into it:
# that handler is a CGI, not a library. Kept to the automatic path - manual mode
# means the user supplies the file, and nothing here may overwrite it.
#####################################################
sub refresh_loxplan
{
	require Loxone::GetLoxplan;
	require Loxone::ParseXML;
	require LoxBerry::IO;

	if( ($Globals::loxone->{loxplansource} // 'auto') eq 'manual' ) {
		LOGINF "$me Loxone configuration is in manual mode - not fetching anything";
		return;
	}

	foreach my $msno ( sort keys %miniservers ) {

		LOGINF "$me MS$msno: Checking the Loxone configuration";

		# Serial, for matching LoxBerry's Miniserver numbers to the LoxPLAN
		my %ms_serials;
		if( $miniservers{$msno}{UseCloudDNS} and $miniservers{$msno}{CloudURL} ) {
			$ms_serials{$msno} = uc( $miniservers{$msno}{CloudURL} );
		}
		else {
			eval {
				my ($response) = LoxBerry::IO::mshttp_call2($msno, "/jdev/cfg/mac");
				my $sn = JSON::from_json( $response )->{LL}->{value};
				$sn =~ tr/://d;
				$ms_serials{$msno} = uc( $sn );
			};
			LOGWARN "$me MS$msno: Could not get the serial - matching may fail" if( $@ );
		}

		my $Loxplanfile = "$Globals::stats4lox->{s4ltmp}/s4l_loxplan_ms$msno.Loxone";
		my $loxplanjson = "$Globals::stats4lox->{loxplanjsondir}/ms$msno.json";

		my $remoteTimestamp;
		eval {
			$remoteTimestamp = Loxone::GetLoxplan::checkLoxplanUpdate( $msno, $loxplanjson, $log );
		};
		my $checkfailed = $@;

		if( $checkfailed ) {
			LOGWARN "$me MS$msno: Could not check for an update: $checkfailed";
			next;
		}
		# checkLoxplanUpdate returns undef when the local copy is up to date.
		if( !defined $remoteTimestamp and -e $loxplanjson ) {
			LOGOK "$me MS$msno: Loxone configuration is up to date";
			next;
		}

		LOGINF "$me MS$msno: Loxone configuration changed - fetching";
		unlink $Loxplanfile;
		my $fetched = Loxone::GetLoxplan::getLoxplan( ms => $msno, log => $log );
		if( !$fetched or ! -e $Loxplanfile ) {
			LOGERR "$me MS$msno: Could not fetch the Loxone configuration";
			next;
		}

		my $loxplan = Loxone::ParseXML::loxplan2json(
			filename => $Loxplanfile,
			msno => $msno,
			output => $loxplanjson,
			log => $log,
			remoteTimestamp => $remoteTimestamp,
			ms_serials => \%ms_serials
		);
		if( !$loxplan ) {
			LOGERR "$me MS$msno: Could not parse the Loxone configuration";
			next;
		}
		LOGOK "$me MS$msno: Loxone configuration updated";
	}
}


#####################################################
# Read one parsed LoxPLAN
#####################################################
sub loxplan_controls
{
	my $msno = shift;
	my $file = "$Globals::stats4lox->{loxplanjsondir}/ms$msno.json";
	return undef if( ! -e $file );
	my $controls;
	eval {
		my $obj = LoxBerry::JSON->new();
		my $plan = $obj->open( filename => $file, readonly => 1 );
		$controls = $plan->{controls} if( $plan );
	};
	return $controls;
}


#####################################################
# Title, description, room, category and type
#####################################################
# Returns a list of changes, it does not write anything: stats.json is held
# under an exclusive lock while it is open, and the grabber gives up on it after
# two seconds. Everything slow happens before the file is touched.
#####################################################
sub collect_plan_changes
{
	my @changes;
	my $orphans = 0;

	my $stats = read_stats() or return \@changes;

	# One LoxPLAN per Miniserver, read once
	my %plans;

	foreach my $element ( @{ $stats->{loxone} } ) {

		my $msno = $element->{msno};
		my $uuid = $element->{uuid};
		next if( !defined $msno or !defined $uuid );

		$plans{$msno} = loxplan_controls( $msno ) if( !exists $plans{$msno} );
		if( !$plans{$msno} ) {
			LOGWARN "$me MS$msno: No parsed Loxone configuration - skipping its statistics";
			next;
		}

		my $ctrl = $plans{$msno}->{$uuid};
		if( !$ctrl ) {
			# Reported, not removed. A block can be missing because it was
			# deleted in Loxone Config - or because the LoxPLAN was fetched
			# while somebody was working on it. Deciding that is the user's.
			LOGWARN "$me Orphaned: '" . ($element->{name} // '?')
			        . "' (MS$msno/$uuid) is no longer in the Loxone configuration"
			        . " - its measurement '" . ($element->{measurementname} // '?')
			        . "' keeps its data";
			$orphans++;
			next;
		}

		# measurementname is deliberately not in this list. It defaults to the
		# block name, but it IS the name of the InfluxDB measurement - renaming
		# it would start a new series and cut the history in two.
		my %new = (
			name        => $ctrl->{Title},
			description => $ctrl->{Desc},
			room        => $ctrl->{Place},
			category    => $ctrl->{Category},
			type        => $ctrl->{Type},
		);

		my %diff;
		foreach my $field ( sort keys %new ) {
			my $old = defined $element->{$field} ? $element->{$field} : '';
			my $val = defined $new{$field}       ? $new{$field}       : '';
			next if( $old eq $val );
			$diff{$field} = $val;
			LOGINF "$me '" . ($element->{name} // '?') . "': $field '$old' -> '$val'";
		}

		push @changes, { msno => $msno, uuid => $uuid, fields => \%diff } if( %diff );
	}

	LOGINF "$me Orphaned statistics: $orphans" if( $orphans );
	LOGOK  "$me Loxone configuration compared: " . scalar(@changes) . " statistics to update";
	return \@changes;
}


#####################################################
# outputkeys and outputlabels
#####################################################
sub collect_output_changes
{
	my @changes;

	my $stats = read_stats() or return \@changes;

	# Copy what is needed, then let go of the file: one HTTP request per block
	# follows, and the grabber must not wait for all of them.
	my @todo;
	foreach my $element ( @{ $stats->{loxone} } ) {
		next if( !defined $element->{msno} or !defined $element->{uuid} );
		# See the header: only entries the grabber queries anyway.
		next if( !defined $element->{active} or lc($element->{active}) ne 'true' );
		push @todo, {
			msno   => $element->{msno},
			uuid   => $element->{uuid},
			name   => $element->{name},
			keys   => ref($element->{outputkeys})   eq 'ARRAY' ? $element->{outputkeys}   : [],
			labels => ref($element->{outputlabels}) eq 'ARRAY' ? $element->{outputlabels} : [],
		};
	}
	undef $stats;

	LOGINF "$me Checking the outputs of " . scalar(@todo) . " active statistics";

	foreach my $t ( @todo ) {

		my ($code, $resp) = Stats4Lox::msget_value( $t->{msno}, $t->{uuid} );
		if( $code ne "200" or ref($resp) ne 'ARRAY' ) {
			LOGWARN "$me '" . ($t->{name} // '?') . "': Miniserver answered $code - outputs left as they are";
			next;
		}

		my @keys   = map { as_bytes( $_->{Key} ) }  grep { defined $_->{Key} } @{$resp};
		my @labels = map { as_bytes( defined $_->{Name} ? $_->{Name} : $_->{Key} ) }
		             grep { defined $_->{Key} } @{$resp};
		next if( !@keys );

		next if(     join("\x00", @keys)   eq join("\x00", @{ $t->{keys} })
		         and join("\x00", @labels) eq join("\x00", @{ $t->{labels} }) );

		LOGINF "$me '" . ($t->{name} // '?') . "': outputs "
		       . join(",", @{ $t->{labels} }) . " -> " . join(",", @labels);

		push @changes, {
			msno => $t->{msno}, uuid => $t->{uuid},
			fields => { outputkeys => \@keys, outputlabels => \@labels }
		};
	}

	LOGOK "$me Outputs compared: " . scalar(@changes) . " statistics to update";
	return \@changes;
}


#####################################################
# A decoded string, turned back into the bytes it stands for
#####################################################
# Nothing cosmetic - without this the script corrupts the whole file. Measured
# on a live installation, and it cost an hour to find:
#
# LoxBerry::JSON hands back what is IN the file, undecoded: "Q↓" arrives as the
# four characters Q, 0xE2, 0x86, 0x93. msget_value() decodes, so the same name
# arrives from there as the two characters Q and U+2193.
#
# JSON serialisers switch mode on the highest character they are given. As long
# as every string stays below 256 the file is written back byte for byte. Put a
# single decoded string into the structure and the encoder switches to UTF-8 for
# EVERYTHING - and every undecoded string in the file gets encoded a second
# time: "Küche" becomes "KÃ¼che".
#
# It hits far more than the field being changed, because writing rewrites the
# whole file. On the test installation one --outputs run mangled 66 values,
# among them measurementname - the name of the InfluxDB measurement. From that
# moment the grabbers wrote into freshly created series with broken names:
# "Alkalinität" last written 15:47:01, "AlkalinitÃ¤t" first written 15:49:02.
#
# So everything that does not come out of LoxBerry::JSON gets brought into the
# same state before it goes near the structure.
#####################################################
sub as_bytes
{
	my $s = shift;
	return $s if( !defined $s );
	utf8::encode($s) if( utf8::is_utf8($s) );
	return $s;
}


#####################################################
# Read stats.json, shared lock, short
#####################################################
sub read_stats
{
	my $obj = LoxBerry::JSON->new();
	my $stats = $obj->open( filename => $Globals::statsconfig, readonly => 1, locktimeout => 10 );
	if( !$stats or ref($stats->{loxone}) ne 'ARRAY' ) {
		LOGERR "$me Could not read $Globals::statsconfig";
		return undef;
	}
	# The object holds the lock until it goes out of scope, so hand back a copy
	# and let it go here.
	return { loxone => [ @{ $stats->{loxone} } ] };
}


#####################################################
# Write the collected changes and rebuild their panels
#####################################################
sub apply_changes
{
	my $changes = shift;

	if( !@{$changes} ) {
		LOGOK "$me Nothing to change";
		return;
	}

	# Several changes can hit the same statistic when both halves run together.
	my %merged;
	foreach my $c ( @{$changes} ) {
		my $k = $c->{msno} . "\x00" . $c->{uuid};
		$merged{$k}->{msno} = $c->{msno};
		$merged{$k}->{uuid} = $c->{uuid};
		$merged{$k}->{fields}->{$_} = $c->{fields}->{$_} foreach ( keys %{ $c->{fields} } );
	}

	my $obj = LoxBerry::JSON->new();
	my $stats = $obj->open( filename => $Globals::statsconfig, locktimeout => 10 );
	if( !$stats or ref($stats->{loxone}) ne 'ARRAY' ) {
		LOGERR "$me Could not open $Globals::statsconfig for writing - no change made";
		return;
	}

	my @provision;
	my $updated = 0;

	foreach my $element ( @{ $stats->{loxone} } ) {
		next if( !defined $element->{msno} or !defined $element->{uuid} );
		my $c = $merged{ $element->{msno} . "\x00" . $element->{uuid} };
		next if( !$c );

		$element->{$_} = $c->{fields}->{$_} foreach ( keys %{ $c->{fields} } );
		$updated++;

		# provisionDashboard fills in the new panel ids, so it has to run on the
		# element BEFORE the file is written - the same order ajax.cgi uses.
		push @provision, $element;
	}

	foreach my $element ( @provision ) {
		eval {
			require GrafanaS4L;
			GrafanaS4L::provisionDashboard( $element );
		};
		LOGERR "$me '" . ($element->{name} // '?') . "': dashboard could not be rebuilt: $@" if( $@ );
	}

	$obj->write();
	undef $obj;

	LOGOK "$me $updated statistics updated";
}
