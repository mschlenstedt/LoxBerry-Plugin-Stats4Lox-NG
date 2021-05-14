#!/usr/bin/php
<?php
require_once "loxberry_system.php";
require_once "loxberry_io.php";
require_once "loxberry_log.php";
require_once "phpMQTT/phpMQTT.php";
require_once LBPBINDIR . "/libs/filechangeTracker.php";

// Create logfile
$log = LBLog::newLog( [ 
	"name" => "MQTTLive",
	"addtime" => 1,
	"append" => 1,
	"filename" => LBPLOGDIR."/mqttlive.log"
] );
LOGSTART("Stats4Lox MQTT Live");

register_shutdown_function('shutdownHandler');
set_exception_handler ('exceptionHandler');
// pcntl_signal(SIGTERM, 'shutdownHandler');
// pcntl_signal(SIGHUP,  'shutdownHandler');
// pcntl_signal(SIGUSR1, 'shutdownHandler');
// pcntl_signal(SIGINT, 'shutdownHandler');

// Global variables
$stats_json = "$lbpconfigdir/stats.json";
$stats4lox_json = "$lbpconfigdir/stats4lox.json";
$plugindatabase = "$lbsdatadir/plugindatabase.json";
$data_transferfolder = "/dev/shm/s4ltmp";
$data_transferfile = $data_transferfolder."/mqttlive_dataspool.json";
$perlprocessor_filename = LBPBINDIR."/lox2telegraf.pl";
$uidata_file = $data_transferfolder."/mqttlive_uidata.json";

$mqtt_connected = false;

if(!file_exists($data_transferfolder) ){
	mkdir( $data_transferfolder );
}

// Create record queue and ui data
$recordqueue = array();
$uidata = array();
$uidata_update = true;

// Tracker for files
$filetracker = new filechangeTracker();
$filetracker->addmonitor( $stats4lox_json, "readStats4loxjson");
$filetracker->addmonitor( $stats_json, "readStatsjson");
$filetracker->addmonitor( $plugindatabase, "readMqttCredentials");
$filetracker->addmonitor( LBHOMEDIR."/config/plugins/mqttgateway/mqtt.json", "readMqttCredentials");
$filetracker->addmonitor( LBHOMEDIR."/config/plugins/mqttgateway/cred.json", "readMqttCredentials");
$filetracker->check();

// Schedules of this program
$runtime_1secs = microtime(true);
$runtime_1mins = microtime(true);

// Measure CPU usage for fun ;-)
$cpu_usage = getrusage()["ru_utime.tv_usec"];

// Initial push file-queued data to influx
callPerlProcessor();

// Permanent loop
while(1) {
	if($mqtt_connected) {
		$mqtt->proc("false");
	}
	else {
		sleep(5);
	}
	if( microtime(true)>=$runtime_1secs+1 ) {
		// Run tasks every second
		tasks_1secs();
		$runtime_1secs=microtime(true);
	}
	
	if( time()>=$runtime_1mins+59 ) {
		// Run tasks every minute
		
		// Calculate CPU usage
		$cpu_usage_now = getrusage()["ru_utime.tv_usec"];
		$newruntime=microtime(true);
		LOGINF("CPU time: " . round( ($cpu_usage_now-$cpu_usage)/($newruntime-$runtime_1mins)/1000000*100, 2) ." %");
		$cpu_usage = $cpu_usage_now;
		
		// Run 1 Min. task
		tasks_1mins();
		if( $mqtt ) {
			$mqtt->ping();
		}
		$runtime_1mins=$newruntime;
	}
}

$mqtt->close();

//
// Incoming MQTT message for S4L Live Update 
//
function s4llive_mqttmsg ($topic, $msg){
	global $basetopic;
	global $lwt_topic;
	global $stats;
	global $statsByMeasurement;
	global $recordqueue;
	global $uidata;
	global $uidata_update;
	
	if( substr($topic, -(strlen("/connected")), strlen("/connected")) == "/connected" ) {
		return;
	}
	if ( substr($topic, -(strlen("/command")), strlen("/command")) == "/command" ) {
		s4llive_command( $topic, $msg );
		return;
	}
	
	
	$timestamp_epoch = microtime(true);
	$timestamp_nsec = sprintf('%.0f', $timestamp_epoch*1000000000);
	LOGOK("{$topic}-->$msg ($timestamp_nsec)");
	
	$reltopic = substr( $topic, strlen($basetopic)+1 );
	LOGDEB("Relative Topic $reltopic");
	list( $msno, $uuid, $output ) = explode( "/", $reltopic );
	LOGINF("MS: $msno UUID: $uuid OUTPUT: $output");
	
	$id = "${msno}_${uuid}";
	
	$errormsg = "";
	
	$item = new stdClass();
	$item->timestamp = $timestamp_nsec;
	$item->timestamp_epoch = $timestamp_epoch;
	$item->originaltopic = $topic;
	$item->relativetopic = $reltopic;
	$item->values = array( 
		array( 
			'key' => $output,
			'value' => $msg 
		) 
	);
	
	if( !property_exists ( $stats, $id ) ) {
		// msno_uuid combination not found - fallback to search for measurementname
		if( property_exists( $statsByMeasurement, $id ) ) {
			$id = $statsByMeasurement->$id;
			LOGOK("Using measurementname, new id is $id");
		}
	}
	
	// Message validated
	if( property_exists ( $stats, $id ) ) {
		$dest = $stats->$id;
		LOGINF("Name: $dest->name Room: $dest->room");
		
		if( !in_array( $output, $dest->outputlabels ) ) {
			$error = "ERROR Output '$output' unknown for this element";
			$item->error = $error;
			LOGWARN($error);
		}
		elseif( empty($dest->measurementname) ) {
			$error = "ERROR No measurementname defined in stats.json for UUID $uuid";
			$item->error = $error;
			LOGWARN($error);
		}
		else {
			$item->measurementname = $dest->measurementname;
			$item->source = "mqttlive";
			if( $dest->name ) $item->name = $dest->name;
			if( $dest->description ) $item->description = $dest->description;
			if( $dest->uuid ) $item->uuid = $dest->uuid;
			if( $dest->type ) $item->type = $dest->type;
			if( $dest->category ) $item->category = $dest->category;
			if( $dest->room ) $item->room = $dest->room;
			if( $dest->msno ) $item->msno = $dest->msno;
			
			$recordqueue[] = $item;
		
			LOGDEB("linequeue length before sending: " . count($recordqueue));
		}
	}
	
	// UNKNOWN Message
	else {
		$item->error = "UNKNOWN: $msno/$uuid not found";
		LOGWARN("UNKNOWN $msno/$uuid");
	}
	
	unset($uidata["topics"]["$reltopic"]);
	$uidata["topics"]["$reltopic"] = $item;
	$uidata_update = true;

}

//
// Incoming MQTT message for S4L Commands 
//
function s4llive_command($topic, $msg){
	global $basetopic;
	global $uidata;
	global $uidata_update;
	LOGOK("s4llive_command received: $msg");

	switch($msg) {
		case "shutdown": 
			LOGOK("Shutting down mqttlive");
			exit(0);
		case "clearuidata":
			LOGOK("Clearing UI data");
			$uidata["topics"] = array();
			$uidata_update = true;
			break;
		default: 
			LOGWARN("command topic: Unknown command $msg");
	}
}



function tasks_1secs() {
	global $uidata_update;
	global $filetracker;
	
	// echo "tasks_1secs\n";
	$filetracker->check();
	// $filetracker->dump();

	// readStatsjson(); 
	outputLinequeue();
	
	if( $uidata_update ) {
		writeInfoForUI();
		$uidata_update = false;
	}
}

function tasks_1mins() {
	global $recordqueue;
	global $mqtt;
	global $lwt_topic;
	
	LOGINF("tasks_1mins");
	// get_miniservers (but possibly by inotify)
	
	// Update LWT
	if( $mqtt ) {
		$mqtt->publish( $lwt_topic, "true", 0, true);
	}
	outputLinequeue();
	
	$queue_size = count($recordqueue);
	LOGINF("Cleanup: Current linequeue length: $queue_size");
		
	// Cleanup queue if queue is too big
	if( $queue_size > 1000 ) {
		LOGWARN("Cleanup: Reducing linequeue to 900");
		usort($recordqueue, function($a, $b) {
			return $a->timestamp < $b->timestamp ? -1 : 1; });
		
		// Reduce queue to the 900 latest entries
		$recordqueue = array_slice($recordqueue, $queue_size-900);
	}
}

function readStats4loxjson( $stats4lox_json, $mtime ) {
	global $basetopic;
	global $mqtt;
	
	LOGINF("READ Stats4Lox.json");
	if( $mtime == false ) {
		LOGWARN("   File does not exist");
	} else {
		$stats4loxcfg = json_decode( file_get_contents( $stats4lox_json ) );
	}
	
	$newbasetopic = !empty( $stats4loxcfg->loxone->mqttlive_basetopic ) ? trim( $stats4loxcfg->loxone->mqttlive_basetopic ) : 's4l/mqttlive';
	$newbasetopic = rtrim( $newbasetopic, "#/" );
	if( $newbasetopic != $basetopic) {
		$basetopic = $newbasetopic;
		LOGOK("Using Base topic $basetopic");
		if( $mqtt ) {
			mqttConnect();
		}
	}
	
}

function readStatsjson( $stats_json, $mtime ) {
	global $stats;
	global $statsByMeasurement;

	if( $mtime == false ) {
		return;
	}
	$statscfg = json_decode( file_get_contents( $stats_json ) );
		
	$stats = new stdClass();
	$statsByMeasurement = new stdClass();
	
	if( !$statscfg ) {
		return;
	}
	

	// Convert Loxone array to list of objects
	//	"loxone" is an unindexed array in stats.json.
	//	To directly access the element, create an object list with key $msno_$uuid
	foreach($statscfg->loxone as $cfg) {
		$msno = $cfg->msno;
		$uuid = $cfg->uuid;
		$measurementname = isset($cfg->measurementname) ? $cfg->measurementname : false ;
		$stats->{"${msno}_${uuid}"} = $cfg;
		// Also create a pointer from measurementname to the msno_uuid object
		if( $measurementname ) {
			// For MQTT Gateway publishes, measurementname topic isn't allowed to have whitespaces
			$measurementname_safe = str_replace( [' ','/','#'], '_', $measurementname );
			$statsByMeasurement->{"${msno}_${measurementname_safe}"} = "${msno}_${uuid}";
		}
	}
}

function outputLinequeue() {
	global $data_transferfile;
	global $recordqueue;
	global $mqtt_connected;

	$queue_size = count($recordqueue);
	
	
	if( $queue_size == 0 ) {
		// Nothing to do
		return;
	}
	else {
		LOGINF("Queue size: $queue_size elements"); 
		if( $mqtt_connected ) {
			LOGOK("MQTT connected");
		}
		else {
			LOGWARN("MQTT not connected");
		}
	}

	$outputfh = fopen($data_transferfile, "c+");
	
	//Lock File, error if unable to lock
	if( !flock($outputfh, LOCK_EX | LOCK_NB) ) {
		LOGINF("Data Transferfile could not be locked. Trying it again in a second. ($data_transferfile)");
		fclose($outputfh);
		return;
	}
	
	// echo "READ FILE\n";
	rewind($outputfh);
	$filedatastr = fread($outputfh, 5242880 );
	// echo "FILEDATASTR:\n".$filedatastr."\n";
	
	if( strlen($filedatastr) > 0) {
		$filedata = json_decode( $filedatastr , false, 512, JSON_THROW_ON_ERROR | JSON_INVALID_UTF8_IGNORE);
	} 
	else {
		$filedata = "";
	}
	
	// echo "FILEDATA is " . gettype($filedata) . "\n";

	if( is_array($filedata) ) {
		// echo "ARRAYMERGE\n";
		$filedata = array_merge( $filedata, $recordqueue );
	}
	else {
		// echo "SET FILEDATA TO RECORDQUEUE\n";
		$filedata = $recordqueue;
	}
	
	try {
		ftruncate($outputfh, 0);
		rewind($outputfh);
		fwrite($outputfh, json_encode( $filedata, JSON_INVALID_UTF8_IGNORE | JSON_PRETTY_PRINT | JSON_UNESCAPED_LINE_TERMINATORS | JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_THROW_ON_ERROR));
		flock($outputfh, LOCK_UN);
		fclose($outputfh);
	}
	catch( Exception $e ) {
		LOGERR("EXCEPTION on writing file - linequeue not truncated. ".$e->getMessage());
		return;
	}
	
	// Things are sent, we can truncate the linequeue
	$recordqueue = array();
	callPerlProcessor();
} 
	
function callPerlProcessor() {
	global $perlprocessor_filename;
	global $perlprocessor_pid;
	global $data_transferfile;
	global $lbplogdir;
	
	LOGINF("PID running? " . posix_getpgid($perlprocessor_pid));
	if( empty($perlprocessor_pid) or empty(posix_getpgid($perlprocessor_pid)) ) {
		LOGINF("RUNNING PERL PROCESSOR");
		exec("$perlprocessor_filename \"$data_transferfile\" >>$lbplogdir/mqttlive_lox2telegraf.log 1>&2 & echo $!; ", $perlprocessor_pid);
		$perlprocessor_pid = $perlprocessor_pid[0];
		LOGOK("PID: $perlprocessor_pid");
	}
	else { 
		LOGINF("Seems to be running. Skipping this round.");
	}
}

function writeInfoForUI() {
	global $uidata;
	global $uidata_file;
	
	// print_r( $uidata );
	
	file_put_contents( $uidata_file, json_encode($uidata, JSON_INVALID_UTF8_IGNORE | JSON_UNESCAPED_LINE_TERMINATORS |  JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE ) );
}


function readMqttCredentials() {
	global $creds;
	global $uidata, $uidata_update;
	$oldcreds = $creds;
	
	// Get the MQTT Gateway connection details from LoxBerry
	LOGINF("Reading MQTT Gateway credentials");
	$creds = mqtt_connectiondetails();
	if( $creds ) {
		LOGOK("Using broker and credentials from MQTT Gateway");
	}
	else {
		$error = "Could not read MQTT Gateway connection details - MQTT Gateway installed?";
		LOGERR($error);
		$uidata["state"]["broker_connected"] = false;
		$uidata["state"]["broker_error"] = $error;
		$uidata_update = true;
	}

	if( $creds && $oldcreds !== $creds ) {
		// MQTT credentials changed, reconnect
		LOGINF("MQTT credentials changed, reconnecting");
		mqttConnect();
	}
}

function mqttConnect() {
	global $creds;
	global $mqtt;
	global $mqtt_connected;
	global $basetopic;
	global $lwt_topic;
	global $uidata;
	global $uidata_update;
	
	LOGINF("mqttConnect $basetopic");
	
	$uidata["state"]["broker_basetopic"] = $basetopic;
	
	if( !$creds ) {
		$error = "mqttConnect: No MQTT credentials. MQTT Gateway not installed?";
		LOGERR($error);
		$uidata["state"]["broker_connected"] = false;
		$uidata["state"]["broker_error"] = $error;
		$uidata_update = true;
		return;
	}
	
	// MQTT requires a unique client id
	$client_id = uniqid(gethostname()."_s4lmqttlive".rand(1,999));
	$lwt_topic = $basetopic."/connected";
	
	// Create mqtt connection
	if( $mqtt ) {
		LOGINF("Closing MQTT connection");
		$mqtt->disconnect();
		sleep(1);
		$mqtt = null;
	}
		
	LOGINF("Creating new mqtt connection");
	$mqtt = new Bluerhinos\phpMQTT($creds['brokerhost'],  $creds['brokerport'], $client_id);
	
	$mqtt_connected = $mqtt->connect(true, [ "topic" => "$lwt_topic", "content" => "false", "qos" => 0, "retain" => true ] , $creds['brokeruser'], $creds['brokerpass'] );
	if( !$mqtt_connected ) {
		$error = "MQTT connection to broker ".$creds['brokerhost'].":".$creds['brokerport']." failed";
		LOGERR($error);
		$uidata["state"]["broker_connected"] = false;
		$uidata["state"]["broker_error"] = $error;
		$uidata_update = true;
		LOGTITLE("MQTT connection offline");
		return;
	}
	LOGOK("Connected to MQTT broker ".$creds['brokerhost'].":".$creds['brokerport']." (Topic $basetopic)");
	LOGTITLE("Base topic $basetopic");
	$uidata["state"]["broker_connected"] = true;
	$uidata["state"]["broker_error"] = "";
	$uidata_update = true;
	
	// Define and subscribe topic
	unset($topics);
	$topics["$basetopic/#"] = array('qos' => 0, 'function' => 's4llive_mqttmsg');
	$mqtt->subscribe($topics, 0);

	// Publish will topic to be online
	$mqtt->publish( $lwt_topic, "true", 0, true);
	
} 






function exceptionHandler ( $ex ) {
	if( $log ) {
		$log->CRIT("PHP EXCEPTION: " . $ex->getMessage());
	}
	shutdownHandler();
}

function shutdownHandler( $signal = null ) {
	global $log;
	
	$log->INF("MQTT Live is shutting down");
	$log->LOGEND("MQTT Live: Shutdown");
	
	exit();
}
