#!/usr/bin/perl
use LoxBerry::System;
use LoxBerry::JSON;

# NAVBAR definition (in scope main)
our %navbar = (
	1 => {
			Name => "Home",
			URL => "index.cgi"
	},
	10 => {
			Name => "Loxone and Import",
			URL => "main_loxone.cgi"
	},
	30 => {
			Name => "Inputs / Outputs",
			URL => "inputs_outputs.cgi"
	},
	40 => {
			Name => "Chart Engines",
			URL => "chartengines.cgi"
	},
	90 => {
			Name => "Logs",
			URL => "logs.cgi"
	}
);
my $relative_webpath = substr( $0, length($lbphtmlauthdir)+1 );
foreach( keys %navbar ) {
	if( $navbar{$_}{URL} eq $relative_webpath ) {
		$navbar{$_}{active} = 1;
		last;
	}
}

#### GLOBALS ####

package Globals;

use base 'Exporter';
our @EXPORT = qw (
	@CONTROL_BLACKLIST
	$statsconfig
	$stats4loxconfig
	$stats4loxcredentials
	whoami
	merge_config
);

# Internal variable, if merge_config was already called
my $config_is_parsed;

# Main configuration files (not changeable in stats4lox.json)
our $statsconfig = "$LoxBerry::System::lbpconfigdir/stats.json";
our $stats4loxconfig = "$LoxBerry::System::lbpconfigdir/stats4lox.json";
our $stats4loxcredentials = "$LoxBerry::System::lbpconfigdir/cred.json";

# Default parameters

our $grafana = {
	port => 3000,
	grafanaport => 3000,
	graf_provisioning_dir => "/etc/grafana/provisioning",
	s4l_provisioning_dir => "$LoxBerry::System::lbpconfigdir/provisioning",
	s4l_provisioning_template_dir => "$LoxBerry::System::lbptemplatedir/grafana/templates",
};

our $influx = {
	influx_bulk_blocksize => 1000,
	influx_bulk_delay_secs => 1,
	influxbasicauth => "true",
	influxdatabase => "stats4lox",
	influxskiptlsverify => "true",
	influxurl => "https://localhost:8086",
};

our $loxberry = {
	active => "True",
	interval => 300,
	measurement => "stats_loxberry",
};

our $loxone = {
	active => "True",
	mqttlive_basetopic => "s4l/mqttlive",
	grabber_max_runtime => 4,
};

our $miniserver = {
	active => "True",
	interval => 300,
	measurement => "stats_miniserver",
};

our $stats4lox = { 
	s4ltmp => 	'/dev/shm/s4ltmp',
	loxplanjsondir => $LoxBerry::System::lbpdatadir,
	import_time_to_dead_minutes => 60,
	import_max_parallel_processes => 4,
	import_max_parallel_per_ms => 4,
	importstatusdir => $LoxBerry::System::lbpdatadir.'/import',
};

our $telegraf = {
	unixsocket => "/tmp/telegraf.sock",
	telegraf_unix_socket => "/tmp/telegraf.sock",
	telegraf_max_buffer_fullness => "0.75",
	telegraf_buffer_checks => ["influxdb"],
	telegraf_internal_files => "/tmp/telegraf_internals*.out",
	internal_statfiles => "/tmp/telegraf_internals*.out",
};


### Run merge_config ###
Globals::merge_config();



# IMPORT MAPPINGS

# How should data columns from a Loxone stat file map to outputs
# statpos --> index in the Loxone stat file (0-based index)
# lxlabel --> label of the output to map to

# Individual mappings by control type

our $ImportMapping = {};
$ImportMapping->{ENERGY} = [ 
	{ statpos => "0", lxlabel => "Default" },
	{ statpos => "0", lxlabel => "AQ" },
	{ statpos => "1", lxlabel => "AQp" } 
];

$ImportMapping->{FRONIUS} = [ 
	{ statpos => "0", lxlabel => "Default" },
	{ statpos => "0", lxlabel => "AQp" },
	{ statpos => "1", lxlabel => "AQc" },
	{ statpos => "2", lxlabel => "AQv" },
	{ statpos => "3", lxlabel => "AQPs" },
	{ statpos => "4", lxlabel => "AQSs" },
	{ statpos => "5", lxlabel => "AQp4" },
	{ statpos => "6", lxlabel => "AQc4" },
	{ statpos => "7", lxlabel => "AQd4" },
	{ statpos => "8", lxlabel => "AQi4" }
];	

# DEFAULT MAPPING
$ImportMapping->{Default} = [
	{ statpos => "0", lxlabel => "Default" },
	{ statpos => "0", lxlabel => "AQ"}
];



# BLACKLIST of controls not to add to controls section in json

# Unsure
# ACTOR="Aktor (Relais)"
# AUTOJALOUSIE="Automatikjalousie"
# BRIGHTNESS="Helligkeitsregler (BETA)"
# CALLERVIRTUALIN="Virtueller Eingang (Caller)"
# CURRENTOUT="Stromausgang (20mA)"
# DAYLIGHTCTRL="Tageslicht Steuerung (BETA)"
# DIMCURRENTIN="Strommessung (A)"
# DIMMER="Dimmerausgang"
# DOORCONTROLLER="Türsteuerung"
# FRONIUS="Energiemonitor"
# HEATCENRAL="Zentralheizung (BETA)"
# HEATCONTROL="Heizungsregelung"
# HEATCURVE="Heizkurve"
# HEATMIXER="Heizungsmischer"
# HEATMIXER2="Intelligente Temperatursteuerung"
# HOUSE="Eingehendes Paket"
# HVACController="Klima Controller"
# INTERCOM="Gegensprechanlage"
# JOINWINSENSOR="Composite-Fensterkontakt"
# LIGHTCONTROLLER="Lichtsteuerung Gen 1"
# LIGHTCONTROLLER2="Lichtsteuerung"
# LIGHTCONTROLLERH="Hotel Lichtsteuerung"
# LOX1WIREAACTOR="Analogaktor"
# LOX1WIREACTOR="Aktor"
# LOX1WIREASENSOR="Analogsensor"
# LOX1WIRESENSOR="Sensor"
# LOX232ACTOR="Aktor"
# LOX232SENSOR="Sensor"
# LOX232TEXTACTOR="Textaktor"
# LOX485ACTOR="Aktor"
# LOX485SENSOR="Sensor"
# LOX485TEXTACTOR="Textaktor"
# LOXAIRAACTOR="Analogaktor"
# LOXAIRACTOR="Aktor"
# LOXAIRASENSOR="Analogsensor"
# LOXAIRSENSOR="Sensor"
# LOXAIRTEXTACTOR="Textaktor"
# LOXAIRTEXTSENSOR="Textsensor"
# LOXDALIAACTOR="Aktor"
# LOXDALIACTOR="Relais"
# LOXDALISENSOR="Sensor"
# LOXDMXACTOR="Aktor"
# LOXDMXSENSOR="Analogsensor"
# LOXINTERCOMAACTOR="Analogaktor"
# LOXINTERCOMACTOR="Aktor"
# LOXINTERCOMASENSOR="Analogsensor"
# LOXINTERCOMSENSOR="Sensor"
# LOXOCEANAACTOR="Analogaktor"
# LOXOCEANACTOR="Aktor"
# LOXOCEANASENSOR="Analogsensor"
# LOXOCEANSENSOR="Sensor"
# MODBUSAACTOR="Analogaktor"
# MODBUSACTOR="Digitalaktor"
# MODBUSASENSOR="Analogsensor"
# MODBUSSENSOR="Digitalsensor"
# NFC="NFC-Tag"
# ONLINE="Onlinestatus"
# PING="Ping"
# POOLCONTROLLER="Poolsteuerung"
# PRESENCE="Visualisierungs-Präsenz"
# PRESENCECONTROLLER="Präsenzmelder (BETA)"
# PUMPCONTROL="Pumpenregelung"
# ROOFWINDOWCONTROLLER="Dachfenster"
# ROOMCONTROL="Raumregelung"
# SAUNA="Saunasteuerung"
# SAUNAVAPOR="Saunasteuerung Verdampfer"
# SHADEROOF="Dachfenster Rollo"
# SMOKEALARM="Brand- und Wassermeldezentrale"
# SOLARCOOLER="Solarkühler"
# SOLARPUMPCONTROL="Solarregelung"
# SOLARSTARTER="Solarstarter"
# STATEV="Virtueller Status"
# SYSTEMP="Systemtemperatur"
# TIMEMINMAX="Min Max seit Reset"
# TREEAACTOR="Analogaktor"
# TREEACTOR="Aktor"
# TREEASENSOR="Analogsensor"
# TREESENSOR="Sensor"
# TREETEXTACTOR="Textaktor"
# UARTACTOR="Aktor"
# UARTSENSOR="Sensor"
# UARTTEXTACTOR="Textaktor"
# VENT="Internorm Lüfter"
# VENTILATION="Raumlüftungssteuerung"
# VIRTUALHTTPINCMD="Virtueller HTTP Eingang Befehl"
# VIRTUALIN="Virtueller Eingang"
# VIRTUALINTEXT="Virtueller Texteingang"
# VIRTUALOUT="Virtueller Ausgang"
# VIRTUALUDPINCMD="Virtueller UDP Eingang Befehl"
# VOLTAGEIN="Spannungseingang"
# VOLTAGEOUT="Spannungsausgang"
# WEED="Viking iMow"
# WIND="Windmesser"
# WINDOWSMONITOR="Fenster- und Türüberwachung"
# ZAMBELLI="Zambelli"

our @CONTROL_BLACKLIST = qw/
2POINT
3POINT
AALSMARTALARM
ACCESS
ACTORCAPTION
ADD
ADD4
ALARMCHAIN
ALARMCLOCK
AMEMORY
AMINMAX
AMULTICLICK
ANALOGCOMPARATOR
ANALOGDIFFTRIGGER
ANALOGINPUTCAPTION
ANALOGMULTIPLEXER
ANALOGMULTIPLEXER2
ANALOGOUTPUTCAPTION
ANALOGSCALER
ANALOGSTEPPER
ANALOGWATCHDOG
AND
APP
APPLICATION
AUTOPILOT
AUTOPILOTRULE
AVERAGE
AVERAGE4
AVG
BINDECODER
CALENDAR
CALENDARCAPTION
CALENDARENTRY
CALLER
CATEGORY
CATEGORYCAPTION
CENTRAL
CMDRECOGNITION
CODE1
CODE16
CODE4
CODE8
COMM1WIRE
COMM232
COMM485
COMMDMX
COMMIR
CONNECTIONIN
CONNECTIONOUT
CONSTANT
CONSTANTCAPTION
COUNTER
DAY
DAY2009
DAYLIGHT
DAYLIGHT2
DAYOFWEEK
DAYTIMER
DEVICEMONITOR
DIV
DOCUMENT
DOCUMENTATION
DOUBLECLICK
EDGEDETECTION
EDGEWIPINGRELAY
EIBACTORCAPTION
EIBLINE
EIBPUSH
EIBSENSORCAPTION
EIBTEXTACTOR
EIBTEXTSENSOR
EQUAL
EVENINGTWILIGHT
FAN
FIDELIOSERVER
FLIPFLOP
FORMULA
GATECONTROLLER
GATEWAY
GATEWAYCLIENT
GEIGERJALOUSIE
GLOBAL
GREATER
GREATEREQUAL
HOUR
ICONCAPTIONCAT
ICONCAPTIONPLACE
ICONCAPTIONSTATE
ICONCAT
ICONPLACE
ICONSTATE
IMPULSEDAY
IMPULSEEVENINGTWILIGHT
IMPULSEHOUR
IMPULSEMINUTE
IMPULSEMONTH
IMPULSEMORNINGTWILIGHT
IMPULSESECOND
IMPULSESUNRISE
IMPULSESUNSET
IMPULSEYEAR
INPUTCAPTION
INPUTREF
INT
IRCONTROLLER
JALOUSIEUPDOWN2
KEYCODE
KRETA
LEAF
LESS
LESSEQUAL
LIGHTGROUP
LIGHTGROUPACTOR
LIGHTSCENE
LIGHTSCENELEARN
LIGHTSCENERGB
LOGGER
LOGGEROUTCAPTION
LONGCLICK
LOX1WIREDEVICE
LOXAINEXT
LOXAIR
LOXAIRDEVICE
LOXCAPTION
LOXDALI
LOXDALIDEVICE
LOXDALIGROUPACTOR
LOXDEVICECAPTION
LOXDEVICECAPTION2
LOXDIGINEXT
LOXDIMM
LOXDMXDEVICE
LOXINTERNORM
LOXINTERNORMDEVICE
LOXIRACTOR
LOXIRRCVDEVICE
LOXIRSENSOR
LOXIRSNDDEVICE
LOXKNXEXT
LOXLIVE
LOXMORE
LOXOCEAN
LOXOCEANDEVICE
LOXOUTEXT
LOXREL
MAILER
MEDIA
MEDIACLIENT
MEDIASERVER
MEMORYCAPTION
MESSAGECENTER
MINISERVERCOMM
MINMAX
MINUTE
MOD
MODBUSDEV
MODBUSSERVER
MODE
MODECAPTION
MONOFLOP
MONTH
MORNINGTWILIGHT
MOTORCONTROL
MULT
MULTICLICK
MULTIFUNCSW
MULTIMEDIASERVER
MUSICZONE
NETWORKDEVICE
NOT
NOTEQUAL
NOTIFICATION
OFFDELAY
ONDELAY
ONOFFDELAY
ONPULSEDELAY
OR
OUTPUTCAPTION
OUTPUTREF
OUTPUTREFLM
OVERTEMP
PAGE
PI
PID
PLACE
PLACECAPTION
PLACEGROUP
PLACEGROUPCAPTION
POWER
PROGRAM
PULSEAT
PULSEBY
PULSEGEN
PUSHBUTTON
PUSHBUTTON2
PUSHBUTTON2SEL
PUSHBUTTONSEL
PUSHDIMMER
PWM
RADIO
RADIO2
RAMP
RAND
RANDOMGEN
RC
RCKEY
REFUSER
REMOTECONTROLS
RETONDELAY
RSFLIPFLOP
SAFECURRENTOUT
SECOND
SECONDSBOOT
SENSORCAPTION
SEQUENCER
SHIFT
SONNENBATTERYDEVICE
SRFLIPFLOP
STAIRWAYLS
STARTPULSE
STATE
STEAKTHERMO
SUB
SUNALTITUDE
SUNAZIMUTH
SUNRISE
SUNSET
SWITCH
SWITCH2BUTTON
SYSVAR
TASKCAPTION
TASKSCHEDULER
TEXT
TEXTACTOR
TIME
TIMECAPTION
TOILET
TRACKER
TREE
TREEDEVICE
TREETURBODEVICE
UPDOWNCOUNTER
USER
USERCAPTION
USERGROUP
USERGROUPCAPTION
VALVEDEVICE
VIRTUALHTTPIN
VIRTUALINCAPTION
VIRTUALOUTCAPTION
VIRTUALOUTCMD
VIRTUALUDPIN
WALLMOUNTDEVICE
WEATHERDATA
WEATHERSERVER
WEBPAGE
WIPINGRELAY
XOR
YEAR
/;

##################################################
# Merge default config with stats4lox.json config
##################################################

sub merge_config 
{
	my %args = @_;
	if( ! $args{config_force_parse} ) {
		return if( $config_is_parsed );
	}

	require Hash::Merge;
	
	my $configobj = LoxBerry::JSON->new();
	my $config = $configobj->open(filename => $Globals::stats4loxconfig, readonly => 1);
	
	my $merge = Hash::Merge->new('LEFT_PRECEDENT');
	
	# print STDERR "Port (Globals) : " . $Globals::grafana->{port} . "\n";
	# print STDERR "Port (S4L.json): " . $config->{grafana}->{port} . "\n";
	
	$Globals::grafana = 	$merge->merge( $config->{grafana}, $Globals::grafana );
	$Globals::influx = 		$merge->merge( $config->{influx}, $Globals::influx );
	$Globals::loxberry = 	$merge->merge( $config->{loxberry}, $Globals::loxberry );
	$Globals::loxone = 		$merge->merge( $config->{loxone}, $Globals::loxone );
	$Globals::miniserver = 	$merge->merge( $config->{miniserver}, $Globals::miniserver );
	$Globals::stats4lox = 	$merge->merge( $config->{stats4lox}, $Globals::stats4lox );
	$Globals::telegraf = 	$merge->merge( $config->{telegraf}, $Globals::telegraf );

	$config_is_parsed = 1;
}



# Returns the name of the current sub (for logfile)
# e.g. my $me = whoami();
# print "$me Starting import"; returns "Loxone::Import::new--> Starting import"
sub whoami { 
	return ( caller(1))[3] . '-->';
}


#####################################################
# Finally 1; ########################################
#####################################################
1;
