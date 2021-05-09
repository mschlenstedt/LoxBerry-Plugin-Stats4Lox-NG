#!/bin/sh

ARGV0=$0 # Zero argument is shell command
ARGV1=$1 # First argument is temp folder during install
ARGV2=$2 # Second argument is Plugin-Name for scipts etc.
ARGV3=$3 # Third argument is Plugin installation folder
ARGV4=$4 # Forth argument is Plugin version
ARGV5=$5 # Fifth argument is Base folder of LoxBerry

echo "<INFO> Stopping services influxdb and telegraf for upgrade."
sudo /bin/systemctl stop influxdb
sudo /bin/systemctl stop telegraf
sudo /bin/systemctl stop grafana-server

echo "<INFO> Stopping internal services for upgrade."
pkill -f mqttlive.php > /dev/null 2>&1
pkill -f import_scheduler.pl > /dev/null 2>&1
pkill -f import_loxone.pl> /dev/null 2>&1

echo "<INFO> Creating temporary folders for upgrading."
mkdir -p $ARGV5/data/plugins/$ARGV1\_upgrade/config
mkdir -p $ARGV5/data/plugins/$ARGV1\_upgrade/log
mkdir -p $ARGV5/data/plugins/$ARGV1\_upgrade/data

echo "<INFO> Backing up existing config files."
if [ -n "$(ls -A "$ARGV5/config/plugins/$ARGV3" 2>/dev/null)" ]; then
	rsync -avz $ARGV5/config/plugins/$ARGV3/* $ARGV5/data/plugins/${ARGV1}_upgrade/config/
	if [ $? -ne 0 ]
	then
	  echo "<FAIL> Backing up config files failed. Giving up."
	  rm -rf $ARGV5/data/plugins/${ARGV1}_upgrade
	  exit 2
	fi
else
	echo "<INFO> Folder is empty. Nothing will be backed up."
fi

echo "<INFO> Backing up existing log files."
if [ -n "$(ls -A "$ARGV5/log/plugins/$ARGV3" 2>/dev/null)" ]; then
	rsync -avz $ARGV5/log/plugins/$ARGV3/* $ARGV5/data/plugins/${ARGV1}_upgrade/log/
	if [ $? -ne 0 ]
	then
	  echo "<FAIL> Backing up log files failed. Giving up."
	  rm -rf $ARGV5/data/plugins/${ARGV1}_upgrade
	  exit 2
	fi
else
	echo "<INFO> Folder is empty. Nothing will be backed up."
fi

echo "<INFO> Backing up existing data files."
if [ -n "$(ls -A "$ARGV5/data/plugins/$ARGV3/" 2>/dev/null)" ]; then
	rsync -avz $ARGV5/data/plugins/$ARGV3/* $ARGV5/data/plugins/${ARGV1}_upgrade/data/
	if [ $? -ne 0 ]
	then
	  echo "<FAIL> Backing up data files failed. Giving up."
	  rm -rf $ARGV5/data/plugins/${ARGV1}_upgrade
	  exit 2
	fi
else
	echo "<INFO> Folder is empty. Nothing will be backed up."
fi

# Clean up old installation
echo "<INFO> Cleaning old temporary files"
S4LTMP=`jq -r '.stats4lox.s4ltmp' $ARGV5/config/plugins/$ARGV3/stats4lox.json`
rm -fr $S4LTMP

# Exit with Status 0
exit 0
