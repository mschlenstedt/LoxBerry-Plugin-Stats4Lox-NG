#!/bin/bash -e
echo Starting Influx via S4L starting script
/usr/bin/influxd -config /etc/influxdb/influxdb.conf $INFLUXD_OPTS &
PID=$!
echo $PID > /var/lib/influxdb/influxd.pid
sleep 10


