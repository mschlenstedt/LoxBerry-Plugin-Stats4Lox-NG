$(function() {
	
	navbarHtml = "";
	navbarHtml += `
	<div data-role="navbar" class="ui-navbar" role="navigation" id="s4l_sub_nav">
		<ul class="ui-grid-d">
			<li class="ui-block-a"><a href="main_loxone.cgi" id="submenu1" class="ui-link ui-btn">Statistic Selection</a></li>
			<li class="ui-block-b"><a href="loxone_import_report.cgi" id="submenu2" class="ui-link ui-btn">Import Report</a></li>
			<li class="ui-block-c"><a href="mqttlive_loxone.cgi" id="submenu3" class="ui-link ui-btn">MQTT Live</a></li>
		</ul>
	</div>
	`;
	
	// $(`[data-role="header"]`).after(navbarHtml);
	$("[data-role=navbar]").after(navbarHtml);
	console.log("window.location.pathname", window.location.pathname)
	if( window.location.pathname.lastIndexOf("main_loxone.cgi") != -1 ) {
		console.log("submenu1");
		$("#submenu1").addClass("ui-btn-active");
	}
	else if (window.location.pathname.lastIndexOf("loxone_import_report.cgi") != -1 ) {
		console.log("submenu2");
		$("#submenu2").addClass("ui-btn-active");
	}
	else if (window.location.pathname.lastIndexOf("mqttlive_loxone.cgi") != -1 ) {
		console.log("submenu3");
		$("#submenu3").addClass("ui-btn-active");
	}

});
