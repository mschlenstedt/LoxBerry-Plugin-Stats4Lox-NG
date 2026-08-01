// Makes the Grafana entry in the main navigation open in a new tab.
//
// Grafana is a separate application on its own port, not a page of this plugin,
// so it should not replace the plugin in the current tab. The LoxBerry navbar
// is rendered by Vue from a JSON structure and has no target attribute, hence
// this small addition.
//
// The navbar is built after the page has loaded, so we wait for the entry to
// appear instead of assuming it is already there.
$(function() {

	function markExternal() {
		var found = false;
		$("a.vuenavbarelement, #s4l_sub_nav a").each(function() {
			var href = $(this).attr("href") || "";
			// Anything pointing at another host or port is not our own page.
			if( /^https?:\/\//i.test(href) && href.indexOf(window.location.host) === -1 ) {
				$(this).attr("target", "_blank").attr("rel", "noopener");
				found = true;
			}
		});
		return found;
	}

	if( markExternal() ) { return; }

	// Give the navbar time to render, but do not keep looking forever.
	var tries = 0;
	var timer = setInterval(function() {
		if( markExternal() || ++tries > 20 ) { clearInterval(timer); }
	}, 250);

});
