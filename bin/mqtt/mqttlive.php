#!/usr/bin/php
<?php
require_once "loxberry_system.php";
require_once "loxberry_io.php";
require_once "phpMQTT/phpMQTT.php";
require_once LBPBINDIR . "/libs/filechangeTracker.php";
 
// Global variables
$stats_json = "$lbpconfigdir/stats.json";
$stats4lox_json = "$lbpconfigdir/stats4lox.json";
$plugindatabase = "$lbsdatadir/plugindatabase.json";
$data_transferfolder = "/dev/shm/s4ltmp";
$data_transferfile = $data_transferfolder."/mqttlive_dataspool.json";
$perlprocessor_filename = LBPBINDIR."/lox2telegraf.pl";
$uidata_file = $data_transferfolder."/mqttlive_uidata.json";

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
		echo "CPU time: " . round( ($cpu_usage_now-$cpu_usage)/($newruntime-$runtime_1mins)/1000000*100, 2) ." %\n";
		$cpu_usage = $cpu_usage_now;
		
		// Run 1 Min. task
		tasks_1mins();
		
		$runtime_1mins=$newruntime;
	}
}

$mqtt->close();

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
	
	$timestamp_epoch = microtime(true);
	$timestamp_nsec = sprintf('%.0f', $timestamp_epoch*1000000000);
	echo date('H:i:s')." {$topic}-->$msg ($timestamp_nsec)\n";
	
	$reltopic = substr( $topic, strlen($basetopic)+1 );
	echo "Relative Topic $reltopic\n";
	list( $msno, $uuid, $output ) = explode( "/", $reltopic );
	echo "MS: $msno UUID: $uuid OUTPUT: $output\n";
	
	$id = "${msno}_${uuid}";
	
	$errormsg = "";
	
	$item = new stdClass();
	$item->timestamp = $timestamp_nsec;
	$item->timestamp_epoch = $timestamp_epoch;
	$item->originaltopic = $topic;
	$item->relativetopic = $reltopic;
	$item->values = array( array( $output => $msg ) );
	
	if( !property_exists ( $stats, $id ) ) {
		// msno_uuid combination not found - fallback to search for measurementname
		if( property_exists( $statsByMeasurement, $id ) ) {
			$id = $statsByMeasurement->$id;
			echo "New id is $id\n";
		}
	}
	
	// Message validated
	if( property_exists ( $stats, $id ) ) {
		$dest = $stats->$id;
		echo "Name: $dest->name Room: $dest->room\n";
		
		if( empty($dest->measurementname) ) {
			$error = "ERROR No measurementname defined in stats.json for UUID $uuid";
			$item->error = $error;
			echo $error."\n";
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
		
			echo "linequeue length before sending: " . count($recordqueue) . "\n";
		}
	}
	
	// UNKNOWN Message
	else {
		$item->error = "UNKNOWN: $msno/$uuid not found";
		echo "UNKNOWN $msno/$uuid\n";
	}
	
	unset($uidata["topics"]["$reltopic"]);
	$uidata["topics"]["$reltopic"] = $item;
	$uidata_update = true;

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
	
	echo date("y-m-d H:i:s") . " tasks_1mins\n";
	// get_miniservers (but possibly by inotify)
	
	// Update LWT
	$mqtt->publish( $lwt_topic, "true", 0, true);
	
	outputLinequeue();
	
	$queue_size = count($recordqueue);
	echo "Cleanup: Current linequeue length: $queue_size\n";
		
	// Cleanup queue if queue is too big
	if( $queue_size > 1000 ) {
		usort($recordqueue, function($a, $b) {
			return $a->timestamp < $b->timestamp ? -1 : 1; });
		
		// Reduce queue to the 900 latest entries
		$recordqueue = array_slice($recordqueue, $queue_size-900);
	}
}

function readStats4loxjson( $stats4lox_json, $mtime ) {
	global $basetopic;
	global $mqtt;
	
	echo "READ Stats4Lox.json\n";
	if( $mtime == false ) {
		echo "   File does not exist\n";
	} else {
		$stats4loxcfg = json_decode( file_get_contents( $stats4lox_json ) );
	}
	
	$newbasetopic = !empty( $stats4loxcfg->loxone->mqttlive_basetopic ) ? trim( $stats4loxcfg->loxone->mqttlive_basetopic ) : 's4l/mqttlive';
	$newbasetopic = rtrim( $newbasetopic, "#/" );
	if( $newbasetopic != $basetopic) {
		echo "Basetopic $basetopic\n";
		$basetopic = $newbasetopic;
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
		print "Queue size: $queue_size elements "; 
		if( $mqtt_connected ) {
			print "(MQTT connected)\n";
		}
		else {
			print "(MQTT not connected)\n";
		}
	}

	$outputfh = fopen($data_transferfile, "c+");
	
	//Lock File, error if unable to lock
	if( !flock($outputfh, LOCK_EX | LOCK_NB) ) {
		echo "Data Transferfile could not be locked. Trying again in a second. ($data_transferfile)\n";
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
		echo "EXCEPTION on writing file - linequeue not truncated. ".$e->getMessage()."\n";
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
	
	echo "PID running? " . posix_getpgid($perlprocessor_pid) . "\n";
if( empty($perlprocessor_pid) or empty(posix_getpgid($perlprocessor_pid)) ) {
		echo "RUN PERL PROCESSOR";
		exec("$perlprocessor_filename \"$data_transferfile\" >/dev/null 2>&1 & echo $!; ", $perlprocessor_pid);
		$perlprocessor_pid = $perlprocessor_pid[0];
		echo " PID: $perlprocessor_pid\n";
	}
	else { 
		echo " seems to be running. Skipping this round.\n";
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
	$oldcreds = $creds;
	
	// Get the MQTT Gateway connection details from LoxBerry
	$creds = mqtt_connectiondetails();

	if( $oldcreds !== $creds ) {
		// MQTT credentials changed, reconnect
		echo "MQTT credentials changed, reconnecting\n";
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
	
	echo "mqttConnect $basetopic\n";
	
	$uidata["state"]["broker_basetopic"] = $basetopic;
	
	if( empty($creds) ) {
		$error = "No MQTT credentials. MQTT Gateway not installed?";
		print $error."\n";
		$uidata["state"]["broker_connected"] = false;
		$uidata["state"]["broker_error"] = $error;
		$uidata_update = true;
	}
	
	// MQTT requires a unique client id
	$client_id = uniqid(gethostname()."_s4lmqttlive".rand(1,999));
	$lwt_topic = $basetopic."/connected";
	
	// Create mqtt connection
	if( $mqtt ) {
		echo "Closing MQTT connection\n";
		$mqtt->disconnect();
		sleep(1);
		$mqtt = null;
	}
		
	echo "Creating new mqtt connection\n";
	$mqtt = new Bluerhinos\phpMQTT($creds['brokerhost'],  $creds['brokerport'], $client_id);
	
	$mqtt_connected = $mqtt->connect(true, [ "topic" => "$lwt_topic", "content" => "false", "qos" => 0, "retain" => true ] , $creds['brokeruser'], $creds['brokerpass'] );
	if( !$mqtt_connected ) {
		$error = "MQTT connection to broker ".$creds['brokerhost'].":".$creds['brokerport']." failed";
		print $error."\n";
		$uidata["state"]["broker_connected"] = false;
		$uidata["state"]["broker_error"] = $error;
		$uidata_update = true;
		return;
	}
	echo "Connected to MQTT broker ".$creds['brokerhost'].":".$creds['brokerport']." (Topic $basetopic)\n";
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


// Wastebasket ;-)

		/* 
		// Socket send - not required anymore
		foreach( $recordqueue as $linekey => $lineobj) {
			$expectedbytes = strlen($lineobj->line);
			$sentbytes = false;
			if( $socket ) {
				$sentbytes = fwrite( $socket, $lineobj->line );
				if( $sentbytes != false && $sentbytes == $expectedbytes ) {
					unset( $recordqueue[$linekey] );
				}
				else { 
					echo "ERROR sending line: Sent: $sentbytes Expected: $expectedbytes\n";
				}
			}
		}
		
		*/
		

/*
// Create Influx lineprot - not necessary anymore
function getLineprot( $timestamp, $value, $dest, $output ) {
	
	$measurement = "stats4lox";
	$tags = array();
	$fields = array();
	
	$measurement = LineProtCleanMeasurements($measurement);
	
	
	if( $dest->category ) $tags["category"] = LineProtCleanTags($dest->category);
	if( $dest->description ) $tags["description"] = LineProtCleanTags($dest->description);
	if( $dest->msno ) $tags["msno"] = LineProtCleanTags($dest->msno);
	if( $dest->name ) $tags["name"] = LineProtCleanTags($dest->name);
	if( $dest->uuid ) $tags["uuid"] = LineProtCleanTags($dest->uuid);
	if( $dest->room ) $tags["room"] = LineProtCleanTags($dest->room);
	if( $dest->type ) $tags["type"] = LineProtCleanTags($dest->type);
	
	$valname = $dest->uuid."_".$output;
	$fields["$valname"] = $value;
	
	$line = "$measurement";
	
	foreach( $tags as $tagkey => $tagvalue ) {
		$line .= ",$tagkey=$tagvalue";
	}
	
	$line .= ' ';
	
	foreach( $fields as $fieldkey => $fieldvalue ) {
		$line .= "$fieldkey=$fieldvalue,";
	}
	$line = rtrim($line, ',');
	
	$line .= ' ';
	
	$line .= $timestamp;
	
	$line .= "\n";
	
	return $line;
	
}

*/

/*
// UNIX socket - not required anymore

function openUnixSocket() {
	
	// Read S4L config
	$s4lcfg = json_decode( file_get_contents( LBPCONFIGDIR . "/stats4lox.json" ) );
	
	$unixsocketfile = "unix://" . $s4lcfg->telegraf->unixsocket;
	
	if( empty( $unixsocketfile ) ) {
		echo "ERROR Reading stats4lox.json telegraf unix socket\n";
		return;
	}
	
	$socket = stream_socket_client ( $unixsocketfile , $errno , $errstr, 10, STREAM_CLIENT_CONNECT );

	if( !$socket ) {
		echo "ERROR opening telegraf unix socket $unixsocketfile\n";
		return;
	}
	
	return $socket;
}
*/


/*
// Tag keys, tag values, field keys
function LineProtCleanTags( $line ) {
	return str_replace( [',', '=', ' '], [ '\,', '\=', '\ '], $line );
}
// Measurements
function LineProtCleanMeasurements( $line ) {
	return str_replace( [',', ' '], [ '\,', '\ '], $line );
}
// String field values
function LineProtCleanStringFieldValues( $line ) {
	return str_replace( ['"'], [ '\"'], $line );
}
*/
