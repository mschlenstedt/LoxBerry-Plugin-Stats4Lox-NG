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

# Srating InfluxDB
if [ ! -x /usr/bin/influxd ]; then
	echo "<FAIL> Seems that InfluxDB was not installed correctly. Giving up."
	exit 2
fi

echo "Starting InfluxDB..."
systemctl unmask influxdb.service
systemctl enable --now influxdb

service influxdb status
if [ $? -ne 0 ]; then
	echo "<ERROR> Seems that InfluxDB could nnot be started. Nevertheless, I will try to continue."
	exit 1
fi

echo "Current configuration of InfluxDB is as follows:"
influxd config

echo "Creating default InfluxDB user loxberry/loxberry."
influx -execute "CREATE USER loxberry WITH PASSWORD 'loxberry' WITH ALL PRIVILEGES"
if [ $? -ne 0 ]; then
	echo "<ERROR> Could not create default InfluxDB user. Nevertheless, I will try to continue."
	exit 1
fi

echo "Creating defailt InfluxDB database loxberry."
influx -username loxberry -password loxberry -execute "CREATE DATABASE loxberry"
if [ $? -ne 0 ]; then
	echo "<ERROR> Could not create default InfluxDB database. Nevertheless, I will try to continue."
	exit 1
fi

echo "Current available InfluxDB databases are as follows:"
influx -username loxberry -password loxberry -execute "SHOW DATABASES"

exit 0
