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

# Stop all services
echo "<INFO> Stopping InfluxDB, Grafana and Telegraf."
systemctl daemon-reload
systemctl stop influxdb
systemctl stop telegraf
systemctl stop grafana-server
killall /usr/bin/influxd

# Check for old debian influx-client package (V1.6.4 - out of date) which we do not want anymore
INFLUXCLIENT=`dpkg -s influxdb-client 2>/dev/null | grep -c "ok installed"`
if [ $INFLUXCLIENT -eq "1" ]; then
	echo "<INFO> Found installed influx-client package from out-of-date Version 1.6.4. We remove it from your system."
	APT_LISTCHANGES_FRONTEND=none DEBIAN_FRONTEND=noninteractive apt-get -y -q purge influxdb-client
fi

# Installing InfluxDB and Grafana in newer versions than Debian included
echo "<INFO> Adding/Updating Influx repository..."
wget -qO- https://repos.influxdata.com/influxdb.key | sudo apt-key add - 2>/dev/null
#source /etc/os-release
echo "deb https://repos.influxdata.com/debian stable main" | sudo tee /etc/apt/sources.list.d/influxdb.list

echo "<INFO> Using Influx Version 1.8.x..."
rm -f /etc/apt/preferences.d/influxdb
cat <<EOT >> /etc/apt/preferences.d/influxdb
Package: influxdb
Pin: version 1.8.*
Pin-Priority: 1000
EOT

echo "<INFO> Using Grafana Version 9.2.x..."
rm -f /etc/apt/preferences.d/grafana
cat <<EOT >> /etc/apt/preferences.d/grafana
Package: grafana
Pin: version 9.2.*
Pin-Priority: 1000
EOT

echo "<INFO> Adding/Updating Grafana repository..."
wget -q -O - https://packages.grafana.com/gpg.key | sudo apt-key add - 2>/dev/null
echo "deb https://packages.grafana.com/oss/deb stable main" | sudo tee /etc/apt/sources.list.d/grafana.list

echo "<INFO> Updating apt database..."
export APT_LISTCHANGES_FRONTEND=none
export DEBIAN_FRONTEND=noninteractive
dpkg --configure -a
APT_LISTCHANGES_FRONTEND=none DEBIAN_FRONTEND=noninteractive apt-get -y -q --allow-unauthenticated --fix-broken --reinstall --allow-downgrades --allow-remove-essential --allow-change-held-packages --purge autoremove
APT_LISTCHANGES_FRONTEND=none DEBIAN_FRONTEND=noninteractive apt-get -q -y --allow-unauthenticated --allow-downgrades --allow-remove-essential --allow-change-held-packages update

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

exit 0
