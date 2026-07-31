#!/bin/bash

# Abort on failures inside pipelines as well - we check apt/gpg results below
set -o pipefail

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

#########################################################################
# Helpers for a safe repository setup
#########################################################################

# Documented location for locally managed apt keyrings. Do NOT use
# /etc/apt/trusted.gpg.d - a key placed there is trusted for EVERY
# repository on the system, which would allow a compromised InfluxData or
# Grafana key to sign forged Debian system packages.
S4L_KEYRING_DIR=/etc/apt/keyrings

s4l_fail() {
	echo "<FAIL> $*"
	exit 2
}

# Downloads a repository signing key, verifies its fingerprint and installs
# it as an ASCII armored keyring. Aborts the installation on any problem -
# we must never trust a key we could not verify.
#
# s4l_install_repo_key <url> <expected fingerprint> <target .asc file>
s4l_install_repo_key() {
	local url="$1"
	local fpr="$2"
	local dest="$3"
	local tmp

	tmp=$(mktemp) || s4l_fail "Could not create a temporary file."

	echo "<INFO> Downloading repository key from $url"
	if ! curl -fsSL --retry 3 --retry-delay 2 -o "$tmp" "$url"; then
		rm -f "$tmp"
		s4l_fail "Could not download the repository key from $url. No internet connection?"
	fi

	echo "<INFO> Verifying key fingerprint $fpr"
	if ! gpg --show-keys --with-fingerprint --with-colons "$tmp" 2>/dev/null | grep -q "^fpr:\+${fpr}:$"; then
		rm -f "$tmp"
		s4l_fail "Fingerprint $fpr was not found in the key from $url. Refusing to trust this key."
	fi

	install -d -m 0755 "$S4L_KEYRING_DIR" || { rm -f "$tmp"; s4l_fail "Could not create $S4L_KEYRING_DIR."; }
	install -m 0644 "$tmp" "$dest" || { rm -f "$tmp"; s4l_fail "Could not install the keyring $dest."; }
	rm -f "$tmp"
	echo "<OK> Installed keyring $dest"
}

# Stop all services
echo "<INFO> Stopping InfluxDB, Grafana and Telegraf."
systemctl daemon-reload
systemctl stop influxdb
systemctl stop telegraf
systemctl stop grafana-server
killall /usr/bin/influxd

# Grafana's postinst moves its bundled plugins into the data directory with an
# unguarded mv:
#
#   mv $GRAFANA_HOME/data/plugins-bundled $DATA_DIR
#
# which fails the moment the target already exists:
#
#   mv: cannot move '/usr/share/grafana/data/plugins-bundled' to
#   '/var/lib/grafana/plugins-bundled': Directory not empty
#   dpkg: error processing package grafana (--configure)
#
# This is a known packaging bug, referenced in their own postinst as
# grafana/grafana#123110. It does not appear on the first installation but on
# every REINSTALL of an already installed version - which is exactly what
# LoxBerry does on every single plugin update.
#
# Grafana's postinst runs TWICE during one plugin installation, and it recreates
# the directory each time it succeeds. Moving it aside once is not enough:
#
#   1. we move it aside                                        -> gone
#   2. "dpkg --configure -a" below repairs a package left over
#      from an earlier run, its postinst succeeds              -> recreated
#   3. LoxBerry reinstalls the packages from dpkg/apt, the
#      postinst runs again and finds the target occupied       -> fails
#
# So this is done at the very beginning - before any apt or dpkg call, because
# a package stuck in "half-configured" makes dpkg refuse everything else and
# would abort the installation long before this point - and once more at the
# very end of this script, immediately before LoxBerry installs the packages.
#
# Deliberately moved and not deleted: if the package step does not run at all,
# postroot.sh puts it back, so the bundled plugins cannot get lost.
# The target is read the way the postinst reads it - DATA_DIR comes from
# /etc/default/grafana-server, which is a conffile and may have been changed.
s4l_grafana_bundled_aside() {
	local datadir
	datadir=$( . /etc/default/grafana-server 2>/dev/null; echo "$DATA_DIR" )
	[ -n "$datadir" ] || datadir=/var/lib/grafana

	if [ -d "$datadir/plugins-bundled" ]; then
		echo "<INFO> Moving Grafana's plugins-bundled aside so its postinst can succeed (grafana/grafana#123110)."
		rm -rf "$datadir/plugins-bundled.stats4lox-bak"
		mv "$datadir/plugins-bundled" "$datadir/plugins-bundled.stats4lox-bak"
	fi
}

s4l_grafana_bundled_aside

# Check for old debian influx-client package (V1.6.4 - out of date) which we do not want anymore
INFLUXCLIENT=`dpkg -s influxdb-client 2>/dev/null | grep -c "ok installed"`
if [ $INFLUXCLIENT -eq "1" ]; then
	echo "<INFO> Found installed influx-client package from out-of-date Version 1.6.4. We remove it from your system."
	APT_LISTCHANGES_FRONTEND=none DEBIAN_FRONTEND=noninteractive apt-get -y -q purge influxdb-client
fi

# Installing InfluxDB and Grafana in newer versions than Debian included

export APT_LISTCHANGES_FRONTEND=none
export DEBIAN_FRONTEND=noninteractive

# Step 1: start from a clean slate.
#
# This has to happen BEFORE the first apt-get call. A previous failed
# installation may have left an unusable source behind (e.g. a repository
# whose key could not be verified), and that alone makes every apt-get
# command fail - including the system's own updates.
echo "<INFO> Removing apt configuration of earlier Stats4Lox installations..."
rm -f /etc/apt/sources.list.d/influxdb.list
rm -f /etc/apt/sources.list.d/influxdata.list
rm -f /etc/apt/sources.list.d/influxdata.sources
rm -f /etc/apt/sources.list.d/grafana.list
rm -f /etc/apt/sources.list.d/grafana.sources
rm -f /usr/share/keyrings/influxdata-archive-keyring.gpg
rm -f /usr/share/keyrings/grafana-archive-keyring.gpg
rm -f /etc/apt/trusted.gpg.d/influxdata-archive_compat.gpg
rm -f /etc/apt/trusted.gpg.d/influxdb.gpg
rm -f /etc/apt/trusted.gpg.d/grafanadata-archive_compat.gpg
rm -f /etc/apt/preferences.d/influxdb
rm -f /etc/apt/preferences.d/telegraf
rm -f /etc/apt/preferences.d/grafana
rm -f /etc/apt/preferences.d/stats4lox-influxdata
rm -f /etc/apt/preferences.d/stats4lox-grafana

# Step 2: make sure the tools for the repository setup are present.
#
# preroot.sh runs BEFORE the packages from dpkg/apt are installed, so we
# cannot rely on that list here.
S4L_PREREQ=""
for pkg in gnupg ca-certificates curl; do
	dpkg -s "$pkg" > /dev/null 2>&1 || S4L_PREREQ="$S4L_PREREQ $pkg"
done
if [ -n "$S4L_PREREQ" ]; then
	echo "<INFO> Installing prerequisites for the repository setup:$S4L_PREREQ"
	apt-get -q -y update || s4l_fail "apt-get update failed. Please check /etc/apt/sources.list.d/ first."
	apt-get -y -q install $S4L_PREREQ || s4l_fail "Could not install the prerequisites:$S4L_PREREQ"
fi

# Step 3: add the repositories.
echo "<INFO> Adding/Updating InfluxData repository..."
# Fingerprint of the InfluxData package signing key as published in
# https://docs.influxdata.com/influxdb/v1/introduction/install/
# The full key bundle (influxdata-archive.key) is required: the older
# influxdata-archive_compat.key does NOT contain the key that currently
# signs the repository (DA61C26A0585BD3B) and expired on 2026-01-17.
s4l_install_repo_key \
	https://repos.influxdata.com/influxdata-archive.key \
	24C975CBA61A024EE1B631787C3D57159FC2F927 \
	"$S4L_KEYRING_DIR/influxdata-archive.asc"

cat <<EOT > /etc/apt/sources.list.d/influxdata.sources
# Added by the LoxBerry plugin Stats4Lox - removed again on uninstall
Types: deb
URIs: https://repos.influxdata.com/debian
Suites: stable
Components: main
Signed-By: $S4L_KEYRING_DIR/influxdata-archive.asc
EOT

echo "<INFO> Adding/Updating Grafana repository..."
# Fingerprint of the Grafana Labs signing key as published in
# https://grafana.com/docs/grafana/latest/setup-grafana/installation/debian/
# We use gpg-full.key (not gpg.key): it also contains the 2017 key which
# never expires, so a rotation of the current key does not break us.
s4l_install_repo_key \
	https://apt.grafana.com/gpg-full.key \
	B53AE77BADB630A683046005963FA27710458545 \
	"$S4L_KEYRING_DIR/grafana.asc"

cat <<EOT > /etc/apt/sources.list.d/grafana.sources
# Added by the LoxBerry plugin Stats4Lox - removed again on uninstall
Types: deb
URIs: https://apt.grafana.com
Suites: stable
Components: main
Signed-By: $S4L_KEYRING_DIR/grafana.asc
EOT

# Version pinning AND scope limitation. The negative priority makes sure
# these third party repositories can only ever deliver the packages we
# explicitly ask for - they must not be able to shadow any Debian system
# package. Package specific stanzas take precedence over "Package: *".
echo "<INFO> Using InfluxDB Version 1.12.x and Telegraf Version 1.39.x..."
cat <<EOT > /etc/apt/preferences.d/stats4lox-influxdata
# Added by the LoxBerry plugin Stats4Lox - removed again on uninstall
Package: *
Pin: release o=InfluxDB
Pin-Priority: -1

Package: influxdb
Pin: version 1.12.*
Pin-Priority: 1000

Package: telegraf
Pin: version 1.39.*
Pin-Priority: 1000
EOT

echo "<INFO> Using Grafana Version 13.1.x..."
cat <<EOT > /etc/apt/preferences.d/stats4lox-grafana
# Added by the LoxBerry plugin Stats4Lox - removed again on uninstall
Package: *
Pin: origin "apt.grafana.com"
Pin-Priority: -1

Package: grafana
Pin: version 13.1.*
Pin-Priority: 1000
EOT

echo "<INFO> Updating apt database..."
dpkg --configure -a
apt-get -y -q --fix-broken install || s4l_fail "apt-get --fix-broken install failed. Please repair your package management first."
apt-get -q -y update || s4l_fail "apt-get update failed. Please check /etc/apt/sources.list.d/ and the messages above."

# The repositories have to be usable at this point. If they are not, the
# packages from dpkg/apt would silently not be installed and postroot.sh
# would only run into a wall much later with a misleading error message.
for pkg in influxdb telegraf grafana; do
	if ! apt-cache policy "$pkg" 2>/dev/null | grep -qE 'repos\.influxdata\.com|apt\.grafana\.com'; then
		echo "<FAIL> Package '$pkg' is not available in the pinned version."
		echo "<FAIL> Usually this means the repository signature could not be verified."
		echo "<FAIL> Please also note: InfluxDB is only available up to 1.8.10 for the"
		echo "<FAIL> 32-bit ARM architecture (armhf). Stats4Lox requires a 64-bit system"
		echo "<FAIL> (arm64/aarch64 or amd64/x86_64)."
		s4l_fail "Please check the apt messages above."
	fi
done
echo "<OK> InfluxData and Grafana repositories are set up and usable."

echo "<INFO> Deactivating existing plugin configuration for Influx, Grafana and Telegraf..."
if [ -L /etc/influxdb ]; then
	rm -rf /etc/influxdb
	if [ -d /etc/influxdb.orig ]; then
		mv /etc/influxdb.orig /etc/influxdb
	else
		mkdir -p /etc/influxdb
	fi
fi
if [ -d /var/lib/influxdb ]; then
	chown -R influxdb:influxdb /var/lib/influxdb
fi

if [ -L /etc/telegraf ]; then
	rm -rf /etc/telegraf
	if [ -d /etc/telegraf.orig ]; then
		mv /etc/telegraf.orig /etc/telegraf
	else
		mkdir -p /etc/telegraf
	fi
fi
if [ -L /etc/grafana ]; then
	rm -rf /etc/grafana
	if [ -d /etc/grafana.orig ]; then
		mv /etc/grafana.orig /etc/grafana
	else
		mkdir -p /etc/grafana
	fi
fi
if [ -d /var/lib/grafana ]; then
	chown -R grafana:grafana /var/lib/grafana
fi

echo "<INFO> Remove old Service DropIn Files..."
rm -f /etc/systemd/system/influxdb.service.d/00-stats4lox.conf
rm -f /etc/systemd/system/telegraf.service.d/00-stats4lox.conf
rm -f /etc/systemd/system/grafana-server.service.d/00-stats4lox.conf
systemctl daemon-reload

echo "<INFO> Chown data files back to loxberry:loxberry for upgrading/backing up..."
if [ -d $PDATA ]; then
	chown -R loxberry:loxberry $PDATA
	chown -R loxberry:loxberry $PCONFIG
	chown -R loxberry:loxberry $PLOG
fi

# Second pass, see the note at the top of this script. Everything above may have
# reconfigured the Grafana package and thereby recreated the directory. This is
# the last thing that runs before LoxBerry installs the packages from dpkg/apt,
# which is what triggers the postinst that trips over it.
s4l_grafana_bundled_aside

exit 0
