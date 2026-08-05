#!/usr/bin/perl
use warnings;
use strict;
use LoxBerry::System;
use LoxBerry::Log;
use CGI;
use JSON;
use FindBin qw($Bin);
use lib "$Bin/../../../../bin/plugins/stats4lox/libs/";
use Globals;

my $error;
my $response;
my $cgi = CGI->new;
my $q = $cgi->Vars;

# Every branch below compares $q->{action} with "eq". Without a defined value a
# request without an action parameter produced a warning for each of them in
# the webserver error log.
$q->{action} = '' if( !defined $q->{action} );

# nofile: this CGI is called constantly - on every page load, for live values,
# for the service status. Each call produced its own log file, so the Logfiles
# overview filled up with dozens of AJAX entries that nobody ever reads.
#
# Nothing is lost: with stderr the messages still land in the webserver error
# log, which is where you look when a CGI misbehaves anyway.
my $log = LoxBerry::Log->new (
    name => 'AJAX',
	nofile => 1,
	stderr => 1,
	loglevel => 7
);

LOGSTART "Request $q->{action}";

## getloxplan
if( $q->{action} eq "getloxplan" ) {
	require Loxone::GetLoxplan;
	require Loxone::ParseXML;
	require LoxBerry::IO;
	
	my $msno = $q->{msno};
	LOGTITLE "getloxplan Miniserver $msno";

	# Piggybacked on this request on purpose: it is the moment the user works
	# with the block list, so that is when the element names should be current.
	# LangUpdate throttles itself to one check a day and never fails hard - if
	# GitHub cannot be reached, everything stays as it is.
	eval {
		require LangUpdate;
		LangUpdate::update( log => $log );
	};
	LOGDEB "Language file check failed: $@" if( $@ );
	
	my %miniservers = LoxBerry::System::get_miniservers();
	
	if( ! defined $miniservers{$msno} ) {
		$error = "Miniserver not defined";
	}
	else {
		
		## Get Serials of Miniservers
		## Serials are used for matching of LoxBerry MSNO to "real" Miniservers in LoxPlan
		my %ms_serials;
		
		$log->INF("Checking MS$msno");
		if( $miniservers{$msno}{UseCloudDNS} and $miniservers{$msno}{CloudURL} ) {
			# CloudDNS has serial defined in LoxBerry
			$ms_serials{$msno} = uc( $miniservers{$msno}{CloudURL} );
			$log->OK("MS $msno: Locally stored serial:  $ms_serials{$msno}");
		}
		else {	
			# Fetch serial from Miniserver
			my ($response) = LoxBerry::IO::mshttp_call2($msno, "/jdev/cfg/mac");
			# print STDERR $response;
			eval {
				my $responseobj=JSON::from_json( $response );
				my $sn = $responseobj->{LL}->{value};
				$sn =~ tr/://d;
				$ms_serials{$msno} = uc( $sn );
				$log->OK("MS$msno: Aquired serial from MS: $ms_serials{$msno}");
			};
			if( $@ ) {
				$log->ERR("Could not aquire MAC from Miniserver $msno: $@");
			}
		}
		
		if( !defined $ms_serials{$msno} ) {
			$log->WARN("MS$msno: Could not get serial, therefore matching of Miniserver may fail");
		}
		
		my $Loxplanfile = "$Globals::stats4lox->{s4ltmp}/s4l_loxplan_ms$msno.Loxone";		
		my $loxplanjson = "$Globals::stats4lox->{loxplanjsondir}/ms".$msno.".json";
		my $remoteTimestamp;
		eval {
			$remoteTimestamp = Loxone::GetLoxplan::checkLoxplanUpdate( $msno, $loxplanjson, $log );
		};
		my $checkfailed = $@;

		# Note: "ne" on an undefined value warns. checkLoxplanUpdate returns
		# undef when the local copy is up-to-date.
		if( $checkfailed or defined $remoteTimestamp ) {
			LOGINF "Loxplan file not up-to-date. Fetching from Miniserver";

			# Every failure has to reach the user. Previously the return
			# values of both calls were discarded, this CGI answered HTTP 200
			# with a stale or empty json, and the web interface kept waiting
			# on "Fetching Loxone Config from Miniservers..." forever.
			unlink $Loxplanfile;
			my $fetched = Loxone::GetLoxplan::getLoxplan(
				ms => $msno,
				log => $log
			);

			if( !$fetched or ! -e $Loxplanfile ) {
				$error = "Miniserver $msno: Could not fetch the Loxone configuration.";
			}
			else {
				LOGOK "Loxplan for MS$msno found, parsing now...";
				my $loxplan = Loxone::ParseXML::loxplan2json(
					filename => $Loxplanfile,
					msno => $msno,
					output => $loxplanjson,
					log => $log,
					remoteTimestamp => $remoteTimestamp,
					ms_serials => \%ms_serials
				);
				if( !$loxplan ) {
					$error = "Miniserver $msno: Could not parse the Loxone configuration.";
				}
			}

		} else {
			LOGINF "Loxplan file is up-to-date. Using local copy";

			# The lookup table for outputs that Loxone reports as a bare UUID is
			# built while the LoxPLAN is being parsed - which does not happen
			# when the configuration is unchanged. Without this an existing
			# installation would never get the file, because after an upgrade the
			# configuration is by definition up-to-date and the parse is skipped.
			my $statenames = Loxone::ParseXML::stateNamesFile( $loxplanjson );
			if( $statenames and ! -e $statenames ) {
				LOGINF "Output name table is missing - creating it now";
				Loxone::ParseXML::writeStateNames( msno => $msno, output => $loxplanjson,
				                                   loxplan => $Loxplanfile, log => $log );
			}
		}

		if( !$error ) {
			if( -e $loxplanjson ) {
				$response = LoxBerry::System::read_file($loxplanjson);
			} else {
				$error = "Miniserver $msno: Could not fetch the Loxone configuration.";
			}
		}

	}

}

## getstatsconfig
if( $q->{action} eq "getstatsconfig" ) {
	if ( -e $statsconfig ) {
		$response = LoxBerry::System::read_file($statsconfig);
		if( !$response ) {
			$response = "{ }";
		}
	}
	else {
		$response = "{ }";
	}
}

## updatestat
if( $q->{action} eq "updatestat" ) {
	require LoxBerry::JSON;
	my $jsonobjcfg = LoxBerry::JSON->new();
	my $cfg = $jsonobjcfg->open(filename => $statsconfig, lockexclusive => 1);
	my @searchresult = $jsonobjcfg->find( $cfg->{loxone}, "\$_->{uuid} eq \"".$q->{uuid}."\"" );
	my $elemKey = $searchresult[0];
	my $element = $cfg->{loxone}[$elemKey] if( defined $elemKey );
	
	my @outputs;
	if ( defined $q->{outputs} ) {
		@outputs = split(",", $q->{outputs});
	}
	else {
		@outputs = ();
	}
	
	my @outputlabels;
	if( $q->{outputlabels} ne "" ) {
		@outputlabels = split(",", $q->{outputlabels});
	} 
	
	my @outputkeys;
	if( $q->{outputkeys} ne "" ) {
		@outputkeys = split(",", $q->{outputkeys});
	} 
	
	
	my $measurementname = $q->{measurementname};
	if( !$measurementname ) {
		if( defined $element->{measurementname} and $element->{measurementname} ne "" ) {
			$measurementname = $element->{measurementname};
		}
		else {
			$measurementname = $q->{description} ne "" ? $q->{description} : $q->{name};
		}
	}
	
	my %updatedelement = (
		name => $q->{name},
		description => $q->{description},
		uuid => $q->{uuid},
		type => $q->{type},
		category => $q->{category},
		room => $q->{room},
		interval => int($q->{interval}) ne "NaN" ? $q->{interval} : 0,
		active => defined $q->{active} ? $q->{active} : "false",
		msno => $q->{msno},
		measurementname => $measurementname,
		outputs => \@outputs,
		grafana => $element->{grafana}, 
		# url => $q->{uuid}
	);
	$updatedelement{outputlabels} = \@outputlabels if(@outputlabels);
	$updatedelement{outputkeys} = \@outputkeys if(@outputkeys);
	# The element is rebuilt from scratch here, so anything not listed above is
	# lost. 'grafana' is carried over in the list; the status recorded by the
	# grabber has to be carried over as well - otherwise changing an interval
	# would quietly clear the error state and start the counting again.
	$updatedelement{status} = $element->{status} if( $element->{status} );
	
	
	# Validation
	my @errors;
	push @errors, "name must be defined" if( ! $updatedelement{name} );
	push @errors, "uuid must be defined" if( ! $updatedelement{uuid} );
	push @errors, "msno must be defined" if( ! $updatedelement{msno} );
	# push @errors, "url must be defined" if( ! $updatedelement{url} );
	push @errors, "active must be defined" if( ! $updatedelement{active} );

	if( ! @errors ) {
		require GrafanaS4L;
		GrafanaS4L::provisionDashboard( \%updatedelement );
	}
	
	
	# Insert/Update element in stats array
	if( defined $elemKey ) {
		# This is an update of an existing element
		$cfg->{loxone}[$elemKey] = \%updatedelement;
	} 
	else {
		# Add a new entry to stats.json
		push @{$cfg->{loxone}}, \%updatedelement;
	}
	
	if( ! @errors ) {
		# The changes are valid
		$jsonobjcfg->write();
		undef $jsonobjcfg;
		$response = to_json( \%updatedelement );
	}
	else {
		# The element is invalid
		$error = "Invalid input data: " . join(". ", @errors);
	}
	
}
	
## lxlquery
if( $q->{action} eq "lxlquery" ) {
	require "$lbpbindir/libs/Stats4Lox.pm";
	my ($code, $data) = Stats4Lox::msget_value( $q->{msno}, $q->{uuid} );
	
	my %response = (
		msno => $q->{msno},
		uuid => $q->{uuid},
		code => $code,
		response => $data,
		mappings => $Globals::ImportMapping,
		# error => $jsonerror
	);
	$response = encode_json( \%response );
}

## import_scheduler_report
if( $q->{action} eq "import_scheduler_report" ) {

	if( ! -e $Globals::stats4lox->{s4ltmp}."/s4l_import_scheduler.json" ) {
		system("$lbpbindir/import_scheduler.pl > $lbplogdir/import_scheduler.log 2>&1 &");
	}
	my $checktime = time();
	while( ! -e $Globals::stats4lox->{s4ltmp}."/s4l_import_scheduler.json" and time() < ($checktime+5) ) {
		# Wait up to 5 seconds
	}
	if( -e $Globals::stats4lox->{s4ltmp}."/s4l_import_scheduler.json" ) {
		$response = LoxBerry::System::read_file( $Globals::stats4lox->{s4ltmp}."/s4l_import_scheduler.json" );
	}
}

## scheduleimport
if( $q->{action} eq "scheduleimport" and $q->{msno} and $q->{uuid} ) {
	my $msno = $q->{msno};
	my $uuid = $q->{uuid};
	createImportFolder();
	my $importfile = $Globals::stats4lox->{importstatusdir}."/import_${msno}_${uuid}.json";
	
	if( $q->{importtype} eq "full" ) {
		
		unlink $importfile;
		require LoxBerry::JSON;
		my $jsonobjimport = LoxBerry::JSON->new();
		my $import = $jsonobjimport->open(filename => $importfile, lockexclusive => 1);
		$import->{msno} = $msno;
		$import->{uuid} = $uuid;
		$import->{name} = $q->{name};
		$import->{status} = "scheduled";
		$jsonobjimport->write();
		
	}
	
	# Start the Import Scheduler
	system("$lbpbindir/import_scheduler.pl > $lbplogdir/import_scheduler.log 2>&1 &");
	
	sleep 1;
	
	# Respond with scheduled file
	$response = LoxBerry::System::read_file( $importfile );
	
}

## deleteimport
if( $q->{action} eq "deleteimport" and $q->{msno} and $q->{uuid} ) {
	my $msno = $q->{msno};
	my $uuid = $q->{uuid};
	createImportFolder();
	my $importfile = $Globals::stats4lox->{importstatusdir}."/import_${msno}_${uuid}.json";
	
	if( ! -e $importfile ) {
		unlink "$importfile.log";
		$response = "{ }";
		system("$lbpbindir/import_scheduler.pl > $lbplogdir/import_scheduler.log 2>&1 &");
		sleep 1;
	}
	else {
		require LoxBerry::JSON;
		my $jsonobjimport = LoxBerry::JSON->new();
		my $import = $jsonobjimport->open(filename => $importfile, lockexclusive => 1, locktimeout => 10);
		if( ! $import or $import->{status} eq "running" ) {
			$error = "Cannot lock import $msno / $uuid or import is currently running";
		}
		else {
			unlink $importfile;
			unlink "$importfile.log";
			$response = "{ }";
			system("$lbpbindir/import_scheduler.pl > $lbplogdir/import_scheduler.log 2>&1 &");
			sleep 1;
		}
	}
}

## deletestat - gets rid of a statistic
##
## Two cases, and the entry itself decides which one applies - not the caller:
##
##   The block is gone from the Miniserver (status 404). Then the entry is
##   removed from stats.json and its panels from the dashboard; there is nothing
##   left it could belong to.
##
##   The block still exists. Then the entry is only switched off. Removing it
##   would throw away the measurement name, the chosen outputs and the interval,
##   and the user would have to set all of it up again to switch the statistic
##   back on. The panels stay for the same reason - update_dashboards.pl builds
##   them regardless of whether a statistic is active.
##
## The measurements in InfluxDB are only removed when the user explicitly asks
## for it, in both cases - they are the history, and the history usually
## outlives the reason the statistic was set up.
if( $q->{action} eq "deletestat" and $q->{msno} and $q->{uuid} ) {
	require LoxBerry::JSON;
	my $msno = $q->{msno};
	my $uuid = $q->{uuid};
	my $dropdata = ( defined $q->{dropdata} and $q->{dropdata} eq "true" ) ? 1 : 0;

	my $obj = LoxBerry::JSON->new();
	my $cfg = $obj->open( filename => $statsconfig, lockexclusive => 1, locktimeout => 10 );
	if( !$cfg or ref($cfg->{loxone}) ne 'ARRAY' ) {
		$error = "Could not open stats.json";
	}
	else {
		my ($index) = grep {
			     $cfg->{loxone}[$_]->{uuid} eq $uuid
			 and $cfg->{loxone}[$_]->{msno} eq $msno
		} 0 .. $#{ $cfg->{loxone} };

		if( !defined $index ) {
			$error = "Statistic $msno / $uuid not found";
		}
		else {
			my $element = $cfg->{loxone}[$index];
			my $measurement = $element->{measurementname};

			# The entry decides, not the caller: only a block the Miniserver no
			# longer knows is removed outright.
			my $gone = ( $element->{status} and $element->{status}->{error}
			             and $element->{status}->{error} eq '404' ) ? 1 : 0;
			my $mode = $gone ? 'removed' : 'deactivated';
			LOGINF "Statistic $msno / $uuid ($element->{name}): $mode";

			my @panel_ids = ();
			if( $gone ) {
				# Panels first: the ids live on the entry we are about to remove.
				@panel_ids = ( defined $element->{grafana}->{panels} )
				           ? values %{ $element->{grafana}->{panels} } : ();
				if( @panel_ids ) {
					eval {
						require Grafana;
						Grafana->deletePanelFromDashboard(
							"$Globals::grafana->{s4l_provisioning_dir}/dashboards/defaultDashboard.json",
							\@panel_ids );
						LOGOK "Removed " . scalar(@panel_ids) . " panels from the dashboard";
					};
					LOGERR "Could not remove the panels: $@" if( $@ );
				}
				splice @{ $cfg->{loxone} }, $index, 1;
				$obj->write();
				LOGOK "Statistic removed from stats.json";
			}
			else {
				# Switched off, everything else kept: measurement name, outputs
				# and interval are what the user configured, and they would all
				# have to be entered again to switch it back on. A status from a
				# previous failure goes, it describes a state that no longer
				# applies to a statistic nobody fetches.
				$element->{active} = "false";
				delete $element->{status};
				$obj->write();
				LOGOK "Statistic switched off, entry and panels kept";
			}

			# Only the series of this block, addressed by its uuid tag - several
			# statistics can share a measurement name, and dropping the whole
			# measurement would take the others with it.
			my $dropped = 0;
			if( $dropdata and $measurement ) {
				my $bin = "$lbpbindir/s4linflux";
				my $db = $Globals::influx->{influxdatabase} // 'stats4lox';
				my $sql = "DELETE FROM \"$measurement\" WHERE \"uuid\"='$uuid'";
				# quotemeta on the whole argument, no quotes of our own around
				# it - measurement names contain spaces and umlauts.
				my $cmd = "$bin -database " . quotemeta($db) . " -execute " . quotemeta($sql);
				my $out = `$cmd 2>&1`;
				if( $? == 0 ) { $dropped = 1; LOGOK "Measurements of $uuid deleted from $measurement" }
				else          { LOGERR "Could not delete the measurements: $out" }
			}

			# The import state file has no owner any more - but only when the
			# entry itself is gone. A statistic that was merely switched off
			# keeps its import history.
			if( $gone ) {
				createImportFolder();
				my $importfile = $Globals::stats4lox->{importstatusdir}."/import_${msno}_${uuid}.json";
				unlink $importfile     if( -e $importfile );
				unlink "$importfile.log" if( -e "$importfile.log" );
			}

			$response = JSON::encode_json( {
				deleted => 1,
				mode    => $mode,
				panels  => scalar(@panel_ids),
				dropped => $dropped,
			} );
		}
	}
}

## resetstatstatus - clears the recorded status so the grabber tries again
if( $q->{action} eq "resetstatstatus" and $q->{msno} and $q->{uuid} ) {
	require LoxBerry::JSON;
	my $obj = LoxBerry::JSON->new();
	my $cfg = $obj->open( filename => $statsconfig, lockexclusive => 1, locktimeout => 10 );
	if( !$cfg or ref($cfg->{loxone}) ne 'ARRAY' ) {
		$error = "Could not open stats.json";
	}
	else {
		my $found = 0;
		foreach my $e ( @{ $cfg->{loxone} } ) {
			next if( $e->{uuid} ne $q->{uuid} or $e->{msno} ne $q->{msno} );
			delete $e->{status};
			$found = 1;
			last;
		}
		if( !$found ) {
			$error = "Statistic $q->{msno} / $q->{uuid} not found";
		}
		else {
			$obj->write();
			LOGOK "Status of $q->{msno} / $q->{uuid} reset";
			$response = '{ "reset": 1 }';
		}
	}
}

## getmqttlivedata
if( $q->{action} eq "getmqttlivedata" ) {
	if ( -e $Globals::stats4lox->{s4ltmp}."/mqttlive_uidata.json" ) {
		$response = LoxBerry::System::read_file($Globals::stats4lox->{s4ltmp}."/mqttlive_uidata.json");
		if( !$response ) {
			$response = "{ }";
		}
	}
	else {
		$response = "{ }";
	}
}

## mqttlive_clearuidata
if( $q->{action} eq "mqttlive_clearuidata" ) {
	my $basetopic = $q->{basetopic};
	if( !$basetopic ) {
		$error = "No base topic sent with request";
		$log->ERR($error);
		# Jump out
	}
	else {
		require LoxBerry::IO;
		my $mqttcred = LoxBerry::IO::mqtt_connectiondetails();
		if( ! $mqttcred ) {
			$error = "Could not get MQTT Connection details - MQTT Gateway installed?";
			$log->WARN($error);
			# Jump out
		}
		else {
			eval {
				if( ! $mqttcred->{brokerport} ) {
					$mqttcred->{brokerport} = "1883";
				}
				
				require Net::MQTT::Simple;
				$ENV{MQTT_SIMPLE_ALLOW_INSECURE_LOGIN} = 1;
				my $mqtt = Net::MQTT::Simple->new($mqttcred->{brokeraddress});
				if($mqttcred->{brokeruser}) {
					$mqtt->login($mqttcred->{brokeruser}, $mqttcred->{brokerpass});
				}
				$mqtt->publish("$basetopic/command", "clearuidata");
			};
			if( $@ ) {
				$error = "Exception sending $basetopic/command=clearuidata: $@";
				$log->ERR($error);
			}
		}
	}
	$response = "{ }";
}

# Raising the plugin log level to debug and then restarting a service is what
# somebody does who wants to see what that service says. So the diagnostic
# logging follows along instead of hiding behind a second switch further away.
#
# Deliberately NOT marked as set by hand: cron.reboot switches this off again on
# the next reboot, so a log level nobody remembers cannot keep the services
# writing forever. The switch under Settings is marked and survives.
sub s4l_servicelog_follow_loglevel
{
	require ServiceLog;
	return if( !ServiceLog::follow_loglevel() );
	LOGINF "Plugin log level is debug - switching the diagnostic logging of the services on";
	system("sudo $lbpbindir/config-handler.pl servicelog >/dev/null 2>&1");
	return;
}


## starttelegraf
if( $q->{action} eq "starttelegraf" ) {
	s4l_servicelog_follow_loglevel();
	system ("sudo systemctl enable telegraf >/dev/null 2>&1");
	system ("sudo systemctl restart telegraf >/dev/null 2>&1");
	$response = $?;
}

## stoptelegraf
if( $q->{action} eq "stoptelegraf" ) {
	system ("sudo systemctl disable telegraf >/dev/null 2>&1");
	system ("sudo systemctl stop telegraf >/dev/null 2>&1");
	$response = $?;
}

## startinfluxdb
if( $q->{action} eq "startinfluxdb" ) {
	s4l_servicelog_follow_loglevel();
	system ("sudo systemctl enable influxdb >/dev/null 2>&1");
	system ("sudo systemctl restart influxdb >/dev/null 2>&1");
	$response = $?;
}

## stopinfluxdb
if( $q->{action} eq "stopinfluxdb" ) {
	system ("sudo systemctl disable influxdb >/dev/null 2>&1");
	system ("sudo systemctl stop influxdb >/dev/null 2>&1");
	$response = $?;
}

## startgrafana-server
if( $q->{action} eq "startgrafana-server" ) {
	s4l_servicelog_follow_loglevel();
	system ("sudo systemctl enable grafana-server >/dev/null 2>&1");
	system ("sudo systemctl restart grafana-server >/dev/null 2>&1");
	$response = $?;
}

## stopgrafana-server
if( $q->{action} eq "stopgrafana-server" ) {
	system ("sudo systemctl disable grafana-server >/dev/null 2>&1");
	system ("sudo systemctl stop grafana-server >/dev/null 2>&1");
	$response = $?;
}

## startmqttlive
if( $q->{action} eq "startmqttlive" ) {
	system ("pkill -f mqttlive.php >/dev/null 2>&1");

	my $jsonobj = LoxBerry::JSON->new();
	my $cfg = $jsonobj->open(filename => $stats4loxconfig, lockexclusive => 1);
	$cfg->{stats4lox}->{mqttlive_active} = "True";
	$jsonobj->write();
	undef $jsonobj;

	system ("$lbpbindir/mqtt/mqttlive.php >> $lbplogdir/mqttlive.log 2>&1 &");
	$response = $?;
}

## stopmqttlive
if( $q->{action} eq "stopmqttlive" ) {
	my $jsonobj = LoxBerry::JSON->new();
	my $cfg = $jsonobj->open(filename => $stats4loxconfig, lockexclusive => 1);
	$cfg->{stats4lox}->{mqttlive_active} = "False";
	$jsonobj->write();
	undef $jsonobj;
	
	system ("pkill -f mqttlive.php >/dev/null 2>&1");
	if ($? < 3 || $? eq "15") { # Don't know why it give 15 as Exit Code back - on cmd it is 0, 1 or 2.
		$response = 0;
	} else {
		$response = $?;
	}
}

## servicestatus
if( $q->{action} eq "servicestatus" ) {
	
	my $telegrafstat = `pgrep -f /usr/bin/telegraf`;
	my $influxstat = `pgrep -f /usr/bin/influxd`;
	my $grafanastat = `pgrep -f /usr/share/grafana/bin/grafana`;
	my $mqttlivestat;
	
	if( is_disabled( $Globals::stats4lox->{mqttlive_active} ) ) {
		$mqttlivestat = 'disabled';
	}
	else {
		$mqttlivestat = `pgrep -f mqttlive.php`;
	}
	
	my %response = (
		telegraf => $telegrafstat,
		influx => $influxstat,
		grafanaserver => $grafanastat,
		mqttlive => $mqttlivestat,
	);
	chomp (%response);
	$response = encode_json( \%response );
}

## getpluginconfig
if( $q->{action} eq "getpluginconfig" ) {
	if ( -e $stats4loxconfig ) {
		$response = LoxBerry::System::read_file($stats4loxconfig);
		if( !$response ) {
			$response = "{ }";
		}
	}
	else {
		$response = "{ }";
	}
}

## savepluginconfig
if( $q->{action} eq "savepluginconfig" ) {
	require LoxBerry::JSON;
	my $errors = 0;
	my $cfgfile = $lbpconfigdir . "/stats4lox.json";
	my $jsonobj = LoxBerry::JSON->new();
	my $cfg = $jsonobj->open(filename => $cfgfile);
	if (!$cfg) {
		$errors++;
	}
	
	# Without the following workaround
	# the script cannot be executed as
	# background process via CGI
	my $pid = fork();
	$errors++ if !defined $pid;
	if ($pid == 0) {
		# do this in the child
		open STDIN, "< /dev/null";
		open STDOUT, "> /dev/null";
		open STDERR, "> /dev/null";

		# Output: Influx
		if ( $q->{'section'} eq "influx" ) {
			$cfg->{'influx'}->{'db_storage'} = $q->{'influx_db_storage'};
			$jsonobj->write();
			system ("sudo $lbpbindir/config-handler.pl influx >/dev/null 2>&1");
		}

		# Diagnostic logging of the services
		if ( $q->{'section'} eq "servicelog" ) {
			my $on = ( defined $q->{'servicelogging'} and $q->{'servicelogging'} eq "true" ) ? 1 : 0;
			$cfg->{'stats4lox'}->{'servicelogging'} = $on ? "True" : "False";
			$jsonobj->write();
			# Set here on purpose, so a reboot leaves it alone - unlike logging
			# that switched itself on because of the debug log level.
			require ServiceLog;
			ServiceLog::set_manual( $on );
			system ("sudo $lbpbindir/config-handler.pl servicelog >/dev/null 2>&1");
		}

	} # End Child process

	$response = '{ "error":' . $errors . '}';
}

##
## Influx page
##
## Split into three requests on purpose. Measured on 134 measurements: the
## overview costs 0.4 s, the timestamps 4.5 s, and counting the values 23.5 s.
## Putting all of that into one request would mean staring at an empty page for
## half a minute.

# stats.json read as characters, not as bytes.
#
# LoxBerry::JSON hands back byte strings, while the measurement names coming out
# of InfluxDB are decoded characters. Comparing the two directly fails for every
# name with an umlaut - "Alkalinität" from the database would never match
# "Alkalinit\xc3\xa4t" from the configuration.
sub s4l_stats_by_measurement
{
	my %out;
	open( my $fh, '<:raw', $statsconfig ) or return \%out;
	local $/;
	my $raw = <$fh>;
	close $fh;
	my $cfg = eval { JSON::decode_json( $raw ) };
	return \%out if( $@ or ref($cfg->{loxone}) ne 'ARRAY' );

	foreach my $e ( @{ $cfg->{loxone} } ) {
		next if( !$e->{measurementname} );
		$out{ $e->{measurementname} } = {
			uuid   => $e->{uuid},
			msno   => $e->{msno},
			name   => $e->{name},
			active => ( defined $e->{active} and $e->{active} eq 'true' ) ? 1 : 0,
		};
	}
	return \%out;
}

## influx_overview - everything that is cheap to know
if( $q->{action} eq "influx_overview" ) {
	require InfluxInfo;
	my $names  = InfluxInfo::measurements();
	my $fields = InfluxInfo::fieldkeys();
	my $srcs   = InfluxInfo::sources();
	my $stats  = s4l_stats_by_measurement();

	my @out;
	foreach my $n ( @$names ) {
		my $s = $stats->{$n};
		push @out, {
			name     => $n,
			fields   => $fields->{$n} // [],
			sources  => $srcs->{$n}   // [],
			encoding => InfluxInfo::name_encoding($n),
			# configured: there is an entry in stats.json using this name
			configured => $s ? 1 : 0,
			active     => $s ? $s->{active} : 0,
			uuid       => $s ? $s->{uuid} : undef,
			msno       => $s ? $s->{msno} : undef,
			blockname  => $s ? $s->{name} : undef,
		};
	}

	# Configured but never written - the counterpart of an orphaned measurement
	my %have = map { $_ => 1 } @$names;
	my @nodata = grep { !$have{$_} } sort keys %$stats;

	$response = JSON::encode_json( {
		measurements => \@out,
		nodata       => \@nodata,
		database     => $Globals::influx->{influxdatabase} // 'stats4lox',
	} );
}

## influx_timestamps - first and last value of every measurement
if( $q->{action} eq "influx_timestamps" ) {
	require InfluxInfo;
	my $names = InfluxInfo::measurements();
	$response = JSON::encode_json( { timestamps => InfluxInfo::timestamps($names) } );
}

## influx_count - how many values, for one measurement or for all of them
if( $q->{action} eq "influx_count" ) {
	require InfluxInfo;
	my $names;
	if( defined $q->{name} and $q->{name} ne '' ) {
		# One name, and only if it really exists - the value ends up in a query.
		my $all = InfluxInfo::measurements();
		my $wanted = $q->{name};
		require Encode;
		$wanted = Encode::decode( 'UTF-8', $wanted, Encode::FB_DEFAULT() | Encode::LEAVE_SRC() );
		$names = [ grep { $_ eq $wanted } @$all ];
		$error = "Unknown measurement" if( !@$names );
	}
	else {
		$names = InfluxInfo::measurements();
	}
	$response = JSON::encode_json( { counts => InfluxInfo::valuecount($names) } ) if( !$error );
}

## influx_drop - removes a measurement, and on request switches its statistic off
if( $q->{action} eq "influx_drop" and defined $q->{name} and $q->{name} ne '' ) {
	require InfluxInfo;
	require Encode;
	my $wanted = Encode::decode( 'UTF-8', $q->{name}, Encode::FB_DEFAULT() | Encode::LEAVE_SRC() );

	# Only a measurement that is really there - the name goes into a DROP.
	my $all = InfluxInfo::measurements();
	if( !grep { $_ eq $wanted } @$all ) {
		$error = "Unknown measurement";
	}
	else {
		# Switching the statistic off first, then dropping. The other way round
		# the grabber could write the measurement again in the second between
		# the two - it runs every minute.
		my $deactivated = 0;
		if( defined $q->{deactivate} and $q->{deactivate} eq 'true' ) {
			my $stats = s4l_stats_by_measurement();
			my $s = $stats->{$wanted};
			if( $s and $s->{uuid} ) {
				require LoxBerry::JSON;
				my $obj = LoxBerry::JSON->new();
				my $cfg = $obj->open( filename => $statsconfig, lockexclusive => 1, locktimeout => 10 );
				if( $cfg and ref($cfg->{loxone}) eq 'ARRAY' ) {
					foreach my $e ( @{ $cfg->{loxone} } ) {
						next if( $e->{uuid} ne $s->{uuid} or $e->{msno} ne $s->{msno} );
						$e->{active} = "false";
						delete $e->{status};
						$deactivated = 1;
						last;
					}
					$obj->write() if( $deactivated );
					LOGOK "Statistic $s->{msno} / $s->{uuid} switched off before dropping the measurement"
						if( $deactivated );
				}
			}
		}

		my $dropped = InfluxInfo::drop_measurement( $wanted );
		if( $dropped ) { LOGOK "Measurement dropped: $q->{name}" }
		else           { LOGERR "Could not drop the measurement: $q->{name}" }
		$response = JSON::encode_json( { dropped => $dropped, deactivated => $deactivated } );
	}
}

##
## Backup
##
## Everything here runs s4l_backup.pl through sudo - the script needs root for
## influxd and for the service restarts. The sudoers rule covers exactly this
## one script.

# The archive names come back from the browser, so they are checked before they
# are handed to a root script: only our own name pattern, and only inside the
# configured storage directory. Returns the checked path or undef.
sub s4l_backup_file
{
	my ($wanted) = @_;
	return undef if( !$wanted );

	require File::Basename;
	my $name = File::Basename::basename($wanted);
	return undef if( $name !~ /^stats4lox_\d{8}_\d{6}\.(?:tar|tar\.gz|tar\.xz|zip|7z)$/ );

	my $dir = $Globals::backup->{storagepath};
	return undef if( !$dir );
	# Compare the resolved directory, not the string - a path with ".." in it
	# must not be able to point somewhere else.
	require Cwd;
	my $realdir = Cwd::realpath($dir) // return undef;
	my $realwanted = Cwd::realpath( File::Basename::dirname($wanted) ) // return undef;
	return undef if( $realwanted ne $realdir );

	return "$realdir/$name";
}

sub s4l_backup_bin { return "sudo $lbpbindir/s4l_backup.pl" }

# The page polls the status file to find out when the script is done. Between
# the click and the first line the script writes there is a gap of a second or
# two - and in that gap the file still holds "running: 0" from the last run, so
# the page would report success immediately. Marked as running before forking.
sub s4l_backup_status_reset
{
	my ($step) = @_;
	my $dir = $Globals::stats4lox->{s4ltmp};
	require File::Path;
	File::Path::make_path($dir) if( ! -d $dir );
	my $statfile = "$dir/backup-status.json";
	if( open( my $fh, '>', $statfile ) ) {
		print {$fh} '{"running":1,"step":"'.$step.'","message":"","time":' . time() . '}';
		close $fh;
	}
	return;
}

## backup_list
if( $q->{action} eq "backup_list" ) {
	my $dir = $Globals::backup->{storagepath};
	if( !$dir or ! -d $dir ) {
		$response = '{ "backups": [], "nostorage": 1 }';
	}
	else {
		$response = `@{[ s4l_backup_bin() ]} list --target "$dir" 2>/dev/null`;
		$response = '{ "backups": [] }' if( !$response or $response !~ /\S/ );
	}
}

## backup_check - may a restore go ahead, and where would the database land
if( $q->{action} eq "backup_check" ) {
	my $f = s4l_backup_file( $q->{file} );
	if( !$f ) {
		$response = '{ "ok": 0, "error": "Unknown archive" }';
	}
	else {
		$response = `@{[ s4l_backup_bin() ]} check --file "$f" 2>/dev/null`;
		$response = '{ "ok": 0, "error": "The check produced no answer" }' if( !$response or $response !~ /\S/ );
	}
}

## backup_status
if( $q->{action} eq "backup_status" ) {
	my $statfile = $Globals::stats4lox->{s4ltmp} . "/backup-status.json";
	$response = ( -e $statfile ) ? LoxBerry::System::read_file($statfile) : undef;
	$response = '{ }' if( !$response );
}

## backup_create
if( $q->{action} eq "backup_create" ) {
	my $dir = $Globals::backup->{storagepath};
	if( !$dir or ! -d $dir ) {
		$error = "No storage location configured";
	}
	else {
		# The backup takes minutes - the browser must not wait for it. The
		# status file is what the page polls.
		s4l_backup_status_reset("preparing");
		my $pid = fork();
		if( !defined $pid ) {
			$error = "Could not start the backup";
		}
		elsif( $pid == 0 ) {
			open STDIN,  "< /dev/null";
			open STDOUT, "> /dev/null";
			open STDERR, "> /dev/null";
			system( s4l_backup_bin() . " create --scheduled" );
			exit 0;
		}
		else {
			$response = '{ "started": 1 }';
		}
	}
}

## backup_restore
if( $q->{action} eq "backup_restore" ) {
	my $f = s4l_backup_file( $q->{file} );
	if( !$f ) {
		$error = "Unknown archive";
	}
	else {
		my $dbopt = ( $q->{dbpath} ) ? " --dbpath " . quotemeta( $q->{dbpath} ) : "";
		# --force is only passed on when the page has shown the warning about an
		# existing database and the user confirmed it.
		my $forceopt = ( defined $q->{force} and $q->{force} eq "true" ) ? " --force" : "";
		s4l_backup_status_reset("preparing");
		my $pid = fork();
		if( !defined $pid ) {
			$error = "Could not start the restore";
		}
		elsif( $pid == 0 ) {
			open STDIN,  "< /dev/null";
			open STDOUT, "> /dev/null";
			open STDERR, "> /dev/null";
			system( s4l_backup_bin() . " restore --file " . quotemeta($f) . $dbopt . $forceopt );
			exit 0;
		}
		else {
			$response = '{ "started": 1 }';
		}
	}
}

## backup_delete
if( $q->{action} eq "backup_delete" ) {
	my $f = s4l_backup_file( $q->{file} );
	if( !$f ) {
		$error = "Unknown archive";
	}
	else {
		system( s4l_backup_bin() . " delete --file " . quotemeta($f) . " >/dev/null 2>&1" );
		$response = ( -e $f ) ? '{ "deleted": 0 }' : '{ "deleted": 1 }';
	}
}

## savebackupconfig
if( $q->{action} eq "savebackupconfig" ) {
	require LoxBerry::JSON;
	my $errors = 0;
	my $jsonobj = LoxBerry::JSON->new();
	my $cfg = $jsonobj->open( filename => $stats4loxconfig );
	if( !$cfg ) {
		$errors++;
	}
	else {
		$cfg->{backup}->{storagepath} = $q->{storagepath} // '';
		$cfg->{backup}->{compression} = $q->{compression} // 'gzip';
		$cfg->{backup}->{keep}        = $q->{keep} // 3;
		$cfg->{backup}->{schedule}->{active} = $q->{scheduleactive} // 'False';
		$cfg->{backup}->{schedule}->{repeat} = $q->{repeat} // 1;
		$cfg->{backup}->{schedule}->{time}   = $q->{timef} // '03:00';
		# The reference week for "every n weeks". Set on every save, so changing
		# the schedule starts the cycle now instead of continuing an old one the
		# user can no longer see.
		my @now = localtime();
		$cfg->{backup}->{schedule}->{since} =
			sprintf( "%04d-%02d-%02d", $now[5]+1900, $now[4]+1, $now[3] );
		foreach my $d ( qw( mon tue wed thu fre sat sun ) ) {
			$cfg->{backup}->{schedule}->{$d} = $q->{$d} // 'False';
		}
		$jsonobj->write();

		$errors++ if( !s4l_write_crontab( $cfg->{backup} ) );
	}
	$response = '{ "error":' . $errors . '}';
}

# Writes the schedule as a crontab, in the same way the LoxBerry backup widget
# does it: build the file with Config::Crontab, then let installcrontab.sh put
# it in place - that is the only path a plugin has into ~/system/cron/cron.d.
sub s4l_write_crontab
{
	my ($b) = @_;

	require Config::Crontab;
	require LoxBerry::System;

	# The crontab is named after the plugin, and the name may carry a suffix if
	# another plugin claimed it first - so it is read, not assumed.
	my $pdata = LoxBerry::System::plugindata();
	my $pname = $pdata ? $pdata->{PLUGINDB_NAME} : undef;
	if( !$pname ) {
		LOGERR "Could not determine the plugin name - crontab not written";
		return 0;
	}

	my $tmp = "/tmp/crontab_stats4lox_$$.txt";
	unlink $tmp if( -e $tmp );
	my $ct = Config::Crontab->new( -file => $tmp );

	my @dow;
	push @dow, "0" if( is_enabled( $b->{schedule}->{sun} ) );
	push @dow, "1" if( is_enabled( $b->{schedule}->{mon} ) );
	push @dow, "2" if( is_enabled( $b->{schedule}->{tue} ) );
	push @dow, "3" if( is_enabled( $b->{schedule}->{wed} ) );
	push @dow, "4" if( is_enabled( $b->{schedule}->{thu} ) );
	push @dow, "5" if( is_enabled( $b->{schedule}->{fre} ) );
	push @dow, "6" if( is_enabled( $b->{schedule}->{sat} ) );

	my $block = Config::Crontab::Block->new();
	$block->last( Config::Crontab::Comment->new(
		-data => '## Stats4Lox Backup - do not change manually. Your changes will be overwritten!' ) );
	$block->last( Config::Crontab::Env->new( -name => 'MAILTO', -value => '""' ) );

	if( is_enabled( $b->{schedule}->{active} ) and scalar @dow ) {
		my ($hour, $minute) = split( /:/, $b->{schedule}->{time} // '03:00' );
		$hour   = 0 if( !$hour   or $hour   eq "00" );
		$minute = 0 if( !$minute or $minute eq "00" );
		$hour   += 0;
		$minute += 0;

		# cron cannot express "every n weeks". The obvious workaround - a shell
		# prefix computing days since a reference date - does not survive here:
		# cron runs commands through /bin/sh, which is dash on LoxBerry and has
		# no [[ ]], and every unescaped % in a crontab command is turned into a
		# newline, which kills any "date +%s". So cron only gets weekday and
		# time, and "--cron" lets the script decide whether this week is due.
		#
		# installcrontab.sh rewrites " root " to " loxberry ", and the script
		# itself insists on root - hence sudo, which the plugin's sudoers rule
		# allows without a password.
		$block->last( Config::Crontab::Event->new(
			-minute  => $minute,
			-hour    => $hour,
			-dow     => join( ",", @dow ),
			-command => "loxberry sudo $lbpbindir/s4l_backup.pl create --cron > /dev/null 2>&1" ) );
	}

	$ct->last($block);
	$ct->write;

	my $rc = system( "sudo $lbhomedir/sbin/installcrontab.sh " . quotemeta($pname)
	                 . " " . quotemeta($tmp) . " >/dev/null 2>&1" );
	unlink $tmp;
	if( $rc != 0 ) {
		LOGERR "installcrontab.sh failed (rc $rc)";
		return 0;
	}
	LOGOK "Backup schedule written to the crontab";
	return 1;
}

## config-handler-status
if( $q->{action} eq "config-handler-status" ) {
	my $section = $q->{section};
	my $statfile = $Globals::stats4lox->{s4ltmp} . "/config-handler-status.json";
	if ( -e $statfile ) {
		$response = LoxBerry::System::read_file($statfile);
	}
	if ( !$response | !$section ) {
		$response = "{ }";
	}
}

## update_mqttsubscriptions
if( $q->{action} eq "update_mqttsubscriptions" ) {
	# The subscriptions are received via POST in form field 'subscriptions' as json
	
	my $subscriptions = from_json( $q->{subscriptions} );
	
	use Data::Dumper;
	LOGDEB "ajax subscriptions: " . $q->{subscriptions};
	# LOGDEB Dumper(\$subscriptions);
	
	# Remove empty elements
	while( my ($index, $subscription) = each @{$subscriptions} ) {
		LOGDEB $index . " " . $subscription;
		if( !defined $subscription->{id} or $subscription->{id} eq "" ) {
			LOGDEB "Removing empty subscription line (index $index)";
			delete @{$subscriptions}[$index];
		}
	}
	
	# LOGDEB Dumper(\$subscriptions);
	require LoxBerry::JSON;
	my $jsonobjcfg = LoxBerry::JSON->new();
	my $cfg = $jsonobjcfg->open(filename => $statsconfig, lockexclusive => 1);
	$cfg->{mqtt}->{subscriptions} = $subscriptions;
	$jsonobjcfg->write();
	
	$response = '{ }';


}



#####################################
# Manage Response and error
#####################################

if( defined $response and !defined $error ) {
	print "Status: 200 OK\r\n";
	print "Content-type: application/json; charset=utf-8\r\n\r\n";
	print $response;
	LOGOK "Parameters ok - responding with HTTP 200";
}
elsif ( defined $error and $error ne "" ) {
	print "Status: 500 Internal Server Error\r\n";
	print "Content-type: application/json; charset=utf-8\r\n\r\n";
	print to_json( { error => $error } );
	LOGCRIT "$error - responding with HTTP 500";
}
else {
	print "Status: 501 Not implemented\r\n";
	print "Content-type: application/json; charset=utf-8\r\n\r\n";
	$error = "Action ".$q->{action}." unknown";
	LOGCRIT "Method not implemented - responding with HTTP 501";
	print to_json( { error => $error } );
}

sub createImportFolder
{
	if( ! -d $Globals::stats4lox->{importstatusdir} ) {
		`mkdir --parents "$Globals::stats4lox->{importstatusdir}"`;
	}
}

END {
	LOGEND if($log);
}
