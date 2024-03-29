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

my $log = LoxBerry::Log->new (
    name => 'AJAX',
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
		if( $@ or $remoteTimestamp ne "" ) {
			LOGINF "Loxplan file not up-to-date. Fetching from Miniserver\n";
			Loxone::GetLoxplan::getLoxplan( 
				ms => $msno, 
				log => $log 
			);
			
			if( -e $Loxplanfile ) {
				LOGOK "Loxplan for MS$msno found, parsing now...\n";
				my $loxplan = Loxone::ParseXML::loxplan2json( 
					filename => $Loxplanfile,
					output => $loxplanjson,
					log => $log,
					remoteTimestamp => $remoteTimestamp,
					ms_serials => \%ms_serials
				);
			}
			
		} else {
			LOGINF "Loxplan file is up-to-date. Using local copy\n";
		}
		
		if( -e $loxplanjson) { 
			$response = LoxBerry::System::read_file($loxplanjson);
		} else {
			$response = '{ "error":"Could not fetch Loxone Config of MS No. '.$msno.'"}';
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

## starttelegraf
if( $q->{action} eq "starttelegraf" ) {
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
	my $grafanastat = `pgrep -f /usr/sbin/grafana-server`;
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

	} # End Child process

	$response = '{ "error":' . $errors . '}';
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
