#!/bin/bash

# To use important variables from command line use the following code:
COMMAND=$0    # Zero argument is shell command
PTEMPDIR=$1   # First argument is temp folder during install
PSHNAME=$2    # Second argument is Plugin-Name for scipts etc.
PDIR=$3       # Third argument is Plugin installation folder
PVERSION=$4   # Forth argument is Plugin version
#LBHOMEDIR=$5 # Comes from /etc/environment now. Fifth argument is
              # Base folder of LoxBerry
PTEMPPATH=$6  # Sixth argument is full temp path during install (see also $1)

# Combine them with /etc/environment
PCGI=$LBPCGI/$PDIR
PHTML=$LBPHTML/$PDIR
PTEMPL=$LBPTEMPL/$PDIR
PDATA=$LBPDATA/$PDIR
PLOG=$LBPLOG/$PDIR # Note! This is stored on a Ramdisk now!
PCONFIG=$LBPCONFIG/$PDIR
PSBIN=$LBPSBIN/$PDIR
PBIN=$LBPBIN/$PDIR

INFLUXDBIN=$(command -v influxd)
INFLUXBIN=$(command -v influx)
OPENSSLBIN=$(command -v openssl)
TELEGRAFBIN=$(command -v telegraf)
ERROR=0
UPGRADE=0
DATE=`date +%Y%m%d%H%M%S`

function pause(){
   read -p "$*"
}

# Checking for InfluxDB, Telegraf and OpenSSL.
#
# Note: the variables MUST be quoted here. If a binary is missing, the
# variable is empty and an unquoted [ ! -x $VAR ] collapses into [ ! -x ],
# which bash evaluates as the negated string test of "-x" - always false.
# That is why broken installations used to run on for another 200 lines and
# then failed with a completely misleading message about the InfluxDB user.
for s4l_entry in "influxd:$INFLUXDBIN" "influx:$INFLUXBIN" "telegraf:$TELEGRAFBIN" "openssl:$OPENSSLBIN"; do
	s4l_name=${s4l_entry%%:*}
	s4l_path=${s4l_entry#*:}
	if [ -z "$s4l_path" ] || [ ! -x "$s4l_path" ]; then
		echo "<FAIL> The program '$s4l_name' is not installed on your system."
		echo "<FAIL> Most likely the InfluxData/Grafana apt repository was not usable"
		echo "<FAIL> and therefore InfluxDB, Telegraf or Grafana could not be installed."
		echo "<FAIL> Please check the BEGINNING of this installation log for the real cause."
		exit 2
	fi
done

# Reports WHY a service did not come up. Without this the installation log
# only stated that a service "could not be started", which is the reason the
# recurring "Telegraf startet nicht" reports were never diagnosable.
s4l_service_failed() {
	local svc="$1"
	echo "<FAIL> Seems that $svc could not be started. Giving up."
	echo "<FAIL> ---------- systemctl status $svc ----------"
	systemctl status "$svc" --no-pager -l 2>&1 | sed 's/^/<FAIL> /'
	echo "<FAIL> ---------- last log lines of $svc ----------"
	journalctl -u "$svc" --no-pager -n 30 2>&1 | sed 's/^/<FAIL> /'
	s4l_service_error_detail "$svc"
	echo "<FAIL> -------------------------------------------"
}

# Retrieves the message the service itself printed when it refused to start.
#
# Our drop-ins send StandardOutput and StandardError to /dev/null, and that is
# deliberate: journald on LoxBerry stores volatile, i.e. in RAM, and InfluxDB
# writes an HTTP access log line per request - roughly 8600 lines a day at the
# default flush interval of 10s. Feeding that into a RAM journal is exactly what
# the redirection avoids.
#
# The price was that a service which died on startup left no trace whatsoever.
# systemd then reports nothing but "New main PID does not exist or is a zombie",
# while the actual cause - for instance InfluxDB 1.12 rejecting a TLS key with
# permissions 0640 - was discarded. Users could not report it and we could not
# see it.
#
# So the redirection is lifted for one single restart, only in the failure case,
# and removed again immediately afterwards. Steady state stays quiet.
s4l_service_error_detail() {
	local svc="$1"
	local ovr="/etc/systemd/system/${svc}.service.d/99-stats4lox-debug.conf"
	local since

	mkdir -p "/etc/systemd/system/${svc}.service.d" 2>/dev/null
	printf '[Service]\nStandardOutput=journal\nStandardError=journal\n' > "$ovr" 2>/dev/null || return 0
	systemctl daemon-reload > /dev/null 2>&1

	since=$(date '+%Y-%m-%d %H:%M:%S')
	systemctl reset-failed "$svc" > /dev/null 2>&1
	systemctl start "$svc" > /dev/null 2>&1
	sleep 8
	systemctl stop "$svc" > /dev/null 2>&1

	echo "<FAIL> ---------- what $svc itself reported ----------"
	journalctl -u "$svc" --no-pager --since "$since" 2>&1 \
		| grep -viE 'systemd\[1\]:' \
		| tail -25 \
		| sed 's/^/<FAIL> /'

	rm -f "$ovr"
	systemctl daemon-reload > /dev/null 2>&1
}

# Adds the two columns Grafana 13 expects in the legacy playlist table.
#
# Grafana 13 migrates the old playlist table into its new unified storage with
# this query:
#
#   SELECT p.id, p.org_id, p.uid, p.name, p.interval,
#          p.created_at, p.updated_at, pi.type, pi.value
#   FROM playlist AS p LEFT OUTER JOIN playlist_item AS pi ON p.id = pi.playlist_id
#
# created_at and updated_at were never part of that table. No schema migration
# in any Grafana version adds them - a fresh Grafana 13 does not create the
# table at all any more - so every database carried over from an older Grafana
# makes the server abort on startup:
#
#   Error: unable to start dualwrite service due to migration error:
#   migration failed (id = playlists migration):
#   SQL logic error: no such column: p.created_at (1)
#
# ALTER TABLE ADD COLUMN only appends, existing rows keep their data. INTEGER is
# not a guess: with DATETIME the migration still fails, with INTEGER Grafana
# starts - verified on a copy of a real database, with a playlist and a playlist
# item in it.
s4l_migrate_grafana_db() {
	local db="$1"
	local cols missing c

	[ -f "$db" ] || return 0
	if ! command -v sqlite3 > /dev/null 2>&1; then
		echo "<WARNING> sqlite3 is not available - cannot check the Grafana database."
		return 0
	fi

	# No legacy playlist table means nothing to migrate and Grafana skips it.
	sqlite3 "$db" "SELECT name FROM sqlite_master WHERE type='table' AND name='playlist'" 2>/dev/null \
		| grep -q playlist || return 0

	cols=$(sqlite3 "$db" "PRAGMA table_info(playlist)" 2>/dev/null | cut -d'|' -f2)
	missing=""
	for c in created_at updated_at; do
		echo "$cols" | grep -qx "$c" || missing="$missing $c"
	done
	[ -n "$missing" ] || return 0

	echo "<INFO> Grafana database: playlist table is missing$missing, which Grafana 13 needs to start."
	if cp -a "$db" "$db.before-stats4lox"; then
		echo "<INFO> Kept a copy of the unmodified database as $(basename "$db").before-stats4lox"
	fi
	for c in $missing; do
		if sqlite3 "$db" "ALTER TABLE playlist ADD COLUMN $c INTEGER NOT NULL DEFAULT 0" 2>&1; then
			echo "<INFO>   added column $c"
		else
			echo "<WARNING>   could not add column $c - Grafana will probably not start"
		fi
	done
	return 0
}

# Turns InfluxDB's HTTP request logging off in an existing configuration.
#
# Same reason as in the shipped influxdb.conf: one line per HTTP request, about
# 8600 a day, on a ramdisk, and none of it useful for finding a problem. And the
# same reason as for Telegraf that this needs a migration at all - an upgrade
# restores the previous configuration over the freshly installed one, so
# correcting our own copy never reaches an existing installation.
#
# Only the entry inside the [http] section is touched; influxdb.conf has a
# second log-enabled further down that belongs to [subscriber]. Idempotent.
s4l_migrate_influxdb_config() {
	local f="$1"
	[ -f "$f" ] || return 0

	# Already set explicitly? Then leave the user's choice alone.
	if awk '/^\[http\]/{h=1;next} /^\[/{h=0} h && /^[[:space:]]*log-enabled[[:space:]]*=/{found=1} END{exit !found}' "$f"; then
		return 0
	fi

	# Insert after the commented default inside [http].
	if awk '/^\[http\]/{h=1;next} /^\[/{h=0} h && /^[[:space:]]*#[[:space:]]*log-enabled[[:space:]]*=/{found=1} END{exit !found}' "$f"; then
		awk '
			/^\[http\]/ { h=1 }
			/^\[/ && !/^\[http\]/ { h=0 }
			{ print }
			h && /^[[:space:]]*#[[:space:]]*log-enabled[[:space:]]*=/ && !done {
				print "  log-enabled = false"
				done=1
			}
		' "$f" > "$f.s4lnew" || { rm -f "$f.s4lnew"; return 0; }
		# Keep owner and mode: writing a new file and moving it over the old one
		# would leave influxdb.conf owned by root, not by influxdb.
		chown --reference="$f" "$f.s4lnew" 2>/dev/null
		chmod --reference="$f" "$f.s4lnew" 2>/dev/null
		mv "$f.s4lnew" "$f"
		echo "<INFO>   $(basename "$f"): disabled the HTTP request log ([http] log-enabled = false)"
	fi
	return 0
}

# Migrates Telegraf options that current Telegraf versions reject.
#
# This is required because an upgrade restores the previous configuration over
# the freshly installed one, so correcting our shipped telegraf.conf alone
# never reaches an existing installation. Exactly that happened in 2022: the
# "1d" -> "24h" correction of logfile_rotation_interval shipped with 0.9.7 but
# only ever helped fresh installations - upgraded systems kept reporting that
# Telegraf could not be started, for years.
#
# Telegraf refuses to start on an unknown option, so every single one of these
# leaves the service dead. The function is idempotent.
s4l_migrate_telegraf_config() {
	local f="$1"
	[ -f "$f" ] || return 0

	# "logtarget" was removed in Telegraf 1.32. Since then the destination is
	# defined by "logfile" alone, which we always set.
	if grep -qE '^[[:space:]]*logtarget[[:space:]]*=' "$f"; then
		sed -i -E 's/^([[:space:]]*)logtarget([[:space:]]*=)/\1## obsolete since Telegraf 1.32, disabled by Stats4Lox: logtarget\2/' "$f"
		echo "<INFO>   $(basename "$f"): disabled obsolete option 'logtarget'"
	fi

	# Shipped between 04/2021 and 03/2022 - "d" is not a valid duration unit.
	if grep -qE '^[[:space:]]*logfile_rotation_interval[[:space:]]*=[[:space:]]*"1d"' "$f"; then
		sed -i -E 's/^([[:space:]]*logfile_rotation_interval[[:space:]]*=[[:space:]]*)"1d"/\1"24h"/' "$f"
		echo "<INFO>   $(basename "$f"): corrected logfile_rotation_interval from \"1d\" to \"24h\""
	fi

	# Not an option Telegraf rejects, but a limit that is now too tight. The
	# Miniserver grabber asks once per selected value, and how many that is became
	# the user's choice. Measured: 2.7 s for one Miniserver with the whole
	# catalogue, so five seconds were already exceeded by the second Miniserver -
	# and Telegraf discards the whole answer, not the part that was late. 290 s is
	# ten short of the shortest interval the page offers.
	if [ "$(basename "$f")" = "stats4lox_miniserver.conf" ] \
		&& grep -qE '^[[:space:]]*timeout[[:space:]]*=[[:space:]]*"5s"' "$f"; then
		sed -i -E 's/^([[:space:]]*timeout[[:space:]]*=[[:space:]]*)"5s"/\1"290s"/' "$f"
		echo "<INFO>   $(basename "$f"): raised the request timeout from 5s to 290s"
	fi

	return 0
}

# Stop all services
echo "<INFO> Stopping InfluxDB and Telegraf."
systemctl stop influxdb
systemctl stop telegraf
systemctl stop grafana-server

# Add all users/groups to each other
echo "<INFO> Adding user loxberry to groups influxdb, telegraf, grafana..."
usermod -a -G influxdb,telegraf,grafana loxberry
echo "<INFO> Adding user influxdb to group loxberry..."
usermod -a -G loxberry influxdb
echo "<INFO> Adding user telegraf to group loxberry..."
usermod -a -G loxberry telegraf
echo "<INFO> Adding user grafana to group loxberry..."
usermod -a -G loxberry grafana

#pause 'Press [Enter] key to continue...'

# Check if we are in upgrade mode
if [ -d $LBHOMEDIR/data/plugins/$PTEMPDIR\_upgrade ]; then
	echo "<INFO> We are in Upgrade mode. Use existing database and credentials."
	UPGRADE=1

	# Log
	if [ -n "$(ls -A "$LBHOMEDIR/data/plugins/${PTEMPDIR}_upgrade/log" 2>/dev/null)" ]; then
		chown -R loxberry:loxberry $PLOG
		rsync -Iav $LBHOMEDIR/data/plugins/$PTEMPDIR\_upgrade/log/* $PLOG/
		if [ $? -ne 0 ]; then
			echo "<FAIL> Restoring log files failed. Giving up."
			#pause 'Press [Enter] key to continue...'
			mv $LBHOMEDIR/data/plugins/${PTEMPDIR}_upgrade $LBHOMEDIR/data/plugins/${DATE}_FAILED_INSTALLATION_STATS4LOX
			exit 2
		fi
	else
		echo "<INFO> Folder is empty. Nothing will be restored."
	fi

	# Data
	if [ -n "$(ls -A "$LBHOMEDIR/data/plugins/${PTEMPDIR}_upgrade/data" 2>/dev/null)" ]; then
		chown -R loxberry:loxberry $PDATA
		rsync -Iav $LBHOMEDIR/data/plugins/${PTEMPDIR}_upgrade/data/* $PDATA/
		if [ $? -ne 0 ]; then
			echo "<FAIL> Restoring data files failed. Giving up."
			#pause 'Press [Enter] key to continue...'
			mv $LBHOMEDIR/data/plugins/${PTEMPDIR}_upgrade $LBHOMEDIR/data/plugins/${DATE}_FAILED_INSTALLATION_STATS4LOX
			exit 2
		fi
	else
		echo "<INFO> Folder is empty. Nothing will be restored."
	fi

	# Config
	if [ -n "$(ls -A "$LBHOMEDIR/data/plugins/${PTEMPDIR}_upgrade/config/" 2>/dev/null)" ]; then
		# The freshly installed Telegraf drop-ins, kept aside before the old ones
		# are copied over them. One of them has to be put back afterwards, see
		# below - and after this rsync the new version no longer exists anywhere.
		S4L_FRESH_TELEGRAFD=$(mktemp -d)
		cp -a $PCONFIG/telegraf/telegraf.d/. "$S4L_FRESH_TELEGRAFD/" 2>/dev/null

		chown -R loxberry:loxberry $PCONFIG
		rsync -Iav --exclude "systemd/*" --exclude "sysctl.conf" $LBHOMEDIR/data/plugins/${PTEMPDIR}_upgrade/config/* $PCONFIG/
		# Kept before anything else runs - the check below used to read $? and
		# would otherwise be testing whatever ran last instead of the rsync.
		S4L_RSYNC_RC=$?

		# The LoxBerry drop-in shipped for years with "urls = []" and a
		# data_format that was never going to work - it collected nothing, ever.
		# An upgrade would restore exactly that over the working one and the
		# LoxBerry data source would silently do nothing on every installation
		# that was not brand new.
		#
		# Only replaced when it still carries that empty URL list. A drop-in that
		# has a URL is either the new one or something the user set up, and
		# neither should be overwritten.
		if grep -qE '^[[:space:]]*urls[[:space:]]*=[[:space:]]*\[[[:space:]]*\]' \
			"$PCONFIG/telegraf/telegraf.d/stats4lox_loxberry.conf" 2>/dev/null \
			&& [ -f "$S4L_FRESH_TELEGRAFD/stats4lox_loxberry.conf" ]; then
			cp -a "$S4L_FRESH_TELEGRAFD/stats4lox_loxberry.conf" "$PCONFIG/telegraf/telegraf.d/stats4lox_loxberry.conf"
			echo "<INFO> Replaced the empty LoxBerry Telegraf drop-in by the current one."
		fi
		rm -rf "$S4L_FRESH_TELEGRAFD"

		if [ $S4L_RSYNC_RC -ne 0 ]; then
			echo "<FAIL> Restoring config files failed. Giving up."
			#pause 'Press [Enter] key to continue...'
			mv $LBHOMEDIR/data/plugins/${PTEMPDIR}_upgrade $LBHOMEDIR/data/plugins/${DATE}_FAILED_INSTALLATION_STATS4LOX
			exit 2
		fi
	else
		echo "<INFO> Folder is empty. Nothing will be restored."
	fi

	#pause 'Press [Enter] key to continue...'

	# The upgrade directory has served its purpose and is removed.
	#
	# It used to be turned into a 7z archive here instead - a backup nobody ever
	# read back. It grew without limit (24 installations meant 8 GB and a full
	# disk on the test machine), carried the whole time series database
	# including _internal, and even contained the plugin's own backup directory.
	# Backups are now made deliberately from the web interface, see
	# bin/s4l_backup.pl. Existing archives are left alone - they belong to the
	# user - and s4l_backup.pl points them out with the space they occupy.
	rm -rf $LBHOMEDIR/data/plugins/${PTEMPDIR}_upgrade
fi

# Get InfluxDB credentials
INFLUXDBUSER=`jq -r '.influx.influxdbuser' $PCONFIG/cred.json`
INFLUXDBPASS=`jq -r '.influx.influxdbpass' $PCONFIG/cred.json`
if [ "$INFLUXDBUSER" = "" ]; then
	INFLUXDBUSER="stats4lox"
	INFLUXDBPASS="loxberry"
fi

# Debug
#echo "Influx User: $INFLUXDBUSER"
#echo "Influx Pass: $INFLUXDBPASS"

# Activate own config delivered with plugin
echo "<INFO> Activating my own InfluxDB configuration."
if [ -d /etc/influxdb ] && [ ! -L /etc/influxdb ]; then
	rm -rf /etc/influxdb.orig
	mv /etc/influxdb /etc/influxdb.orig
fi
rm -rf /etc/influxdb > /dev/null 2>&1
ln -sfn $PCONFIG/influxdb /etc/influxdb
#chown -R loxberry:loxberry $PCONFIG/influxdb

if [ ! -e $PCONFIG/influxdb/influxdb-selfsigned.key ]; then
	echo "<INFO> No SSL certificates for InfluxDB found."
	echo "<INFO> Creating (new) self-signed SSL certificates."
	$OPENSSLBIN req -x509 -nodes -newkey rsa:2048 -keyout $PCONFIG/influxdb/influxdb-selfsigned.key -out $PCONFIG/influxdb/influxdb-selfsigned.crt -days 3650 -subj "/C=DE/ST=Austria/L=Kollerschlag/O=LoxBerry"
	#chown loxberry:loxberry $PCONFIG/influxdb/influxdb-selfsigned.*
	# The private key must not be group readable, see the note below.
	chmod 644 $PCONFIG/influxdb/influxdb-selfsigned.crt
	chmod 600 $PCONFIG/influxdb/influxdb-selfsigned.key
else
	echo "<INFO> Found SSL certificates for InfluxDB. I will not create new ones."
fi

# Correct permissions - influxdb must have write permissions to database folders
echo "<INFO> Set permissions for user influxdb for all config/data folders: $PDATA/influxdb $PCONFIG/influxdb"
chown -R influxdb:loxberry $PDATA/influxdb
chown -R influxdb:loxberry $PCONFIG/influxdb

# InfluxDB 1.12 refuses to start when the TLS private key is readable by anyone
# but its owner:
#
#   run: open server: open service: httpd: error creating TLS manager:
#   LoadCertificate: file permissions are too open: maximum is 0600 (-rw-------)
#   but found 0640 (-rw-r-----)
#
# 1.8 accepted 0640/0660, so EVERY installation upgraded from 1.8 carries a key
# that the new version rejects - the service then dies a few seconds after
# start, which systemd only reports as "New main PID does not exist or is a
# zombie" because our drop-in sends influxd's own output to /dev/null.
#
# Therefore enforced on every run and not only when the key is created, so that
# existing installations are repaired by the upgrade. Only influxd itself reads
# these two files (https-certificate/https-private-key in influxdb.conf), so
# restricting the key breaks nothing else.
if [ -e "$PCONFIG/influxdb/influxdb-selfsigned.key" ]; then
	chmod 600 "$PCONFIG/influxdb/influxdb-selfsigned.key"
	echo "<INFO> Restricted InfluxDB private key to 0600 - required since InfluxDB 1.12."
fi

echo "<INFO> Checking InfluxDB configuration for obsolete options..."
s4l_migrate_influxdb_config "$PCONFIG/influxdb/influxdb.conf"

# Debug:
echo "<INFO> Current file permisssions in $PDATA/influxdb:"
ls -l $PDATA/influxdb
echo "<INFO> Current file permisssions in $PCONFIG/influxdb"
ls -l $PCONFIG/influxdb

# Enlarge UDP/IP receive buffer limit for import
echo "<INFO> Enlarge Unix receive buffer limit..."
sysctl -w net.unix.max_dgram_qlen=10000
rm -f /etc/sysctl.d/96-stats4lox.conf
ln -s $PCONFIG/sysctl.conf /etc/sysctl.d/96-stats4lox.conf

# Systemd DropIn Config
echo "<INFO> Install Drop-In for Influx and Telegraf and Grafana systemd services..."
rm -f /etc/systemd/system/influxdb.service.d/00-stats4lox.conf > /dev/null 2>&1
rm -f /etc/systemd/system/telegraf.service.d/00-stats4lox.conf > /dev/null 2>&1
rm -f /etc/systemd/system/grafana-server.service.d/00-stats4lox.conf > /dev/null 2>&1
rm -f /etc/systemd/system/influxdb.service.d/00-stats4lox-influxdb.conf > /dev/null 2>&1
rm -f /etc/systemd/system/telegraf.service.d/00-stats4lox-telegraf.conf > /dev/null 2>&1
rm -f /etc/systemd/system/grafana-server.service.d/00-stats4lox-grafana.conf > /dev/null 2>&1
mkdir -p /etc/systemd/system/influxdb.service.d
mkdir -p /etc/systemd/system/telegraf.service.d
mkdir -p /etc/systemd/system/grafana-server.service.d
ln -s $PCONFIG/systemd/00-stats4lox-influxdb.conf /etc/systemd/system/influxdb.service.d/00-stats4lox-influxdb.conf
ln -s $PCONFIG/systemd/00-stats4lox-telegraf.conf /etc/systemd/system/telegraf.service.d/00-stats4lox-telegraf.conf
ln -s $PCONFIG/systemd/00-stats4lox-grafana.conf /etc/systemd/system/grafana-server.service.d/00-stats4lox-grafana.conf
systemctl daemon-reload

# The drop-ins shipped with the plugin always contain the "off" state. If the
# user has switched diagnostic logging on, this writes it back into them -
# otherwise every upgrade would silently turn the switch off again while the
# setting still said it was on.
#
# Deliberately NOT by calling config-handler.pl, even though it does exactly
# this at runtime: config-handler.pl takes a LoxBerry lock, and that lock waits
# for "plugininstall" - which is held by the very installation running this
# script. That is a guaranteed ten minute deadlock, and it is how this was
# written the first time round.
echo "<INFO> Applying the service logging setting..."
s4l_servicelog=$(jq -r '.stats4lox.servicelogging // "False"' "$PCONFIG/stats4lox.json" 2>/dev/null)
case "${s4l_servicelog,,}" in
	true|yes|on|1|enabled) s4l_logon=1 ;;
	*)                     s4l_logon=0 ;;
esac

if [ "$s4l_logon" = "1" ]; then
	echo "<INFO>   Diagnostic logging is ENABLED - the services log to $PLOG"
	chmod 0775 "$PLOG" 2>/dev/null
else
	echo "<INFO>   Diagnostic logging is disabled - service output goes to /dev/null"
fi

for s4l_pair in "influxdb:influxdb" "telegraf:telegraf" "grafana-server:grafana"; do
	s4l_svc=${s4l_pair%%:*}
	s4l_user=${s4l_pair#*:}
	case "$s4l_svc" in
		grafana-server) s4l_file="$PCONFIG/systemd/00-stats4lox-grafana.conf" ;;
		*)              s4l_file="$PCONFIG/systemd/00-stats4lox-$s4l_svc.conf" ;;
	esac
	# Rebuilt from scratch rather than patched. These files are managed by the
	# plugin, not by the user, and an upgrade restores the user's copy over the
	# shipped one - so a drop-in damaged by an earlier version would survive
	# forever. Rebuilding also repairs the InfluxDB drop-in, which lost its
	# ExecStart override once and made the service fall back to the packaged
	# start script without anything looking wrong.
	printf '# Written by Stats4Lox - do not edit, use the switch under Settings\n[Service]\n' > "$s4l_file.s4lnew"
	if [ "$s4l_svc" = "influxdb" ]; then
		printf 'ExecStart=\nExecStart=%s/startinflux.sh\n' "$PBIN" >> "$s4l_file.s4lnew"
	fi
	if [ "$s4l_logon" = "1" ]; then
		printf 'StandardOutput=append:%s/%s.log\nStandardError=append:%s/%s.log\n' \
			"$PLOG" "$s4l_svc" "$PLOG" "$s4l_svc" >> "$s4l_file.s4lnew"
		touch "$PLOG/$s4l_svc.log"
		chown "$s4l_user:loxberry" "$PLOG/$s4l_svc.log" 2>/dev/null
		chmod 0644 "$PLOG/$s4l_svc.log" 2>/dev/null
	else
		printf 'StandardOutput=null\nStandardError=null\n' >> "$s4l_file.s4lnew"
	fi
	mv "$s4l_file.s4lnew" "$s4l_file"
done
systemctl daemon-reload

# Activate InfluxDB service and start
echo "<INFO> Starting InfluxDB..."
systemctl unmask influxdb.service
systemctl enable --now influxdb
systemctl daemon-reload
systemctl start influxdb
sleep 3

# Check status
if ! systemctl is-active --quiet influxdb; then
	s4l_service_failed influxdb
	exit 2
else
	echo "<OK> InfluxDB service is running."
fi

# Check InfluxDB user. Create it if not exists
#RESP=`$PBIN/s4linflux -execute "SHOW USERS" | grep -e "^$INFLUXDBUSER\W*true$" | wc -l`
#RESP=`$INFLUXBIN -ssl -unsafeSsl -username $INFLUXDBUSER -password '$INFLUXDBPASS' -execute "SHOW USERS" | grep -e "^$INFLUXDBUSER\W*true$" | wc -l`
#echo "Response checking Influx user is: $RESP"
if [ $UPGRADE -eq "0" ]; then
	echo "<INFO> Creating default InfluxDB user 'stats4lox' as admin user."
	INFLUXDBUSER="stats4lox"
	INFLUXDBPASS=`head /dev/urandom | tr -dc A-Za-z0-9 | head -c16`

	# Debug
	#echo "Influx User: $INFLUXDBUSER"
	#echo "Influx Pass: $INFLUXDBPASS"

	$INFLUXBIN -ssl -unsafeSsl -execute "CREATE USER $INFLUXDBUSER WITH PASSWORD '$INFLUXDBPASS' WITH ALL PRIVILEGES"
	#echo "Coammand is: $INFLUXBIN -ssl -unsafeSsl -execute \"CREATE USER $INFLUXDBUSER WITH PASSWORD '$INFLUXDBPASS' WITH ALL PRIVILEGES\""
	#echo "Response creating Influx user is: $?"
	if [ $? -ne 0 ]; then
		echo "<ERROR> Could not create default InfluxDB user. Giving up."
		exit 2
	else
		echo "<OK> Default InfluxDB user '$INFLUXDBUSER' created successfully."
		echo "<INFO> Saving credentials in cred.json."
		jq ".influx.influxdbuser = \"$INFLUXDBUSER\"" $PCONFIG/cred.json > $PCONFIG/cred.json.new
		mv $PCONFIG/cred.json.new $PCONFIG/cred.json
		jq ".influx.influxdbpass = \"$INFLUXDBPASS\"" $PCONFIG/cred.json > $PCONFIG/cred.json.new
		mv $PCONFIG/cred.json.new $PCONFIG/cred.json
		chown loxberry:loxberry $PCONFIG/cred.json
		chmod 640 $PCONFIG/cred.json
	fi
else
	echo "<OK> We are in Upgrade mode. I will use existing credentials."
fi

# Check for stats4lox database. Create it if not exists
#RESP=`$PBIN/s4linflux -execute "SHOW DATABASES" | grep -e "^stats4lox$" | wc -l`
#if [ $RESP -eq 0 ]; then
if [ $UPGRADE -eq "0" ]; then
	echo "<INFO> Creating default InfluxDB database 'stats4lox'."
	$PBIN/s4linflux -execute "CREATE DATABASE stats4lox"
	if [ $? -gt 0 ]; then
		echo "<ERROR> Could not create default InfluxDB database. Giving up."
		exit 2
	else
		echo "<OK> InfluxDB database 'stats4lox' created successfully."
	fi
else
	echo "<OK> We are in Upgrade mode. I will use existing database stats4lox."
fi

# Activating own telegraf config which is delivered with the plugin
echo "<INFO> Activating my own Telegraf configuration."
if [ -d /etc/telegraf ] && [ ! -L /etc/telegraf ]; then
	rm -rf /etc/telegraf.orig
	mv /etc/telegraf /etc/telegraf.orig
fi
if [ ! -L /etc/default/telegraf ]; then
	rm -f /etc/default/telegraf.orig
	mv /etc/default/telegraf /etc/default/telegraf.orig
fi
rm -rf /etc/telegraf > /dev/null 2>&1
rm -f /etc/default/telegraf > /dev/null 2>&1
ln -sfn $PCONFIG/telegraf /etc/telegraf
ln -s $PCONFIG/telegraf/telegraf.env /etc/default/telegraf

# Correct permissions - influxdb must have write permissions to database folders
echo "<INFO> Set permissions for user telegraf for all config/data folders: $PDATA/telegraf $PCONFIG/telegraf"
chown -R telegraf:loxberry $PDATA/telegraf
chown -R telegraf:loxberry $PCONFIG/telegraf

# Debug:
echo "<INFO> Current file permisssions in $PDATA/telegraf"
ls -l $PDATA/telegraf
echo "<INFO> Current file permisssions in $PCONFIG/telegraf"
ls -l $PCONFIG/telegraf

# Saving InfluxDB credentials in Telegraf config and set restrictive permissions to that file
#
# REPLACE THIS WITH CONFIG-HANDLER LATER ON
#
echo "<INFO> Saving credentials in Telegraf configuration (telegraf.env) and restart Telegraf afterwards."
awk -v s="USER_INFLUXDB=\"$INFLUXDBUSER\"" '/^USER_INFLUXDB=/{$0=s;f=1} {a[++n]=$0} END{if(!f)a[++n]=s;for(i=1;i<=n;i++)print a[i]>ARGV[1]}' $PCONFIG/telegraf/telegraf.env
awk -v s="PASS_INFLUXDB=\"$INFLUXDBPASS\"" '/^PASS_INFLUXDB=/{$0=s;f=1} {a[++n]=$0} END{if(!f)a[++n]=s;for(i=1;i<=n;i++)print a[i]>ARGV[1]}' $PCONFIG/telegraf/telegraf.env
chown telegraf:loxberry $PCONFIG/telegraf/telegraf.env
chmod 660 $PCONFIG/telegraf/telegraf.env

# Use correct Webserver Port in Telegraf
#
# REPLACE THIS WITH CONFIG-HANDLER LATER ON
#
echo "<INFO> Activating LB Webserver Port in the Telegraf grabber drop-ins and restart Telegraf afterwards."
LBWEBSERVERPORT=`perl -e 'use LoxBerry::System; print lbwebserverport();'`
# Every grabber URL in every drop-in, addressed by the URL itself rather than by
# the line it sits on. The Loxone drop-in writes its array on one line, the other
# two spread it over several, and the previous version rewrote "the line that
# starts with urls =" - which only ever worked for the first of them. The
# Miniserver grabber has therefore always been called on port 80 no matter what
# the LoxBerry web server was configured to use.
sed -i -E "s#http://localhost(:[0-9]+)?/admin/plugins/[^/]+/grabber/#http://localhost:$LBWEBSERVERPORT/admin/plugins/$PDIR/grabber/#g" \
	$PCONFIG/telegraf/telegraf.d/*.conf

# Migrate options that the installed Telegraf version does not accept any
# more. Runs on every install and upgrade, so a configuration restored from an
# older version is repaired before Telegraf is started for the first time.
echo "<INFO> Checking Telegraf configuration for obsolete options..."
s4l_migrate_telegraf_config "$PCONFIG/telegraf/telegraf.conf"
for s4l_dropin in "$PCONFIG"/telegraf/telegraf.d/*.conf; do
	s4l_migrate_telegraf_config "$s4l_dropin"
done

# Telegraf mit neuer Config starten
echo "<INFO> Starting Telegraf..."
systemctl unmask telegraf.service
systemctl enable --now telegraf
systemctl daemon-reload
systemctl start telegraf
sleep 3

# Check status
if ! systemctl is-active --quiet telegraf; then
	s4l_service_failed telegraf
	echo "<FAIL> A common cause is an option in a telegraf.d/*.conf drop-in that"
	echo "<FAIL> the installed Telegraf version does not know any more."
	exit 2
else
	echo "<OK> Telegraf service is running."
fi

# Activate own config delivered with plugin
echo "<INFO> Activating my own Grafana configuration."
if [ -d /etc/grafana ] && [ ! -L /etc/grafana ]; then
	rm -rf /etc/grafana.orig
	mv /etc/grafana /etc/grafana.orig
fi
rm -rf /etc/grafana > /dev/null 2>&1
ln -sfn $PCONFIG/grafana /etc/grafana

# Remove the self-referencing symlink that older plugin versions left behind.
#
# Those versions ran "ln -s $PCONFIG/grafana /etc/grafana" without removing
# /etc/grafana first. When it already was a symlink to $PCONFIG/grafana, ln
# followed it and created the link INSIDE the target - $PCONFIG/grafana/grafana
# pointing at itself. It survives every upgrade because the configuration is
# restored with rsync, so it is still sitting in installations from 2024.
#
# Harmless in daily use, but anything that resolves it runs into a loop. The
# "ln -sfn" above keeps it from coming back.
if [ -L "$PCONFIG/grafana/grafana" ]; then
	rm -f "$PCONFIG/grafana/grafana"
	echo "<INFO> Removed stale self-referencing symlink $PCONFIG/grafana/grafana."
fi

# Give grafana user permissions to data/provisioning
$PBIN/provisioning/set_datasource_influx.pl
$PBIN/provisioning/set_dashboard_provider.pl

# Correct permissions - influxdb must have write permissions to database folders
echo "<INFO> Set permissions for user grafana for all config/data folders: $PDATA/grafana $PCONFIG/grafana"
# Deliberately before the chown below: sqlite3 runs as root here and leaves
# root-owned -wal/-journal files behind, which the chown then puts right.
s4l_migrate_grafana_db "$PDATA/grafana/grafana.db"

chown -R grafana:loxberry $PDATA/grafana
chown -R grafana:loxberry $PCONFIG/grafana

# Debug:
echo "<INFO> Current file permisssions in $PDATA/grafana:"
ls -l $PDATA/grafana
echo "<INFO> Current file permisssions in $PCONFIG/grafana"
ls -l $PCONFIG/grafana

# Counterpart to the plugins-bundled workaround in preroot.sh.
#
# If the Grafana package was reconfigured, its postinst has put the directory
# back in place and the copy we saved is obsolete. If it did not run - because
# apt had nothing to do - we move ours back, so that the bundled plugins are
# not lost.
S4L_GRAFANA_DATA_DIR=$( . /etc/default/grafana-server 2>/dev/null; echo "$DATA_DIR" )
[ -n "$S4L_GRAFANA_DATA_DIR" ] || S4L_GRAFANA_DATA_DIR=/var/lib/grafana

if [ -d "$S4L_GRAFANA_DATA_DIR/plugins-bundled.stats4lox-bak" ]; then
	if [ -d "$S4L_GRAFANA_DATA_DIR/plugins-bundled" ]; then
		rm -rf "$S4L_GRAFANA_DATA_DIR/plugins-bundled.stats4lox-bak"
	else
		mv "$S4L_GRAFANA_DATA_DIR/plugins-bundled.stats4lox-bak" "$S4L_GRAFANA_DATA_DIR/plugins-bundled"
		echo "<INFO> Restored Grafana's plugins-bundled - the package was not reconfigured."
	fi
	chown -R grafana:grafana "$S4L_GRAFANA_DATA_DIR/plugins-bundled" > /dev/null 2>&1
fi

# Activate Grafana
echo "<INFO> Starting Grafana..."
systemctl enable --now grafana-server
systemctl daemon-reload
systemctl start grafana-server
sleep 5

# Check status. This check was missing completely before, so a Grafana that
# refused to start was reported as a successful installation.
if ! systemctl is-active --quiet grafana-server; then
	s4l_service_failed grafana-server
	echo "<FAIL> A common cause is an option in grafana.ini that the installed"
	echo "<FAIL> Grafana version does not know any more, or an invalid file in"
	echo "<FAIL> $PCONFIG/grafana/provisioning/."
	exit 2
else
	echo "<OK> Grafana service is running."
fi

# Start/Stop MQTT Live Service
echo "<INFO> Starting MQTTLive Service..."
su loxberry -c "$PBIN/mqtt/mqttlive.php >> $PLOG/mqttlive.log 2>&1 &"

# Adjust owner of config-handler
echo "<INFO> Chown config-handler to root..."
chown root:root $PBIN/config-handler.pl

# For debugging
if [ $UPGRADE -eq "1" ]; then
	echo "<INFO> We are in Upgrade mode. Do some checks for debugging..."
	echo "<INFO> Existing users (gives an error if we have wrong credentials):"
	$PBIN/s4linflux -execute "SHOW USERS"
	echo "<INFO> Existing databases (gives an error if we have wrong credentials):"
	$PBIN/s4linflux -execute "SHOW DATABASES"
fi

exit 0
