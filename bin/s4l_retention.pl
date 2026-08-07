#!/usr/bin/perl

# Retention and downsampling for Stats4Lox (issue #44).
#
# Usage:
#   s4l_retention.pl preview  [--text]
#   s4l_retention.pl apply    [--backfill] [--force]
#   s4l_retention.pl backfill [--stage <n>] [--measurement <name>]
#   s4l_retention.pl status
#
#   --database <name> works on another database than the configured one. For
#   trying this out on a throwaway copy; not offered in the web interface.
#
# "preview" changes nothing and answers with JSON: what is configured, what is in
# the database, which statements an apply would send, and - the part that matters -
# what data would be gone afterwards. The web interface shows that before anything
# happens.
#
# No root. Everything goes through InfluxInfo, which talks to InfluxDB over its
# own client with the credentials from cred.json - the same way the InfluxDB page
# already does it, so this script runs as the user the web server runs as.
#
#############################################################################
# The two decisions that shape everything below
#############################################################################
#
# The retention is applied to autogen itself. Creating another policy and making
# it the default was tried in a throwaway database: the existing data stays in
# autogen and becomes invisible to every query that does not name a policy - which
# is every existing Grafana panel. See the comment at $Globals::retention.
#
# Every continuous query reads from autogen, not from the stage before it. A
# cascade would be cheaper to run and is what the InfluxDB documentation shows,
# but it aggregates aggregates: stage 3 reading mean_x and last_x out of stage 2
# produces mean_mean_x, last_mean_x, mean_last_x and last_last_x. Four fields
# instead of two, and a field name that gets one prefix longer per stage. Reading
# raw data at every stage keeps the fields called mean_<field> and last_<field>
# everywhere, which is what a Grafana panel has to be written against.
#
# The price is that autogen must still hold the data when a coarse continuous
# query fires - a weekly query needs a week of raw data. is_consistent() below
# checks that and preview() reports it.
#
#############################################################################

use warnings;
use strict;
use LoxBerry::System;
use LoxBerry::JSON;
use LoxBerry::Log;
use Getopt::Long;
use JSON;
use Time::HiRes ();
use File::Path qw(make_path);
use FindBin qw($Bin);
use lib "$Bin/libs";
use Globals;
use InfluxInfo;

my $command = shift @ARGV // '';

my ( $opt_text, $opt_force, $opt_backfill, $opt_stage, $opt_measurement,
     $opt_database, $opt_config, $opt_resume );
GetOptions(
	'text'          => \$opt_text,
	'force'         => \$opt_force,
	'backfill'      => \$opt_backfill,
	'stage=i'       => \$opt_stage,
	'measurement=s' => \$opt_measurement,
	'database=s'    => \$opt_database,
	'config=s'      => \$opt_config,
	'resume'        => \$opt_resume,
);

# --database exists for one purpose: trying all of this out on a throwaway copy
# before it is let near eleven years of somebody's history. It is not offered
# anywhere in the web interface.
#
# Set on the Globals hash rather than kept in a variable of our own, because
# InfluxInfo reads it from there on every call - measurements() and timestamps()
# would otherwise keep asking the real database while everything else worked on
# the copy.
$Globals::influx->{influxdatabase} = $opt_database if( $opt_database );

# --config lets the caller ask "what would THESE settings do" without saving them
# anywhere. The web interface uses it for the preview, so that pressing Preview is
# genuinely a read-only act: it used to save the form first, which meant a button
# called "Preview" quietly wrote to the configuration.
#
# Only ever used by preview. apply and backfill deliberately ignore it - they run
# in the background from the saved configuration, and letting a command line
# override that would mean the run and the settings could disagree.
if( defined $opt_config ) {
	my $c = eval { JSON::decode_json( $opt_config ) };
	if( !$c or ref($c) ne 'HASH' ) {
		print STDERR "--config is not a JSON object\n";
		exit 1;
	}
	$Globals::retention = Globals::merge_retention( $c );
}

# The name arrives from the command line as UTF-8 BYTES, while the names from
# InfluxInfo::measurements() are CHARACTERS - they come out of decode_json. Byte
# string "M\xc3\xa4hzeit" never equals character string "Mähzeit", so without this
# every measurement with an umlaut answered "gibt es nicht". Measured, not feared.
if( defined $opt_measurement ) {
	require Encode;
	$opt_measurement = Encode::decode( 'UTF-8', $opt_measurement );
}

my $DB = $Globals::influx->{influxdatabase} // 'stats4lox';

# Names we own. Everything with this prefix was made by this script and may be
# changed or dropped by it; anything else in the database is somebody else's and
# is never touched.
my $PREFIX    = 's4l_';
my $CQ_PREFIX = 's4l_cq_';

# Stages are named after their NUMBER - s4l_stage2 - and not after what they do.
#
# s4l_6h reads better and was wrong, and s4l_6h_2y would have been worse. A name
# that carries a setting changes when the setting changes, and a renamed policy is
# not a renamed policy in InfluxDB: the old one is no longer configured, so it is
# dropped with everything in it, and a new empty one has to be filled again from
# scratch. Moving a stage from two years to three would have cost the condensed
# history and hours of recomputing.
#
# And the reason that matters most is outside this file. A Grafana panel refers to
# a policy BY NAME. Rename it because somebody changed a dropdown, and every panel
# the user has pointed at the condensed data stops finding it - silently, with no
# error anywhere. The number is the one thing about a stage that does not move.
#
# The price is that the name says nothing. The web interface numbers the stages
# the same way, so "stage2" is the row called "Stufe 2" there, and the wiki says
# so as well.

my $STATUSFILE = $Globals::stats4lox->{s4ltmp} . "/retention-status.json";
my $LOCKFILE   = $Globals::stats4lox->{s4ltmp} . "/retention.lock";

#############################################################################
# Two files, because they answer two different questions
#############################################################################
# The status file above is the progress display. It is written on EVERY chunk -
# 991 times in 19 minutes on the test installation, and more on a larger one - so
# it lives in s4ltmp, which is a ramdisk. Writing that to an SD card would wear it
# for nothing: nobody wants yesterday's progress bar.
#
# The resume point is the opposite. It is needed exactly when the ramdisk is gone,
# because the machine rebooted in the middle of a run - which is the case the
# whole resume feature exists for. So it goes on the card, and to keep that
# affordable it is written at most once a minute rather than per chunk. A crash
# then costs at most a minute of recomputing instead of hours.
#
# In the data directory and not in the config directory: this is runtime state,
# not something the user set, and it has no business turning up in a backup of
# their settings.
my $PROGRESSFILE = $LoxBerry::System::lbpdatadir . "/retention-progress.json";
my $PROGRESS_EVERY = 60;   # seconds

#############################################################################
# Only one at a time
#############################################################################
# A second apply started while the first one is halfway through would work on a
# database that is in neither the old nor the new state. A backfill running twice
# would only waste hours - INTO overwrites the same points - but the two together
# can drop autogen's history while the other one is still reading it.
#
# In s4ltmp and not in /var/lock: that directory is ours, always writable, and on
# a ramdisk, so a lock cannot survive a reboot. The handle is deliberately kept in
# a file-scoped variable - closing it would release the lock.
my $lockfh;
sub take_lock
{
	make_path( $Globals::stats4lox->{s4ltmp} ) if( ! -d $Globals::stats4lox->{s4ltmp} );
	require Fcntl;
	# With parentheses, because this sub sits above the definition of LOGE and an
	# unparenthesised call to a sub Perl has not seen yet is a syntax error.
	if( !open( $lockfh, '>', $LOCKFILE ) ) {
		LOGE( "Cannot create the lock file $LOCKFILE: $!" );
		return 0;
	}
	if( !flock( $lockfh, Fcntl::LOCK_EX() | Fcntl::LOCK_NB() ) ) {
		LOGE( "A run is already in progress. Nothing is changed." );
		return 0;
	}
	print {$lockfh} $$;
	return 1;
}

#############################################################################
# Logging and status
#############################################################################
# The log is called Downsampling and is written WHILE the work runs, because the
# user is meant to read along - a backfill can take hours on a Raspberry. That is
# also why the web interface links to it without only=once, unlike the healthcheck
# report which is finished by the time anybody opens it.

my $log;
sub openlog
{
	my ($title) = @_;
	$log = LoxBerry::Log->new( name => 'Downsampling', stderr => 1, addtime => 1, loglevel => 7 );
	LOGSTART "Downsampling: $title";
}

# LoxBerry::Log writes bytes. Measurement names arrive here as CHARACTERS out of
# decode_json, and handing those over unchanged turns "Mähzeit" into "M?hzeit".
sub logsafe
{
	my ($s) = @_;
	return $s if( !defined $s );
	require Encode;
	return Encode::is_utf8($s) ? Encode::encode( 'UTF-8', $s ) : $s;
}

sub LOG  { $log->INF ( logsafe($_[0]) ) if( $log ); return }
sub LOGO { $log->OK  ( logsafe($_[0]) ) if( $log ); return }
sub LOGW { $log->WARN( logsafe($_[0]) ) if( $log ); return }
sub LOGE { $log->ERR ( logsafe($_[0]) ) if( $log ); return }

# The page polls this file to follow the run. Written completely on every update -
# it is a few hundred bytes and a partial write would be worse than a slow one.
my %status;
sub status
{
	my (%p) = @_;
	%status = ( %status, %p, time => time() );
	eval {
		make_path( $Globals::stats4lox->{s4ltmp} ) if( ! -d $Globals::stats4lox->{s4ltmp} );
		open( my $fh, '>', $STATUSFILE ) or die;
		print {$fh} JSON::encode_json( \%status );
		close $fh;
		# Only when running as root - normally this script is the web server user
		# and the file already belongs to the right one.
		if( !$< ) {
			chown( scalar getpwnam('loxberry'), scalar getgrnam('loxberry'), $STATUSFILE );
		}
	};
	return;
}

sub read_json_file
{
	my ($path) = @_;
	open( my $fh, '<', $path ) or return {};
	local $/;
	my $raw = <$fh>;
	close $fh;
	my $d = eval { JSON::decode_json( $raw ) };
	return ( ref($d) eq 'HASH' ) ? $d : {};
}

sub read_status   { return read_json_file( $STATUSFILE ) }
sub read_progress { return read_json_file( $PROGRESSFILE ) }

# The resume point, on the card and written at most once a minute.
#
# Through a temporary file and a rename, because the one event this file exists
# for is the power cut - and a half-written file caught by one would be worse than
# no file at all. rename() is atomic on the same filesystem.
my $progress_last = 0;
sub write_progress
{
	my (%p) = @_;
	return if( !$p{force} and time() - $progress_last < $PROGRESS_EVERY );
	$progress_last = time();
	delete $p{force};
	eval {
		open( my $fh, '>', "$PROGRESSFILE.new" ) or die;
		print {$fh} JSON::encode_json( { %p, time => time() } );
		close $fh;
		rename( "$PROGRESSFILE.new", $PROGRESSFILE );
	};
	return;
}

sub clear_progress { unlink $PROGRESSFILE, "$PROGRESSFILE.new"; $progress_last = 0; return }

# What the run was told to do, as one short string.
#
# An interrupted run may only be carried on if the settings are still the ones it
# started with - otherwise its saved position points into a list of work that no
# longer exists, and it would skip the wrong chunks.
sub config_fingerprint
{
	my ($stages) = @_;
	require Digest::MD5;
	my $s = join( "|", map { "$_->{no}:$_->{interval}:$_->{duration}" } @$stages );
	return Digest::MD5::md5_hex( $s );
}

#############################################################################
# Durations
#############################################################################
# InfluxDB reports a duration as "0s", "168h0m0s", "8760h0m0s" and accepts
# "30d", "1w", "INF". Both directions are needed, so both are here.
#
# 0 means unlimited, in the configuration and in InfluxDB alike - autogen sits at
# DURATION 0s today and keeps everything.

my @UNITS = ( [ 'ns', 1e-9 ], [ 'us', 1e-6 ], [ 'ms', 1e-3 ],
              [ 'w', 604800 ], [ 'd', 86400 ], [ 'h', 3600 ], [ 'm', 60 ], [ 's', 1 ] );

sub dur_seconds
{
	my ($d) = @_;
	return 0 if( !defined $d or $d eq '' or $d eq '0' );
	return 0 if( uc($d) eq 'INF' );

	my $rest = $d;
	my $sec  = 0;
	my $any  = 0;
	while( $rest =~ s/^\s*(\d+(?:\.\d+)?)\s*([a-zµ]+)// ) {
		my ($n, $u) = ( $1, lc($2) );
		$u = 'us' if( $u eq "\x{b5}s" or $u eq 'µs' );
		my ($match) = grep { $_->[0] eq $u } @UNITS;
		return undef if( !$match );
		$sec += $n * $match->[1];
		$any = 1;
	}
	return undef if( !$any or $rest =~ /\S/ );
	return int( $sec + 0.5 );
}

sub dur_string
{
	my ($s) = @_;
	return "INF" if( !$s );
	return sprintf( "%dd", $s/86400 ) if( $s % 86400 == 0 );
	return sprintf( "%dh", $s/3600 )  if( $s % 3600 == 0 );
	return sprintf( "%dm", $s/60 )    if( $s % 60 == 0 );
	return sprintf( "%ds", $s );
}

sub mb
{
	my ($b) = @_;
	return "?" if( !defined $b );
	# Sparse early years really do come to a few hundred kilobytes, and "0 MB"
	# next to "23 Messreihen" reads like a fault rather than like an answer.
	return "< 1 MB" if( $b > 0 and $b < 1048576 );
	return sprintf( "%.1f GB", $b/1073741824 ) if( $b >= 1073741824 );
	return sprintf( "%.0f MB", $b/1048576 );
}

sub dur_human
{
	my ($s) = @_;
	return "unlimited" if( !$s );
	return sprintf( "%.0f years", $s/31536000 ) if( $s >= 2*31536000 );
	return sprintf( "%d days", $s/86400 )       if( $s >= 2*86400 );
	return sprintf( "%d hours", $s/3600 );
}

# How long one shard of a policy should cover.
#
# InfluxDB deletes whole shards, never single points, so a policy whose shard
# duration is close to its retention keeps data far longer than it says. About a
# quarter of the retention is the upper bound, and about 720 points per series
# and shard the target - that is what keeps the shard count sane. The raw data on
# the test installation sits at 436 shards for 571 MB; a downsampled policy over
# ten years at 7 day shards would add another 520 for a fraction of the data.
sub shard_for_stage
{
	my ($interval_secs, $dur_secs) = @_;
	my $want = $interval_secs * 720;
	$want = 604800   if( $want < 604800 );     # never below a week
	$want = 31536000 if( $want > 31536000 );   # and never above a year
	if( $dur_secs ) {
		my $max = int( $dur_secs / 4 );
		$want = $max  if( $max > 0 and $want > $max );
		$want = 3600  if( $want < 3600 );      # InfluxDB's own minimum
	}
	return $want;
}

# For autogen the table InfluxDB uses itself, so nothing changes as long as the
# retention stays unlimited: 0 keeps the 168h it has today.
sub shard_for_autogen
{
	my ($dur_secs) = @_;
	return 604800 if( !$dur_secs );
	return 3600   if( $dur_secs <= 2*86400 );
	return 86400  if( $dur_secs <= 180*86400 );
	return 604800;
}

#############################################################################
# Talking to InfluxDB
#############################################################################

# Runs statements and returns ( $ok, $results, $errortext ). InfluxInfo::query
# hands back a result per statement and puts a failure in its "error" key - a
# CREATE that fails looks exactly like one that worked unless somebody looks.
sub influx
{
	my ($sql) = @_;
	my $res = InfluxInfo::query( $sql );
	return ( 0, [], "no answer from InfluxDB" ) if( ref($res) ne 'ARRAY' or !@$res );
	foreach my $r ( @$res ) {
		return ( 0, $res, $r->{error} ) if( $r->{error} );
	}
	return ( 1, $res, undef );
}

# name => { duration, shard, default, replication }
sub read_policies
{
	my ($ok, $res, $err) = influx( "SHOW RETENTION POLICIES ON \"$DB\"" );
	return ( undef, $err ) if( !$ok );

	my %out;
	foreach my $s ( @{ $res->[0]->{series} || [] } ) {
		my @c = @{ $s->{columns} || [] };
		my %idx = map { $c[$_] => $_ } 0..$#c;
		next if( !defined $idx{name} );
		foreach my $v ( @{ $s->{values} || [] } ) {
			$out{ $v->[ $idx{name} ] } = {
				duration    => defined $idx{duration}            ? $v->[ $idx{duration} ]            : '',
				shard       => defined $idx{shardGroupDuration}  ? $v->[ $idx{shardGroupDuration} ]  : '',
				replication => defined $idx{replicaN}            ? $v->[ $idx{replicaN} ]            : 1,
				default     => ( defined $idx{default} and $v->[ $idx{default} ] ) ? 1 : 0,
			};
		}
	}
	return ( \%out, undef );
}

# name => query text, for this database only
sub read_cqs
{
	my ($ok, $res, $err) = influx( "SHOW CONTINUOUS QUERIES" );
	return ( undef, $err ) if( !$ok );

	my %out;
	foreach my $r ( @$res ) {
		foreach my $s ( @{ $r->{series} || [] } ) {
			next if( ( $s->{name} // '' ) ne $DB );
			my @c = @{ $s->{columns} || [] };
			my %idx = map { $c[$_] => $_ } 0..$#c;
			next if( !defined $idx{name} );
			foreach my $v ( @{ $s->{values} || [] } ) {
				$out{ $v->[ $idx{name} ] } = defined $idx{query} ? $v->[ $idx{query} ] : '';
			}
		}
	}
	return ( \%out, undef );
}

#############################################################################
# What the configuration asks for
#############################################################################
# One entry per ACTIVE stage, in order, stage 1 first. Stage 1 is the raw data in
# autogen and is always there.
#
# The retention of the last active stage is the global one. Two fields for the
# same number can only contradict each other, so the web interface shows it
# greyed out and this is where it is actually taken from.

sub wanted_stages
{
	my $cfg    = $Globals::retention;
	my $global = dur_seconds( $cfg->{duration} );
	my $down   = is_enabled( $cfg->{downsampling} ) ? 1 : 0;

	my @out = ( {
		no       => 1,
		policy   => 'autogen',
		interval => 'raw',
		interval_secs => 0,
	} );

	if( $down ) {
		my $stages = $cfg->{stages} || [];
		# The cascade breaks at the first inactive stage. The web interface only
		# lets the next one be ticked, but a hand-edited stats4lox.json can say
		# anything, and a gap would mean a continuous query feeding a policy that
		# nothing reads.
		for( my $i = 1; $i < scalar @$stages; $i++ ) {
			last if( !is_enabled( $stages->[$i]->{active} ) );
			my $secs = dur_seconds( $stages->[$i]->{interval} );
			next if( !$secs );
			push @out, {
				no            => $i + 1,
				policy        => $PREFIX . "stage" . ( $i + 1 ),
				interval      => $stages->[$i]->{interval},
				interval_secs => $secs,
			};
		}
	}

	# Retention per stage, from the configuration, and the global one for the last
	for( my $i = 0; $i < scalar @out; $i++ ) {
		my $s = $out[$i];
		if( $i == $#out ) {
			$s->{duration_secs} = $global;
		}
		else {
			my $raw = $Globals::retention->{stages}->[ $s->{no} - 1 ]->{duration};
			$s->{duration_secs} = dur_seconds( $raw );
		}
		$s->{duration}       = dur_string( $s->{duration_secs} );
		$s->{duration_human} = dur_human( $s->{duration_secs} );
		$s->{shard_secs}     = ( $s->{no} == 1 )
			? shard_for_autogen( $s->{duration_secs} )
			: shard_for_stage( $s->{interval_secs}, $s->{duration_secs} );
		$s->{shard} = dur_string( $s->{shard_secs} );
		$s->{last}  = ( $i == $#out ) ? 1 : 0;
	}

	return \@out;
}

# The largest interval the grabber writes with. A downsampling interval below it
# does not condense anything - it turns one point with one field into one point
# with two, which is more data than it replaces.
sub largest_grabber_interval
{
	my $max = 0;
	foreach my $g ( $Globals::miniserver, $Globals::loxberry ) {
		next if( !is_enabled( $g->{active} ) );
		$max = $g->{interval} if( ( $g->{interval} // 0 ) > $max );
	}

	# stats.json read by hand with a shared lock, the same way the healthcheck
	# does it - LoxBerry::JSON::write() writes in place, so an unlocked reader can
	# catch a half-written file.
	require Fcntl;
	if( open( my $fh, '<:raw', $Globals::statsconfig ) ) {
		my $got = 0;
		foreach ( 1 .. 6 ) {
			last if( $got = flock( $fh, Fcntl::LOCK_SH() | Fcntl::LOCK_NB() ) );
			select( undef, undef, undef, 0.5 );
		}
		if( $got ) {
			local $/;
			my $raw = <$fh>;
			flock( $fh, Fcntl::LOCK_UN() );
			my $j = eval { decode_json( $raw ) };
			if( $j and ref($j->{loxone}) eq 'ARRAY' ) {
				foreach my $e ( @{ $j->{loxone} } ) {
					next if( !is_enabled( $e->{active} ) );
					$max = $e->{interval} if( ( $e->{interval} // 0 ) > $max );
				}
			}
		}
		close $fh;
	}
	return $max;
}

# Everything the configuration says that cannot be carried out. Errors stop an
# apply, warnings do not.
sub check_config
{
	my ($stages) = @_;
	my (@errors, @warnings);

	my $cfg = $Globals::retention;
	foreach my $k ( 'duration' ) {
		push @errors, "\"$cfg->{$k}\" is not a valid retention."
			if( !defined dur_seconds( $cfg->{$k} ) );
	}

	my $grabber = largest_grabber_interval();

	for( my $i = 0; $i < scalar @$stages; $i++ ) {
		my $s = $stages->[$i];

		if( $i > 0 ) {
			my $p = $stages->[$i-1];
			push @errors, sprintf(
				"Stage %d condenses to %s and stage %d already to %s - a later stage has to be coarser.",
				$s->{no}, $s->{interval}, $p->{no}, $p->{interval} )
				if( $s->{interval_secs} <= $p->{interval_secs} );

			# Unlimited beats everything, so a 0 further up is fine and a 0 in the
			# middle is not: the stage after it would never receive anything to keep.
			if( !$p->{duration_secs} ) {
				push @errors, sprintf(
					"Stage %d keeps everything, so stage %d would never receive anything to take over.",
					$p->{no}, $s->{no} );
			}
			elsif( $s->{duration_secs} and $s->{duration_secs} <= $p->{duration_secs} ) {
				push @errors, sprintf(
					"Stage %d is to keep %s and stage %d already keeps %s - a later stage has to keep it longer.",
					$s->{no}, $s->{duration_human}, $p->{no}, $p->{duration_human} );
			}
		}

		next if( $s->{no} == 1 );

		# "<=" and not "<": at exactly the grabber interval one point with one
		# field becomes one point with two, which is the case that started this
		# whole rule. So the wording must not say "below" - it is this interval
		# and everything finer.
		push @warnings, {
			code     => "grabber",
			stage    => $s->{no},
			interval => $s->{interval},
			minutes  => int( $grabber/60 ),
			text     => sprintf(
				"Stage %d condenses to %s. The grabber writes every %d minutes - at that rate or finer this makes the data larger instead of smaller.",
				$s->{no}, $s->{interval}, $grabber/60 ),
		} if( $grabber and $s->{interval_secs} <= $grabber );
	}

	# The consequence nobody expects, and the one that undercuts the whole promise
	# if it is not said out loud.
	#
	# Every panel this plugin provisions carries "policy": "default" and selects
	# the field by its raw name - see templates/grafana/templates/
	# template_panel_graph.json. A query that does not name a policy sees ONLY the
	# default one, measured. So once the raw data is trimmed, a panel showing a
	# year shows the retained window and nothing before it: the condensed history
	# is there, it just lives under another policy and its fields are called
	# mean_<field> and last_<field>.
	#
	# "My history is kept, only condensed" is true of the database and false of
	# the graphs until the panels are changed. That has to be in the preview.
	if( scalar @$stages > 1 and $stages->[0]->{duration_secs} ) {
		push @warnings, {
			code     => "grafana",
			duration => $stages->[0]->{duration_human},
			wiki     => 1,
			text     => "The existing Grafana panels will then only show the last "
				. $stages->[0]->{duration_human}
				. ". The condensed values are there, but they sit in a retention stage of"
				. " their own and are called mean_<field> and last_<field> - a panel finds"
				. " them only once it has been pointed at them. Details: Wiki.",
		};
	}

	# Every continuous query reads from autogen, so autogen has to still hold the
	# data when the coarsest one fires. Two intervals of margin: a query grouping
	# by a week needs the whole week to be there, and the retention check runs only
	# every 60 minutes.
	my $raw = $stages->[0];
	if( $raw->{duration_secs} and scalar @$stages > 1 ) {
		my $coarsest = $stages->[-1]->{interval_secs};
		push @errors, sprintf(
			"The raw data is to stay for only %s, but the coarsest condensation groups by %s. The condensation would find no data left.",
			$raw->{duration_human}, $stages->[-1]->{interval} )
			if( $raw->{duration_secs} < 2 * $coarsest );
	}

	return ( \@errors, \@warnings );
}

#############################################################################
# The statements an apply would send
#############################################################################
# Built in the order they have to run, and that order is the whole point:
#
#   1. create and adjust the stage policies
#   2. create the continuous queries that fill them
#   3. remove what we own and no longer want
#   4. LAST of all, the retention on autogen
#
# The last step is the one that deletes. Everything that is supposed to catch the
# data has to exist before it, otherwise a run that is interrupted in the middle
# leaves the history gone and nothing to show for it.

# Policies with our prefix that the configuration no longer asks for. Dropping
# one takes its data with it, so assess_loss() needs the same list and it must be
# the same list - hence one function instead of two loops that agree today.
sub obsolete_policies
{
	my ($stages, $policies) = @_;
	my %keep = map { $_->{policy} => 1 } @$stages;
	return [ grep { index( $_, $PREFIX ) == 0 and !$keep{$_} } sort keys %$policies ];
}

sub build_plan
{
	my ($stages, $policies, $cqs) = @_;
	my @plan;

	my %keep_cq;

	foreach my $s ( @$stages ) {
		next if( $s->{no} == 1 );
		my $p = $policies->{ $s->{policy} };
		if( !$p ) {
			push @plan, {
				kind => 'create_rp',
				text => sprintf( "Create retention stage \"%s\" (%s, condensed to %s)",
				                 $s->{policy}, $s->{duration_human}, $s->{interval} ),
				sql  => sprintf( 'CREATE RETENTION POLICY "%s" ON "%s" DURATION %s REPLICATION 1 SHARD DURATION %s',
				                 $s->{policy}, $DB, $s->{duration}, $s->{shard} ),
			};
		}
		elsif( dur_seconds( $p->{duration} ) != $s->{duration_secs}
		    or dur_seconds( $p->{shard} )    != $s->{shard_secs} ) {
			# The text says what actually differs. Both the retention and the shard
			# size can trigger this, and the shard size follows the interval - so a
			# changed interval alone produced "change it to 2 years (was 2 years)",
			# which reads like the preview is broken.
			my $samedur = ( dur_seconds( $p->{duration} ) == $s->{duration_secs} );
			push @plan, {
				kind => 'alter_rp',
				text => $samedur
					? sprintf( "Adjust retention stage \"%s\" to the new interval (%s, stays at %s)",
					           $s->{policy}, $s->{interval}, $s->{duration_human} )
					: sprintf( "Change retention stage \"%s\" to %s (was %s)",
					           $s->{policy}, $s->{duration_human}, dur_human( dur_seconds( $p->{duration} ) ) ),
				sql  => sprintf( 'ALTER RETENTION POLICY "%s" ON "%s" DURATION %s SHARD DURATION %s',
				                 $s->{policy}, $DB, $s->{duration}, $s->{shard} ),
			};
		}

		my $cqname = $CQ_PREFIX . "stage" . $s->{no};
		$keep_cq{$cqname} = 1;
		my $want = cq_text( $s );
		my $have = $cqs->{$cqname};

		# InfluxDB cannot change a continuous query, so a changed one is dropped and
		# created again. Whether it HAS changed cannot be decided on the text: what
		# SHOW CONTINUOUS QUERIES hands back is the parsed statement printed again.
		# It drops the quotes around identifiers that do not need them, writes the
		# database and policy with dots instead, and adds the AS aliases that were
		# never in the statement. Comparing the strings therefore always says
		# "different", and every apply would drop and recreate every query.
		if( defined $have and cq_fingerprint($have) eq cq_fingerprint($want) ) {
			# already right
		}
		else {
			push @plan, {
				kind => 'drop_cq',
				text => "Remove the previous condensation \"$cqname\"",
				sql  => sprintf( 'DROP CONTINUOUS QUERY "%s" ON "%s"', $cqname, $DB ),
			} if( defined $have );
			push @plan, {
				kind => 'create_cq',
				text => sprintf( "Set up the running condensation \"%s\": group new values every %s",
				                 $cqname, $s->{interval} ),
				sql  => $want,
			};
		}
	}

	# Ours and no longer wanted. The continuous query goes first - dropping a policy
	# that a query still writes into leaves the query failing on every run.
	foreach my $name ( sort keys %$cqs ) {
		next if( index( $name, $CQ_PREFIX ) != 0 );
		next if( $keep_cq{$name} );
		push @plan, {
			kind => 'drop_cq',
			text => "Remove the condensation \"$name\" - no longer configured",
			sql  => sprintf( 'DROP CONTINUOUS QUERY "%s" ON "%s"', $name, $DB ),
		};
	}
	foreach my $name ( @{ obsolete_policies( $stages, $policies ) } ) {
		push @plan, {
			kind    => 'drop_rp',
			destroys => 1,
			text    => "Delete the retention stage \"$name\" and all its data - no longer configured",
			sql     => sprintf( 'DROP RETENTION POLICY "%s" ON "%s"', $name, $DB ),
		};
	}

	# autogen last
	my $raw = $stages->[0];
	my $ap  = $policies->{autogen};
	if( $ap and ( dur_seconds( $ap->{duration} ) != $raw->{duration_secs}
	           or dur_seconds( $ap->{shard} )    != $raw->{shard_secs} ) ) {
		push @plan, {
			kind     => 'alter_autogen',
			destroys => ( $raw->{duration_secs} ? 1 : 0 ),
			text     => sprintf( "Keep the raw data for %s from now on (was %s)",
			                     $raw->{duration_human}, dur_human( dur_seconds( $ap->{duration} ) ) ),
			sql      => sprintf( 'ALTER RETENTION POLICY "autogen" ON "%s" DURATION %s SHARD DURATION %s',
			                     $DB, $raw->{duration}, $raw->{shard} ),
		};
	}

	return \@plan;
}

# What a continuous query actually does, boiled down to the four things that can
# differ: where it writes, where it reads, how far it groups, and with which
# aggregates. Everything InfluxDB is free to reformat is thrown away first.
sub cq_fingerprint
{
	my ($text) = @_;
	return '' if( !defined $text );

	my $t = $text;
	$t =~ s/"//g;
	$t =~ s/\s+/ /g;

	my ($into)  = ( $t =~ /\bINTO\s+(\S+?)\.:MEASUREMENT/i );
	my ($from)  = ( $t =~ /\bFROM\s+(\S+)/i );
	my ($every) = ( $t =~ /\bGROUP BY time\(\s*([^),]+?)\s*\)/i );
	my @agg     = sort map { lc } ( $t =~ /(\w+)\(\*\)/g );

	# The interval through the parser, because "1h" and "1h0m0s" are the same
	# thing and InfluxDB may print either
	my $secs = defined $every ? dur_seconds( $every ) : undef;

	return join( "|", lc( $into // '' ), lc( $from // '' ),
	                  ( defined $secs ? $secs : 'x' ), join( ",", @agg ) );
}

# One continuous query per stage, over all measurements at once.
#
# :MEASUREMENT writes every source measurement into a target of the same name, and
# "GROUP BY time(...), *" keeps the tags - measured, both of them.
#
# The regex catches Telegraf's own internal_* series as well, which the rest of
# the plugin filters out. They are condensed along with everything else, and that
# is deliberate: Go's regular expressions have no negative lookahead, so there is
# no way to write "everything except internal_", and one query per measurement
# would mean 146 of them that nobody maintains and that miss every measurement
# added afterwards.
sub cq_text
{
	my ($s) = @_;
	my $agg = join( ", ", map { "$_(*)" } @{ $Globals::retention->{aggregates} } );
	return sprintf(
		'CREATE CONTINUOUS QUERY "%sstage%d" ON "%s" BEGIN SELECT %s INTO "%s"."%s".:MEASUREMENT FROM "%s"."autogen"./.*/ GROUP BY time(%s), * END',
		$CQ_PREFIX, $s->{no}, $DB, $agg, $DB, $s->{policy}, $DB, $s->{interval} );
}

#############################################################################
# What would be lost
#############################################################################
# The question the user actually has, and the reason preview exists.
#
# There are two kinds of loss and they must not be mixed up, because one of them
# can be repaired and the other one is the point of the setting.
#
#   avoidable  A stage drops data that the next, coarser stage does not hold yet.
#              Continuous queries only ever touch data arriving after they were
#              created - measured - so the history has to be condensed once by
#              hand. That is what backfill does.
#
#   final      Data older than the total retention. Nothing catches it, because
#              there is no stage after the last one. This is not a fault: it is
#              exactly what "keep for ten years" means. It still has to be
#              confirmed, and it has to be visible BEFORE anything happens.
#
# The final loss is measured against what is in autogen, not against what is in
# the last policy. The last policy is usually still empty at this point, and
# asking it would answer "nothing to lose here" - right up until the backfill has
# filled it and the deletion suddenly has something to delete. That is how a run
# with --backfill and no --force managed to destroy 2015 and 2016 in a test: the
# loss only became visible after the point where it could still be refused.
#
# Costs two batched queries per policy, about 2.2 s for 146 measurements each -
# measured. Not cheap, but this runs on a button press and answers the only
# question that matters before deleting eleven years of history.

sub oldest_per_measurement
{
	my ($policy, $names) = @_;
	my %out;
	return \%out if( !@$names );

	( my $safepol = $policy ) =~ s/"/\\"/g;
	my $res = InfluxInfo::query_each(
		qq{SELECT * FROM "$DB"."$safepol"."__NAME__" LIMIT 1}, $names );

	for( my $i = 0; $i < scalar @$names; $i++ ) {
		my $s = ( ( $res->[$i] || {} )->{series} || [] )->[0];
		my $v = $s ? ( $s->{values} || [] )->[0] : undef;
		$out{ $names->[$i] } = $v ? $v->[0] : undef;
	}
	return \%out;
}

sub ns2iso
{
	my ($ns) = @_;
	return undef if( !defined $ns );
	my @t = gmtime( int( $ns / 1e9 ) );
	return sprintf( "%04d-%02d-%02dT%02d:%02d:%02dZ",
	                $t[5]+1900, $t[4]+1, $t[3], $t[2], $t[1], $t[0] );
}

sub assess_loss
{
	my ($stages, $policies) = @_;

	my $names = InfluxInfo::measurements();
	my $now   = time() * 1e9;

	# Only policies that exist are asked - a SELECT against a policy InfluxDB does
	# not know is an error, not an empty answer.
	my %oldest;
	foreach my $s ( @$stages ) {
		$oldest{ $s->{policy} } = $policies->{ $s->{policy} }
			? oldest_per_measurement( $s->{policy}, $names )
			: {};
	}
	my $raw = $oldest{ $stages->[0]->{policy} };

	my @report;
	my $backfill_needed = 0;
	my $final_loss      = 0;

	# --- avoidable: everything but the last stage ---------------------------
	for( my $i = 0; $i < $#{$stages}; $i++ ) {
		my $s     = $stages->[$i];
		my @later = @{$stages}[ $i+1 .. $#{$stages} ];
		next if( !$s->{duration_secs} );          # keeps everything, deletes nothing

		my $cut  = $now - $s->{duration_secs} * 1e9;
		my $mine = $oldest{ $s->{policy} };

		my (@missing, @covered);
		my $oldest_at_risk;
		foreach my $m ( @$names ) {
			my $t = $mine->{$m};
			next if( !defined $t or $t >= $cut );  # nothing that old here

			$oldest_at_risk = $t if( !defined $oldest_at_risk or $t < $oldest_at_risk );

			# Covered when SOME later stage reaches back at least to where this
			# stage stops - not necessarily the one immediately after it.
			#
			# Asking only the next stage looked right and refused a correct run on
			# the real installation. 25 of 146 measurements are retired: they hold
			# years of history but have written nothing recently. The six hour
			# stage covers the last two years, so it gets nothing for them and can
			# never cover them - while the daily stage, whose window is the whole
			# history, holds every one of their values. The data was safe and the
			# check said it was not.
			#
			# One interval of slack per stage, because a condensed point sits at
			# the start of its interval and can fall a little later than the
			# boundary it came from.
			my $ok = 0;
			foreach my $n ( @later ) {
				my $o = $oldest{ $n->{policy} }->{$m};
				next if( !defined $o );
				if( $o <= $cut + $n->{interval_secs} * 1e9 ) { $ok = 1; last }
			}
			if( $ok ) { push @covered, $m } else { push @missing, $m }
		}
		next if( !@missing and !@covered );

		push @report, {
			kind       => 'backfill',
			stage      => $s->{no},
			policy     => $s->{policy},
			duration   => $s->{duration_human},
			cut        => ns2iso( $cut ),
			oldest     => ns2iso( $oldest_at_risk ),
			covered    => scalar @covered,
			affected   => scalar @missing,
			names      => shortlist( \@missing ),
			# Which later stage holds it is no longer a single answer - it can be
			# any of them, and for retired measurements it usually is not the next.
			next_stage => join( ", ", map { $_->{policy} } @later ),
		};
		$backfill_needed = 1 if( @missing );
	}

	# --- final: the last stage ----------------------------------------------
	my $last = $stages->[-1];
	if( $last->{duration_secs} ) {
		my $cut  = $now - $last->{duration_secs} * 1e9;
		my $mine = $oldest{ $last->{policy} };
		my (@gone, $oldest_at_risk);
		foreach my $m ( @$names ) {
			# Whichever reaches further back. Before a backfill the last stage is
			# empty and autogen is the only thing that says how old the data is;
			# afterwards - and especially once autogen has been trimmed - the last
			# stage holds the history and autogen no longer does. Taking the minimum
			# is right in both states, and asking only one of them is wrong in one
			# of them.
			my @t = grep { defined } ( $raw->{$m}, $mine->{$m} );
			next if( !@t );
			my ($t) = sort { $a <=> $b } @t;
			next if( $t >= $cut );
			$oldest_at_risk = $t if( !defined $oldest_at_risk or $t < $oldest_at_risk );
			push @gone, $m;
		}
		if( @gone ) {
			push @report, {
				kind     => 'final',
				stage    => $last->{no},
				policy   => $last->{policy},
				duration => $last->{duration_human},
				cut      => ns2iso( $cut ),
				oldest   => ns2iso( $oldest_at_risk ),
				covered  => 0,
				affected => scalar @gone,
				names    => shortlist( \@gone ),
			};
			$final_loss = 1;
		}
	}

	# --- dropped stages ------------------------------------------------------
	# A stage the user has switched off takes its data with it. Nothing in the
	# section above notices that: the policy is not part of the cascade any more,
	# so no cut is computed for it and no successor is looked for. Without this it
	# was possible to delete a fully condensed history of eleven years with no
	# warning at all, as long as nothing else in the configuration lost anything.
	foreach my $name ( @{ obsolete_policies( $stages, $policies ) } ) {
		my $o   = oldest_per_measurement( $name, $names );
		my @has = grep { defined $o->{$_} } @$names;
		next if( !@has );
		my ($t) = sort { $a <=> $b } map { $o->{$_} } @has;
		push @report, {
			kind     => 'drop',
			policy   => $name,
			oldest   => ns2iso( $t ),
			covered  => 0,
			affected => scalar @has,
			names    => shortlist( \@has ),
		};
		$final_loss = 1;
	}

	# How far the raw data reaches back, for the one line of overview the dialogue
	# starts with. Free - the timestamps were fetched above anyway.
	my $first;
	foreach my $m ( @$names ) {
		next if( !defined $raw->{$m} );
		$first = $raw->{$m} if( !defined $first or $raw->{$m} < $first );
	}

	return {
		measurements    => scalar @$names,
		oldest          => ns2iso( $first ),
		stages          => \@report,
		final_loss      => $final_loss,
		backfill_needed => $backfill_needed,
	};
}

# Names, but not all of them - a list of 146 is not something anybody reads in a
# dialogue box, and it would be the bulk of the answer the web interface polls.
sub shortlist
{
	my ($names) = @_;
	my @s = sort @$names;
	return [ @s ] if( scalar @s <= 10 );
	return [ @s[0..9] ];
}

#############################################################################
# How many megabytes are where, and how many a change would free
#############################################################################
# The question the user asks first and the one the old preview could not answer:
# it talked about policies and measurement counts, and nobody outside this file
# knows what "s4l_1h" is or how big it is.
#
# Two queries, both already used elsewhere and both cheap:
#
#   SHOW STATS  gives diskBytes per shard, tagged with the database and the shard
#               id. Not du - the data directory belongs to the influxdb user and
#               du stops at wal/ with 48 KB for a 758 MB database (measured).
#   SHOW SHARDS gives each shard its policy and its time range.
#
# Joined on the shard id, that is the size of every policy split by time. And the
# figure for "what a retention would free" is then not an estimate at all:
# InfluxDB deletes whole shards, never single points, so a shard whose end lies
# before the cut goes entirely and one that straddles it stays entirely.

sub rfc2ns
{
	my ($t) = @_;
	return undef if( !defined $t or $t !~ /^(\d{4})-(\d\d)-(\d\d)T(\d\d):(\d\d):(\d\d)/ );
	require Time::Local;
	return Time::Local::timegm( $6, $5, $4, $3, $2 - 1, $1 ) * 1e9;
}

sub shard_sizes
{
	my %bytes;
	my $st = InfluxInfo::query( "SHOW STATS" );
	foreach my $r ( @$st ) {
		foreach my $s ( @{ $r->{series} || [] } ) {
			next if( ( $s->{name} // '' ) ne 'tsm1_filestore' );
			my $t = $s->{tags} || {};
			next if( ( $t->{database} // '' ) ne $DB or !defined $t->{id} );
			my @c = @{ $s->{columns} || [] };
			my ($di) = grep { $c[$_] eq 'diskBytes' } 0..$#c;
			next if( !defined $di );
			$bytes{ $t->{id} } += ( $_->[$di] // 0 ) foreach @{ $s->{values} || [] };
		}
	}
	return undef if( !%bytes );

	my %out;
	my $sh = InfluxInfo::query( "SHOW SHARDS" );
	foreach my $r ( @$sh ) {
		foreach my $s ( @{ $r->{series} || [] } ) {
			next if( ( $s->{name} // '' ) ne $DB );
			my @c = @{ $s->{columns} || [] };
			my %i = map { $c[$_] => $_ } 0..$#c;
			next if( !defined $i{id} or !defined $i{retention_policy} );
			foreach my $v ( @{ $s->{values} || [] } ) {
				push @{ $out{ $v->[ $i{retention_policy} ] } }, {
					end   => defined $i{end_time} ? rfc2ns( $v->[ $i{end_time} ] ) : undef,
					bytes => $bytes{ $v->[ $i{id} ] } // 0,
				};
			}
		}
	}
	return \%out;
}

sub bytes_of
{
	my ($sizes, $rp, $which, $cut) = @_;
	return 0 if( !$sizes or !$sizes->{$rp} );
	my $n = 0;
	foreach my $s ( @{ $sizes->{$rp} } ) {
		if   ( $which eq 'all' )   { $n += $s->{bytes} }
		elsif( $which eq 'before' ){ $n += $s->{bytes} if( defined $s->{end} and $s->{end} <= $cut ) }
		else                       { $n += $s->{bytes} if( !defined $s->{end} or $s->{end} >  $cut ) }
	}
	return $n;
}

# What a stage costs compared with the raw data it condenses.
#
# Measured on the test installation at a five minute write interval and two
# fields: an hour saved about 3x, six hours 18x, a day 72x. That is the interval
# divided by four write intervals, and it is deliberately the pessimistic reading
# of those three numbers - a point does not only cost its values, it costs its
# timestamp and its place in the index as well.
#
# Below 1 the stage is LARGER than what it replaces. That is not a rounding error
# but the whole reason nothing under an hour is offered, and the preview says so
# in figures rather than only in a warning.
sub condense_factor
{
	my ($interval_secs, $grabber) = @_;
	return undef if( !$grabber or !$interval_secs );
	return $interval_secs / ( $grabber * 4 );
}

# A rough idea of how long a backfill runs, without counting a single value.
#
# count(*) over all measurements was measured at 23.5 s and is far too expensive
# for a preview. The disk size is already known from SHOW STATS, and on the test
# installation 571 MB held 33 267 401 values - about 18 bytes each. The read side
# of the condensing query was measured at 20.6 s for 5.9 million values grouped by
# the hour, so about 3.5 microseconds per value and stage.
#
# This is an order of magnitude and is presented as one. On a Raspberry with an SD
# card it is a multiple of it.
sub estimate_backfill
{
	my ($stages) = @_;
	my $bytes = 0;
	my $res = InfluxInfo::query( "SHOW STATS" );
	foreach my $r ( @$res ) {
		foreach my $s ( @{ $r->{series} || [] } ) {
			next if( ( $s->{name} // '' ) ne 'tsm1_filestore' );
			next if( ( ( $s->{tags} || {} )->{database} // '' ) ne $DB );
			my @c = @{ $s->{columns} || [] };
			my ($di) = grep { $c[$_] eq 'diskBytes' } 0..$#c;
			next if( !defined $di );
			$bytes += ( $_->[$di] // 0 ) foreach @{ $s->{values} || [] };
		}
	}
	my $values = int( $bytes / 18 );
	my $secs   = int( $values * 3.5e-6 * ( scalar(@$stages) - 1 ) );
	return { values => $values, seconds => $secs };
}

#############################################################################
# preview
#############################################################################

# Fills every stage with what it holds today and what it would hold afterwards,
# and adds the total. Modifies $stages and $loss in place.
sub add_sizes
{
	my ($stages, $loss) = @_;

	my $sizes = shard_sizes();
	return if( !$sizes );

	my $grabber = largest_grabber_interval();
	my $now     = time() * 1e9;
	my $raw     = $stages->[0];

	my $total_now   = 0;
	$total_now += bytes_of( $sizes, $_, 'all' ) foreach keys %$sizes;
	my $total_after = 0;

	foreach my $s ( @$stages ) {
		my $cut = $s->{duration_secs} ? ( $now - $s->{duration_secs} * 1e9 ) : undef;

		if( $s->{no} == 1 ) {
			$s->{bytes_now}  = bytes_of( $sizes, 'autogen', 'all' );
			$s->{bytes_drop} = defined $cut ? bytes_of( $sizes, 'autogen', 'before', $cut ) : 0;
			$s->{bytes_after}= $s->{bytes_now} - $s->{bytes_drop};
		}
		else {
			# What this stage condenses is the raw data inside its own window -
			# see the comment on the backfill for why it is its own window and not
			# the whole history.
			my $rawin = defined $cut ? bytes_of( $sizes, 'autogen', 'after', $cut )
			                         : bytes_of( $sizes, 'autogen', 'all' );
			my $f = condense_factor( $s->{interval_secs}, $grabber );
			$s->{bytes_now}   = bytes_of( $sizes, $s->{policy}, 'all' );
			$s->{bytes_rawin} = $rawin;
			$s->{bytes_after} = defined $f ? int( $rawin / $f ) : undef;
			# A stage that costs more than the raw data it stands in for
			$s->{grows}       = ( defined $f and $f < 1 ) ? 1 : 0;
		}
		$total_after += ( $s->{bytes_after} // 0 );
	}

	# Stages that are being switched off take their bytes with them, and they are
	# gone from the total afterwards - so they must not be counted into it.
	foreach my $r ( @{ $loss->{stages} || [] } ) {
		next if( $r->{kind} ne 'drop' );
		$r->{bytes} = bytes_of( $sizes, $r->{policy}, 'all' );
	}

	# The final deletion is already inside stage 1's bytes_drop when there is no
	# downsampling. With downsampling it is what the LAST stage throws away, and
	# that is measured on the last stage's own policy - which today is usually
	# empty, so the honest answer is the share of the raw data of that age.
	foreach my $r ( @{ $loss->{stages} || [] } ) {
		next if( $r->{kind} ne 'final' );
		my $cut = $stages->[-1]->{duration_secs}
		        ? ( $now - $stages->[-1]->{duration_secs} * 1e9 ) : undef;
		next if( !defined $cut );
		$r->{bytes} = bytes_of( $sizes, 'autogen', 'before', $cut )
		            + bytes_of( $sizes, $stages->[-1]->{policy}, 'before', $cut );
	}

	$loss->{sizes} = {
		total_now   => $total_now,
		total_after => $total_after,
		grabber     => $grabber,
	};
	return;
}

sub cmd_preview
{
	my $stages = wanted_stages();
	my ($errors, $warnings) = check_config( $stages );

	my ($policies, $perr) = read_policies();
	if( !$policies ) {
		return { ok => 0, error => "The database is not answering: $perr" };
	}
	my ($cqs, $cerr) = read_cqs();
	$cqs = {} if( !$cqs );

	# A configuration with errors gets no plan and no assessment. Both would be
	# built from settings that cannot be carried out, and showing "this is what
	# would happen" next to "this cannot happen" only reads as a contradiction.
	my $plan = @$errors ? [] : build_plan( $stages, $policies, $cqs );

	# A changed interval on a stage that already holds values.
	#
	# This is new, and it is new because of the naming: a stage is called after its
	# number now, so changing its interval no longer throws the stage away and
	# starts over - it keeps what it has. Which means the older values in it stay
	# at the resolution they were condensed with, and only the new ones arrive at
	# the new one. Nothing is wrong with that data, there is simply more of it in
	# the past than the label promises. Worth saying, not worth destroying a
	# condensed history over.
	if( !@$errors ) {
		foreach my $s ( @$stages ) {
			next if( $s->{no} == 1 or !$policies->{ $s->{policy} } );
			my $have = $cqs->{ $CQ_PREFIX . "stage" . $s->{no} };
			next if( !defined $have );
			my (undef, undef, $secs) = split( /\|/, cq_fingerprint( $have ) );
			next if( !defined $secs or $secs eq 'x' or $secs == $s->{interval_secs} );
			push @$warnings, {
				code     => 'mixedres',
				stage    => $s->{no},
				interval => $s->{interval},
				text     => sprintf(
					"Stage %d already holds values condensed with the previous interval. They keep that resolution; only new values arrive at %s.",
					$s->{no}, $s->{interval} ),
			};
		}
	}
	my $loss = @$errors ? { stages => [], final_loss => 0, backfill_needed => 0 }
	                    : assess_loss( $stages, $policies );
	add_sizes( $stages, $loss ) if( !@$errors );

	return {
		ok       => 1,
		database => $DB,
		config   => {
			duration     => $Globals::retention->{duration},
			downsampling => $Globals::retention->{downsampling},
			aggregates   => $Globals::retention->{aggregates},
		},
		stages   => [ map { { %$_ } } @$stages ],
		current  => { policies => $policies, cqs => $cqs },
		plan     => $plan,
		changes  => scalar @$plan,
		errors   => $errors,
		warnings => $warnings,
		loss     => $loss,
		backfill => ( $loss->{backfill_needed} ? estimate_backfill( $stages ) : undef ),
	};
}

sub print_preview_text
{
	my ($p) = @_;
	binmode( STDOUT, ':encoding(UTF-8)' );

	if( !$p->{ok} ) { print "ERROR: $p->{error}\n"; return }

	printf( "Database: %s\n\n", $p->{database} );

	print "Configured\n";
	foreach my $s ( @{ $p->{stages} } ) {
		printf( "  Stage %d  %-10s -> %-10s  keeps %s%s\n",
			$s->{no}, ( $s->{interval} eq 'raw' ? 'raw data' : $s->{interval} ),
			$s->{policy}, $s->{duration_human}, ( $s->{last} ? " (from the total)" : "" ) );
	}

	print "\nIn the database\n";
	foreach my $n ( sort keys %{ $p->{current}->{policies} } ) {
		my $x = $p->{current}->{policies}->{$n};
		printf( "  %-14s duration %-12s shard %-12s%s\n",
			$n, $x->{duration}, $x->{shard}, ( $x->{default} ? " [default]" : "" ) );
	}
	printf( "  condensations: %s\n",
		( %{ $p->{current}->{cqs} } ? join( ", ", sort keys %{ $p->{current}->{cqs} } ) : "none" ) );

	foreach my $e ( @{ $p->{errors} || [] } )   { print "\nERROR:   $e\n" }
	# A warning is a structure now - code, parameters and an English sentence. The
	# web interface translates it by the code; here only the sentence is wanted.
	foreach my $w ( @{ $p->{warnings} || [] } ) {
		print "\nWARNING: " . ( ref($w) eq 'HASH' ? $w->{text} : $w ) . "\n";
	}

	if( @{ $p->{errors} || [] } ) {
		print "\nThis cannot be carried out. Please correct the settings.\n";
		return;
	}

	print "\nWhat would happen (" . scalar( @{ $p->{plan} } ) . ")\n";
	print "  nothing, it already stands like this\n" if( !@{ $p->{plan} } );
	foreach my $a ( @{ $p->{plan} } ) {
		printf( "  %s%s\n     %s\n", ( $a->{destroys} ? "[DELETES] " : "" ), $a->{text}, $a->{sql} );
	}

	my $l = $p->{loss} || {};

	print "\nWhat happens to the data\n";
	printf( "  today: %s across %d measurements, from %s\n\n",
		mb( ( $l->{sizes} || {} )->{total_now} ), ( $l->{measurements} // 0 ), ( $l->{oldest} // '?' ) );
	foreach my $s ( @{ $p->{stages} } ) {
		printf( "  Stage %d  %-22s keeps %s\n", $s->{no},
			( $s->{no} == 1 ? "raw data" : "average over $s->{interval}" ), $s->{duration_human} );
		if( $s->{no} == 1 ) {
			printf( "           %s today, %s of that drops out, %s stays\n",
				mb($s->{bytes_now}), mb($s->{bytes_drop}), mb($s->{bytes_after}) );
		}
		else {
			printf( "           %s of raw data becomes about %s%s\n",
				mb($s->{bytes_rawin}), mb($s->{bytes_after}),
				( $s->{grows} ? "  <-- LARGER than the raw data it replaces" : "" ) );
		}
	}
	my $z = $l->{sizes} || {};
	if( defined $z->{total_after} ) {
		my $diff = ( $z->{total_now} // 0 ) - $z->{total_after};
		printf( "\n  Bottom line: %s today, about %s afterwards -> %s %s\n",
			mb($z->{total_now}), mb($z->{total_after}),
			( $diff >= 0 ? "saves" : "costs" ), mb( abs $diff ) );
	}

	print "\nConsequences for the data that is there\n";
	if( !@{ $l->{stages} || [] } ) {
		print "  none - nothing that is there falls out of the retention\n";
	}

	foreach my $r ( grep { $_->{kind} eq 'backfill' } @{ $l->{stages} || [] } ) {
		printf( "  Stage %d (%s) keeps %s, cut at %s\n", $r->{stage}, $r->{policy}, $r->{duration}, $r->{cut} );
		printf( "    oldest affected value: %s\n", $r->{oldest} // '?' );
		printf( "    %d measurements are already condensed in a later stage (%s)\n", $r->{covered}, $r->{next_stage} )
			if( $r->{covered} );
		if( $r->{affected} ) {
			printf( "    %d measurements are in no later stage yet - without condensing they would be gone:\n",
				$r->{affected} );
			printf( "      %s\n", $_ ) foreach @{ $r->{names} };
			printf( "      ... and %d more\n", $r->{affected} - scalar @{ $r->{names} } )
				if( $r->{affected} > scalar @{ $r->{names} } );
		}
	}

	foreach my $r ( grep { $_->{kind} eq 'final' } @{ $l->{stages} || [] } ) {
		printf( "\n  FOR GOOD: everything before %s is deleted.\n", $r->{cut} );
		printf( "    The retention is set to %s and the oldest value is from %s.\n",
			$r->{duration}, $r->{oldest} // '?' );
		printf( "    %d measurements are affected:\n", $r->{affected} );
		printf( "      %s\n", $_ ) foreach @{ $r->{names} };
		printf( "      ... and %d more\n", $r->{affected} - scalar @{ $r->{names} } )
			if( $r->{affected} > scalar @{ $r->{names} } );
		print   "    No condensation can catch this - after the last stage there is nothing left.\n";
	}

	foreach my $r ( grep { $_->{kind} eq 'drop' } @{ $l->{stages} || [] } ) {
		printf( "\n  FOR GOOD: the stage \"%s\" you switched off is deleted with its data.\n", $r->{policy} );
		printf( "    %d measurements with condensed values from %s:\n", $r->{affected}, $r->{oldest} // '?' );
		printf( "      %s\n", $_ ) foreach @{ $r->{names} };
		printf( "      ... and %d more\n", $r->{affected} - scalar @{ $r->{names} } )
			if( $r->{affected} > scalar @{ $r->{names} } );
	}

	if( $l->{backfill_needed} ) {
		my $b = $p->{backfill} || {};
		printf( "\n  Condensing the history is needed. Roughly %d values, about %d minutes\n",
			( $b->{values} // 0 ), int( ( $b->{seconds} // 0 ) / 60 ) );
		print   "  on a PC - a multiple of that on a Raspberry.\n";
	}
	if( $l->{backfill_needed} or $l->{final_loss} ) {
		printf( "\n  Call: s4l_retention.pl apply%s%s\n",
			( $l->{backfill_needed} ? " --backfill" : "" ),
			( $l->{final_loss}      ? " --force"    : "" ) );
	}
	return;
}

#############################################################################
# backfill
#############################################################################
# Condenses the history that is already there. Continuous queries do NOT do this -
# measured: they only ever look at data that arrives after they were created.
#
# Every stage reads from autogen, for the reason at the top of this file. The work
# is chunked by calendar year, per measurement: it bounds what one statement has
# to hold, it makes the progress real instead of a spinner, and a run that dies
# halfway has still done everything up to that point - INTO overwrites points with
# the same timestamp and tags, so running it again costs time and nothing else.

sub backfill_one
{
	my ($stage, $name, $from_ns, $to_ns) = @_;

	my $agg = join( ", ", map { "$_(*)" } @{ $Globals::retention->{aggregates} } );
	( my $safe = $name ) =~ s/"/\\"/g;

	# fill(none) so that the empty intervals - and over eleven years there are
	# many - are not written as rows of nulls.
	my $sql = sprintf(
		'SELECT %s INTO "%s"."%s".:MEASUREMENT FROM "%s"."autogen"."%s" WHERE time >= %d AND time < %d GROUP BY time(%s), * fill(none)',
		$agg, $DB, $stage->{policy}, $DB, $safe, $from_ns, $to_ns, $stage->{interval} );

	my ($ok, $res, $err) = influx( $sql );

	# "partial write ... outside retention policy" is not a failure, it is the
	# boundary. A chunk that straddles the start of the target policy's window has
	# points on both sides of it, and InfluxDB writes the ones inside and reports
	# the ones outside. It also happens at the exact edge, because "now" moves on
	# between building the statement and the write landing. Treated as an error
	# this turned a correct run into thirteen red lines and exit code 1.
	if( !$ok and defined $err and $err =~ /outside retention policy/ ) {
		$ok = 1;
	}
	return ( 0, 0, $err ) if( !$ok );

	# The answer of an INTO query is one row with the number of points written
	my $written = 0;
	foreach my $r ( @$res ) {
		foreach my $s ( @{ $r->{series} || [] } ) {
			my @c = @{ $s->{columns} || [] };
			my ($wi) = grep { $c[$_] eq 'written' } 0..$#c;
			next if( !defined $wi );
			$written += ( $_->[$wi] // 0 ) foreach @{ $s->{values} || [] };
		}
	}
	return ( 1, $written, undef );
}

sub year_bounds
{
	my ($year) = @_;
	require Time::Local;
	my $from = Time::Local::timegm( 0, 0, 0, 1, 0, $year );
	my $to   = Time::Local::timegm( 0, 0, 0, 1, 0, $year + 1 );
	return ( $from * 1e9, $to * 1e9 );
}

# $keep_running: set when this is the first half of an apply. Without it the
# status file goes to running => 0 the moment the condensing is done, and the page
# polling it announces "finished" while the retention has not been touched yet -
# measured, the poll landed exactly in that gap.
sub cmd_backfill
{
	my ($stages, $keep_running) = @_;
	$stages //= wanted_stages();

	my @targets = grep { $_->{no} > 1 } @$stages;
	@targets = grep { $_->{no} == $opt_stage } @targets if( $opt_stage );
	if( !@targets ) {
		LOGW "No stage to condense into - condensing is off, or the chosen stage is not active.";
		return 1;
	}

	my $names = InfluxInfo::measurements();
	if( $opt_measurement ) {
		$names = [ grep { $_ eq $opt_measurement } @$names ];
		if( !@$names ) {
			LOGE "There is no measurement called \"$opt_measurement\".";
			return 0;
		}
	}

	# The range to work over, per measurement. Costs one batched query pair and
	# saves scanning years in which a measurement did not exist yet.
	my $span = InfluxInfo::timestamps( $names );

	my $thisyear = (gmtime)[5] + 1900;
	my $now      = time() * 1e9;

	# Where a stage's condensing has to start, and this is the correction that
	# only the real database revealed.
	#
	# It used to be "the whole history, into every stage", and InfluxDB threw most
	# of it away: a policy REFUSES a write older than its own retention - "dropped
	# ... outside retention policy ... violates a Retention Policy Lower Bound".
	# Condensing eleven years into a stage that keeps one is not merely wasteful,
	# it writes nothing at all.
	#
	# And it should never have been asked for. A stage is responsible for exactly
	# its own window: the hourly stage for the last year, the daily one for the
	# last ten. What is older belongs to the next stage, not to this one.
	my %from;
	foreach my $s ( @targets ) {
		$from{ $s->{no} } = $s->{duration_secs} ? ( $now - $s->{duration_secs} * 1e9 ) : 0;
	}

	# Which calendar years a stage has to walk for a measurement
	my $years = sub {
		my ($stage, $m) = @_;
		my $f = $span->{$m}->{first};
		my $l = $span->{$m}->{last};
		return () if( !defined $f or !defined $l );
		my $start = $from{ $stage->{no} };
		$f = $start if( $start and $start > $f );
		return () if( $f > $l );
		my $y0 = (gmtime( int($f/1e9) ))[5] + 1900;
		my $y1 = (gmtime( int($l/1e9) ))[5] + 1900;
		$y1 = $thisyear if( $y1 > $thisyear );
		return ( $y0 .. $y1 );
	};

	# The whole job as one ordered list, built before anything runs.
	#
	# Two things fall out of that and both were worth the rewrite. Counting is
	# exact - the old count called the year generator in SCALAR context, where
	# ".." is the flip-flop operator and not a range, and the progress ran past
	# its own total in front of the user. And a chunk now has a POSITION, which is
	# what makes it possible to carry on where an interrupted run stopped.
	my @chunks;
	foreach my $stage ( @targets ) {
		foreach my $m ( sort @$names ) {
			foreach my $y ( $years->( $stage, $m ) ) {
				my ($from, $to) = year_bounds( $y );
				# The first chunk starts where the stage's window starts, not at
				# New Year - otherwise every run would offer the target policy a
				# few weeks of points it is bound to refuse.
				$from = $from{ $stage->{no} }
					if( $from{ $stage->{no} } and $from{ $stage->{no} } > $from );
				push @chunks, { stage => $stage, m => $m, year => $y, from => $from, to => $to };
			}
		}
	}
	my $total = scalar @chunks;

	# Carrying on after an interruption.
	#
	# Nothing is ever damaged by starting over - INTO overwrites the same points,
	# so a repeated chunk costs time and nothing else. But on a Raspberry the
	# whole run is hours, and losing all of it to a power cut ten minutes before
	# the end is not something anybody should have to accept.
	#
	# The position is only trusted when the settings have not changed since -
	# otherwise it points into a list that no longer exists.
	my $start = 0;
	if( $opt_resume ) {
		# Erst die dauerhafte Datei - nach einem Neustart ist die Ramdisk leer, und
		# genau dann wird fortgesetzt.
		my $st = read_progress();
		$st = read_status() if( ref($st->{cursor}) ne "HASH" );
		if( ( $st->{fingerprint} // '' ) ne config_fingerprint( $stages ) ) {
			LOGW "The settings have changed since the interrupted run - starting from the beginning.";
		}
		elsif( ref($st->{cursor}) eq 'HASH' ) {
			my $c = $st->{cursor};
			for( my $i = 0; $i < $total; $i++ ) {
				next if( $chunks[$i]->{stage}->{no} != ( $c->{stage} // -1 ) );
				next if( $chunks[$i]->{m}          ne ( $c->{measurement} // '' ) );
				next if( $chunks[$i]->{year}       != ( $c->{year} // -1 ) );
				$start = $i + 1;
				last;
			}
			if( $start ) {
				LOG sprintf( "Carrying on after the interruption: %d of %d chunks were already done.",
				             $start, $total );
			}
			else {
				LOGW "The position of the interrupted run is not in this job - starting from the beginning.";
			}
		}
	}

	LOG sprintf( "Condensing the history: %d measurements, %d stage(s), %d chunks",
	             scalar @$names, scalar @targets, $total );
	LOG "With a lot of data this can take hours. This logfile follows along.";

	status( running => 1, step => 'backfill', total => $total, done => $start,
	        written => 0, current => '', started => time(), error => '', pid => $$,
	        fingerprint => config_fingerprint( $stages ), cursor => undef );

	my $done    = $start;
	my $written = 0;
	my $failed  = 0;
	my $t_all   = Time::HiRes::time();
	my $laststage = 0;
	my ($t0, $sub, $lastm) = ( Time::HiRes::time(), 0, undef );

	for( my $i = $start; $i < $total; $i++ ) {
		my $c = $chunks[$i];

		if( $c->{stage}->{no} != $laststage ) {
			$laststage = $c->{stage}->{no};
			LOG sprintf( "Stage %d: condenses to %s, writes into %s",
			             $c->{stage}->{no}, $c->{stage}->{interval}, $c->{stage}->{policy} );
		}
		if( !defined $lastm or $c->{m} ne $lastm ) {
			LOG sprintf( "  %-30s %8d points in %5.1f s", $lastm, $sub, Time::HiRes::time() - $t0 )
				if( defined $lastm );
			( $lastm, $sub, $t0 ) = ( $c->{m}, 0, Time::HiRes::time() );
		}

		my ($ok, $n, $err) = backfill_one( $c->{stage}, $c->{m}, $c->{from}, $c->{to} );
		$done++;
		if( $ok ) { $sub += $n; $written += $n }
		else {
			$failed++;
			LOGE "  $c->{m} $c->{year}: $err";
		}
		# The cursor is written with every chunk - it is what a resumed run reads.
		status( done => $done, written => $written,
		        current => sprintf( "%s %d (stage %d)", $c->{m}, $c->{year}, $c->{stage}->{no} ),
		        cursor  => { stage => $c->{stage}->{no}, measurement => $c->{m}, year => $c->{year} } );
		write_progress(
			force       => ( $i == $start ),
			step        => "backfill",
			done        => $done,
			total       => $total,
			fingerprint => config_fingerprint( $stages ),
			cursor      => { stage => $c->{stage}->{no}, measurement => $c->{m}, year => $c->{year} },
		);
	}
	LOG sprintf( "  %-30s %8d points in %5.1f s", $lastm, $sub, Time::HiRes::time() - $t0 )
		if( defined $lastm );

	my $secs = Time::HiRes::time() - $t_all;
	if( $failed ) {
		LOGW sprintf( "Condensing finished with %d errors: %d points in %.0f s", $failed, $written, $secs );
	}
	else {
		LOGO sprintf( "Condensing done: %d points in %.0f s", $written, $secs );
	}
	# Die Liste ist durch - ein Fortsetzungspunkt waere ab hier eine Luege.
	clear_progress();
	status( ( $keep_running ? () : ( running => 0, finished => time() ) ),
	        done => $done, written => $written, current => '', failed => $failed,
	        cursor => undef );

	return $failed ? 0 : 1;
}

#############################################################################
# apply
#############################################################################

sub cmd_apply
{
	my $stages = wanted_stages();
	my ($errors, $warnings) = check_config( $stages );

	if( @$errors ) {
		LOGE $_ foreach @$errors;
		LOGE "Nothing changed.";
		status( running => 0, step => 'apply', error => join( " ", @$errors ), finished => time() );
		return 0;
	}
	LOGW $_->{text} foreach @$warnings;

	my ($policies, $perr) = read_policies();
	if( !$policies ) {
		LOGE "The database is not answering: $perr";
		status( running => 0, step => 'apply', error => $perr, finished => time() );
		return 0;
	}
	my ($cqs) = read_cqs();
	$cqs = {} if( !$cqs );

	my $loss = assess_loss( $stages, $policies );

	# The two refusals this whole script exists for.
	#
	# The final one is checked FIRST and before anything is created, because it is
	# the one that used to slip through: it only becomes measurable once the last
	# stage has data, so a run that backfilled first found out too late.
	if( $loss->{final_loss} and !$opt_force ) {
		foreach my $r ( @{ $loss->{stages} } ) {
			if( $r->{kind} eq 'final' ) {
				LOGE sprintf( "Everything before %s is deleted for good - %d measurements are older.",
				              $r->{cut}, $r->{affected} );
				LOGE "That is exactly what the retention of $r->{duration} you set means.";
			}
			elsif( $r->{kind} eq 'drop' ) {
				LOGE sprintf( "The stage \"%s\" you switched off is deleted, with the condensed data of %d measurements from %s.",
				              $r->{policy}, $r->{affected}, $r->{oldest} // '?' );
			}
		}
		LOGE "No condensation can catch this. Confirm with --force.";
		status( running => 0, step => 'apply', error => 'final_loss', finished => time() );
		return 0;
	}

	if( $loss->{backfill_needed} and !$opt_backfill and !$opt_force ) {
		LOGE "There is data that would be deleted and that is not in the next stage yet.";
		LOGE "Either condense the history first with --backfill, or accept the loss with --force.";
		foreach my $r ( @{ $loss->{stages} } ) {
			next if( $r->{kind} ne 'backfill' or !$r->{affected} );
			LOGE sprintf( "  Stage %d: %d measurements, oldest value %s", $r->{stage}, $r->{affected}, $r->{oldest} // '?' );
		}
		status( running => 0, step => 'apply', error => 'backfill_needed', finished => time() );
		return 0;
	}

	# Nachverdichten first, and only then delete. In the other order the backfill
	# would read data that autogen has already dropped.
	if( $loss->{backfill_needed} and $opt_backfill ) {
		LOG "Condense the history first, then apply.";

		# Only the policies have to exist for the backfill to have somewhere to
		# write - the continuous queries and the retention on autogen come after.
		my $plan = build_plan( $stages, $policies, $cqs );
		foreach my $a ( @$plan ) {
			next if( $a->{kind} ne 'create_rp' and $a->{kind} ne 'alter_rp' );
			return 0 if( !run_action( $a ) );
		}

		( $policies ) = read_policies();
		return 0 if( !cmd_backfill( $stages, 1 ) );

		# Asked again rather than assumed: if the backfill did not reach far enough
		# back, deleting now would still destroy history.
		$loss = assess_loss( $stages, $policies );
		if( $loss->{backfill_needed} and !$opt_force ) {
			LOGE "Data is still missing in the next stage after condensing. Nothing is deleted.";
			status( running => 0, step => 'apply', error => 'backfill_incomplete', finished => time() );
			return 0;
		}
	}

	( $cqs ) = read_cqs();
	$cqs = {} if( !$cqs );
	my $plan = build_plan( $stages, $policies, $cqs );

	if( !@$plan ) {
		LOGO "The database already stands as configured - nothing to do.";
		status( running => 0, step => 'apply', done => 0, total => 0, finished => time() );
		return 1;
	}

	status( running => 1, step => 'apply', total => scalar @$plan, done => 0,
	        error => '', started => time(), pid => $$ );

	my $done = 0;
	foreach my $a ( @$plan ) {
		if( !run_action( $a ) ) {
			status( running => 0, done => $done, error => $a->{text}, finished => time() );
			return 0;
		}
		$done++;
		status( done => $done, current => $a->{text} );
	}

	LOGO "Done. " . scalar(@$plan) . " change(s) to the database.";
	LOG  "InfluxDB only tidies up every 60 minutes - the space is freed after that."
		if( grep { $_->{destroys} } @$plan );

	status( running => 0, done => $done, current => '', finished => time() );
	return 1;
}

sub run_action
{
	my ($a) = @_;
	LOG $a->{text};
	my ($ok, $res, $err) = influx( $a->{sql} );
	if( !$ok ) {
		LOGE "  failed: $err";
		LOGE "  $a->{sql}";
		return 0;
	}
	return 1;
}

#############################################################################
# Dispatch
#############################################################################

if( $command eq 'preview' ) {
	my $p = cmd_preview();
	if( $opt_text ) { print_preview_text( $p ) }
	# encode_json returns UTF-8 bytes, so STDOUT must NOT carry an encoding layer
	# here - the measurement names would otherwise be encoded a second time.
	else            { print JSON::encode_json( $p ) }
	exit( $p->{ok} ? 0 : 1 );
}
elsif( $command eq 'apply' ) {
	openlog( 'apply' );
	if( !take_lock() ) { LOGEND; exit 1 }
	my $ok = cmd_apply();
	LOGEND;
	exit( $ok ? 0 : 1 );
}
elsif( $command eq 'backfill' ) {
	openlog( 'backfill' );
	if( !take_lock() ) { LOGEND; exit 1 }
	my $stages = wanted_stages();
	my ($errors) = check_config( $stages );
	if( @$errors ) {
		LOGE $_ foreach @$errors;
		LOGEND;
		exit 1;
	}
	# The target policies have to exist before anything can be written into them
	my ($policies) = read_policies();
	if( $policies ) {
		foreach my $a ( @{ build_plan( $stages, $policies, {} ) } ) {
			next if( $a->{kind} ne 'create_rp' and $a->{kind} ne 'alter_rp' );
			run_action( $a );
		}
	}
	my $ok = cmd_backfill( $stages );
	LOGEND;
	exit( $ok ? 0 : 1 );
}
elsif( $command eq 'status' ) {
	if( open( my $fh, '<', $STATUSFILE ) ) {
		local $/;
		print <$fh>;
		close $fh;
	}
	else { print '{"running":0}' }
	exit 0;
}
else {
	print STDERR "Usage: s4l_retention.pl preview [--text]\n";
	print STDERR "       s4l_retention.pl apply [--backfill] [--force]\n";
	print STDERR "       s4l_retention.pl backfill [--stage <n>] [--measurement <name>]\n";
	print STDERR "       s4l_retention.pl status\n";
	print STDERR "\n";
	print STDERR "       --database <name>  work on a throwaway copy instead of the real one\n";
	print STDERR "       --config <json>    preview these settings instead of the saved ones\n";
	exit 1;
}
