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

INFLUXDBIN=`which influxd`
INFLUXBIN=`which influx`
OPENSSLBIN=`which openssl`
TELEGRAFBIN=`which telegraf`
ERROR=0

# Checking for InfluxDB and Telegraf
if [ ! -x $INFLUXDBIN ]; then
	echo "<FAIL> Seems that InfluxDB was not installed correctly. Giving up."
	exit 2
fi
if [ ! -x $TELEGRAFBIN ]; then
	echo "<FAIL> Seems that Telegraf was not installed correctly. Giving up."
	exit 2
fi

# Stop all services
echo "<INFO> Stopping InfluxDB and Telegraf."
systemctl stop influxdb
systemctl stop telegraf

# Set permissions
echo "<INFO> Adding user influxdb and telegraf to loxberry group."
usermod -a -G loxberry telegraf
usermod -a -G loxberry influxdb

# Get InfluxDB credentials
INFLUXDBUSER=`jq -r '.influx.influxdbuser' $PCONFIG/cred.json`
INFLUXDBPASS=`jq -r '.influx.influxdbpass' $PCONFIG/cred.json`
if [ "$INFLUXDBUSER" = "" ]; then
	echo "<WARNING> Could not find credentials for InfluxDB. This may be an error, but I will try to continue. Using default ones: stats4lox/loxberry"
	INFLUXDBUSER="stats4lox"
	INFLUXDBPASS="loxberry"
fi

# Debug
echo "Influx User: $INFLUXDBUSER"
echo "Influx Pass: $INFLUXDBPASS"

# Activate own config delivered with plugin
echo "<INFO> Activating my own InfluxDB configuration."
if [ -d /etc/influxdb ] && [ ! -L /etc/influxdb ]; then
	rm -rf /etc/influxdb.orig
	mv /etc/influxdb /etc/influxdb.orig
fi
rm -rf /etc/influxdb > /dev/null 2>&1
ln -s $PCONFIG/influxdb /etc/influxdb

if [ ! -e $PCONFIG/influxdb/influxdb-selfsigned.key ]; then
	echo "<INFO> No SSL certificates for InfluxDB found."
	echo "<INFO> Creating (new) self-signed SSL certificates."
	$OPENSSLBIN req -x509 -nodes -newkey rsa:2048 -keyout $PCONFIG/influxdb/influxdb-selfsigned.key -out $PCONFIG/influxdb/influxdb-selfsigned.crt -days 3650 -subj "/C=DE/ST=Austria/L=Kollerschlag/O=LoxBerry"
	chown loxberry:loxberry $PCONFIG/influxdb/influxdb-selfsigned.*
	chmod 640 $PCONFIG/influxdb/influxdb-selfsigned.*
else
	echo "<INFO> Found SSL certificates for InfluxDB. I will not create new ones."
fi

# Correct permissions - influxdb must have write permissions to database folders
echo "<INFO> Set permissions for user influxdb for database folders..."
chmod -R 775 $PDATA/influxdb

# Enlarge UDP/IP receive buffer limit for import
echo "<INFO> Enlarge UDP/IP and Unix receive buffer limit..."
sysctl -w net.core.rmem_max=8388608
sysctl -w net.core.rmem_default=8388608
sysctl -w net.unix.max_dgram_qlen=10000
rm -f /etc/sysctl.d/96-stats4lox.conf
ln -s $PCONFIG/sysctl.conf /etc/sysctl.d/96-stats4lox.conf

# Systemd DropIn Config
echo "<INFO> Install Drop-In for Influx and Telegraf systemd services..."
rm -f /etc/systemd/system/influxdb.service.d/00-stats4lox.conf
rm -f /etc/systemd/system/telegraf.service.d/00-stats4lox.conf
mkdir /etc/systemd/system/influxdb.service.d
mkdir /etc/systemd/system/telegraf.service.d
ln -s $PCONFIG/systemd/00-stats4lox.conf /etc/systemd/system/influxdb.service.d/00-stats4lox.conf
ln -s $PCONFIG/systemd/00-stats4lox.conf /etc/systemd/system/telegraf.service.d/00-stats4lox.conf
systemctl daemon-reload

# Activate InfluxDB service and start
echo "<INFO> Starting InfluxDB..."
systemctl unmask influxdb.service
systemctl enable --now influxdb
systemctl start influxdb
sleep 5

# Check status
systemctl status influxdb > /dev/null 2>&1
if [ $? -gt 0 ]; then
	echo "<FAIL> Seems that InfluxDB could not be started. Giving up."
	exit 2
else
	echo "<OK> InfluxDB service is running. Fine."
fi

# Check InfluxDB user. Create it if not exists
RESP=`$INFLUXBIN -ssl -unsafeSsl -username $INFLUXDBUSER -password $INFLUXDBPASS -execute "SHOW USERS" | grep -e "^$INFLUXDBUSER\W*true$" | wc -l`
if [ $RESP -eq 0 ] || [ $? -eq 127 ]; then # If user does not exist or if no admin user at all exists in a fresh installation:
	echo "<INFO> Creating default InfluxDB user 'stats4lox' as dadmin."
	INFLUXDBUSER="stats4lox"
	INFLUXDBPASS=`head /dev/urandom | tr -dc A-Za-z0-9 | head -c16`
	$INFLUXBIN -ssl -unsafeSsl -execute "CREATE USER $INFLUXDBUSER WITH PASSWORD '$INFLUXDBPASS' WITH ALL PRIVILEGES"
	if [ $? -ne 0 ]; then
		echo "<ERROR> Could not create default InfluxDB user. Giving up."
		exit 2
	else
		echo "<OK> Default InfluxDB user 'stats4lox' created successfully. Fine."
		echo "<INFO> Saving credentials in cred.json."
		jq ".influx.influxdbuser = \"$INFLUXDBUSER\"" $PCONFIG/cred.json > $PCONFIG/cred.json.new
		mv $PCONFIG/cred.json.new $PCONFIG/cred.json
		jq ".influx.influxdbpass = \"$INFLUXDBPASS\"" $PCONFIG/cred.json > $PCONFIG/cred.json.new
		mv $PCONFIG/cred.json.new $PCONFIG/cred.json
		chown loxberry:loxberry $PCONFIG/cred.json
		chmod 640 $PCONFIG/cred.json
	fi
else
	echo "<OK> InfluxDB user $INFLUXDBUSER already exists. Fine, I will use this account and leave it untouched."
fi

# Check for stats4lox database. Create it if not exists
RESP=`$INFLUXBIN -ssl -unsafeSsl -username $INFLUXDBUSER -password $INFLUXDBPASS -execute "SHOW DATABASES" | grep -e "^stats4lox$" | wc -l`
if [ $RESP -eq 0 ]; then
	echo "<INFO> Creating default InfluxDB database 'stats4lox'."
	$INFLUXBIN -ssl -unsafeSsl -username $INFLUXDBUSER -password $INFLUXDBPASS -execute "CREATE DATABASE stats4lox"
	if [ $? -gt 0 ]; then
		echo "<ERROR> Could not create default InfluxDB database. Giving up."
		exit 2
	else
		echo "<OK> InfluxDB database 'stat4lox' created successfully. Fine."
	fi

	#echo "<INFO> Current available InfluxDB databases are as follows:"
	#$INFLUXBIN -username loxberry -password loxberry -execute "SHOW DATABASES"
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
ln -s $PCONFIG/telegraf /etc/telegraf
ln -s $PCONFIG/telegraf/telegraf.env /etc/default/telegraf

# Saving InfluxDB credentials in Telegraf config and set restrictive permissions to that file
echo "<INFO> Saving credentials in Telegraf configuration (telegraf.env) and restart Telegraf afterwards."
awk -v s="USER_INFLUXDB=\"$INFLUXDBUSER\"" '/^USER_INFLUXDB=/{$0=s;f=1} {a[++n]=$0} END{if(!f)a[++n]=s;for(i=1;i<=n;i++)print a[i]>ARGV[1]}' $PCONFIG/telegraf/telegraf.env
awk -v s="PASS_INFLUXDB=\"$INFLUXDBPASS\"" '/^PASS_INFLUXDB=/{$0=s;f=1} {a[++n]=$0} END{if(!f)a[++n]=s;for(i=1;i<=n;i++)print a[i]>ARGV[1]}' $PCONFIG/telegraf/telegraf.env
chown loxberry:loxberry $PCONFIG/telegraf/telegraf.env
chmod 640 $PCONFIG/telegraf/telegraf.env

# Telegraf mit neuer Config starten
echo "<INFO> Starting Telegraf..."
systemctl unmask telegraf.service
systemctl enable --now telegraf
systemctl start telegraf
sleep 3

# Check status
systemctl status telegraf > /dev/null 2>&1
if [ $? -gt 0 ]; then
	echo "<FAIL> Seems that Telegraf could not be started. Giving up."
	exit 2
else
	echo "<OK> Telegraf service is running. Fine."
fi

# Give grafana user permissions to data/provisioning
chmod 770 $PDATA/provisioning
if [ -d "$LBPHTMLAUTH/grafana" ]; then
	$PBIN/provisioning/set_datasource_influx.pl
	$PBIN/provisioning/set_dashboard_provider.pl
fi

# Start/Stop MQTT Live Service
echo "<INFO> Starting MQTTLive Service..."
pkill -f mqttlive.php > /dev/null 2>&1
su loxberry -c "$PBIN/mqtt/mqttlive.php >> $PLOG/mqttlive.log 2>&1 &"

exit 0
