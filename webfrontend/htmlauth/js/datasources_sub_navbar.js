// Sub navigation of the "Data Sources" tab.
//
// The first two entries used to live elsewhere: the MQTT Collector below "Inputs
// / Outputs", MQTT Live below "Loxone and Import". They belong together - all
// four are sources the plugin reads data from, and neither the Miniserver's own
// vital signs nor a LoxBerry's are a Loxone block.
$(function() {

	var navbarHtml = `
	<div data-role="navbar" class="ui-navbar" role="navigation" id="s4l_sub_nav">
		<ul class="ui-grid-c">
			<li class="ui-block-a"><a href="mqttcollector.cgi" id="submenu1" class="ui-link ui-btn">${$('#lang_sub_mqtt_collector').text()}</a></li>
			<li class="ui-block-b"><a href="mqttlive_loxone.cgi" id="submenu2" class="ui-link ui-btn">${$('#lang_sub_mqtt_live').text()}</a></li>
			<li class="ui-block-c"><a href="miniserver.cgi" id="submenu3" class="ui-link ui-btn">${$('#lang_sub_miniserver').text()}</a></li>
			<li class="ui-block-d"><a href="loxberry.cgi" id="submenu4" class="ui-link ui-btn">${$('#lang_sub_loxberry').text()}</a></li>
		</ul>
	</div>
	`;

	$("#page_content").before(navbarHtml);

	if( window.location.pathname.lastIndexOf("mqttcollector.cgi") != -1 ) {
		$("#submenu1").addClass("ui-btn-active");
	}
	else if( window.location.pathname.lastIndexOf("mqttlive_loxone.cgi") != -1 ) {
		$("#submenu2").addClass("ui-btn-active");
	}
	else if( window.location.pathname.lastIndexOf("miniserver.cgi") != -1 ) {
		$("#submenu3").addClass("ui-btn-active");
	}
	else if( window.location.pathname.lastIndexOf("loxberry.cgi") != -1 ) {
		$("#submenu4").addClass("ui-btn-active");
	}

});
