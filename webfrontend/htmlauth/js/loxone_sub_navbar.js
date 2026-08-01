// Sub navigation of the "Loxone and Import" tab.
//
// MQTT Live used to be the third entry here and has moved to "Data Sources".
$(function() {

	var navbarHtml = `
	<div data-role="navbar" class="ui-navbar" role="navigation" id="s4l_sub_nav">
		<ul class="ui-grid-a">
			<li class="ui-block-a"><a href="loxone.cgi" id="submenu1" class="ui-link ui-btn">${$('#lang_sub_statistic_selection').text()}</a></li>
			<li class="ui-block-b"><a href="loxone_import_report.cgi" id="submenu2" class="ui-link ui-btn">${$('#lang_sub_import_report').text()}</a></li>
		</ul>
	</div>
	`;

	$("#page_content").before(navbarHtml);

	if( window.location.pathname.lastIndexOf("loxone.cgi") != -1 ) {
		$("#submenu1").addClass("ui-btn-active");
	}
	else if( window.location.pathname.lastIndexOf("loxone_import_report.cgi") != -1 ) {
		$("#submenu2").addClass("ui-btn-active");
	}

});
