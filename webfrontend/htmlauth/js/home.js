$(function() {
	
	setInterval(function(){ servicestatus(); }, 5000);
	servicestatus();

});

// State
function servicestatus(update) {

	if (update) {
		$("#telegraf_status").attr("style", "background:#dfdfdf").html("Updating...");
		$("#influx_status").attr("style", "background:#dfdfdf").html("Updating...");
		$("#grafana-server_status").attr("style", "background:#dfdfdf").html("Updating...");
		$("#mqttlive_status").attr("style", "background:#dfdfdf").html("Updating...");
	}

	$.ajax( { 
			url:  'ajax.cgi',
			type: 'POST',
			data: { 
				action: 'servicestatus'
			}
		} )
	.fail(function( data ) {
		console.log( "Servicestatus Fail", data );
		$("#telegraf_status").attr("style", "background:#dfdfdf; color:red").html("Failed");
		$("#influx_status").attr("style", "background:#dfdfdf; color:red").html("Failed");
		$("#grafana-server_status").attr("style", "background:#dfdfdf; color:red").html("Failed");
		$("#mqttlive_status").attr("style", "background:#dfdfdf; color:red").html("Failed");
	})
	.done(function( data ) {
		console.log( "Servicestatus Success", data );
		if (data.telegraf) {
			$("#telegraf_status").attr("style", "background:#32DE00; color:black").html("Running (PID " + data.telegraf + ")");
		} else {
			$("#telegraf_status").attr("style", "background:#FF6339; color:black").html("Stopped");
		}
		if (data.influx) {
			$("#influx_status").attr("style", "background:#32DE00; color:black").html("Running (PID " + data.influx + ")");
		} else {
			$("#influx_status").attr("style", "background:#FF6339; color:black").html("Stopped");
		}
		if (data.grafanaserver) {
			$("#grafana-server_status").attr("style", "background:#32DE00; color:black").html("Running (PID " + data.grafanaserver + ")");
		} else {
			$("#grafana-server_status").attr("style", "background:#FF6339; color:black").html("Stopped");
		}
		if (data.mqttlive == 'disabled') {
			$("#mqttlive_status").attr("style", "background:#ffff00; color:black").html("Disabled by config");
		} else if (data.mqttlive) {
			$("#mqttlive_status").attr("style", "background:#32DE00; color:black").html("Running (PID " + data.mqttlive + ")");
		} else {
			$("#mqttlive_status").attr("style", "background:#FF6339; color:black").html("Stopped");
		}
	})
	.always(function( data ) {
		console.log( "Servicestatus Finished", data );
	});
}

// Start / Stop Services
function service(command) {
	var service;

	if ( command == "starttelegraf" || command == "stoptelegraf" ) {
		service = "telegraf";
	}
	if ( command == "startinfluxdb" || command == "stopinfluxdb" ) {
		service = "influx";
	}
	if ( command == "startgrafana-server" || command == "stopgrafana-server" ) {
		service = "grafana-server";
	}
	if ( command == "startmqttlive" || command == "stopmqttlive" ) {
		service = "mqttlive";
	}

	$("#" + service + "_hint").attr("style", "color:blue").html("Executing...");
	$.ajax( { 
			url:  'ajax.cgi',
			type: 'POST',
			data: { 
				action: command
			}
		} )
	.fail(function( data ) {
		console.log( "Service " + command + " Fail", data );
		$("#" + service + "_hint").attr("style", "color:red").html("Failed: "+data.statusText);
	})
	.done(function( data ) {
		console.log( "Service " + command + " Success", data );
		$("#" + service + "_hint").attr("style", "color:green").html("OK");
	})
	.always(function( data ) {
		if (data != 0) {
			$("#" + service + "_hint").attr("style", "color:red").html("Error");
		}
		console.log( "Service " + command + " Finished", data );
		servicestatus(1);
	});
}
