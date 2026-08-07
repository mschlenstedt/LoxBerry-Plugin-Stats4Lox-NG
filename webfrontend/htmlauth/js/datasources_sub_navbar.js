// Sub navigation of the "Data Sources" tab.
//
// The first two entries used to live elsewhere: the MQTT Collector below "Inputs
// / Outputs", MQTT Live below "Loxone and Import". They belong together - all
// three are sources the plugin reads data from, and the Miniserver's own vital
// signs are one of them: they come from the Miniserver, not from a Loxone block.
$(function() {

	var navbarHtml = `
	<div data-role="navbar" class="ui-navbar" role="navigation" id="s4l_sub_nav">
		<ul class="ui-grid-b">
			<li class="ui-block-a"><a href="data_inputs.cgi" id="submenu1" class="ui-link ui-btn">${$('#lang_sub_mqtt_collector').text()}</a></li>
			<li class="ui-block-b"><a href="mqttlive_loxone.cgi" id="submenu2" class="ui-link ui-btn">${$('#lang_sub_mqtt_live').text()}</a></li>
			<li class="ui-block-c"><a href="miniserver.cgi" id="submenu3" class="ui-link ui-btn">${$('#lang_sub_miniserver').text()}</a></li>
		</ul>
	</div>
	`;

	$("#page_content").before(navbarHtml);

	if( window.location.pathname.lastIndexOf("data_inputs.cgi") != -1 ) {
		$("#submenu1").addClass("ui-btn-active");
	}
	else if( window.location.pathname.lastIndexOf("mqttlive_loxone.cgi") != -1 ) {
		$("#submenu2").addClass("ui-btn-active");
	}
	else if( window.location.pathname.lastIndexOf("miniserver.cgi") != -1 ) {
		$("#submenu3").addClass("ui-btn-active");
	}

});
