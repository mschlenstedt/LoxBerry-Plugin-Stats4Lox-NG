#!/bin/bash

# $Globals::s4ltmp --> $Globals::stats4lox->{s4ltmp}
find /opt/loxberry/webfrontend/legacy/LoxBerry-Plugin-Stats4Lox-NG-main/ -type f -exec sed -i 's/\$Globals\:\:s4ltmp/\$Globals\:\:stats4lox\-\>\{s4ltmp\}/g' {} \;

# $Globals::loxplanjsondir --> $Globals::stats4lox->{loxplanjsondir}
find /opt/loxberry/webfrontend/legacy/LoxBerry-Plugin-Stats4Lox-NG-main/ -type f -exec sed -i 's/\$Globals\:\:loxplanjsondir/\$Globals\:\:stats4lox\-\>\{loxplanjsondir\}/g' {} \;

# $Globals::influx_bulk_blocksize --> $Globals::influx->{influx_bulk_blocksize}
find /opt/loxberry/webfrontend/legacy/LoxBerry-Plugin-Stats4Lox-NG-main/ -type f -exec sed -i 's/\$Globals\:\:influx_bulk_blocksize/\$Globals\:\:influx\-\>\{influx_bulk_blocksize\}/g' {} \;

# $Globals::influx_bulk_delay_secs --> $Globals::influx->{influx_bulk_delay_secs}
find /opt/loxberry/webfrontend/legacy/LoxBerry-Plugin-Stats4Lox-NG-main/ -type f -exec sed -i 's/\$Globals\:\:influx_bulk_delay_secs/\$Globals\:\:influx\-\>\{influx_bulk_delay_secs\}/g' {} \;

# $Globals::import_time_to_dead_minutes --> $Globals::stats4lox->{import_time_to_dead_minutes}
find /opt/loxberry/webfrontend/legacy/LoxBerry-Plugin-Stats4Lox-NG-main/ -type f -exec sed -i 's/\$Globals\:\:import_time_to_dead_minutes/\$Globals\:\:stats4lox\-\>\{import_time_to_dead_minutes\}/g' {} \;

# $Globals::import_max_parallel_processes --> $Globals::stats4lox->{import_max_parallel_processes}
find /opt/loxberry/webfrontend/legacy/LoxBerry-Plugin-Stats4Lox-NG-main/ -type f -exec sed -i 's/\$Globals\:\:import_max_parallel_processes/\$Globals\:\:stats4lox\-\>\{import_max_parallel_processes\}/g' {} \;

# $Globals::import_max_parallel_per_ms --> $Globals::stats4lox->{import_max_parallel_per_ms}
find /opt/loxberry/webfrontend/legacy/LoxBerry-Plugin-Stats4Lox-NG-main/ -type f -exec sed -i 's/\$Globals\:\:import_max_parallel_per_ms/\$Globals\:\:stats4lox\-\>\{import_max_parallel_per_ms\}/g' {} \;

# $Globals::importstatusdir --> $Globals::stats4lox->{importstatusdir}
find /opt/loxberry/webfrontend/legacy/LoxBerry-Plugin-Stats4Lox-NG-main/ -type f -exec sed -i 's/\$Globals\:\:importstatusdir/\$Globals\:\:stats4lox\-\>\{importstatusdir\}/g' {} \;

# $Globals::telegraf_unix_socket --> $Globals::telegraf->{telegraf_unix_socket}
find /opt/loxberry/webfrontend/legacy/LoxBerry-Plugin-Stats4Lox-NG-main/ -type f -exec sed -i 's/\$Globals\:\:telegraf_unix_socket/\$Globals\:\:telegraf\-\>\{telegraf_unix_socket\}/g' {} \;

# $Globals::telegraf_max_buffer_fullness --> $Globals::telegraf->{telegraf_max_buffer_fullness}
find /opt/loxberry/webfrontend/legacy/LoxBerry-Plugin-Stats4Lox-NG-main/ -type f -exec sed -i 's/\$Globals\:\:telegraf_max_buffer_fullness/\$Globals\:\:telegraf\-\>\{telegraf_max_buffer_fullness\}/g' {} \;

# $Globals::telegraf_buffer_checks --> $Globals::telegraf->{telegraf_buffer_checks}
find /opt/loxberry/webfrontend/legacy/LoxBerry-Plugin-Stats4Lox-NG-main/ -type f -exec sed -i 's/\$Globals\:\:telegraf_buffer_checks/\$Globals\:\:telegraf\-\>\{telegraf_buffer_checks\}/g' {} \;
# @Globals::telegraf_buffer_checks --> @Globals::telegraf->{telegraf_buffer_checks}
find /opt/loxberry/webfrontend/legacy/LoxBerry-Plugin-Stats4Lox-NG-main/ -type f -exec sed -i 's/@Globals\:\:telegraf_buffer_checks/@Globals\:\:telegraf\-\>\{telegraf_buffer_checks\}/g' {} \;

# $Globals::telegraf_internal_files --> $Globals::telegraf->{telegraf_internal_files}
find /opt/loxberry/webfrontend/legacy/LoxBerry-Plugin-Stats4Lox-NG-main/ -type f -exec sed -i 's/\$Globals\:\:telegraf_internal_files/\$Globals\:\:telegraf\-\>\{telegraf_internal_files\}/g' {} \;

# $Globals::graf_provisioning_dir --> $Globals::grafana->{graf_provisioning_dir}
find /opt/loxberry/webfrontend/legacy/LoxBerry-Plugin-Stats4Lox-NG-main/ -type f -exec sed -i 's/\$Globals\:\:graf_provisioning_dir/\$Globals\:\:grafana\-\>\{graf_provisioning_dir\}/g' {} \;

# $Globals::s4l_provisioning_dir --> $Globals::grafana->{s4l_provisioning_dir}
find /opt/loxberry/webfrontend/legacy/LoxBerry-Plugin-Stats4Lox-NG-main/ -type f -exec sed -i 's/\$Globals\:\:s4l_provisioning_dir/\$Globals\:\:grafana\-\>\{s4l_provisioning_dir\}/g' {} \;

# $Globals::s4l_provisioning_template_dir --> $Globals::grafana->{s4l_provisioning_template_dir}
find /opt/loxberry/webfrontend/legacy/LoxBerry-Plugin-Stats4Lox-NG-main/ -type f -exec sed -i 's/\$Globals\:\:s4l_provisioning_template_dir/\$Globals\:\:grafana\-\>\{s4l_provisioning_template_dir\}/g' {} \;

# $Globals::grafanaport --> $Globals::grafana->{port}
find /opt/loxberry/webfrontend/legacy/LoxBerry-Plugin-Stats4Lox-NG-main/ -type f -exec sed -i 's/\$Globals\:\:grafanaport/\$Globals\:\:grafana\-\>\{port\}/g' {} \;
