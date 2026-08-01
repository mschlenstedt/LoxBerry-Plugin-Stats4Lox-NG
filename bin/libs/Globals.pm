#!/usr/bin/perl
use LoxBerry::System;
use LoxBerry::JSON;

# NAVBAR definition (in scope main) - English defaults, translated by init_navbar_i18n()
#
# The Grafana entry links straight into Grafana's own web interface instead of
# going through a page of our own. That page existed, but its only live content
# was a button doing exactly this - everything else in it had been commented out
# as unfinished. js/s4l_navbar.js makes the entry open in a new tab; the
# LoxBerry navbar has no target attribute of its own.
our %navbar = (
	1 => {
			Name => "Home",
			URL => "index.cgi"
	},
	10 => {
			Name => "Loxone and Import",
			URL => "main_loxone.cgi"
	},
	20 => {
			Name => "Data Sources",
			URL => "input_mqtt.cgi"
	},
	30 => {
			Name => "Database",
			URL => "output_influx.cgi"
	},
	40 => {
			Name => "Grafana",
			# The real URL is set in init_navbar_i18n(): the configured port is
			# only known after merge_config(), which runs further down in this
			# file - after this definition.
			URL => "",
			# The navbar does not use the anchor's target attribute at all - its
			# click handler calls preventDefault() and then window.open(url,
			# target), taking "target" from this structure. So this property is
			# what actually opens Grafana in a new tab.
			target => "_blank"
	},
	90 => {
			Name => "Logfiles",
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
	@CONTROL_MS_FALLBACK
	$statsconfig
	$stats4loxconfig
	$stats4loxcredentials
	whoami
	merge_config
	init_navbar_i18n
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
	mqttlive_active => "True"
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


##################################################
# Translate navbar labels using readlanguage
# Must be called from CGI context before lbheader()
##################################################

sub init_navbar_i18n
{
	my %L = LoxBerry::System::readlanguage(undef, "language.ini");
	$main::navbar{1}{Name} = $L{'NAVBAR.NAV_HOME'} if $L{'NAVBAR.NAV_HOME'};
	$main::navbar{10}{Name} = $L{'NAVBAR.NAV_LOXONE_IMPORT'} if $L{'NAVBAR.NAV_LOXONE_IMPORT'};
	$main::navbar{20}{Name} = $L{'NAVBAR.NAV_DATASOURCES'} if $L{'NAVBAR.NAV_DATASOURCES'};
	$main::navbar{30}{Name} = $L{'NAVBAR.NAV_DATABASE'} if $L{'NAVBAR.NAV_DATABASE'};
	$main::navbar{40}{Name} = $L{'NAVBAR.NAV_GRAFANA'} if $L{'NAVBAR.NAV_GRAFANA'};
	$main::navbar{90}{Name} = $L{'NAVBAR.NAV_LOGS'} if $L{'NAVBAR.NAV_LOGS'};

	# Grafana runs on its own port, so the link needs the host name the browser
	# is currently talking to - not a name only the LoxBerry itself can resolve.
	# Filled in here and not in the definition above because merge_config(),
	# which supplies the configured port, only runs after it.
	my $port = ( $Globals::grafana && $Globals::grafana->{port} ) ? $Globals::grafana->{port} : 3000;
	my $host = $ENV{HTTP_HOST} // '';
	$host =~ s/:\d+$//;
	$host = LoxBerry::System::get_localip() if( $host eq '' );
	$main::navbar{40}{URL} = "http://$host:$port";
}



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
#
# VIRTUALINTEXT ("Virtueller Texteingang") is on this list for a reason that
# goes beyond tidiness: a virtual text input is writable, and the Loxone API
# WRITES on every read attempt. /jdev/sps/io/<uuid>/all sets the value to the
# literal string "all", and the form without a suffix sets it to an empty
# string. Offering such a block for statistics meant the grabber silently
# overwrote the user's value on every interval (issue #143). There is no safe
# read via this interface, so the block must not be selectable at all - use
# the MQTT Collector for text values instead.

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

# CONTROLS that get their Miniserver assigned as a fallback
#
# Some device containers - MTablet (Touch/Tablet), AudioServer, ... - are
# children of the Document instead of the LoxLIVE node. Controls below them
# find no Miniserver when walking up the tree, get no msno, and are then
# silently dropped by the frontend (settings_loxone.js: controls.filter
# msno > 0). Statistics enabled on such a block would disappear without a
# trace.
#
# Deliberately a positive list: a general fallback would also surface a few
# hundred structural objects (PuDe, RightGroup, Permission, ...) in the
# statistics selection.
#
# APIACTOR, GENSENSOR, GENASENSOR and AUDIOOUT were on this list and have been
# removed again: they are not function blocks. In the LoxPLAN they sit below a
# device, not below a program page - GENSENSOR and GENASENSOR belong to a
# Managed Tablet and are not sensors of their own, AUDIOOUT belongs to the
# Audio Server, APIACTOR to an intercom device. They are on the blacklist now.
our @CONTROL_MS_FALLBACK = qw/
ONLINE
/;

# The first block of entries below are not function blocks at all. They are
# other LoxPLAN objects that the parser picks up along the way, and their Title
# gives them away:
#
#   DateTime "Unix Timestamp", NightTime "Nacht", Week "Woche"  system variables
#   GlobalStates "Systemvariablen"                              their container
#   PuDe "Registriertes Gerät"                                  a paired device
#   RightGroup, Permission                                      user rights
#   MTablet "FlurEG"                                            a touch device
#   LanInt, LoxTree                                             interfaces
#   WeatherCaption "Netzwerkperipherie"                         a caption
#   SwitchingTimer "Immer"                                      a switching time
#   OvertempShutdown, AudioOut, ApiActor, GenSensor, GenAsensor belong to a
#                                            device, not to a program page
#
# On the test installation that alone was 264 entries in the selection list.
#
# Note on why this is a list and not a rule: it looks as if "everything that is
# not below a Page inside Program" would do it - that is exactly where the real
# function blocks live. Measured, that rule removes 1167 of 1527 entries,
# including VirtualIn (161), DigitalIn (56), VoltageIn (21) and Online (18),
# which sit below the peripherals and are perfectly legitimate. So the list it
# is.
our @CONTROL_BLACKLIST = qw/
APIACTOR
AUDIOOUT
DATETIME
GENASENSOR
GENSENSOR
GLOBALSTATES
LANINT
LOXTREE
MTABLET
NIGHTTIME
OVERTEMPSHUTDOWN
PERMISSION
PUDE
RIGHTGROUP
SWITCHINGTIMER
WEATHERCAPTION
WEEK
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
VIRTUALINTEXT
VIRTUALOUTCAPTION
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
