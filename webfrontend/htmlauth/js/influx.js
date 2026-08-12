// The InfluxDB page: what is actually stored in the database.
//
// Loaded in three stages, because the queries differ in cost by two orders of
// magnitude. Measured on 134 measurements: the overview takes 0.4 s, the
// timestamps 4.5 s and counting the values 23.5 s. So the table appears at
// once, the timestamps drop in a moment later, and the values are only counted
// when someone asks for them.

let measurements = [];          // one entry per measurement
let byName = {};                // name -> entry, for the updates that follow
let filters = { status: "all", source: "all", search: "" };

// Yellow background and clear button follow the content of the search field.
//
// jQuery Mobile shows and hides its clear button by toggling
// ui-input-clear-hidden, and it only does that from its own key handlers. A
// value that arrives any other way - restored by the browser after a reload,
// set from code - leaves the button hidden although the field is full. The
// Loxone page has the same function for the same reason.
function syncSearchDecorations() {

	var field = $('#filter_search');
	if( !field.length ) return;
	var filled = field.val() !== "";

	field.toggleClass( 'filter-highlight', filled );
	field.parent().find('.ui-input-clear').toggleClass( 'ui-input-clear-hidden', !filled );
}
let tableSort = { key: "name", dir: 1 };
let dropTarget = null;

$(function() {

	$('.filter_radio, .filter_select').on( "change", function(event){
		var name = event.currentTarget.name;
		var val;
		if( event.currentTarget.nodeName == "INPUT" ) {
			val = $("input[name='"+name+"']:checked").val();
		} else {
			val = $("#"+name+" option:selected").val();
			if( val != "all" ) $(event.currentTarget.parentNode).addClass('filter-highlight');
			else               $(event.currentTarget.parentNode).removeClass('filter-highlight');
		}
		if( name == "filter_status" ) filters.status = val;
		if( name == "filter_source" ) filters.source = val;
		updateTable();
	});

	// Marked yellow while a search is active, the same way the Loxone page does
	// it - otherwise a filter left in place explains a half empty table badly.
	//
	// Bound to input AND change: the clear button jQuery Mobile puts inside the
	// field does not fire input, only change. With input alone the field went
	// empty while the filter and the yellow background stayed - the Loxone page
	// has a second handler for exactly this.
	// The decorations follow every keystroke, the table does not.
	//
	// updateTable filters, sorts and rebuilds every row - 160 measurements on
	// the test installation, with a localeCompare per comparison. Running that
	// on every character made the tab stop responding while typing. The Loxone
	// page has waited half a second for the same reason since it was written;
	// this one never did.
	//
	// The yellow background and the clear button stay immediate: they are two
	// class toggles, and a search field that reacts late feels broken.
	let searchDelay;
	function searchChanged() {
		filters.search = $("#filter_search").val().toLowerCase();
		syncSearchDecorations();
		window.clearTimeout( searchDelay );
		searchDelay = window.setTimeout( updateTable, 500 );
	}
	$("#filter_search").on( "input change", searchChanged );

	// The field can be filled without anyone typing: the browser puts the last
	// search back when the page is reloaded. That leaves both decorations
	// behind, so they are set once on load - after jQuery Mobile has built the
	// clear button, which is the thing being addressed.
	$(window).on( "load", function() { searchChanged(); } );

	// Every dropdown and radio filter back to "all" in one go - see the Loxone
	// page, which has the same button. The search field keeps its content: it is
	// the one filter the user typed themselves.
	jQuery(document).on('click', '#btnResetFilters', function(event){
		event.preventDefault();

		$('input.filter_radio[value="all"]').prop('checked', true);
		try { $('input.filter_radio').checkboxradio('refresh'); } catch(e) {}

		$('select.filter_select').each( function() {
			try { $(this).val('all').selectmenu('refresh'); } catch(e) { $(this).val('all'); }
			$(this).parent().removeClass('filter-highlight');
			$(this).closest('.ui-btn').removeClass('filter-highlight');
		});

		filters.status = "all";
		filters.source = "all";
		updateTable();
	});

	jQuery(document).on('click', '.influxtable th.s4l-sortable', function(){
		var key = $(this).data("sortkey");
		if( !key ) return;
		if( tableSort.key == key ) tableSort.dir = -tableSort.dir;
		else { tableSort.key = key; tableSort.dir = 1; }
		updateTable();
	});

	jQuery(document).on('click', '.btnDropMeasurement', function(event){
		event.preventDefault();
		askDrop( $(this).closest('tr').data("name") );
	});

	jQuery(document).on('click', '.btnCountOne', function(event){
		event.preventDefault();
		countOne( $(this).closest('tr').data("name") );
	});

	jQuery(document).on('click', '#drop_only', function(event){
		event.preventDefault();
		doDrop( false );
	});
	jQuery(document).on('click', '#drop_and_off', function(event){
		event.preventDefault();
		doDrop( true );
	});

	load();
});

function escHtml( s ) {
	return $('<div>').text( s === undefined || s === null ? '' : s ).html();
}
function escAttr( s ) {
	return escHtml(s).replace( /"/g, '&quot;' );
}

// --- stage 1: the overview -------------------------------------------------

function load() {
	$.post( "ajax.cgi", { action: "influx_overview" } )
	.fail( function( data ) {
		console.log( "influx_overview failed", data );
		$('#influxtablediv').html( "<p>" + escHtml($('#lang_error_generic').text()) + "</p>" );
	} )
	.done( function( data ) {
		if( !data || !data.measurements ) {
			$('#influxtablediv').html( "<p>" + escHtml($('#lang_error_generic').text()) + "</p>" );
			return;
		}
		measurements = data.measurements;
		byName = {};
		$.each( measurements, function( i, m ) { byName[m.name] = m; } );

		fillSourceFilter();
		updateTable();
		loadTimestamps();
	} );
}

// The origins that actually occur, so the filter offers nothing empty.
function fillSourceFilter() {
	var seen = {};
	$.each( measurements, function( i, m ) {
		$.each( m.sources || [], function( j, s ) { seen[s] = true; } );
	} );
	var sel = $('#filter_source');
	$.each( Object.keys(seen).sort(), function( i, s ) {
		sel.append( '<option value="' + escAttr(s) + '">' + escHtml(s) + '</option>' );
	} );
	if( sel.selectmenu ) { try { sel.selectmenu("refresh"); } catch(e) {} }
}

// --- stage 2: first and last timestamp -------------------------------------

function loadTimestamps() {
	$.post( "ajax.cgi", { action: "influx_timestamps" } )
	.fail( function( data ) { console.log( "influx_timestamps failed", data ); } )
	.done( function( data ) {
		if( !data || !data.timestamps ) return;
		$.each( data.timestamps, function( name, ts ) {
			if( byName[name] ) {
				byName[name].first = ts.first;
				byName[name].last  = ts.last;
			}
		} );
		updateTable();
	} );
}

// --- stage 3: counting values ----------------------------------------------

function countAll() {
	$('#btncountall').addClass('ui-disabled');
	$.each( measurements, function( i, m ) { if( m.count === undefined ) m.counting = true; } );
	updateTable();
	$.post( "ajax.cgi", { action: "influx_count" } )
	.always( function() { $('#btncountall').removeClass('ui-disabled'); } )
	.fail( function( data ) {
		console.log( "influx_count failed", data );
		$.each( measurements, function( i, m ) { m.counting = false; } );
		updateTable();
	} )
	.done( function( data ) {
		$.each( measurements, function( i, m ) { m.counting = false; } );
		if( data && data.counts ) {
			$.each( data.counts, function( name, c ) { if( byName[name] ) byName[name].count = c; } );
		}
		updateTable();
	} );
}

function countOne( name ) {
	if( !byName[name] ) return;
	byName[name].counting = true;
	updateTable();
	$.post( "ajax.cgi", { action: "influx_count", name: name } )
	.always( function() { if( byName[name] ) byName[name].counting = false; } )
	.fail( function( data ) { console.log( "influx_count failed", data ); updateTable(); } )
	.done( function( data ) {
		if( data && data.counts && data.counts[name] !== undefined ) byName[name].count = data.counts[name];
		updateTable();
	} );
}

// --- deleting --------------------------------------------------------------

function askDrop( name ) {
	var m = byName[name];
	if( !m ) return;
	dropTarget = name;
	$('#drop_what').html( escHtml( $('#lang_confirm_drop').text().replace( '__NAME__', name ) ) );
	$('#drop_hint').html("&nbsp;");

	// An active statistic would have the grabber recreate the measurement
	// within a minute, so that case offers the combined action instead.
	if( m.active ) {
		$('#drop_activewarn').show();
		$('#drop_only').hide();
		$('#drop_and_off').show().removeClass('ui-disabled');
	} else {
		$('#drop_activewarn').hide();
		$('#drop_and_off').hide();
		$('#drop_only').show().removeClass('ui-disabled');
	}
	$('#popupDrop').popup("option","positionTo","window");
	$('#popupDrop').popup("open");
}

function doDrop( deactivate ) {
	if( !dropTarget ) return;
	$('#drop_only, #drop_and_off').addClass('ui-disabled');
	$('#drop_hint').attr("style","").html( $('#lang_counting').text() );
	$.post( "ajax.cgi", {
		action: "influx_drop",
		name: dropTarget,
		deactivate: deactivate ? "true" : "false"
	} )
	.fail( function( data ) {
		console.log( "influx_drop failed", data );
		$('#drop_hint').attr("style","color:red").html( $('#lang_hint_drop_fail').text() );
		$('#drop_only, #drop_and_off').removeClass('ui-disabled');
	} )
	.done( function( data ) {
		if( !data || !data.dropped ) {
			$('#drop_hint').attr("style","color:red").html( $('#lang_hint_drop_fail').text() );
			$('#drop_only, #drop_and_off').removeClass('ui-disabled');
			return;
		}
		measurements = measurements.filter( function( m ) { return m.name !== dropTarget; } );
		delete byName[dropTarget];
		$('#drop_hint').attr("style","color:green").html( $('#lang_hint_drop_done').text() );
		updateTable();
		window.setTimeout( function() { $('#popupDrop').popup("close"); }, 1200 );
	} );
}

// --- the table -------------------------------------------------------------

// The state of a measurement, using the same wording and the same symbols as
// the Loxone page - a red cross means the same thing on both, otherwise the two
// pages would contradict each other.
//
//   ok         green tick    statistic exists and is running, no error
//   404        red cross     statistic has the grabber's 404 status
//   limit      yellow        statistic has the grabber's time limit status
//   off        grey "Off"    statistic exists but is switched off
//   orphaned   red cross     no statistic, and the block is not in the LoxPLAN
//   blockleft  yellow        no statistic, but the block still exists
//   system     green tick    stats_miniserver / stats_loxberry, written by us
//   mqtt       green tick    comes from the MQTT collector
//   unknown    grey "?"      none of the above - origin cannot be determined
function statusOf( m ) {
	if( m.configured ) {
		if( m.error === "404" )   return "404";
		if( m.error )             return "limit";
		return m.active ? "ok" : "off";
	}
	// No entry in stats.json. What it is depends on where it came from.
	if( m.system ) return "system";
	if( ( m.sources || [] ).indexOf("mqtt") > -1 ) return "mqtt";
	if( ( m.sources || [] ).indexOf("grabber") > -1 && m.hasuuid ) {
		return m.inplan ? "blockleft" : "orphaned";
	}
	return "unknown";
}

// Which symbol a state gets. Three of them share the green tick: a running
// statistic, our own system measurements and the MQTT collector are all simply
// in order.
var STATUS_ICON = {
	ok:        { kind: "ok" },
	system:    { kind: "ok" },
	mqtt:      { kind: "ok" },
	limit:     { kind: "warn" },
	blockleft: { kind: "warn" },
	"404":     { kind: "err" },
	orphaned:  { kind: "err" },
	off:       { kind: "label", text: "Off" },
	unknown:   { kind: "label", text: "?" }
};

// For the filter: which of the four buttons a state belongs to.
function statusColour( m ) {
	var k = STATUS_ICON[ statusOf(m) ].kind;
	return ( k == "label" ) ? "grey" : ( k == "off" ? "grey" : k );
}

function statusCell( m ) {
	var s = statusOf( m );
	var def = STATUS_ICON[s];
	var label = $('#lang_status_' + s).text();
	var hover = $('#lang_hover_' + s).text();
	var inner = ( def.kind == "label" )
		? '<span class="s4l-icon s4l-icon-label">' + escHtml(def.text) + '</span>'
		: '<span class="s4l-icon s4l-icon-' + def.kind + '"></span>';
	return '<td class="center" title="' + escAttr( label + " - " + hover ) + '">' + inner + '</td>';
}

function fmtTime( ns ) {
	if( ns === undefined ) return '<span class="grayed">' + escHtml($('#lang_loading_timestamps').text()) + '</span>';
	if( !ns ) return '<span class="grayed">-</span>';
	return escHtml( new Date( Number(ns) / 1e6 ).toLocaleString() );
}

function fmtCount( m ) {
	if( m.counting ) return '<span class="grayed">' + escHtml($('#lang_counting').text()) + '</span>';
	if( m.count === undefined ) {
		return '<a href="#" class="s4l-tbtn s4l-tbtn-count btnCountOne" title="'
		     + escAttr($('#lang_hover_count_one').text()) + '"></a>';
	}
	return escHtml( Number(m.count).toLocaleString() );
}

function matchesFilter( m ) {
	// The filter works on the symbol, not on the state: several states share a
	// symbol, and someone clicking the red cross wants everything that is red.
	if( filters.status != "all" && statusColour(m) != filters.status ) return false;
	if( filters.source != "all" && ( m.sources || [] ).indexOf( filters.source ) == -1 ) return false;
	if( filters.search != "" && m.name.toLowerCase().indexOf( filters.search ) == -1 ) return false;
	return true;
}

function sortValue( m, key ) {
	if( key == "name" )   return m.name.toLowerCase();
	if( key == "source" ) return ( m.sources || [] ).join(",");
	// Sorted by severity, so one click brings whatever needs attention up top.
	if( key == "status" ) return {
		ok: 0, system: 0, mqtt: 0,
		off: 1, unknown: 2,
		limit: 3, blockleft: 4,
		orphaned: 5, "404": 6
	}[ statusOf(m) ];
	if( key == "fields" ) return ( m.fields || [] ).length;
	if( key == "first" )  return Number( m.first ) || 0;
	if( key == "last" )   return Number( m.last )  || 0;
	if( key == "count" )  return ( m.count === undefined ) ? -1 : Number( m.count );
	return "";
}

function updateTable() {

	var rows = measurements.filter( matchesFilter );
	rows.sort( function( a, b ) {
		var va = sortValue( a, tableSort.key );
		var vb = sortValue( b, tableSort.key );
		var r;
		if( typeof va === "number" && typeof vb === "number" ) r = va - vb;
		else r = String(va).localeCompare( String(vb), undefined, { numeric:true, sensitivity:"base" } );
		if( r === 0 ) return a.name.toLowerCase().localeCompare( b.name.toLowerCase() );
		return r * tableSort.dir;
	} );

	function th( key, cls, label ) {
		var arrow = ( tableSort.key == key ) ? ( tableSort.dir > 0 ? "&#8593;" : "&#8595;" ) : "&#8597;";
		var active = ( tableSort.key == key ) ? " sortactive" : "";
		return '<th class="' + cls + ' s4l-sortable' + active + '" data-sortkey="' + key + '">'
		     + escHtml(label) + '<span class="sortarrow">' + arrow + '</span></th>';
	}

	if( !measurements.length ) {
		$('#influxtablediv').html( "<p>" + escHtml($('#lang_hint_no_measurements').text()) + "</p>" );
		$('#influx_summary').html("&nbsp;");
		return;
	}

	var html = '<table class="influxtable"><thead><tr>'
	   + th( "name",   "col-name",   $('#lang_th_measurement').text() )
	   + th( "source", "col-source", $('#lang_th_source').text() )
	   + th( "status", "col-status", $('#lang_th_status').text() )
	   + th( "fields", "col-fields", $('#lang_th_fields').text() )
	   + th( "first",  "col-first",  $('#lang_th_first').text() )
	   + th( "last",   "col-last",   $('#lang_th_last').text() )
	   + th( "count",  "col-count",  $('#lang_th_count').text() )
	   + '<th class="col-btn">' + escHtml($('#lang_th_actions').text()) + '</th>'
	   + '</tr></thead><tbody>';

	$.each( rows, function( i, m ) {
		var fields = m.fields || [];
		html += '<tr class="influxtable_tr" data-name="' + escAttr(m.name) + '">'
		     +  '<td>' + escHtml(m.name)
		     +  ( m.blockname && m.blockname != m.name
		          ? '<br><span class="small grayed">' + escHtml(m.blockname) + '</span>' : '' )
		     +  '</td>'
		     +  '<td class="small center">' + escHtml( ( m.sources || [] ).join(", ") ) + '</td>'
		     +  statusCell( m )
		     +  '<td class="small center" title="' + escAttr( fields.join(", ") ) + '">'
		     +  escHtml( fields.join(", ") ) + '</td>'
		     +  '<td class="small center">' + fmtTime( m.first ) + '</td>'
		     +  '<td class="small center">' + fmtTime( m.last ) + '</td>'
		     +  '<td class="small center">' + fmtCount( m ) + '</td>'
		     +  '<td class="actionbuttons">'
		     +  '<a href="#" class="s4l-tbtn s4l-tbtn-danger s4l-tbtn-cross btnDropMeasurement" title="'
		     +  escAttr($('#lang_hover_button_drop').text()) + '"></a>'
		     +  '</td></tr>';
	} );
	html += '</tbody></table>';

	$('#influxtablediv').html( html );

	// Summary by symbol, the same grouping the filter uses.
	var counts = { ok:0, warn:0, err:0, grey:0 };
	$.each( measurements, function( i, m ) { counts[ statusColour(m) ]++; } );
	$('#influx_summary').text(
		$('#lang_hint_summary').text()
			.replace( '__TOTAL__', measurements.length )
			.replace( '__OK__', counts.ok )
			.replace( '__WARN__', counts.warn )
			.replace( '__ERR__', counts.err )
			.replace( '__GREY__', counts.grey ) );
}
