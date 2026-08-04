// Sub navigation of the "System" tab.
$(function() {

	var navbarHtml = `
	<div data-role="navbar" class="ui-navbar" role="navigation" id="s4l_sub_nav">
		<ul class="ui-grid-a">
			<li class="ui-block-a"><a href="system.cgi" id="submenu1" class="ui-link ui-btn">${$('#lang_sub_system_settings').text()}</a></li>
			<li class="ui-block-b"><a href="backup.cgi" id="submenu2" class="ui-link ui-btn">${$('#lang_sub_system_backup').text()}</a></li>
		</ul>
	</div>
	`;

	$("#page_content").before(navbarHtml);

	if( window.location.pathname.lastIndexOf("system.cgi") != -1 ) {
		$("#submenu1").addClass("ui-btn-active");
	}
	else if( window.location.pathname.lastIndexOf("backup.cgi") != -1 ) {
		$("#submenu2").addClass("ui-btn-active");
	}

});
