$(function() {
	
	setInterval(function(){ servicestatus(); }, 5000);
	servicestatus();

});

// State
function servicestatus(update) {

	if (update) {
		$("#telegraf_status").attr("style", "background:#dfdfdf").html($('#lang_status_updating').text());
		$("#influx_status").attr("style", "background:#dfdfdf").html($('#lang_status_updating').text());
		$("#grafana-server_status").attr("style", "background:#dfdfdf").html($('#lang_status_updating').text());
		$("#mqttlive_status").attr("style", "background:#dfdfdf").html($('#lang_status_updating').text());
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
		$("#telegraf_status").attr("style", "background:#dfdfdf; color:red").html($('#lang_status_failed').text());
		$("#influx_status").attr("style", "background:#dfdfdf; color:red").html($('#lang_status_failed').text());
		$("#grafana-server_status").attr("style", "background:#dfdfdf; color:red").html($('#lang_status_failed').text());
		$("#mqttlive_status").attr("style", "background:#dfdfdf; color:red").html($('#lang_status_failed').text());
	})
	.done(function( data ) {
		console.log( "Servicestatus Success", data );
		if (data.telegraf) {
			$("#telegraf_status").attr("style", "background:#32DE00; color:black").html($('#lang_status_running').text().replace('__PID__', data.telegraf));
		} else {
			$("#telegraf_status").attr("style", "background:#FF6339; color:black").html($('#lang_status_stopped').text());
		}
		if (data.influx) {
			$("#influx_status").attr("style", "background:#32DE00; color:black").html($('#lang_status_running').text().replace('__PID__', data.influx));
		} else {
			$("#influx_status").attr("style", "background:#FF6339; color:black").html($('#lang_status_stopped').text());
		}
		if (data.grafanaserver) {
			$("#grafana-server_status").attr("style", "background:#32DE00; color:black").html($('#lang_status_running').text().replace('__PID__', data.grafanaserver));
		} else {
			$("#grafana-server_status").attr("style", "background:#FF6339; color:black").html($('#lang_status_stopped').text());
		}
		if (data.mqttlive == 'disabled') {
			$("#mqttlive_status").attr("style", "background:#ffff00; color:black").html($('#lang_status_disabled').text());
		} else if (data.mqttlive) {
			$("#mqttlive_status").attr("style", "background:#32DE00; color:black").html($('#lang_status_running').text().replace('__PID__', data.mqttlive));
		} else {
			$("#mqttlive_status").attr("style", "background:#FF6339; color:black").html($('#lang_status_stopped').text());
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

	$("#" + service + "_hint").attr("style", "color:blue").html($('#lang_status_executing').text());
	$.ajax( { 
			url:  'ajax.cgi',
			type: 'POST',
			data: { 
				action: command
			}
		} )
	.fail(function( data ) {
		console.log( "Service " + command + " Fail", data );
		$("#" + service + "_hint").attr("style", "color:red").html($('#lang_status_failed').text() + ": " + data.statusText);
	})
	.done(function( data ) {
		console.log( "Service " + command + " Success", data );
		$("#" + service + "_hint").attr("style", "color:green").html("OK");
	})
	.always(function( data ) {
		if (data != 0) {
			$("#" + service + "_hint").attr("style", "color:red").html($('#lang_status_error').text());
		}
		console.log( "Service " + command + " Finished", data );
		servicestatus(1);
	});
}
