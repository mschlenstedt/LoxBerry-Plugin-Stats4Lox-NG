#!/usr/bin/perl

# Backup and restore for Stats4Lox.
#
# Replaces the archive that postroot.sh used to leave behind on every
# installation. That one was a by-product of the upgrade directory: nothing ever
# read it back, it grew without limit, and it carried the whole time series
# database including _internal.
#
# Usage (root):
#   s4l_backup.pl create  --target <dir>
#   s4l_backup.pl list    --target <dir>
#   s4l_backup.pl check   --file <archive> [--dbpath <dir>]
#   s4l_backup.pl restore --file <archive> [--dbpath <dir>] [--force]
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
my ( $target, $file, $dbpath, $force, $json_only );
GetOptions(
	'target=s' => \$target,
	'file=s'   => \$file,
	'dbpath=s' => \$dbpath,
	'force'    => \$force,
	'json'     => \$json_only,
);

# "check" only prints JSON, so no log file for it
my $log;
if( $command ne 'check' ) {
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

# Where the time series database lives. Configurable in the web interface, so
# never assumed - db_storage holds the parent, influxd gets <parent>/influxdb.
sub dbdir
{
	my $c = cfg();
	my $storage = $c->{influx}->{db_storage};
	return "$storage/influxdb" if( $storage and -d $storage );
	return $LoxBerry::System::lbpdatadir . "/influxdb";
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
	my $archive = "$target/stats4lox_$stamp.tar.gz";

	status( running => 1, step => 'preparing', message => 'Preparing backup' );
	LOG "Target: $archive";

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
		# grafana.db.before-stats4lox is our own safety copy, no need to carry it
		run( "rsync -a --exclude '*.before-stats4lox' " . quotemeta($src) . " " . quotemeta("$work/data") . "/" );
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
	($rc, $out) = run( "tar -czf " . quotemeta($archive) . " -C " . quotemeta($work) . " ." );
	remove_tree($work);
	if( $rc != 0 ) { LOGE "Could not pack the archive: $out"; unlink $archive; exit 1 }

	chown( scalar getpwnam('loxberry'), scalar getgrnam('loxberry'), $archive );
	chmod 0644, $archive;

	LOGO "Backup finished: $archive (" . human( -s $archive ) . ")";
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
	foreach my $a ( sort { $b cmp $a } glob( quotemeta($target) . "/stats4lox_*.tar.gz" ) ) {
		my $m = read_manifest($a);
		push @out, {
			file     => $a,
			name     => basename($a),
			size     => ( -s $a ),
			size_h   => human( -s $a ),
			manifest => $m,
		};
	}
	print JSON->new->canonical->encode( { backups => \@out } ), "\n";
	return 0;
}

sub read_manifest
{
	my ($archive) = @_;
	my $raw = `tar -xzOf "$archive" ./manifest.json 2>/dev/null`;
	$raw = `tar -xzOf "$archive" manifest.json 2>/dev/null` if( !$raw );
	my $m = eval { JSON::decode_json($raw) };
	return $@ ? undef : $m;
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
	my ($rc, $out) = run( "tar -xzf " . quotemeta($file) . " -C " . quotemeta($work) );
	if( $rc != 0 ) { LOGE "Could not unpack the archive: $out"; remove_tree($work); restart_services(); exit 1 }

	# --- configuration ---------------------------------------------------
	status( running => 1, step => 'config', message => 'Restoring the configuration' );
	if( -d "$work/config" ) {
		($rc, $out) = run( "rsync -a --exclude 'systemd/' " . quotemeta("$work/config") . "/ "
		                   . quotemeta($LoxBerry::System::lbpconfigdir) . "/" );
		LOGE "Restoring the configuration failed: $out" if( $rc != 0 );
		run( "chown -R loxberry:loxberry " . quotemeta($LoxBerry::System::lbpconfigdir) );
		LOGO "Configuration restored, including provisioning";
	}

	# If we had to move to another path, the configuration has to say so -
	# otherwise the plugin would look for the database in the old place.
	if( $target_db ne ( $m->{db_path} // '' ) ) {
		my $obj = LoxBerry::JSON->new();
		my $c = $obj->open( filename => $Globals::stats4loxconfig );
		if( $c ) {
			( my $storage = $target_db ) =~ s{/influxdb/?$}{};
			$c->{influx}->{db_storage} = $storage;
			$obj->write();
			LOGO "Database path in the configuration set to $storage";
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

	if( -d "$work/influxdb" ) {
		($rc, $out) = run( "influxd restore -portable -db " . quotemeta($m->{db_name})
		                   . " " . quotemeta("$work/influxdb") );
		if( $rc != 0 ) { LOGE "influxd restore failed: $out" }
		else           { LOGO "Database restored" }
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

	LOGO "Restore finished, all services are running";
	status( running => 0, step => 'done', message => 'Restore finished', errors => 0,
	        warnings => $m->{warnings} || [] );
	return 0;
}

sub restart_services
{
	run( "systemctl start influxdb" );
	run( "systemctl start telegraf" );
	run( "systemctl start grafana-server" );
	return;
}

# ---------------------------------------------------------------- dispatch

my $rc = 0;
if   ( $command eq 'create'  ) { $rc = cmd_create() }
elsif( $command eq 'list'    ) { $rc = cmd_list() }
elsif( $command eq 'check'   ) { $rc = cmd_check() }
elsif( $command eq 'restore' ) { $rc = cmd_restore() }
else {
	print STDERR "Usage: $0 create|list|check|restore [options]\n";
	print STDERR "  create  --target <dir>\n";
	print STDERR "  list    --target <dir>\n";
	print STDERR "  check   --file <archive> [--dbpath <dir>]\n";
	print STDERR "  restore --file <archive> [--dbpath <dir>] [--force]\n";
	exit 1;
}

LOGEND if( $log );
exit $rc;
