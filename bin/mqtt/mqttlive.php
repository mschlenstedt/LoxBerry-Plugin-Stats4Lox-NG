#!/usr/bin/php
<?php
require_once "loxberry_system.php";
require_once "loxberry_io.php";
require_once "./phpMQTT.php";
 
// Get the MQTT Gateway connection details from LoxBerry
$creds = mqtt_connectiondetails();
 
// MQTT requires a unique client id
$client_id = uniqid(gethostname()."_s4llive");
 
$basetopic = 's4llive/';
 
$mqtt = new Bluerhinos\phpMQTT($creds['brokerhost'],  $creds['brokerport'], $client_id);
if( ! $mqtt->connect(true, NULL, $creds['brokeruser'], $creds['brokerpass'] ) ) {
	
	echo "MQTT connection failed";
	exit(1);
	// We should do a retry here
} 

echo "Connected to MQTT broker ".$creds['brokerhost'].":".$creds['brokerport']."\n";

// Define and subscribe topic
$topics['s4llive/#'] = array('qos' => 0, 'function' => 's4llive_mqttmsg');
$mqtt->subscribe($topics, 0);

// Open Unix Socket
$socket = openUnixSocket();
$linequeue = array();
$uidata = array();
$uidata_update = true;

$runtime_5secs = microtime(true);
$runtime_5mins = microtime(true);

$cpu_usage = getrusage()["ru_utime.tv_usec"];

// Read stats.json
$socket = readStatsjson();

// Permanent loop
while($mqtt->proc()) {
	if( time()>=$runtime_5secs+5 ) {
		// Run tasks every 5 seconds
		tasks_5secs();
		$cpu_usage_now = getrusage()["ru_utime.tv_usec"];
		$newruntime=microtime(true);
		
	echo "CPU time: " . round( ($cpu_usage_now-$cpu_usage)/($newruntime-$runtime_5secs)/1000000*100, 2) ." %\n";
		$cpu_usage = $cpu_usage_now;
		$runtime_5secs=$newruntime;
	}
	
	if( time()>=$runtime_5mins+307 ) {
		// Run tasks every 5 minutes
		tasks_5mins();
		$runtime_5mins=microtime(true);
	}
}

$mqtt->close();

function s4llive_mqttmsg ($topic, $msg){
	global $basetopic;
	global $stats;
	global $linequeue;
	global $socket;
	
	$timestamp_epoch = microtime(true);
	$timestamp_nsec = $timestamp_epoch*1000000000;
	echo "Msg Recieved: " . date('r') . "Topic: {$topic}\t$msg\n";
	
	$reltopic = substr( $topic, strlen( $basetopic ) );
	echo "Relative Topic $reltopic\n";
	list( $msno, $uuid, $output ) = explode( "/", $reltopic );
	echo "MS: $msno UUID: $uuid OUTPUT: $output\n";
	
	$id = "${msno}_${uuid}";
	
	// Message validated
	if( property_exists ( $stats, $id ) ) {
		$dest = $stats->$id;
		echo "Name: $dest->name Room: $dest->room\n";
		
		$item = new stdClass();
		$item->line = getLineprot($timestamp_nsec, $msg, $dest, $output);
		$item->timestamp = $timestamp_nsec;
				
		$linequeue[] = $item;
	
		echo "linequeue length before sending: " . count($linequeue) . "\n";
		
		foreach( $linequeue as $linekey => $lineobj) {
			$expectedbytes = strlen($lineobj->line);
			$sentbytes = false;
			if( $socket ) {
				$sentbytes = fwrite( $socket, $lineobj->line );
				if( $sentbytes != false && $sentbytes == $expectedbytes ) {
					unset( $linequeue[$linekey] );
				}
				else { 
					echo "ERROR sending line: Sent: $sentbytes Expected: $expectedbytes\n";
				}
			}
		}
	}
	
	// UNKNOWN Message
	else {
		echo "UNKNOWN $msno/$uuid\n";
	}
	
	unset($uidata["$reltopic"]);
	$uirecord = array(
		"timestamp_epoch" => $timestamp_epoch,
		"topic_full" => $topic,
		"topic_rel" => $reltopic,
		"msno" => $msno,
		"uuid" => $uuid,
		"output" => $output,
		"value" => $value,
		"stat_found" => isset( $dest ) ? true : false,
	);
	$uidata["$reltopic"] = $uirecord;
	$uidata_update = true;

}

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



function tasks_5secs() {
	global $socket;
	global $uidata_update;
	
	echo "tasks_5secs\n";
	readStatsjson(); // (but possibly by inotify)
	if( !$socket ) {
		$socket = openUnixSocket();
	}
	if( $uidata_update ) {
		writeInfoForUI();
		$uidata_update = false;
	}

}

function tasks_5mins() {
	global $linequeue;
	
	echo "tasks_5mins\n";
	// get_miniservers (but possibly by inotify)
	
	$queue_size = count($linequeue);
	echo "Cleanup: Current linequeue length: $queue_size\n";
		
	// Cleanup queue if queue is too big
	if( $queue_size > 5000 ) {
		usort($linequeue, function($a, $b) {
			return $a->timestamp < $b->timestamp ? -1 : 1; });
		
		$linequeue = array_slice($linequeue, 0, 5000);
	}
}



function readStatsjson() {
	global $stats;
	$statscfg = json_decode( file_get_contents( LBPCONFIGDIR . "/stats.json" ) );
	// Convert Loxone array to list of objects
	$stats = new stdClass();
	if( !$statscfg ) {
		return;
	}
	
	//	"loxone" is an unindexed array in stats.json.
	//	To directly access the element, create an object list with key $msno_$uuid
	
	foreach($statscfg->loxone as $cfg) {
        $msno = $cfg->msno;
		$uuid = $cfg->uuid;
		$stats->{"${msno}_${uuid}"} = $cfg;
		
    }

	// print_r( $stats );

}
	
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

function writeInfoForUI() {

	// tbi
	
}
