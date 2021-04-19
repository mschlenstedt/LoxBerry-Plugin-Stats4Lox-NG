#!/usr/bin/perl

# NAVBAR definition (in scope main)
our %navbar = (
	10 => {
			Name => "Loxone",
			URL => "index.cgi"
	},
	30 => {
			Name => "Inputs",
			URL => "input_settings.cgi"
	},
	50 => {
			Name => "Outputs",
			URL => "output_settings.cgi"
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
	$s4ltmp
	@CONTROL_BLACKLIST
	$importstatusdir
	$loxplanjsondir
	$statsconfig
	$stats4loxconfig
	$stats4loxcredentials
	$influx_bulk_blocksize
	whoami
);


# RAMDISK temporary directory
our $s4ltmp = '/dev/shm/s4ltmp';
our $loxplanjsondir = $LoxBerry::System::lbpdatadir;
our $statsconfig = "$LoxBerry::System::lbpconfigdir/stats.json";
our $stats4loxconfig = "$LoxBerry::System::lbpconfigdir/stats4lox.json";
our $stats4loxcredentials = "$LoxBerry::System::lbpconfigdir/cred.json";

# IMPORT SETTINGS
our $influx_bulk_blocksize = 1000;
our $influx_bulk_delay_secs = 1;

our $import_time_to_dead_minutes = 60;
our $import_max_parallel_processes = 4;
our $import_max_parallel_per_ms = 4;
our $importstatusdir = $LoxBerry::System::lbpdatadir.'/import';
our $influx_measurement = 'stats_loxone';
our $telegraf_unix_socket = '/tmp/telegraf.sock';
our $telegraf_udp_socket = '8094';

# GRAFANA PROVISIONING
our $graf_provisioning_dir = "/etc/grafana/provisioning";
our $s4l_provisioning_dir = "$LoxBerry::System::lbpdatadir/provisioning";


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
