// Sub navigation of the "Data Sources" tab.
//
// Both entries used to live elsewhere: the MQTT Collector below "Inputs /
// Outputs", MQTT Live below "Loxone and Import". They belong together - both
// are sources the plugin reads data from.
$(function() {

	var navbarHtml = `
	<div data-role="navbar" class="ui-navbar" role="navigation" id="s4l_sub_nav">
		<ul class="ui-grid-a">
			<li class="ui-block-a"><a href="input_mqtt.cgi" id="submenu1" class="ui-link ui-btn">${$('#lang_sub_mqtt_collector').text()}</a></li>
			<li class="ui-block-b"><a href="mqttlive_loxone.cgi" id="submenu2" class="ui-link ui-btn">${$('#lang_sub_mqtt_live').text()}</a></li>
		</ul>
	</div>
	`;

	$("#page_content").before(navbarHtml);

	if( window.location.pathname.lastIndexOf("input_mqtt.cgi") != -1 ) {
		$("#submenu1").addClass("ui-btn-active");
	}
	else if( window.location.pathname.lastIndexOf("mqttlive_loxone.cgi") != -1 ) {
		$("#submenu2").addClass("ui-btn-active");
	}

});
