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
UPGRADE=0
DATE=`date +%Y%m%d%H%M%S`

function pause(){
   read -p "$*"
}

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
		chown -R loxberry:loxberry $PCONFIG
		rsync -Iav $LBHOMEDIR/data/plugins/${PTEMPDIR}_upgrade/config/* $PCONFIG/
		if [ $? -ne 0 ]; then
			echo "<FAIL> Restoring config files failed. Giving up."
			#pause 'Press [Enter] key to continue...'
			mv $LBHOMEDIR/data/plugins/${PTEMPDIR}_upgrade $LBHOMEDIR/data/plugins/${DATE}_FAILED_INSTALLATION_STATS4LOX
			exit 2
		fi
	else
		echo "<INFO> Folder is empty. Nothing will be restored."
	fi

	#pause 'Press [Enter] key to continue...'

	# Create backup
	mkdir -p $PDATA/backups/plugininstall
	mv $LBHOMEDIR/data/plugins/${PTEMPDIR}_upgrade $PDATA/backups/plugininstall/${DATE}_backup_plugininstall
	PWD=`pwd`
	cd $PDATA/backups/plugininstall
	7z a ${DATE}_backup_plugininstall.7z ${DATE}_backup_plugininstall '-xr!*.7z'
	if [ $? -eq 0 ]; then
		rm -rf $PDATA/backups/plugininstall/${DATE}_backup_plugininstall
	fi
	chown -R loxberry:loxberry $PDATA/backups/plugininstall
	cd $PWD
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
ln -s $PCONFIG/influxdb /etc/influxdb
#chown -R loxberry:loxberry $PCONFIG/influxdb

if [ ! -e $PCONFIG/influxdb/influxdb-selfsigned.key ]; then
	echo "<INFO> No SSL certificates for InfluxDB found."
	echo "<INFO> Creating (new) self-signed SSL certificates."
	$OPENSSLBIN req -x509 -nodes -newkey rsa:2048 -keyout $PCONFIG/influxdb/influxdb-selfsigned.key -out $PCONFIG/influxdb/influxdb-selfsigned.crt -days 3650 -subj "/C=DE/ST=Austria/L=Kollerschlag/O=LoxBerry"
	#chown loxberry:loxberry $PCONFIG/influxdb/influxdb-selfsigned.*
	chmod 660 $PCONFIG/influxdb/influxdb-selfsigned.*
else
	echo "<INFO> Found SSL certificates for InfluxDB. I will not create new ones."
fi

# Correct permissions - influxdb must have write permissions to database folders
echo "<INFO> Set permissions for user influxdb for all config/data folders..."
chown -R influxdb:loxberry $PDATA/influxdb
chown -R influxdb:loxberry $PCONFIG/influxdb

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
mkdir -p /etc/systemd/system/influxdb.service.d
mkdir -p /etc/systemd/system/telegraf.service.d
mkdir -p /etc/systemd/system/grafana-server.service.d
ln -s $PCONFIG/systemd/00-stats4lox.conf /etc/systemd/system/influxdb.service.d/00-stats4lox.conf
ln -s $PCONFIG/systemd/00-stats4lox.conf /etc/systemd/system/telegraf.service.d/00-stats4lox.conf
ln -s $PCONFIG/systemd/00-stats4lox.conf /etc/systemd/system/grafana-server.service.d/00-stats4lox.conf
systemctl daemon-reload

# Activate InfluxDB service and start
echo "<INFO> Starting InfluxDB..."
systemctl unmask influxdb.service
systemctl enable --now influxdb
systemctl start influxdb
sleep 3

# Check status
systemctl status influxdb > /dev/null 2>&1
if [ $? -gt 0 ]; then
	echo "<FAIL> Seems that InfluxDB could not be started. Giving up."
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
ln -s $PCONFIG/telegraf /etc/telegraf
ln -s $PCONFIG/telegraf/telegraf.env /etc/default/telegraf

# Correct permissions - influxdb must have write permissions to database folders
echo "<INFO> Set permissions for user telegraf for all config/data folders..."
chown -R telegraf:loxberry $PDATA/telegraf
chown -R telegraf:loxberry $PCONFIG/telegraf

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
echo "<INFO> Activating LB Webserver Port in Telegraf configuration (telegraf.d/stats4lox_loxone.conf) and restart Telegraf afterwards."
LBWEBSERVERPORT=`perl -e 'use LoxBerry::System; print lbwebserverport();'`
sed -i "s/^  urls = .*$/  urls = [ \"http:\/\/localhost:$LBWEBSERVERPORT\/admin\/plugins\/$PDIR\/grabber\/grabber_loxone.cgi\" ]/g" $PCONFIG/telegraf/telegraf.d/stats4lox_loxone.conf

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
	echo "<OK> Telegraf service is running."
fi

# Activate own config delivered with plugin
echo "<INFO> Activating my own Grafana configuration."
if [ -d /etc/grafana ] && [ ! -L /etc/grafana ]; then
	rm -rf /etc/grafana.orig
	mv /etc/grafana /etc/grafana.orig
fi
rm -rf /etc/grafana > /dev/null 2>&1
ln -s $PCONFIG/grafana /etc/grafana

# Give grafana user permissions to data/provisioning
$PBIN/provisioning/set_datasource_influx.pl
$PBIN/provisioning/set_dashboard_provider.pl

# Correct permissions - influxdb must have write permissions to database folders
echo "<INFO> Set permissions for user grafana for all config/data folders..."
chown -R grafana:loxberry $PDATA/grafana
chown -R grafana:loxberry $PCONFIG/grafana

# Activate Grafana
echo "<INFO> Starting Grafana..."
systemctl enable --now grafana-server
systemctl start grafana-server
sleep 3

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
