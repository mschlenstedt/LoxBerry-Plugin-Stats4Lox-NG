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

# Get InfluxDB credentials
INFLUXDBUSER=`jq -r '.Credentials.influxdbuser' $PCONFIG/cred.json`
INFLUXDBPASS=`jq -r '.Credentials.influxdbpass' $PCONFIG/cred.json`
if [ $INFLUXDBUSER -eq "" ]; then
	echo "<WARNING> Could not find credentials for InfluxDB. This may be an error, but I will try to continue. Using default ones: stat4lox/loxberry"
	INFLUXDBUSER = "stat4lox"
	INFLUXDBPASS = "loxberry"
	ERROR = 1
fi

# ctivate own config delivered with plugin
echo "<INFO> Activating my own InfluxDB configuration."
if [ -d /etc/influxdb ] && [ ! -L /etc/influxdb ]; then
	mv /etc/influxdb /etc/influxdb.orig
fi
rm -rf /etc/influxdb > /dev/null 2>&1
ln -s $PCONFIG/influxdb /etc/influxdb

if [ ! -x "$PCONFIG/influxdb/influxdb-selfsigned.key" ]; then
	echo "<INFO> No SSL certificates for InfluxDB found."
	echo "<INFO> Creating (new) self-signed SSL certificates."
	$OPENSSLBIN req -x509 -nodes -newkey rsa:2048 -keyout $PCONFIG/influxdb/influxdb-selfsigned.key -out $PCONFIG/influxdb/influxdb-selfsigned.crt -days 3650 -subj "/C=DE/ST=Austria/L=Kollerschlag/O=LoxBerry"
	chown loxberry:loxberry $PCONFIG/influxdb/influxdb-selfsigned.*
else
	echo "<INFO> Found SSL certificates for InfluxDB. I will not create new ones."
fi

# Activate InfluxDB service and start
echo "<INFO> Starting InfluxDB..."
systemctl unmask influxdb.service
systemctl enable --now influxdb
#systemctl restart influxdb # Also restart to make sure new config is used

# Check status
service influxdb status
if [ $? -gt 0 ]; then
	echo "<FAIL> Seems that InfluxDB could not be started. Giving up."
	exit 2
else
	echo "<OK> InfluxDB service is running. Fine."
fi

# Show current config to log
#echo "<INFO> Current configuration of InfluxDB is as follows:"
#$INFLUXDBIN config

# Check InfluxDB user. Create it if not exists
RESP=`$INFLUXBIN -username $INFLUXDBUSER -password $INFLUXDBPASS -execute "SHOW USERS" | grep -e "^$INFLUXDBUSER\W*true$" | wc -l`
if [ $RESP -eq 0 ]; then
	echo "<INFO> Creating default InfluxDB user 'stat4lox'."
	INFLUXDBNEWPASS=`cat /dev/urandom|tr -dc "a-zA-Z0-9-_\$\?" | fold -w16 | head -n 1`
	$INFLUXBIN -execute "CREATE USER stat4lox WITH PASSWORD $INFLUXDBNEWPASS WITH ALL PRIVILEGES"
	if [ $? -ne 0 ]; then
		echo "<ERROR> Could not create default InfluxDB user. Nevertheless, I will try to continue. You have to make sure that you configure user/password for InfluxDB correctly by your own later on!"
		ERROR = 1
	else
		echo "<OK> Default InfluxDB user 'stat4lox' created sucessfully. Fine."
		echo "<INFO> Saving credentials in cred.json."
		INFLUXDBUSER = `jq -r '.Credentials.influxdbuser' $PCONFIG/cred.json`
		jq ".Credentials.influxdbuser = \"$INFLUXDBUSER\"" $PCONFIG/cred.json > $PCONFIG/cred.json.new
		mv $PCONFIG/cred.json.new $PCONFIG/cred.json
		jq ".Credentials.influxdbpass = \"$INFLUXDBPASS\"" $PCONFIG/cred.json > $PCONFIG/cred.json.new
		mv $PCONFIG/cred.json.new $PCONFIG/cred.json
		chown loxberry:loxberry $PCONFIG/cred.json
		chmod 640 $PCONFIG/cred.json
	fi
else
	echo "<OK> InfluxDB user $INFLUXDBUSER already exists. Fine, I will use this one."
fi

# Check for stat4lox database. Create it if not exists
RESP=`$INFLUXBIN -username $INFLUXDBUSER -password $INFLUXDBPASS -execute "SHOW DATABASES" | grep -e "^stats4lox$" | wc -l`
if [ $RESP -eq 0 ]; then
	echo "<INFO> Creating default InfluxDB database 'stats4lox'."
	$INFLUXBIN -username $INFLUXDBUSER -password $INFLUXDBPASS -execute "CREATE DATABASE stats4lox"
	if [ $? -ne 0 ]; then
		echo "<ERROR> Could not create default InfluxDB database. Nevertheless, I will try to continue. You have to make sure that a database 'stats4lox' exists later on!"
		ERROR=1
	else
		echo "<OK> InfluxDB database 'stat4lox' created sucessfully. Fine."
	fi

	echo "<INFO> Current available InfluxDB databases are as follows:"
	$INFLUXBIN -username loxberry -password loxberry -execute "SHOW DATABASES"
fi

# Activating own telegraf config which is delivered with the plugin
echo "<INFO> Activating my own Telegraf configuration."
if [ -d /etc/telegraf ] && [ ! -L /etc/telegraf ]; then
	mv /etc/telegraf /etc/telegraf.orig
	mv /etc/default/telegraf /etc/default/telegraf.orig
fi
if [ ! -L /etc/default/telegraf ]; then
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
usermod -a -G loxberry telegraf

# Telegraf mit neuer Config starten
echo "<INFO> Starting Telegraf..."
systemctl unmask telegraf.service
systemctl enable --now telegraf
#systemctl restart telegraf # Also restart to make sure new config is used

# Check status
service telegraf status
if [ $? -gt 0 ]; then
	echo "<FAIL> Seems that Telegraf could not be started. Giving up."
	exit 2
else
	echo "<OK> Telegraf service is running. Fine."
fi

if [ $ERROR -eq "1" ]; then
	exit 1
else
	exit 0
fi

exit 0
