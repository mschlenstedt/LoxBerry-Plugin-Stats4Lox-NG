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

# Checking for InfluxDB
if [ ! -x $INFLUXDBIN ]; then
	echo "<FAIL> Seems that InfluxDB was not installed correctly. Giving up."
	exit 2
fi

echo "<INFO> Starting InfluxDB..."
systemctl unmask influxdb.service
systemctl enable --now influxdb

service influxdb status
if [ $? -ne 0 ]; then
	echo "<FAIL> Seems that InfluxDB could not be started. Giving up."
	exit 2
else
	echo "<OK> InfluxDB service is running."
fi

echo "<INFO> Current configuration of InfluxDB is as follows:"
$INFLUXDBIN config

USEREXISTS=0
RESP=`$INFLUXBIN -execute "SHOW USERS" | grep -e "^loxberry\W*true$" | wc -l`
if [ $RESP -eq 0 ]; then
	echo "<INFO> Creating default InfluxDB user loxberry/loxberry."
	$INFLUXBIN -execute "CREATE USER loxberry WITH PASSWORD 'loxberry' WITH ALL PRIVILEGES"
	if [ $? -ne 0 ]; then
		echo "<ERROR> Could not create default InfluxDB user. Nevertheless, I will try to continue. You have to make sure that a user 'loxberry' with password 'loxberry' exists!"
		exit 1
	else
		echo "<OK> InfluxDB user loxberry created sucessfully."
	fi
else
	echo "<OK> InfluxDB user loxberry already exists. Note! Skippig also creation of new loxberry database!"
	USEREXISTS=1
fi


if [ $USEREXISTS -eq 0 ]; then
	echo "<INFO> Creating default InfluxDB database loxberry."
	$INFLUXBIN -username loxberry -password loxberry -execute "CREATE DATABASE loxberry"
	if [ $? -ne 0 ]; then
		echo "<ERROR> Could not create default InfluxDB database. Nevertheless, I will try to continue. You have to make sure that a idatabase 'loxberry' exists!"
		exit 1
	fi
	echo "<INFO> Current available InfluxDB databases are as follows:"
	$INFLUXBIN -username loxberry -password loxberry -execute "SHOW DATABASES"
fi

echo "<INFO> Creating (new) self-signed SSL certificates."
$OPENSSLBIN req -x509 -nodes -newkey rsa:2048 -keyout $PCONFIG/influxdb-selfsigned.key -out $PCONFIG/influxdb-selfsigned.crt -days 3650 -subj "/C=DE/ST=Saxony/L=Dresden/O=LoxBerry"
chown influxdb:influxdb $PCONFIG/influxdb-selfsigned.*

echo "<INFO> Activating new InfluxDB configuration."
if [ -d /etc/influxdb ] && [ ! -L /etc/influxdb ]; then
	mv /etc/influxdb /etc/influxdb.orig
fi
rm -rf /etc/influxdb
ln -s $PCONFIG /etc/influxdb
systemctl restart influxdb

exit 0
