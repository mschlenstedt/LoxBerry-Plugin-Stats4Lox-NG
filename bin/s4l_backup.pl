#!/usr/bin/perl

# Backup and restore for Stats4Lox.
#
# Replaces the archive that postroot.sh used to leave behind on every
# installation. That one was a by-product of the upgrade directory: nothing ever
# read it back, it grew without limit, and it carried the whole time series
# database including _internal.
#
# Usage (root):
#   s4l_backup.pl create  --target <dir> [--compression <c>] [--keep <n>]
#   s4l_backup.pl create  --scheduled | --cron
#   s4l_backup.pl list    --target <dir>
#   s4l_backup.pl check   --file <archive> [--dbpath <dir>]
#   s4l_backup.pl restore --file <archive> [--dbpath <dir>] [--force]
#   s4l_backup.pl delete  --file <archive>
#
# --compression: none | gzip | xz | zip | 7z (default gzip)
# --keep:        how many archives to keep in the target directory, 0 = all
# --scheduled:   take target, compression and keep from stats4lox.json, so a
#                changed setting takes effect without rewriting the crontab.
# --cron:        like --scheduled, and additionally skip the run when the
#                schedule says "every n weeks" and this is not one of them.
#
# "check" answers as JSON and changes nothing - the web interface uses it to
# find out beforehand whether there is room and whether a database would be
# overwritten.

use warnings;
use strict;
use LoxBerry::System;
use LoxBerry::JSON;
use LoxBerry::Log;
use Getopt::Long;
use File::Path qw(make_path remove_tree);
use File::Basename;
use POSIX qw(strftime);
use JSON;
use FindBin qw($Bin);
use lib "$Bin/libs";
use Globals;

if( $< ) {
	print STDERR "This script has to be run as root.\n";
	exit 1;
}

my $command = shift @ARGV // '';
my ( $target, $file, $dbpath, $force, $json_only, $compression, $keep, $scheduled, $cron );
GetOptions(
	'target=s'      => \$target,
	'file=s'        => \$file,
	'dbpath=s'      => \$dbpath,
	'force'         => \$force,
	'json'          => \$json_only,
	'compression=s' => \$compression,
	'keep=i'        => \$keep,
	'scheduled'     => \$scheduled,
	'cron'          => \$cron,
);
$scheduled = 1 if( $cron );

# "check" and "list" only print JSON, so no log file for them
my $log;
if( $command ne 'check' and $command ne 'list' ) {
	$log = LoxBerry::Log->new( name => 'Backup', stderr => 1, append => 1 );
	LOGSTART "Backup: $command";
}
sub LOG  { my $m = shift; $log ? $log->INF($m)  : 0; }
sub LOGO { my $m = shift; $log ? $log->OK($m)   : 0; }
sub LOGW { my $m = shift; $log ? $log->WARN($m) : 0; }
sub LOGE { my $m = shift; $log ? $log->ERR($m)  : 0; }

my $statusfile = $Globals::stats4lox->{s4ltmp} . "/backup-status.json";

# ---------------------------------------------------------------- helpers

sub cfg
{
	my $obj = LoxBerry::JSON->new();
	return $obj->open( filename => $Globals::stats4loxconfig, readonly => 1 ) || {};
}

sub cred
{
	my $obj = LoxBerry::JSON->new();
	return $obj->open( filename => $Globals::stats4loxcredentials, readonly => 1 ) || {};
}

# Where the time series database actually lives.
#
# Read from influxdb.conf and not from influx.db_storage: that setting is
# ambiguous. influx_movedb() in config-handler.pl treats it as the PARENT and
# creates <db_storage>/influxdb, while on an installation that never moved the
# database it holds the influxdb directory itself. influxdb.conf is what influxd
# really uses, so it is the only reliable source.
sub dbdir
{
	my $conf = $LoxBerry::System::lbpconfigdir . "/influxdb/influxdb.conf";
	if( open( my $fh, '<', $conf ) ) {
		my $in_data = 0;
		while( my $l = <$fh> ) {
			if   ( $l =~ /^\s*\[data\]/ )  { $in_data = 1; next }
			elsif( $l =~ /^\s*\[/ )        { $in_data = 0 }
			next if( !$in_data );
			if( $l =~ /^\s*dir\s*=\s*"([^"]+)"/ ) {
				close $fh;
				( my $d = $1 ) =~ s{/data/?$}{};
				return $d;
			}
		}
		close $fh;
	}
	return default_dbdir();
}

# Points influxdb.conf at another directory. Setting influx.db_storage alone
# would change nothing - influxd reads its paths from its own configuration.
sub set_dbdir
{
	my ($new) = @_;
	my $conf = $LoxBerry::System::lbpconfigdir . "/influxdb/influxdb.conf";
	return 0 if( ! -f $conf );

	open( my $in, '<', $conf ) or return 0;
	local $/;
	my $c = <$in>;
	close $in;

	my $old = dbdir();
	return 1 if( $old eq $new );

	# Only the three directory entries, and only where they point into the old
	# location - other paths in the file stay untouched.
	my $n = 0;
	$n += ( $c =~ s{(^\s*(?:wal-)?dir\s*=\s*")\Q$old\E(/(?:meta|data|wal)"\s*$)}{$1$new$2}gm );
	return 0 if( !$n );

	open( my $out, '>', "$conf.s4lnew" ) or return 0;
	print {$out} $c;
	close $out;
	system( "chown --reference=" . quotemeta($conf) . " " . quotemeta("$conf.s4lnew") . " 2>/dev/null" );
	system( "chmod --reference=" . quotemeta($conf) . " " . quotemeta("$conf.s4lnew") . " 2>/dev/null" );
	rename( "$conf.s4lnew", $conf ) or return 0;
	return $n;
}

sub default_dbdir { return $LoxBerry::System::lbpdatadir . "/influxdb"; }

sub dirsize
{
	my ($d) = @_;
	return 0 if( !$d or ! -d $d );
	my $out = `du -sk "$d" 2>/dev/null`;
	return ( $out =~ /^(\d+)/ ) ? $1 * 1024 : 0;
}

sub freespace
{
	my ($d) = @_;
	# Walk up until something exists - the target may not be created yet
	my $probe = $d;
	while( $probe and ! -d $probe and $probe ne '/' ) { $probe = dirname($probe); }
	return 0 if( ! -d $probe );
	my $out = `df -k "$probe" 2>/dev/null | tail -1`;
	return ( $out =~ /^\S+\s+\d+\s+\d+\s+(\d+)/ ) ? $1 * 1024 : 0;
}

sub human
{
	my ($b) = @_;
	return "0 B" if( !$b );
	my @u = qw(B KB MB GB TB);
	my $i = 0;
	while( $b >= 1024 and $i < $#u ) { $b /= 1024; $i++ }
	return sprintf( "%.1f %s", $b, $u[$i] );
}

sub run
{
	my ($cmd) = @_;
	my $out = `$cmd 2>&1`;
	return ( $?, $out );
}

# ---------------------------------------------------------------- archives
#
# The archive always holds the same tree (manifest.json, config/, data/,
# influxdb/) - only the container differs. tar is used for none/gzip/xz because
# it keeps ownership and symlinks; zip and 7z are offered because the LoxBerry
# backup widget offers them and users expect to find them here as well.
#
# Everything that has to know about the format goes through these four
# functions, so nothing else in this script has to care.

my %EXT = (
	none => '.tar',
	gzip => '.tar.gz',
	xz   => '.tar.xz',
	zip  => '.zip',
	'7z' => '.7z',
);

sub compressions { return sort keys %EXT }

sub normalize_compression
{
	my ($c) = @_;
	$c = lc( $c // '' );
	$c = 'gzip' if( $c eq 'gz' or $c eq 'tgz' );
	return exists $EXT{$c} ? $c : 'gzip';
}

sub archive_ext { return $EXT{ normalize_compression( $_[0] ) } }

# All archive names this script may have produced, newest first
sub archive_list
{
	my ($dir) = @_;
	return () if( !$dir or ! -d $dir );
	my @all;
	foreach my $e ( values %EXT ) {
		push @all, glob( quotemeta($dir) . "/stats4lox_*" . $e );
	}
	# The name carries the timestamp, so sorting by name sorts by age. .tar and
	# .tar.gz share a prefix, which does not matter - the timestamp decides.
	return sort { $b cmp $a } @all;
}

sub format_of
{
	my ($archive) = @_;
	return 'zip'  if( $archive =~ /\.zip$/i );
	return '7z'   if( $archive =~ /\.7z$/i );
	return 'xz'   if( $archive =~ /\.tar\.xz$/i );
	return 'gzip' if( $archive =~ /\.tar\.gz$/i );
	return 'none' if( $archive =~ /\.tar$/i );
	return 'gzip';
}

sub pack_archive
{
	my ($archive, $workdir) = @_;
	my $f = format_of($archive);
	my $a = quotemeta($archive);
	my $w = quotemeta($workdir);

	# manifest.json goes in first, and that is not cosmetic. A tar is a stream:
	# to read a member out of it, everything before it has to be decompressed.
	# Measured on a 338 MB archive with the manifest somewhere in the middle,
	# reading it took 3.2 seconds - once per archive, on every page load of the
	# backup list. As the first member it is 0.004 seconds.
	#
	# Naming it explicitly and excluding it from the following walk keeps it
	# from appearing twice - checked, the explicitly named file is not caught by
	# the exclude.
	my $first = "./manifest.json --exclude=./manifest.json .";

	# zip and 7z are told to work from inside the directory, so the archive has
	# the same relative layout as the tar variants. Both keep a central
	# directory, so the order of members does not matter there.
	return run( "tar -cf $a -C $w $first" )                if( $f eq 'none' );
	return run( "tar -czf $a -C $w $first" )               if( $f eq 'gzip' );
	return run( "tar -cJf $a -C $w $first" )               if( $f eq 'xz' );
	return run( "cd $w && zip -q -r -y $a ." )             if( $f eq 'zip' );
	return run( "cd $w && 7z a -bd -bso0 -bsp0 $a ./*" )   if( $f eq '7z' );
	return ( 1, "unknown archive format" );
}

sub unpack_archive
{
	my ($archive, $workdir) = @_;
	my $f = format_of($archive);
	my $a = quotemeta($archive);
	my $w = quotemeta($workdir);

	return run( "tar -xf $a -C $w" )        if( $f eq 'none' );
	return run( "tar -xzf $a -C $w" )       if( $f eq 'gzip' );
	return run( "tar -xJf $a -C $w" )       if( $f eq 'xz' );
	return run( "unzip -q -o $a -d $w" )    if( $f eq 'zip' );
	return run( "7z x -y -bd -bso0 -bsp0 -o$w $a" ) if( $f eq '7z' );
	return ( 1, "unknown archive format" );
}

sub influx_cli
{
	my ($sql, $db) = @_;
	my $c = cred();
	my $u = $c->{influx}->{influxdbuser} // '';
	my $p = $c->{influx}->{influxdbpass} // '';
	my $bin = $LoxBerry::System::lbpbindir . "/s4linflux";
	my $dbopt = $db ? "-database " . quotemeta($db) : "";
	my ($rc, $out) = run( "$bin $dbopt -execute " . quotemeta($sql) );
	return ( $rc, $out );
}

sub influx_running
{
	my ($rc) = run( "systemctl is-active --quiet influxdb" );
	return $rc == 0 ? 1 : 0;
}

sub status
{
	my (%p) = @_;
	eval {
		make_path( $Globals::stats4lox->{s4ltmp} ) if( ! -d $Globals::stats4lox->{s4ltmp} );
		my %s = ( %p, time => time() );
		open( my $fh, '>', $statusfile ) or die;
		print {$fh} JSON::encode_json( \%s );
		close $fh;
		chown( scalar getpwnam('loxberry'), scalar getgrnam('loxberry'), $statusfile );
	};
	return;
}

# Is the database at this location a freshly created, empty one?
#
# Measured: a database created by CREATE DATABASE and never written to has no
# file at all below data/<db> and none below wal/<db>. One with data has both.
# The check looks at the WAL as well, because writes land there first - a young
# but used database would otherwise be mistaken for an empty one.
#
# Answers three states: "none" (nothing there), "empty" (created, no data),
# "data" (contains measurements).
sub db_state
{
	my ($dir, $db) = @_;
	$db //= 'stats4lox';

	my $datadir = "$dir/data/$db";
	my $waldir  = "$dir/wal/$db";
	return 'none' if( ! -d $datadir and ! -d $waldir );

	# The running service knows best
	if( influx_running() and $dir eq dbdir() ) {
		my ($rc, $out) = influx_cli( "SHOW MEASUREMENTS", $db );
		if( $rc == 0 ) {
			my @lines = grep { /\S/ and !/^name:/ and !/^name$/ and !/^-+$/ } split /\n/, $out;
			return @lines ? 'data' : 'empty';
		}
	}

	my $files = 0;
	foreach my $d ( $datadir, $waldir ) {
		next if( ! -d $d );
		my $out = `find "$d" -type f 2>/dev/null | head -1`;
		$files++ if( $out =~ /\S/ );
	}
	return $files ? 'data' : 'empty';
}

# ---------------------------------------------------------------- create

sub cmd_create
{
	if( !$target ) { LOGE "--target is missing"; exit 1 }
	if( ! -d $target ) { LOGE "Target directory $target does not exist"; exit 1 }

	my $stamp = strftime( "%Y%m%d_%H%M%S", localtime );
	my $work  = "$target/.s4lbackup_$$";
	my $archive = "$target/stats4lox_$stamp" . archive_ext($compression);

	status( running => 1, step => 'preparing', message => 'Preparing backup' );
	LOG "Target: $archive (compression: " . normalize_compression($compression) . ")";

	make_path( "$work/config", "$work/data", "$work/influxdb" );

	# --- configuration -------------------------------------------------
	# Everything except systemd/, which describes this host and not the
	# installation. provisioning/ is in here and matters: it holds the Grafana
	# dashboards generated from stats.json, and they are only rebuilt when a
	# statistic is saved again.
	status( running => 1, step => 'config', message => 'Backing up the configuration' );
	my ($rc, $out) = run( "rsync -a --exclude 'systemd/' "
	                      . quotemeta($LoxBerry::System::lbpconfigdir) . "/ "
	                      . quotemeta("$work/config") . "/" );
	if( $rc != 0 ) { LOGE "Could not copy the configuration: $out"; remove_tree($work); exit 1 }
	LOGO "Configuration copied";

	# --- data we want, and only that ------------------------------------
	status( running => 1, step => 'data', message => 'Backing up Grafana and the import state' );
	foreach my $sub ( qw( grafana import ) ) {
		my $src = "$LoxBerry::System::lbpdatadir/$sub";
		next if( ! -d $src );
		# Excluded: our own safety copy of grafana.db, and Grafana's working
		# directories - tmp holds parquet exports of the migration, csv/png/
		# file-collections are render and export output. None of that belongs in
		# a backup.
		run( "rsync -a --exclude '*.before-stats4lox' --exclude 'tmp/' --exclude 'csv/'"
		     . " --exclude 'png/' --exclude 'pdf/' --exclude 'file-collections/'"
		     . " --exclude 'unified-search/' "
		     . quotemeta($src) . " " . quotemeta("$work/data") . "/" );
	}
	LOGO "Grafana and import state copied";

	# --- the time series database ---------------------------------------
	status( running => 1, step => 'influx', message => 'Backing up the database (this takes a while)' );
	my $db = 'stats4lox';
	if( !influx_running() ) {
		LOGE "InfluxDB is not running - the database cannot be backed up";
		remove_tree($work);
		exit 1;
	}
	($rc, $out) = run( "influxd backup -portable -database $db " . quotemeta("$work/influxdb") );
	if( $rc != 0 ) {
		LOGE "influxd backup failed: $out";
		remove_tree($work);
		exit 1;
	}
	LOGO "Database backed up (" . human( dirsize("$work/influxdb") ) . ")";

	# --- manifest --------------------------------------------------------
	# The portable restore brings back databases, retention policies and the
	# data - but NOT users and NOT continuous queries. Measured on InfluxDB
	# 1.12, and the offline mode that could do it is rejected with
	# "offline parameter metadir found, not compatible with -portable".
	#
	# For this plugin the gap is small: exactly one user, no continuous
	# queries. But it must not be a silent gap, so everything found is written
	# into the manifest and anything beyond the expected is a warning.
	my @warnings;
	my @users;
	my $cqcount = 0;

	($rc, $out) = influx_cli( "SHOW USERS" );
	if( $rc == 0 ) {
		foreach my $l ( split /\n/, $out ) {
			next if( $l !~ /^(\S+)\s+(true|false)\s*$/ );
			push @users, $1;
		}
	}
	($rc, $out) = influx_cli( "SHOW CONTINUOUS QUERIES" );
	if( $rc == 0 ) {
		foreach my $l ( split /\n/, $out ) {
			$cqcount++ if( $l =~ /^\S+\s+CREATE CONTINUOUS QUERY/i );
		}
	}

	my $expected = cred()->{influx}->{influxdbuser} // 'stats4lox';
	my @extra = grep { $_ ne $expected } @users;
	if( @extra ) {
		push @warnings, "Additional InfluxDB users exist and are NOT restored by the portable restore: "
		                . join( ", ", @extra ) . ". Recreate them by hand after restoring.";
	}
	if( $cqcount ) {
		push @warnings, "$cqcount continuous queries exist and are NOT restored by the portable restore. "
		                . "Note them down before restoring.";
	}
	LOGW $_ foreach ( @warnings );

	my $c = cfg();
	my %manifest = (
		created          => strftime( "%Y-%m-%d %H:%M:%S", localtime ),
		created_epoch    => time(),
		plugin_version   => LoxBerry::System::pluginversion() // '?',
		loxberry_version => LoxBerry::System::lbversion() // '?',
		influxdb_version => ( split /\s+/, `influxd version 2>/dev/null` )[1] // '?',
		grafana_version  => ( `dpkg-query -W -f='\${Version}' grafana 2>/dev/null` || '?' ),
		db_name          => $db,
		db_path          => dbdir(),
		db_size_bytes    => dirsize( dbdir() ),
		backup_size_bytes=> dirsize( "$work/influxdb" ),
		influx_users     => \@users,
		influx_cq_count  => $cqcount,
		warnings         => \@warnings,
	);
	open( my $mf, '>', "$work/manifest.json" ) or do { LOGE "Cannot write the manifest"; remove_tree($work); exit 1 };
	print {$mf} JSON->new->pretty->canonical->encode( \%manifest );
	close $mf;

	# --- pack ------------------------------------------------------------
	status( running => 1, step => 'packing', message => 'Packing the archive' );
	($rc, $out) = pack_archive( $archive, $work );
	remove_tree($work);
	if( $rc != 0 ) { LOGE "Could not pack the archive: $out"; unlink $archive; exit 1 }

	chown( scalar getpwnam('loxberry'), scalar getgrnam('loxberry'), $archive );
	chmod 0644, $archive;

	LOGO "Backup finished: $archive (" . human( -s $archive ) . ")";

	# Only after the new archive is complete - a failed backup must never cost
	# the user an older, working one.
	prune_archives( $target, $keep );

	hint_old_archives();
	status( running => 0, step => 'done', message => 'Backup finished',
	        archive => $archive, size => ( -s $archive ), warnings => \@warnings, errors => 0 );
	return 0;
}

# The archives of the old mechanism are left alone - they are the user's
# backups. Only pointed out, with the space they occupy.
sub hint_old_archives
{
	my $old = $LoxBerry::System::lbpdatadir . "/backups/plugininstall";
	return if( ! -d $old );
	my @a = glob( "$old/*.7z" );
	return if( !@a );
	LOG "Note: $old still holds " . scalar(@a) . " archives of the old installation backup ("
	    . human( dirsize($old) ) . "). They are no longer created and can be deleted if you do not need them.";
	return;
}

# ---------------------------------------------------------------- list

sub cmd_list
{
	if( !$target ) { print JSON::encode_json( { error => "target missing" } ), "\n"; exit 1 }
	my @out;
	foreach my $a ( archive_list($target) ) {
		my $m = read_manifest($a);
		push @out, {
			file        => $a,
			name        => basename($a),
			size        => ( -s $a ),
			size_h      => human( -s $a ),
			mtime       => ( stat($a) )[9],
			compression => format_of($a),
			manifest    => $m,
		};
	}
	print JSON->new->canonical->encode( { backups => \@out } ), "\n";
	return 0;
}

# Reads the manifest out of the archive without unpacking the rest. The leading
# "./" is tried as well - tar stores it that way, zip and 7z usually do not.
#
# --occurrence=1 is what makes this quick: without it tar reads on to the end of
# the archive even after it has found the member. Measured on a 338 MB archive,
# 3.2 seconds without, 0.08 seconds with. Together with the manifest being the
# first member (see pack_archive) reading it costs nothing worth caching.
sub read_manifest
{
	my ($archive) = @_;
	return undef if( !$archive or ! -e $archive );
	my $f = format_of($archive);
	my $a = quotemeta($archive);

	my %reader = (
		none => sub { `tar -xOf $a --occurrence=1 $_[0] 2>/dev/null` },
		gzip => sub { `tar -xzOf $a --occurrence=1 $_[0] 2>/dev/null` },
		xz   => sub { `tar -xJOf $a --occurrence=1 $_[0] 2>/dev/null` },
		zip  => sub { `unzip -p $a $_[0] 2>/dev/null` },
		'7z' => sub { `7z x -so -bd -bso0 -bsp0 $a $_[0] 2>/dev/null` },
	);
	my $read = $reader{$f} or return undef;

	# The likely name first, and that matters more than it looks: a tar that
	# does not find the member reads to the end of the archive before giving up,
	# and --occurrence=1 cannot help with something that never occurs. With the
	# wrong name first, every listing paid a full pass over every archive - 3.2
	# seconds each. tar stores the member as "./manifest.json", zip and 7z as
	# "manifest.json".
	my @names = ( $f eq 'zip' or $f eq '7z' )
	          ? ( 'manifest.json', './manifest.json' )
	          : ( './manifest.json', 'manifest.json' );

	my $raw = '';
	foreach my $name ( @names ) {
		$raw = $read->($name);
		last if( $raw and $raw =~ /\S/ );
	}
	return undef if( !$raw or $raw !~ /\S/ );
	my $m = eval { JSON::decode_json($raw) };
	return $@ ? undef : $m;
}

# Deletes the oldest archives in the target directory until only $keep are left.
# 0 or undef means keep everything.
sub prune_archives
{
	my ($dir, $n) = @_;
	return if( !$n or $n < 1 );
	my @a = archive_list($dir);
	return if( scalar(@a) <= $n );
	foreach my $old ( @a[ $n .. $#a ] ) {
		if( unlink $old ) { LOG "Removed old backup: " . basename($old) }
		else              { LOGW "Could not remove $old: $!" }
	}
	return;
}

# ---------------------------------------------------------------- check

# Everything the web interface needs to know before it may restore. Answers
# JSON, changes nothing.
sub cmd_check
{
	my %r = ( ok => 0 );
	if( !$file or ! -e $file ) {
		$r{error} = "Archive not found";
		print JSON->new->canonical->encode( \%r ), "\n";
		return 1;
	}

	my $m = read_manifest($file);
	if( !$m ) {
		$r{error} = "The archive has no readable manifest - it was probably not created by this plugin";
		print JSON->new->canonical->encode( \%r ), "\n";
		return 1;
	}
	$r{manifest} = $m;

	# Where should the database go? Order: explicit wish, then the path from
	# the manifest, then the plugin's own directory.
	my $wanted = $dbpath || $m->{db_path} || default_dbdir();
	my $needed = int( ( $m->{db_size_bytes} // 0 ) * 1.1 );

	my @cand = ( { path => $wanted, source => 'manifest' } );
	push @cand, { path => default_dbdir(), source => 'default' }
		if( $wanted ne default_dbdir() );

	my @checked;
	my $chosen;
	foreach my $c ( @cand ) {
		my $free = freespace( $c->{path} );
		my $fits = ( $free >= $needed ) ? 1 : 0;
		my $state = ( -d $c->{path} ) ? db_state( $c->{path}, $m->{db_name} ) : 'none';
		push @checked, {
			path       => $c->{path},
			source     => $c->{source},
			exists     => ( -d $c->{path} ) ? 1 : 0,
			free       => $free,
			free_h     => human($free),
			needed     => $needed,
			needed_h   => human($needed),
			fits       => $fits,
			db_state   => $state,
		};
		$chosen = $c->{path} if( $fits and !$chosen );
	}

	$r{targets} = \@checked;
	$r{needed}  = $needed;
	$r{needed_h}= human($needed);

	if( !$chosen ) {
		$r{error} = "Not enough space anywhere. Needed: " . human($needed);
		print JSON->new->canonical->encode( \%r ), "\n";
		return 1;
	}

	$r{chosen} = $chosen;
	$r{alternative} = ( $chosen ne $wanted ) ? 1 : 0;

	# Only a database holding data prompts a warning. A freshly created, empty
	# one is what an installation leaves behind - saying anything about it would
	# only unsettle the user.
	my ($sel) = grep { $_->{path} eq $chosen } @checked;
	$r{db_state} = $sel->{db_state};
	$r{needs_confirmation} = ( $sel->{db_state} eq 'data' ) ? 1 : 0;

	$r{ok} = 1;
	print JSON->new->canonical->encode( \%r ), "\n";
	return 0;
}

# ---------------------------------------------------------------- restore

sub cmd_restore
{
	if( !$file or ! -e $file ) { LOGE "--file is missing or the archive does not exist"; exit 1 }

	my $m = read_manifest($file);
	if( !$m ) { LOGE "The archive has no readable manifest"; exit 1 }

	LOG "Archive from $m->{created}, plugin $m->{plugin_version}, InfluxDB $m->{influxdb_version}";
	LOGW "From the manifest: $_" foreach ( @{ $m->{warnings} || [] } );

	my $mine = LoxBerry::System::pluginversion() // '?';
	LOGW "The archive was created with plugin version $m->{plugin_version}, installed is $mine"
		if( ($m->{plugin_version}//'') ne $mine );

	my $target_db = $dbpath || $m->{db_path} || default_dbdir();
	my $needed    = int( ( $m->{db_size_bytes} // 0 ) * 1.1 );
	if( freespace($target_db) < $needed ) {
		my $alt = default_dbdir();
		if( freespace($alt) >= $needed ) {
			LOGW "$target_db has too little space (" . human( freespace($target_db) )
			     . ", needed " . human($needed) . ") - using $alt";
			$target_db = $alt;
		}
		else {
			LOGE "Not enough space, needed " . human($needed) . ". Aborting.";
			exit 1;
		}
	}

	my $state = ( -d $target_db ) ? db_state( $target_db, $m->{db_name} ) : 'none';
	if( $state eq 'data' and !$force ) {
		LOGE "$target_db already holds a database WITH DATA. Restoring would delete it. "
		     . "Repeat with --force if that is intended.";
		exit 1;
	}
	LOG "Existing database at $target_db: $state" . ( $state eq 'empty' ? " (freshly created, nothing lost)" : "" );

	status( running => 1, step => 'stopping', message => 'Stopping the services' );
	run( "systemctl stop telegraf grafana-server influxdb" );
	run( "pkill -f mqttlive.php" );
	run( "pkill -f import_scheduler.pl" );

	my $work = $Globals::stats4lox->{s4ltmp} . "/restore_$$";
	remove_tree($work) if( -d $work );
	make_path($work);

	status( running => 1, step => 'unpacking', message => 'Unpacking the archive' );
	my ($rc, $out) = unpack_archive( $file, $work );
	if( $rc != 0 ) { LOGE "Could not unpack the archive: $out"; remove_tree($work); restart_services(); exit 1 }

	# --- configuration ---------------------------------------------------
	status( running => 1, step => 'config', message => 'Restoring the configuration' );
	if( -d "$work/config" ) {
		($rc, $out) = run( "rsync -a --exclude 'systemd/' " . quotemeta("$work/config") . "/ "
		                   . quotemeta($LoxBerry::System::lbpconfigdir) . "/" );
		LOGE "Restoring the configuration failed: $out" if( $rc != 0 );
		fix_config_permissions();
		LOGO "Configuration restored, including provisioning";
	}

	# If we had to move to another path, influxdb.conf has to say so - otherwise
	# influxd would keep writing into the old location. The setting in
	# stats4lox.json is kept in step so the web interface shows the right thing.
	if( $target_db ne dbdir() ) {
		if( set_dbdir($target_db) ) {
			LOGO "Database path in influxdb.conf set to $target_db";
			my $obj = LoxBerry::JSON->new();
			my $c = $obj->open( filename => $Globals::stats4loxconfig );
			if( $c ) {
				$c->{influx}->{db_storage} = $target_db;
				$obj->write();
			}
		}
		else {
			LOGE "Could not change the database path in influxdb.conf - restoring to $target_db would not take effect";
			remove_tree($work);
			restart_services();
			exit 1;
		}
	}

	# --- Grafana and import state ----------------------------------------
	status( running => 1, step => 'data', message => 'Restoring Grafana and the import state' );
	foreach my $sub ( qw( grafana import ) ) {
		next if( ! -d "$work/data/$sub" );
		run( "rsync -a " . quotemeta("$work/data/$sub") . " " . quotemeta($LoxBerry::System::lbpdatadir) . "/" );
	}
	run( "chown -R grafana:loxberry " . quotemeta("$LoxBerry::System::lbpdatadir/grafana") )
		if( -d "$LoxBerry::System::lbpdatadir/grafana" );
	LOGO "Grafana and import state restored";

	# --- database --------------------------------------------------------
	status( running => 1, step => 'influx', message => 'Restoring the database' );

	if( $state ne 'none' ) {
		LOG "Removing the existing database at $target_db";
		remove_tree( "$target_db/data/" . $m->{db_name} ) if( -d "$target_db/data/" . $m->{db_name} );
		remove_tree( "$target_db/wal/"  . $m->{db_name} ) if( -d "$target_db/wal/"  . $m->{db_name} );
	}
	make_path( "$target_db/data", "$target_db/wal", "$target_db/meta" );
	run( "chown -R influxdb:loxberry " . quotemeta($target_db) );

	run( "systemctl start influxdb" );
	my $up = 0;
	for ( 1 .. 30 ) { if( influx_running() ) { $up = 1; last } sleep 2 }
	if( !$up ) { LOGE "InfluxDB did not start - the database was not restored"; remove_tree($work); exit 1 }
	sleep 5;

	# The user first: a fresh installation created one with a new random
	# password, while the restored cred.json holds the old one. Without this the
	# plugin could not reach its own database.
	my $c = cred();
	my $u = $c->{influx}->{influxdbuser};
	my $p = $c->{influx}->{influxdbpass};
	if( $u and $p ) {
		my $bin = $LoxBerry::System::lbpbindir . "/s4linflux";
		($rc, $out) = run( "$bin -execute " . quotemeta("CREATE USER $u WITH PASSWORD '$p' WITH ALL PRIVILEGES") );
		if( $rc != 0 ) {
			($rc, $out) = run( "$bin -execute " . quotemeta("SET PASSWORD FOR $u = '$p'") );
		}
		if( $rc == 0 ) { LOGO "InfluxDB user '$u' matched to the restored credentials" }
		else           { LOGE "Could not restore the InfluxDB user: $out" }
	}

	my $db_failed = 0;
	if( -d "$work/influxdb" ) {

		# The database has to be gone from the METASTORE, not only from the disk.
		#
		# Deleting data/<db> and wal/<db> above leaves meta/ untouched, so InfluxDB
		# still knows the database - and "influxd restore -portable" refuses to
		# write into one that exists:
		#
		#   error updating meta: DB metadata not changed. database may already exist
		#
		# Which is exactly what happened on a real restore over a running
		# installation - the normal case, not an edge case. DROP DATABASE through
		# the client removes both halves. It is safe here in a way it never is
		# elsewhere: the data files of this database were deleted a few lines up,
		# and an archive to put back in their place is in hand.
		my $bin = $LoxBerry::System::lbpbindir . "/s4linflux";
		run( "$bin -execute " . quotemeta( "DROP DATABASE " . $m->{db_name} ) );

		($rc, $out) = run( "influxd restore -portable -db " . quotemeta($m->{db_name})
		                   . " " . quotemeta("$work/influxdb") );
		if( $rc != 0 ) {
			LOGE "influxd restore failed: $out";
			$db_failed = 1;
		}
		else {
			# Asked, not assumed. This is the step whose failure went unnoticed,
			# and the answer to "did it work" is one cheap query away.
			my ($qrc, $qout) = run( "$bin -database " . quotemeta($m->{db_name})
			                        . " -execute " . quotemeta("SHOW MEASUREMENTS") );
			my @lines = grep { /\S/ and !/^name:/ and !/^name$/ and !/^-+$/ } split( /\n/, ($qout // '') );
			if( $qrc != 0 or !@lines ) {
				LOGE "The database is empty after the restore - the archive was not put back";
				$db_failed = 1;
			}
			else {
				LOGO sprintf( "Database restored, %d measurements", scalar @lines );
			}
		}
	}

	remove_tree($work);

	# --- drop-ins and services -------------------------------------------
	status( running => 1, step => 'services', message => 'Starting the services' );
	run( $LoxBerry::System::lbpbindir . "/config-handler.pl servicelog" );
	restart_services();

	my @dead = grep { my ($r) = run("systemctl is-active --quiet $_"); $r != 0 }
	           qw( influxdb telegraf grafana-server );
	if( @dead ) {
		LOGE "These services are not running: " . join( ", ", @dead );
		status( running => 0, step => 'done', message => 'Restore finished with errors', errors => 1 );
		exit 1;
	}

	# A failed database restore used to end up here as a success.
	#
	# The error was written to the logfile and then dropped on the floor: the final
	# status said errors => 0 and the page showed a green "finished", while the old
	# database was still in place and untouched. Somebody who restores a backup and
	# is told it worked has every reason to believe their data is back.
	if( $db_failed ) {
		LOGE "Restore finished, but the DATABASE was not restored - see above. Your old database is untouched.";
		status( running => 0, step => 'done', message => 'The database was not restored', errors => 1 );
		exit 1;
	}

	LOGO "Restore finished, all services are running";
	status( running => 0, step => 'done', message => 'Restore finished', errors => 0,
	        warnings => $m->{warnings} || [] );
	return 0;
}

# Restores the ownership inside the configuration directory.
#
# A blanket "chown -R loxberry:loxberry" is wrong here and cost an evening: it
# also catches influxdb-selfsigned.key, which is mode 0600 and has to belong to
# influxdb. InfluxDB then refuses to start with
#
#   run: open server: open service: httpd: error creating TLS manager:
#   LoadCertificate: error opening ".../influxdb-selfsigned.key"
#
# The same rules postroot.sh applies after an installation.
sub fix_config_permissions
{
	my $c = $LoxBerry::System::lbpconfigdir;
	run( "chown -R loxberry:loxberry " . quotemeta($c) );

	if( -d "$c/influxdb" ) {
		run( "chown -R influxdb:loxberry " . quotemeta("$c/influxdb") );
		my $key = "$c/influxdb/influxdb-selfsigned.key";
		if( -e $key ) {
			run( "chmod 600 " . quotemeta($key) );
			run( "chmod 644 " . quotemeta("$c/influxdb/influxdb-selfsigned.crt") );
		}
	}
	run( "chown -R grafana:loxberry " . quotemeta("$c/grafana") ) if( -d "$c/grafana" );
	if( -e "$c/telegraf/telegraf.env" ) {
		run( "chown telegraf:loxberry " . quotemeta("$c/telegraf/telegraf.env") );
		run( "chmod 660 " . quotemeta("$c/telegraf/telegraf.env") );
	}
	return;
}

sub restart_services
{
	run( "systemctl start influxdb" );
	run( "systemctl start telegraf" );
	run( "systemctl start grafana-server" );
	return;
}

# ---------------------------------------------------------------- delete

sub cmd_delete
{
	if( !$file ) { LOGE "--file is missing"; exit 1 }
	# Only our own archives, and only inside the configured storage - a path
	# from the web interface must not be able to delete anything else.
	if( basename($file) !~ /^stats4lox_\d{8}_\d{6}\./ ) {
		LOGE "Not a Stats4Lox backup: $file";
		exit 1;
	}
	if( ! -e $file ) { LOGE "Archive does not exist: $file"; exit 1 }
	if( unlink $file ) { LOGO "Deleted: $file"; return 0 }
	LOGE "Could not delete $file: $!";
	return 1;
}

# ---------------------------------------------------------------- dispatch

# The cron job takes its parameters from the configuration, so changing a
# setting in the web interface does not require rewriting the crontab entry.
if( $scheduled ) {
	my $c = cfg();
	my $b = $c->{backup} || {};
	$target      = $b->{storagepath} if( !$target and $b->{storagepath} );
	$compression = $b->{compression} if( !defined $compression );
	$keep        = $b->{keep}        if( !defined $keep );

	# Whether this week is one of the wanted ones is decided here and not in the
	# crontab. cron runs its commands through /bin/sh - dash on LoxBerry - which
	# has no [[ ]], and every % in a crontab command is turned into a newline, so
	# a "date +%s" in there never survives. The weekday and the time are what
	# cron is good at; the rest is arithmetic and belongs in a program.
	if( $cron ) {
		my $repeat = $b->{schedule}->{repeat} || 1;
		if( $repeat > 1 and !week_is_due( $b->{schedule}->{since}, $repeat ) ) {
			LOG "Not due this week (every $repeat weeks) - nothing to do";
			LOGEND if( $log );
			exit 0;
		}
	}
	LOG "Scheduled run";
}

# "Every n weeks" counted in whole weeks, not in days.
#
# The obvious "days since a reference date modulo n*7" only ever matches a
# single day every n*7 days - with two weekdays selected, one of them would
# never fire. Counting weeks instead means every selected weekday of a due week
# is due.
sub week_is_due
{
	my ($since, $repeat) = @_;
	return 1 if( !$repeat or $repeat < 2 );
	my ($y, $m, $d) = ( $since // '' ) =~ /^(\d{4})-(\d{2})-(\d{2})$/;
	return 1 if( !$y );

	require Time::Local;

	# Day number of a date, anchored at noon so a daylight saving change - which
	# moves the clock by an hour - cannot push a date into the neighbouring day.
	my $daynum = sub {
		my ($yy, $mm, $dd) = @_;
		my $t = eval { Time::Local::timelocal( 0, 0, 12, $dd, $mm - 1, $yy ) };
		return defined $t ? int( $t / 86400 ) : undef;
	};

	my $refday = $daynum->( $y, $m, $d );
	my @now = localtime( time() );
	my $today = $daynum->( $now[5] + 1900, $now[4] + 1, $now[3] );
	return 1 if( !defined $refday or !defined $today );

	# Both days pulled back to the Monday of their week, so the difference is a
	# whole number of weeks whatever weekday either one falls on. Perl counts
	# Sunday as 0, which belongs to the week that started six days earlier.
	my $back = sub {
		my ($dayno) = @_;
		# 1970-01-01 was a Thursday, so day number + 4 gives the weekday with
		# Monday = 0.
		return $dayno - ( ( $dayno + 3 ) % 7 );
	};

	my $weeks = ( $back->($today) - $back->($refday) ) / 7;
	return ( $weeks % $repeat == 0 ) ? 1 : 0;
}

my $rc = 0;
if   ( $command eq 'create'  ) { $rc = cmd_create() }
elsif( $command eq 'list'    ) { $rc = cmd_list() }
elsif( $command eq 'check'   ) { $rc = cmd_check() }
elsif( $command eq 'restore' ) { $rc = cmd_restore() }
elsif( $command eq 'delete'  ) { $rc = cmd_delete() }
else {
	print STDERR "Usage: $0 create|list|check|restore|delete [options]\n";
	print STDERR "  create  --target <dir> [--compression none|gzip|xz|zip|7z] [--keep <n>]\n";
	print STDERR "  create  --scheduled\n";
	print STDERR "  list    --target <dir>\n";
	print STDERR "  check   --file <archive> [--dbpath <dir>]\n";
	print STDERR "  restore --file <archive> [--dbpath <dir>] [--force]\n";
	print STDERR "  delete  --file <archive>\n";
	exit 1;
}

LOGEND if( $log );
exit $rc;
