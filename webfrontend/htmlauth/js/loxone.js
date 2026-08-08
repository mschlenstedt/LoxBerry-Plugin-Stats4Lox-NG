let miniservers;
let miniservers_used = [];
let rooms;
let rooms_used = [];
let categories;
let categories_used = [];
let controls = [];
let pages;
let pages_used = [];
let statsconfig;
let statsconfigLoxone;
let controlstable = "";
let elementTypes_used = [];
let loxone_elements;

let filters = {};

let hints_hide = {};

let filterSearchDelay;
var filterSearchString = "";

let timer = false;
let timer_interval = 7000;
let getImportSchedulerReport_running = false;

let imports = [];

$(function() {
	
	// debugger;
	restore_hints_hide();
	if(hints_hide?.hint_activatestatistics != true) {
		$("#hint_activatestatistics").show();
	}
	
	miniservers = JSON.parse( $("#miniservers_json").text() );
	loxone_elements = JSON.parse( $("#loxone_elements_json").text() );

	// Where the Loxone configuration comes from has to be known before the
	// configuration is asked for - in manual mode nothing is fetched from the
	// Miniserver, and the upload field decides whether there is anything to read.
	initLoxplanSource();
	
	// Create filter radio and select bindings
	$('.filter_radio, .filter_select').on( "change", function(event, ui){
		var filter_parent = event.currentTarget.name;
		console.log( "filter_select", event, ui );
		
		if( event.currentTarget.nodeName == "INPUT" ) {
			var filterval = $("input[name='"+filter_parent+"']:checked").val();
		}
		if( event.currentTarget.nodeName == "SELECT" ) {
			var filterval = $("#"+filter_parent+" option:selected").val();
			if( filterval != "all" ) 
				$(event.currentTarget.parentNode).addClass('filter-highlight');
			else
				$(event.currentTarget.parentNode).removeClass('filter-highlight');
		}
		
		console.log("Filter parent", filter_parent, filterval);
		filters[filter_parent] = filterval;
		
		// After changing the filter, recreate the table
		saveFilters();
		updateTable();
		updateReportTables();
	});
	
	// Create S4L Stat change bindings (Detail View)
	jQuery(document).on('change focusout keyup','.s4lchange',function (event, ui) {
		console.log( ".s4lchange binding entered");
		if( typeof event.keyCode !== "undefined" && event.keyCode != 13)
			// NOT pressed Enter
			return;
		target = event.target;
		uid = $(target).closest('table').data("uid");
		msno = $(target).closest('table').data("msno");
		var control = controls.find( obj => { return obj.UID === uid && obj.msno == msno })
		var stat = statsconfigLoxone.find(obj => {
			return obj.uuid === control.UID && obj.msno == control.msno })
		// Validations and changes of dependent inputs 
		
		if( target.id == "LoxoneDetails_s4lmeasurementname" ) {
			// s4lmeasurementname MUST be defined
			var measurementname = $("#LoxoneDetails_s4lmeasurementname").val();
			measurementname = validateMeasurementname( measurementname, msno, uid );
			$("#LoxoneDetails_s4lmeasurementname").val( measurementname ).textinput("refresh");
		}
		
		if( target.id == "LoxoneDetails_s4lstatactive" ) {
			// Stats active checkbox was pressed
			console.log( "LoxoneDetails_s4lstatactive pressed", $(target).is(":checked") );
			if( $(target).is(":checked") ) {
				// Activated
				if( ( $("#LoxoneDetails_s4lstatinterval").val() ) == "" ) {
					// Fill a number to the interval
					$("#LoxoneDetails_s4lstatinterval").val("5").textinput("refresh");
				}
				// Activate interval field
				$("#LoxoneDetails_s4lstatinterval").prop( "disabled", false ).textinput("refresh");
				$('[name="LoxoneDetails_s4loutput"]').prop( "disabled", false );
				
				// Enable "Default" setting only when nothing else is activated
				if( !stat ) {
					// This element does not exist in stats.json yet, therefore enable "Default" on activation
					$('[name="LoxoneDetails_s4loutput"][value="Default"').prop( "checked", true );
				}
			} 
			else {
				// Disable interval field and outputs
				$("#LoxoneDetails_s4lstatinterval").prop( "disabled", true ).textinput("refresh");
				$('[name="LoxoneDetails_s4loutput"]').prop( "disabled", true );
			}
			
		}
		else if ( target.id == "LoxoneDetails_s4lstatinterval" ) {
			// Interval was changed
			console.log( "LoxoneDetails_s4lstatinterval changed" );
			var interval = parseInt( $("#LoxoneDetails_s4lstatinterval").val() );
			if ( isNaN( interval ) || interval <= 0 ) {
				// Not a number
				$("#LoxoneDetails_s4lstatinterval").val( "5" ).textinput("refresh");
			}
		}

		// Below the shortest interval the System tab allows.
		//
		// Marked and NOT saved. Saving it would put a value into stats.json that
		// the grabber may not poll with, and the next time the minimum is applied
		// it would silently be raised again - so the field says so instead and
		// waits. Everything else in the popup waits with it: this leaves before
		// the values are collected further down.
		if( !s4lIntervalOk() ) {
			console.log( "interval below the configured minimum - not saved" );
			return;
		}
		else if ( target.name == "LoxoneDetails_s4loutput" ) {
			// Checkboxes of outputs were changed
			console.log( "LoxoneDetails_s4loutput changed" );
		}
		
		// Now collect latest data of inputs 
		
		var stat_active = $("#LoxoneDetails_s4lstatactive").is(":checked") ? "true" : "false";
		var measurementname = $("#LoxoneDetails_s4lmeasurementname").val();
		var stat_interval = parseInt($("#LoxoneDetails_s4lstatinterval").val()) * 60;
		// Collect checkboxes
		var stat_outputs = [];
		$('[name="LoxoneDetails_s4loutput"]:checked').each(function(){
			stat_outputs.push($(this).val());
		});
		var output_labels = [];
		
		
		console.log("stat details data to send", control, stat_active, stat_interval, stat_outputs);

		// Post data
		
		$.post( "ajax.cgi", { 
			action : "updatestat",  
			name : control.Title,
			description :control.Desc,
			uuid : uid,
			msno : msno,
			type : control.Type,
			category : control.Category,
			room: control.Place,
			active: stat_active,
			measurementname: measurementname,
			interval: stat_interval,
			outputs : stat_outputs.join(','),
			outputlabels : control.outputlabels ? control.outputlabels.toString() : "",
			outputkeys : control.outputkeys ? control.outputkeys.toString() : "",
			minval : control.MinVal,
			maxval : control.MaxVal,
			unit : control.Unit
			
		})
		.done(function(data){
			// Find internal key of statistic element
			
			var statkey = statsconfigLoxone.findIndex(obj => {
			return obj.uuid === control.UID && obj.msno == control.msno })
			
			// Enable the Import button if a stats.json entry exists now, and Loxone Stats are active
			if( control.StatsType != 0 ) {
				$("#LoxoneDetails_s4lstatimportbutton")
					.removeClass("ui-disabled");
			}
			
			if( statkey != -1 ) {
				// If element found in internal data
				// Update internal statsconfigLoxone with ajax result
				statsconfigLoxone[statkey] = data;
			}
			else {
				// Not found in internal data - add object to array
				statsconfigLoxone.push( data );
			}
			
			// We should have found the element in the table
			
			updateTable();
			updateReportTables(data);
			
		});
	});
	

	// Bind on Search text box
	$("#filter_search").on( "input", function(event, ui){
		window.clearTimeout(filterSearchDelay); 
		filterSearchString = $(event.target).val();
		filters["filter_search"] = filterSearchString;
		saveFilters();
		// console.log("Text filter", filterSearchString);
		filterSearchDelay = window.setTimeout(function() { updateTable(); updateReportTables(); }, 500);
	});
	$("#filter_search").on( "change", function(event, ui){
		if( $(event.target).val() == "" ) {
			// $('#filter_search').css({'backgroundColor':'white'});
			$('#filter_search').removeClass('filter-highlight');
			$('#filter_search').attr("data-clear-btn", false);
			window.clearTimeout(filterSearchDelay); 
			filterSearchString = $(event.target).val();
			filters["filter_search"] = filterSearchString;
			saveFilters();
			updateTable();
			updateReportTables();
		} else {
			// $('#filter_search').css({'backgroundColor':'#FFFF99'});
			$('#filter_search').addClass('filter-highlight');
			$('#filter_search').attr("data-clear-btn", true);
		}

	});

	// Bind Loxone Details button
	jQuery(document).on('click', '.btnLoxoneDetails', function(event, ui){
		target = event.target;
		uid = $(target).closest('tr').data("uid");
		msno = $(target).closest('tr').data("msno");
		popupLoxoneDetails(uid, msno);
	});
	
	// Bind Delete button (rows and details popup)
	jQuery(document).on('click', '.btnDeleteStat', function(event, ui){
		event.preventDefault();
		var row = $(event.target).closest('tr');
		askDeleteStat( row.data("uid"), row.data("msno") );
	});
	jQuery(document).on('click', '#LoxoneDetails_deletebutton', function(event, ui){
		event.preventDefault();
		var uid = $("#LoxoneDetails_deletebutton").data("uid");
		var msno = $("#LoxoneDetails_deletebutton").data("msno");

		// jQuery Mobile refuses to open a second popup while the first is still
		// closing, so the details popup goes first and the confirmation waits
		// for popupafterclose.
		//
		// The order matters and is what broke this on the first attempt: the
		// handler used to be bound AFTER popup("close"). Without a transition
		// the close finishes immediately, the event has fired by then, and the
		// confirmation never appeared - it worked from the table, where no
		// popup has to close, and only there. Bound first, closed second.
		$("#popupLoxoneDetails").one( "popupafterclose", function() {
			askDeleteStat( uid, msno );
		});
		$("#popupLoxoneDetails").popup("close");

		// And a fallback, should the event not arrive at all.
		window.setTimeout( function() {
			if( $("#popupDeleteStat").parent().hasClass("ui-popup-active") ) return;
			$("#popupLoxoneDetails").off( "popupafterclose" );
			askDeleteStat( uid, msno );
		}, 600 );
	});

	// Sort by column
	jQuery(document).on('click', '.controlstable th.s4l-sortable', function(event){
		var key = $(this).data("sortkey");
		if( !key ) return;
		if( tableSort.key == key ) { tableSort.dir = -tableSort.dir; }
		else                       { tableSort.key = key; tableSort.dir = 1; }
		updateTable();
		updateReportTables();
	});

	// Bind Reset status button
	jQuery(document).on('click', '.btnResetStatus', function(event, ui){
		event.preventDefault();
		var row = $(event.target).closest('tr');
		resetStatStatus( row.data("uid"), row.data("msno") );
	});

	// Delete popup buttons. Closing is the cross in the top right corner, the
	// same one the details popup uses - jQuery Mobile builds it from
	// data-rel="back".
	jQuery(document).on('click', '#deleteStat_keep', function(event){
		event.preventDefault();
		deleteStat( false );
	});
	jQuery(document).on('click', '#deleteStat_drop', function(event){
		event.preventDefault();
		deleteStat( true );
	});

	// Bind Import Now button
	jQuery(document).on('click', '#LoxoneDetails_s4lstatimportbutton', function(event, ui){
		target = event.target;
		uid = $(target).data("uid");
		msno = $(target).data("msno");
		scheduleImport(msno, uid);
	});
	
});

// Looks up the description of an output of a block.
//
// Loxone describes outputs that exist several times with a printf pattern,
// e.g. "Q%d" for the sources of the Energiemanager or "A%d" for an alarm
// chain. A literal key lookup never matches the actual labels Q1, Q2, ...,
// which is why those blocks showed no descriptions at all. So after the
// direct hit fails, the pattern keys are tried as well.
function lookupOutputDescription( type, outputName ) {
	if( !type || !outputName ) return undefined;
	var element = loxone_elements[ type.toUpperCase() ];
	if( !element || !element.OL ) return undefined;

	// exact match first - the normal case and cheapest
	if( element.OL[outputName] != undefined ) return element.OL[outputName];

	for( var key in element.OL ) {
		if( key.indexOf('%') < 0 ) continue;
		// %d -> digits, %e and any other %x -> a short token
		var rx = '^' + key.replace( /[.*+?^${}()|[\]\\]/g, '\\$&' )
		                  .replace( /%d/g, '(\\d+)' )
		                  .replace( /%[a-z]/g, '([A-Za-z0-9]+)' ) + '$';
		try {
			if( new RegExp(rx).test(outputName) ) return element.OL[key];
		} catch(e) { /* malformed pattern - ignore */ }
	}
	return undefined;
}

function getLoxplan() {
	$("#popupProgress").popup("open");
	var msupdateTextPre = $('#lang_fetching_config').text();
	$("#progressState").html(msupdateTextPre);
	
	// Get elements of all Miniservers
	var async_request=[];
	var responses=[];

	// Every request is wrapped in a Deferred that ALWAYS resolves.
	//
	// $.when() rejects as soon as one request fails, and .done() then never
	// runs - which means the "Fetching Loxone Config from Miniservers..."
	// dialog would stay open forever. That is exactly what users saw when a
	// Miniserver could not be read. By resolving in the fail handler as well
	// the dialog always closes and the error is displayed instead.
	function requestLoxplan( msno ) {
		var deferred = $.Deferred();
		$.post( "ajax.cgi", { action : "getloxplan", msno : msno } )
			.done( function(data){
				console.log(data);
				responses.push(data);
				deferred.resolve();
			})
			.fail( function(jqXHR){
				var msg;
				try { msg = JSON.parse( jqXHR.responseText ).error; } catch(e) { msg = undefined; }
				if( !msg ) {
					msg = "Miniserver " + msno + ": request failed (HTTP " + jqXHR.status + ")";
				}
				console.log( "getloxplan failed for MS" + msno, msg );
				responses.push( { error: msg } );
				deferred.resolve();
			});
		return deferred.promise();
	}

	for (msno in miniservers) {
		async_request.push( requestLoxplan( msno ) );
	}

	async_request.push( (function(){
		var deferred = $.Deferred();
		$.post( "ajax.cgi", { action : "getstatsconfig" } )
			.done( function(data){
				try {
					statsconfig = data;
					statsconfigLoxone = Object.values( statsconfig.loxone );
				}
				catch(e) {
					console.log( "statsconfigLoxone seems to be empty" );
					statsconfigLoxone = [];
				}
				deferred.resolve();
			})
			.fail( function(jqXHR){
				$("#progress_errors").append( "<p>Could not read stats.json (HTTP " + jqXHR.status + "). Assuming it is empty.</p>" );
				$("#box_progress_errors").fadeIn();
				statsconfigLoxone = [];
				deferred.resolve();
			});
		return deferred.promise();
	})() );


	$.when.apply( null, async_request).always( function(){
		$("#progressState").html($('#lang_preparing').text());
		consolidateLoxPlan( responses );
		$("#progressState").html($('#lang_generating').text());
		updateTable();
		$("#popupProgress").popup("close");
		$("#progressState").html("");
		setTimer();
		getImportSchedulerReport();


	});
}

function consolidateLoxPlan( data ) {

	// Start from scratch on every run.
	//
	// This runs a second time after a manual upload, and everything below only
	// ever adds: controls are concat'ed, so every block appeared twice in the
	// table, and the filter dropdowns got a second set of entries. miniservers_used
	// was worse - the first run turns it into an array with Object.values(), and
	// $.extend() then merged the next Miniserver hash into it by index.
	controls = [];
	rooms = {};
	categories = {};
	pages = {};
	miniservers_used = {};
	rooms_used = [];
	categories_used = [];
	elementTypes_used = [];
	pages_used = [];

	for (const [key, msobj] of Object.entries(data)) {
	  
	  if( data[key]?.error ) {
		console.log( "Error", data[key] );
		$("#progress_errors").append( "<p>"+data[key]?.error+"</p>" );
		$("#box_progress_errors").fadeIn();
		// Nothing else to merge from a failed Miniserver. Without this the
		// undefined values below end up as an "undefined" entry in the
		// element type filter.
		continue;
	  }


	  rooms = $.extend( rooms, data[key].rooms );
	  categories = $.extend( categories, data[key].categories );
	  pages = $.extend( pages, data[key].pages );
	  miniservers_used = $.extend ( miniservers_used, data[key].miniservers );

	  // rooms_used and categories_used are ARRAYS. $.extend merges objects by
	  // key, so for arrays it merged them by INDEX - with a second Miniserver
	  // its entries overwrote those of the first instead of adding to them,
	  // and categories went missing from the filter (issue #120).
	  rooms_used = rooms_used.concat( data[key].rooms_used || [] );
	  categories_used = categories_used.concat( data[key].categories_used || [] );
	  elementTypes_used = elementTypes_used.concat( data[key].elementTypes || [] );
	  
	  if( typeof data[key].controls !== "undefined" ) {
	     console.log( "controls from key", key, Object.keys(data[key].controls).length );
		 var objarr = Object.values( data[key].controls );
		 controls = controls.concat( objarr );
	  }
	
	}
	
	// Sort controls by Title
	controls = controls.filter ( control => control.msno > 0 ); // Filter controls not on an MS in LoxBerry
	controls.sort( dynamicSortMultiple( "Title" ) );
	
	// Uniquify the merged lists
	function uniquify( arr ) {
		return arr.filter( function(item, pos) { return arr.indexOf(item) == pos; } );
	}
	elementTypes_used = uniquify( elementTypes_used );
	elementTypes_used.sort();
	categories_used = uniquify( categories_used );
	rooms_used = uniquify( rooms_used );

	miniservers_used = Object.values( miniservers_used );
	miniservers_used = miniservers_used.filter( item => item.msno > 0 ); // Filter MS that are not in LoxBerry
	miniservers_used.sort( dynamicSort( "msno" ) );

	// console.log("controls array", controls);
	// console.log("Controls", controls);
	
	var rooms_tmp = [];
	for (var roomid in rooms) {
		// Was "if(! roomid in rooms_used )", which JavaScript reads as
		// "(!roomid) in rooms_used" - always false, so the filter never did
		// anything and every room of the project was offered, not just the
		// ones actually in use.
		if( !rooms_used.includes(roomid) ) continue;
		rooms_tmp.push([rooms[roomid], roomid]);
	}
	rooms = rooms_tmp.sort();
	
	var cat_tmp = [];
	for (var catid in categories) {
		if(categories_used.includes(catid)) {
			cat_tmp.push([categories[catid], catid]);
		}
	}
	categories = cat_tmp.sort();

	// Every page of the project is offered (issue #20), including those whose
	// blocks are all filtered out by the blacklist - a page holding nothing but
	// logic blocks then simply gives an empty table.
	//
	// Blocks reference their page by title, not by UUID, so the titles from the
	// pages list are what the filter compares against. The blocks are used as a
	// second source for the rare case of an ms<n>.json still written without a
	// pages list - the filter is then incomplete rather than empty.
	// localeCompare because these are names a user reads, and a plain sort() would
	// put umlauts behind Z.
	pages_used = [ ...new Set(
		Object.values( pages || {} ).concat( controls.map( c => c.Page ) ).filter( p => p )
	) ];
	pages_used.sort( ( a, b ) => a.localeCompare( b ) );

	generateFilter();
	
}

function generateFilter() {

	// Drop what a previous run added, keeping the entries that come from the
	// template ("All rooms", "Without a page", ...). Same reason as the reset in
	// consolidateLoxPlan: this runs again after a manual upload.
	$('.filter_select option').not('.staticopt').remove();

	// Add Miniservers to options

	for( const [key, msobj] of Object.entries(miniservers_used) ) {
		$('#filter_miniserver').append(
		`<option value="${msobj.msno}">(${msobj.msno}) ${msobj.Title}</option>`); 
	}
	
	// Add used rooms to options
	
	for( obj of rooms ) {
		// console.log(obj);
		$('#filter_room').append(
		`<option value="${obj[0]}">${obj[0]}</option>`); 
	}

	// Add used categories to options
	
	for( obj of categories ) {
		// console.log(obj);
		$('#filter_category').append(
		`<option value="${obj[0]}">${obj[0]}</option>`); 
	}
	
	// Add used pages to options

	for( obj of pages_used ) {
		$('#filter_page').append(
		`<option value="${escAttr(obj)}">${escHtml(obj)}</option>`);
	}

	// Add used elements to options in native language
	var elementsArr = [];
	for( var key in elementTypes_used ) {
		var ucKey = typeof elementTypes_used[key] !== "undefined" ? elementTypes_used[key].toUpperCase() : "undefined";
		elementsArr.push( [ ucKey, typeof loxone_elements[ucKey]?.localname !== "undefined" ? loxone_elements[ucKey]?.localname : ucKey ] );
	}
	
	elementsArr.sort(function(a, b) {
		a=a[1];
		b=b[1];
		return a<b ? -1 : (a > b ? 1 : 0);
	});
	
	for( obj of elementsArr ) {
		// console.log(obj);
		$('#filter_element').append(
		`<option value="${obj[0]}">${obj[1]}</option>`); 
	}
	
	restoreFilters();
	
	
}

function updateTable() {
	console.log("updateTable called");
	controlstable = "";
	createTableHead();
	createTableBody();
	createTableEnd();
	
	$("#loxonecontrolstablediv").html( controlstable );
	$("#loxonecontrolstablediv").removeClass("datahidden");
	
	
	
}
	
function createTableHead() {
	
	// The sorting is done on the data, not on the DOM.
	//
	// LoxBerry brings its own (system/scripts/lb-table-sort.js) and it does not
	// fit here twice over: it initialises once on DOMContentLoaded while this
	// table is only built afterwards by JavaScript, and it reorders the rows in
	// place - which the next filter change would undo, because the table is
	// rebuilt from scratch every time. Sorting the list before rendering
	// survives both.
	function th( key, cls, label ) {
		var arrow = ( tableSort.key == key ) ? ( tableSort.dir > 0 ? "&#8593;" : "&#8595;" ) : "&#8597;";
		var active = ( tableSort.key == key ) ? " sortactive" : "";
		return `<th class="${cls} s4l-sortable${active}" data-sortkey="${key}">${label}<span class="sortarrow">${arrow}</span></th>`;
	}

	controlstable += `
	<table class="controlstable">
	<thead>
	<tr>
		${th( "ms",     "col-ms",     $('#lang_th_ms').text() )}
		${th( "name",   "col-name",   $('#lang_th_name_type').text() )}
		${th( "loc",    "col-loc",    $('#lang_th_location').text() )}
		${th( "stat",   "col-stat",   $('#lang_th_statistics').text() )}
		${th( "status", "col-status", $('#lang_th_status').text() )}
		${th( "import", "col-import", $('#lang_th_import').text() )}
		<th class="col-buttons">${$('#lang_th_actions').text()}</th>
	</tr>
	</thead>
	<tbody>
	`;

}

function createTableEnd() {
	controlstable += `</tbody></table>`;
}

// Status of a statistic, as the grabber recorded it in stats.json.
//
// No status means the statistic is fine - the grabber only writes when
// something is wrong, because the configuration directory is on the SD card on
// most installations.
function statusOf( statmatch ) {
	if( typeof statmatch === "undefined" || statmatch === null ) return null;
	if( !statmatch.status || !statmatch.status.error ) return null;
	return {
		error: statmatch.status.error,
		since: Number( statmatch.status.since ) || 0,
		count: Number( statmatch.status.count ) || 0
	};
}

// green = fine, yellow = the grabber ran out of time, red = the Miniserver
// does not know the block any more.
function statusColour( st ) {
	if( !st ) return "green";
	if( st.error === "404" ) return "red";
	return "yellow";
}

// The icons are drawn with CSS (see the stylesheet in loxone.html) instead of
// the PNGs this plugin used to ship. The shape carries the meaning, not only
// the colour - a tick, a warning triangle and a cross stay distinguishable in
// print, on a poor screen, or for someone who cannot tell red from green.
function icon( kind, title ) {
	var t = title ? ` title="${escAttr(title)}"` : "";
	return `<span class="s4l-icon s4l-icon-${kind}"${t}></span>`;
}

function formatTimestamp( epoch ) {
	if( !epoch ) return "?";
	var d = new Date( epoch * 1000 );
	return d.toLocaleString();
}

// Icon only, the wording in the tooltip. That keeps the column exactly one icon
// wide whatever is filtered. Statistics that are not switched on at all get
// nothing - there is no status to report about them.
function statusCell( statmatch ) {
	if( typeof statmatch === "undefined" || statmatch === null ) {
		return `<td class="statuscell">&nbsp;</td>`;
	}
	var st = statusOf( statmatch );
	var title, kind;
	if( !st ) {
		title = $('#lang_status_ok').text() + " - " + $('#lang_hover_status_ok').text();
		kind = "ok";
	}
	else {
		var key = ( st.error === "404" ) ? 'lang_hover_status_404' : 'lang_hover_status_limit';
		var label = ( st.error === "404" ) ? $('#lang_status_404').text() : $('#lang_status_limit').text();
		title = label + " - " + $('#'+key).text()
			.replace( '__COUNT__', st.count )
			.replace( '__SINCE__', formatTimestamp( st.since ) );
		if( st.count >= 10 ) title += $('#lang_hover_status_givenup').text();
		kind = ( st.error === "404" ) ? "err" : "warn";
	}
	return `<td class="statuscell">` + icon( kind, title ) + `</td>`;
}

function escHtml( s ) {
	return $('<div>').text( s === undefined || s === null ? '' : s ).html();
}

// --- Where the Loxone configuration comes from (issue #101) ----------------

var loxplanFiles = {};

function initLoxplanSource() {
	// The Miniserver list for the upload comes from the same source as the
	// filter, so both always offer the same set.
	var sel = $('#upload_msno');
	sel.empty();
	for( var n in miniservers ) {
		sel.append( '<option value="' + escAttr(n) + '">' + escHtml( miniservers[n].Name + ' (' + n + ')' ) + '</option>' );
	}
	try { sel.selectmenu("refresh"); } catch(e) {}

	$('#upload_msno').on( "change", showLoxplanFileInfo );

	// The page follows the radio button immediately, the configuration does not
	// necessarily: "manual" is only stored once something has been uploaded, so
	// the server may answer with "auto" here. That is deliberate - the upload
	// field opens either way, and uploadLoxplan stores the mode afterwards.
	$('input[name="loxplansource"]').on( "change", function() {
		var v = $('input[name="loxplansource"]:checked').val();
		applyLoxplanSource( v );
		$.post( "ajax.cgi", { action: 'saveloxplansource', loxplansource: v } )
		.fail( function( d ) { console.log( "saveloxplansource failed", d ); } );
	} );

	// The stored setting decides, not the markup - and only once it is known is
	// the configuration requested.
	$.post( "ajax.cgi", { action: 'loxplaninfo' } )
	.fail( function( d ) {
		console.log( "loxplaninfo failed", d );
		applyLoxplanSource( "auto" );
		getLoxplan();
	} )
	.done( function( data ) {
		var v = ( data && data.loxplansource == "manual" ) ? "manual" : "auto";
		loxplanFiles = ( data && data.files ) ? data.files : {};
		$('input[name="loxplansource"][value="' + v + '"]').prop( "checked", true );
		try { $('input[name="loxplansource"]').checkboxradio("refresh"); } catch(e) {}
		applyLoxplanSource( v );
		getLoxplan();
	} );
}

function applyLoxplanSource( v ) {
	if( v == "manual" ) {
		$('#loxplanupload').removeClass('disabled');
		showLoxplanFileInfo();
	} else {
		$('#loxplanupload').addClass('disabled');
		$('#loxplanupload_hint').text( $('#lang_loxplansource_auto_hint').text() );
	}
}

// What is on file for the selected Miniserver, so the user can tell whether an
// upload is still missing.
function showLoxplanFileInfo() {
	var n = $('#upload_msno').val();
	var f = loxplanFiles[n];
	if( !f || !f.exists ) {
		$('#loxplanupload_hint').text( $('#lang_loxplan_none').text() );
		return;
	}
	var d = new Date( Number(f.mtime) * 1000 ).toLocaleString();
	var kb = Math.round( Number(f.size) / 1024 ) + " KB";
	$('#loxplanupload_hint').text(
		$('#lang_loxplan_uploaded').text().replace( '__DATE__', d ).replace( '__SIZE__', kb ) );
}

function uploadLoxplan() {
	var input = document.getElementById('loxplanfile');
	if( !input || !input.files || !input.files.length ) {
		$('#loxplanupload_hint').attr("style","color:red").text( $('#lang_loxplan_nofile').text() );
		return;
	}

	var fd = new FormData();
	fd.append( 'action', 'uploadloxplan' );
	fd.append( 'msno', $('#upload_msno').val() );
	fd.append( 'loxplanfile', input.files[0] );

	$('#loxplanupload').addClass('disabled');
	$('#loxplanupload_hint').attr("style","color:blue").text( $('#lang_loxplan_uploading').text() );

	$.ajax({
		url: 'ajax.cgi',
		type: 'POST',
		data: fd,
		// Both off: jQuery must not touch a FormData object, the browser sets
		// the multipart boundary itself.
		processData: false,
		contentType: false
	})
	.fail( function( d ) {
		console.log( "uploadloxplan failed", d );
		$('#loxplanupload').removeClass('disabled');
		$('#loxplanupload_hint').attr("style","color:red").text( $('#lang_loxplan_upload_fail').text() );
	} )
	.done( function( data ) {
		$('#loxplanupload').removeClass('disabled');
		if( !data || !data.uploaded ) {
			var msg = ( data && data.error ) ? data.error : $('#lang_loxplan_upload_fail').text();
			$('#loxplanupload_hint').attr("style","color:red").text( msg );
			return;
		}
		$('#loxplanupload_hint').attr("style","color:green").text( $('#lang_loxplan_upload_ok').text() );
		input.value = "";
		// Only now is manual mode worth storing - the radio button alone does not
		// do it, the server refuses it while no file is there. And it has to
		// happen before the configuration is requested, otherwise that request
		// would still be served from the Miniserver instead of from the upload.
		$.post( "ajax.cgi", { action: 'saveloxplansource', loxplansource: 'manual' } )
		.fail( function( d ) { console.log( "saveloxplansource failed", d ); } )
		.always( function() {
			// Read in right away - that is the point of the upload.
			getLoxplan();
			$.post( "ajax.cgi", { action: 'loxplaninfo' } )
			.done( function( d ) { if( d && d.files ) { loxplanFiles = d.files; } } );
		} );
	} );
}
function escAttr( s ) {
	return escHtml(s).replace( /"/g, '&quot;' );
}

// The buttons that belong to a status: remove a block that is gone, reset the
// counter of one that only ran out of time. Icon only - the column is narrow
// and the tooltip says what they do.
// The buttons use the plugin's own square style, not jQuery Mobile's. Its
// icon-only buttons put the glyph on a round grey disc, which looks like a
// round button in a table of square cells.
function actionButtons( statmatch ) {
	var st = statusOf( statmatch );
	var out = "";

	// A statistic that ran into the time limit can be put back into service
	// without any of the rest.
	if( st && st.error !== "404" ) {
		var res = escAttr( $('#lang_hover_reset_status').text() );
		out += `<a href="#" class="s4l-tbtn s4l-tbtn-reset btnResetStatus"`
		     + ` title="${res}" aria-label="${escAttr($('#lang_button_reset_status').text())}"></a>`;
	}

	// The red button appears for a block that is gone and for a statistic that
	// is running. What it does differs - remove there, switch off here - and the
	// tooltip and the dialog say which of the two it is. Deciding it is the
	// backend's job, it reads the status from the entry itself.
	var gone = ( st && st.error === "404" );
	if( gone || statmatch?.active === "true" ) {
		var lbl = escAttr( gone ? $('#lang_button_remove_from_s4l').text()
		                        : $('#lang_hover_button_deactivate').text() );
		out += `<a href="#" class="s4l-tbtn s4l-tbtn-danger s4l-tbtn-cross btnDeleteStat"`
		     + ` title="${lbl}" aria-label="${lbl}"></a>`;
	}

	return out;
}

// Settings button - grey, gear. The hole in the gear is an element of its own:
// it has to be painted in the button colour, and the two pseudo elements are
// already taken by the two squares that form the teeth.
function settingsButton() {
	var lbl = escAttr( $('#lang_hover_button_settings').text() );
	return `<a href="#" class="s4l-tbtn s4l-tbtn-gear btnLoxoneDetails"`
	     + ` title="${lbl}" aria-label="${lbl}"><span class="hole"></span></a>`;
}

// The "Statistics" cell. A block the Miniserver no longer knows shows since
// when instead of the interval - the interval would be a promise that is not
// being kept.
function statisticsCell( statmatch, statmatchkey ) {
	var st = statusOf( statmatch );
	if( st && st.error === "404" ) {
		var since = $('#lang_not_reachable_since').text().replace( '__SINCE__', formatTimestamp( st.since ) );
		return `<td class="iconcell"><div class="statdata">`
		     + icon( "err", since )
		     + `<span class="iconline" style="color:#c0392b">${escHtml(since)}</span>`
		     + `</div></td>`;
	}

	var statDisplay, s4l_interval;
	if( statmatch?.active === "true" ) {
		statDisplay = "";
		s4l_interval = statmatch.interval/60;
	}
	else {
		statDisplay = "display:none;";
		s4l_interval = "";
	}
	return `<td class="iconcell">`
	     + `<div class="statdata" id="statskey-${statmatchkey}" style="${statDisplay}">`
	     + icon( "ok" )
	     + `<span class="iconline"><span name="s4l_interval">${s4l_interval}</span> ${$('#lang_minutes_short').text()}</span>`
	     + `</div></td>`;
}

// Statistics whose block is not in the LoxPLAN, as pseudo blocks.
//
// The table walks the LoxPLAN, so these would be invisible - which is exactly
// how they went unnoticed for two years on the author's system: 21 entries, all
// active, all being fetched every interval, none of them shown anywhere. Turned
// into block-shaped objects here so they go through the same rendering and the
// same sorting as everything else instead of being appended at the end.
//
// Note what is NOT done here: nothing is declared "deleted" because it is
// missing from the LoxPLAN. The blacklist keeps 276 control types out of that
// list entirely, so a perfectly working statistic of such a type is missing
// here too. What state it is in comes from the status the grabber recorded -
// only the Miniserver can say whether a block answers.
function orphanControls() {
	if( typeof statsconfigLoxone === "undefined" ) return [];
	var out = [];
	for( var key in statsconfigLoxone ) {
		var stat = statsconfigLoxone[key];
		if( !stat || !stat.uuid ) continue;
		if( controls.find( obj => { return obj.UID === stat.uuid && obj.msno == stat.msno } ) ) continue;
		out.push( {
			UID: stat.uuid, msno: stat.msno,
			Title: stat.name || stat.measurementname || stat.uuid,
			Desc: ( stat.description && stat.description != stat.name ) ? stat.description : "",
			Place: stat.room || "", Category: stat.category || "",
			Type: stat.type || "", Page: "", Visu: "false", StatsType: 0,
			_orphan: true
		} );
	}
	return out;
}

function createTableBody() {

	var filterSearchStr_lc = filterSearchString.toLowerCase();

	// One list for both kinds, so a statistic without a block appears where its
	// name belongs instead of being appended at the end.
	var rows = sortRows( controls.concat( orphanControls() ) );

	for( elementno in rows ) {
		element = rows[elementno];

		// 
		// Filter section
		// 
		
		// Miniserver filter
		if( typeof filters["filter_miniserver"] !== "undefined" && filters["filter_miniserver"] != "all" && filters["filter_miniserver"] != element.msno )
			continue;
		
		// Room filter
		if( typeof filters["filter_room"] !== "undefined" && filters["filter_room"] != "all" && filters["filter_room"] != element.Place )
			continue;
		
		// Category filter
		if( typeof filters["filter_category"] !== "undefined" && filters["filter_category"] != "all" && filters["filter_category"] != element.Category )
			continue;
		
		// Page filter (issue #20)
		// __nopage__ catches everything that sits on no page: the inputs and
		// outputs from the peripheral tree, and the orphaned statistics that only
		// exist in stats.json and therefore have no page either.
		if( typeof filters["filter_page"] !== "undefined" && filters["filter_page"] != "all" ) {
			if( filters["filter_page"] == "__nopage__" ) {
				if( element.Page ) continue;
			}
			else if( filters["filter_page"] != element.Page ) continue;
		}

		// Element filter
		if( typeof filters["filter_element"] !== "undefined" && filters["filter_element"] != "all" && filters["filter_element"] != element.Type.toUpperCase() )
			continue;
		
		// Loxone Visu filter
		if( typeof filters["filter_loxvisu"] !== "undefined" && filters["filter_loxvisu"] != "all") {
			if( filters["filter_loxvisu"] == "on" && element.Visu != "true" ) continue;
			if( filters["filter_loxvisu"] == "off" && element.Visu == "true" ) continue;
		}
		
		// Loxone Stat filter
		if( typeof filters["filter_loxstat"] !== "undefined" && filters["filter_loxstat"] != "all") {
			if( filters["filter_loxstat"] == "on" && element.StatsType == 0 ) continue;
			if( filters["filter_loxstat"] == "off" && element.Visu > 0 ) continue;
		}
		
		// S4L Stat filter
		var statmatchkey = statsconfigLoxone.findIndex(obj => {
			return obj.uuid === element.UID && obj.msno == element.msno
		})
		var statmatch = statsconfigLoxone[statmatchkey];
		if( typeof filters["filter_s4lstat"] !== "undefined" && filters["filter_s4lstat"] != "all") {
			if( filters["filter_s4lstat"] == "on" && ( typeof statmatch === "undefined" || statmatch.active !== "true" ) ) continue;
			if( filters["filter_s4lstat"] == "off" && typeof statmatch !== "undefined" &&  statmatch.active === "true" ) continue;
		}

		// Status filter. Blocks without a statistic have no status at all and
		// are therefore not part of any of the three colours.
		if( typeof filters["filter_status"] !== "undefined" && filters["filter_status"] != "all" ) {
			if( typeof statmatch === "undefined" ) continue;
			if( statusColour( statusOf(statmatch) ) != filters["filter_status"] ) continue;
		}

		// Text filter (filterSearchString)
		if( filterSearchStr_lc != "" ) {
			if ( 
				element.Title?.toLowerCase().indexOf(filterSearchStr_lc) == -1 &&
				element.Desc?.toLowerCase().indexOf(filterSearchStr_lc) == -1 &&
				element.UID?.toLowerCase().indexOf(filterSearchStr_lc) == -1 
				) continue;
		}
		
		//
		// Create row section
		//
		
		controlstable += `<tr class="controlstable_tr${element._orphan ? ' orphanrow' : ''}" data-uid="${element.UID}" data-msno="${element.msno}">`;
		
		// Miniserver
		controlstable += `<td>${element.msno}</td>`;
		
		// Name (Type)
		controlstable += `<td>${element.Title}`;
		if(typeof element.Desc != "undefined" && element.Desc != "" ) 
			controlstable += `<br>${element.Desc}`;
		var TypeLocal = loxone_elements[element.Type.toUpperCase()]?.localname;
		if(typeof TypeLocal == "undefined")
			TypeLocal = element.Type.toUpperCase();
		controlstable += `<br><span class="small">${TypeLocal}</span>`;
		
		
		// Location
		controlstable += `<td>${element.Place}
			<br>${element.Category}
			</td>`;
		
		// Statistics
		controlstable += statisticsCell( statmatch, statmatchkey );

		// Status
		controlstable += statusCell( statmatch );

		// Import section. iconcell so what updateReportTables() writes in here
		// later gets the same layout as the statistics column - icon, then a
		// short line underneath.
		controlstable += `<td class="importInfo iconcell"></td>`;

		// Button section
		controlstable += `<td class="actionbuttons">`
		               + actionButtons( statmatch )
		               + settingsButton()
		               + `</td>`;

		// End of row

		controlstable += `</tr>`;

	}
}

// Which column the table is sorted by. "name" is what it always was.
var tableSort = { key: "name", dir: 1 };

// Names that do not start with a letter or a digit belong at the end. Loxone
// generates such names for the pseudo inputs of service blocks - _0, _1, _2 and
// so on. The old sort compared the strings directly and put them last by
// accident, because the underscore sits behind the letters in the character
// table; localeCompare puts them first, which is how 30 of them suddenly
// appeared at the top of the table.
//
// The letter test works without unicode regular expressions, so umlauts and
// other scripts are covered too: only a character that has case differs between
// its upper and its lower case form.
function nameGroup( title ) {
	var c = String( title || "" ).charAt(0);
	return ( /[0-9]/.test(c) || c.toLowerCase() !== c.toUpperCase() ) ? 0 : 1;
}

// The group is compared separately and NOT folded into the sort key. A key like
// "0" + name looks tempting, but with numeric collation the prefix digit merges
// with a leading digit of the name into one number - "01W" then sorts as 1 and
// lands behind everything beginning with a letter.
function compareNames( a, b ) {
	var ga = nameGroup( a ), gb = nameGroup( b );
	if( ga !== gb ) return ga - gb;
	return String( a || "" ).toLowerCase()
	       .localeCompare( String( b || "" ).toLowerCase(), undefined,
	                       { numeric: true, sensitivity: "base" } );
}

// Sort keys per column. Not the displayed text but what the text means: the
// status sorts by severity, so one click brings everything that needs
// attention to the top - sorting the words alphabetically would put "Nicht
// erreichbar" between "OK" and "Zeitlimit" and say nothing.
function sortValue( element, key ) {
	var stat = statsconfigLoxone ? statsconfigLoxone.find( obj => {
		return obj.uuid === element.UID && obj.msno == element.msno } ) : undefined;

	if( key == "ms" )   return Number( element.msno ) || 0;
	// "name" is handled in the comparator - it needs two stages, see
	// compareNames().
	if( key == "loc" )  return ( ( element.Place || "" ) + " " + ( element.Category || "" ) ).toLowerCase();
	if( key == "stat" ) {
		if( !stat || stat.active !== "true" ) return -1;
		return Number( stat.interval ) || 0;
	}
	if( key == "status" ) {
		if( !stat ) return -1;                       // no statistic at all
		var st = statusOf( stat );
		if( !st ) return 0;                          // fine
		return ( st.error === "404" ) ? 2 : 1;       // time limit, then gone
	}
	if( key == "import" ) {
		var imp = imports.find( obj => {
			return obj.data?.msno == element.msno && obj.data?.uuid == element.UID } );
		return Number( imp?.data?.status?.endtime ) || 0;
	}
	return "";
}

function sortRows( rows ) {
	var key = tableSort.key;
	var dir = tableSort.dir;
	rows.sort( function( a, b ) {
		if( key == "name" ) return compareNames( a.Title, b.Title ) * dir;

		var va = sortValue( a, key );
		var vb = sortValue( b, key );
		var r;
		if( typeof va === "number" && typeof vb === "number" ) r = va - vb;
		else r = String(va).localeCompare( String(vb), undefined, { numeric: true, sensitivity: "base" } );
		// Rows that compare equal fall back to the name, so the order stays
		// predictable instead of depending on what the sort happens to do.
		if( r === 0 ) return compareNames( a.Title, b.Title );
		return r * dir;
	} );
	return rows;
}

// --- Deleting and resetting a statistic ------------------------------------

var deleteStatTarget = {};

function askDeleteStat( uid, msno ) {
	var stat = statsconfigLoxone.find( obj => { return obj.uuid === uid && obj.msno == msno } );
	if( !stat ) return;

	// Same rule the backend applies, so the dialog promises what actually
	// happens: only a block the Miniserver no longer knows is removed.
	var st = statusOf( stat );
	var gone = ( st && st.error === "404" ) ? true : false;
	deleteStatTarget = { uuid: uid, msno: msno, gone: gone };

	var name = stat.name || stat.measurementname || uid;
	$("#deleteStat_title").text( gone ? $('#lang_popup_delete_title').text()
	                                  : $('#lang_popup_deactivate_title').text() );
	$("#deleteStat_what").html( escHtml(
		( gone ? $('#lang_confirm_delete_stat').text() : $('#lang_confirm_deactivate_stat').text() )
			.replace( '__NAME__', name ) ) );
	$("#deleteStat_keep").text( gone ? $('#lang_button_delete_keepdata').text()
	                                 : $('#lang_button_deactivate_keepdata').text() );
	$("#deleteStat_drop").text( gone ? $('#lang_button_delete_withdata').text()
	                                 : $('#lang_button_deactivate_withdata').text() );

	$("#deleteStat_hint").html("&nbsp;");
	$("#deleteStat_keep, #deleteStat_drop").removeClass("ui-disabled");
	$("#popupDeleteStat").popup("option","positionTo","window");
	$("#popupDeleteStat").popup("open");
}

function deleteStat( dropdata ) {
	if( !deleteStatTarget.uuid ) return;
	$("#deleteStat_keep, #deleteStat_drop").addClass("ui-disabled");
	$("#deleteStat_hint").html( $('#lang_status_updating').text() );
	$.post( "ajax.cgi", {
		action:   "deletestat",
		uuid:     deleteStatTarget.uuid,
		msno:     deleteStatTarget.msno,
		dropdata: dropdata ? "true" : "false"
	} )
	// On failure the buttons come back so a second attempt is possible - the
	// popup itself is closed with the cross in the corner.
	.fail( function( data ) {
		console.log( "deletestat failed", data );
		$("#deleteStat_hint").attr("style","color:red").html( $('#lang_hint_delete_fail').text() );
		$("#deleteStat_keep, #deleteStat_drop").removeClass("ui-disabled");
	} )
	.done( function( data ) {
		if( !data || !data.deleted ) {
			$("#deleteStat_hint").attr("style","color:red").html( $('#lang_hint_delete_fail').text() );
			$("#deleteStat_keep, #deleteStat_drop").removeClass("ui-disabled");
			return;
		}
		// The local copy follows what the backend reports, otherwise the row
		// would come back unchanged on the next redraw until the page is
		// reloaded.
		var idx = statsconfigLoxone.findIndex( obj => {
			return obj.uuid === deleteStatTarget.uuid && obj.msno == deleteStatTarget.msno } );
		if( idx > -1 ) {
			if( data.mode == "removed" ) {
				statsconfigLoxone.splice( idx, 1 );
			}
			else {
				statsconfigLoxone[idx].active = "false";
				delete statsconfigLoxone[idx].status;
			}
		}
		$("#deleteStat_hint").attr("style","color:green").html(
			( data.mode == "removed" ) ? $('#lang_hint_delete_done').text()
			                           : $('#lang_hint_deactivate_done').text() );
		window.setTimeout( function() {
			$("#popupDeleteStat").popup("close");
			updateTable();
		}, 1200 );
	} );
}

function resetStatStatus( uid, msno ) {
	$.post( "ajax.cgi", { action: "resetstatstatus", uuid: uid, msno: msno } )
	.fail( function( data ) { console.log( "resetstatstatus failed", data ); } )
	.done( function( data ) {
		if( !data || !data.reset ) return;
		var stat = statsconfigLoxone.find( obj => { return obj.uuid === uid && obj.msno == msno } );
		if( stat ) delete stat.status;
		updateTable();
	} );
}

function popupLoxoneDetails( uid, msno ) {
	$("#popupLoxoneDetails").popup("option","positionTo","window"); 
	$("#popupLoxoneDetails").popup("open");
	if(hints_hide?.hint_importbutton != true) {
		$("#hint_importbutton").show();
	}
	//$("#contentLoxoneDetails #valuesLoxoneDetails").empty();
	var control = controls.find( obj => { return obj.UID === uid && obj.msno == msno })

	// A statistic whose block is no longer in the LoxPLAN. Everything the popup
	// needs is built from what stats.json remembers about it - that is all the
	// information there is left. Live data is impossible, so that box is
	// replaced by the note and the delete button.
	var blockGone = ( typeof control === "undefined" );
	if( blockGone ) {
		var stat = statsconfigLoxone.find( obj => { return obj.uuid === uid && obj.msno == msno } );
		if( !stat ) return;
		control = {
			UID: stat.uuid, msno: stat.msno,
			Title: stat.name, Desc: stat.description,
			Place: stat.room, Category: stat.category,
			Type: stat.type, Page: "", Visu: "false", StatsType: 0
		};
		$("#LoxoneDetails_deletebutton").data("uid", uid).data("msno", msno);
		$("#LoxoneDetails_gone").show();
		$("#LoxoneDetails_livebox").hide();
	}
	else {
		$("#LoxoneDetails_gone").hide();
		$("#LoxoneDetails_livebox").show();
	}

	// Set data properties to tables
	$(".data-uidmsno").data("uid", control.UID).data("msno", control.msno);
	$("#LoxoneDetails_s4lstatimportbutton").data("uid", control.UID).data("msno", control.msno);
	
	updateReportTables();
	
	// Fill popup title 
	$("#LoxoneDetails_titletitle").text(control.Title);
	$("#LoxoneDetails_titledesc").text(control.Desc);
	
	// Fill popup properties
	$("#LoxoneDetails_uid").val(control.UID);
	
	$("#LoxoneDetails_placelabel").text(loxone_elements['PLACE'].localname);
	$("#LoxoneDetails_place").html(control.Place ? control.Place : "&nbsp;" );
	$("#LoxoneDetails_categorylabel").text(loxone_elements['CATEGORY'].localname);
	$("#LoxoneDetails_category").html(control.Category ? control.Category : "&nbsp;");
	
	$("#LoxoneDetails_typelabel").text($('#lang_label_type').text());
	var TypeLocal = loxone_elements[control.Type?.toUpperCase()]?.localname;
	if(typeof TypeLocal == "undefined") 
		TypeLocal = control.Type?.toUpperCase();
	$("#LoxoneDetails_type").text(TypeLocal);
	$("#LoxoneDetails_typehover").prop("title", control.Type);
	
	
	$("#LoxoneDetails_miniserver").text(miniservers[control.msno].Name+' ('+control.msno+')');
	
	$("#LoxoneDetails_pagelabel").text(loxone_elements['PAGE'].localname);
	$("#LoxoneDetails_page").html( control.Page ? control.Page : "&nbsp;" );

	// Status blocks get a warning about their state texts (issue #20). The
	// Miniserver only reports the text of the active state, so the state - and
	// with it the value of the Val output - can only be worked out when the texts
	// differ from each other.
	$("#LoxoneDetails_statehint").toggle( (control.Type || "").toUpperCase() == "STATE" );
	
	// Icons
	var isLoxVisu = control.Visu === "true" ? true : false;
	var checkedImg = icon( "ok" );
	var uncheckedImg = icon( "off" );
	
	$("#LoxoneDetails_visu").html(isLoxVisu ? checkedImg : uncheckedImg);
	$("#LoxoneDetails_loxstat").html(control.StatsType > 0 ? checkedImg : uncheckedImg);
	
	// S4L Settings
	var statmatch = statsconfigLoxone.find(obj => {
			return obj.uuid === control.UID && obj.msno == control.msno
		})
	if( statmatch?.outputs ) {
		console.log("outputs", statmatch.outputs );
	}
	
	console.log("s4lstats checkboxes", statmatch);
	if( statmatch?.active == "true" || statmatch?.active == true ) {
		console.log("active = true");
		$("#LoxoneDetails_s4lstatactive")
			.prop('checked', true)
			.prop('disabled', false)
			.checkboxradio('refresh');
		$("#LoxoneDetails_s4lstatinterval")
			//.addClass("s4l_interval_highlight")
			.prop('disabled', false)
			.textinput( "refresh" );
	}
	else {
		console.log("active = false");
		$("#LoxoneDetails_s4lstatactive")
			.prop('checked', false)
			.prop('disabled', true)
			.checkboxradio('refresh');
		$("#LoxoneDetails_s4lstatinterval")
			.prop('disabled', true)
			//.removeClass("s4l_interval_highlight")
			.textinput( "refresh" );
	}
	
	if( statmatch?.measurementname ) {
		$("#LoxoneDetails_s4lmeasurementname").val(statmatch?.measurementname);
	}
	else {
		
		$("#LoxoneDetails_s4lmeasurementname").val( validateMeasurementname( control.Desc ? control.Desc : control.Title, msno, uid) );
	}
	
	if( statmatch?.interval ) {
		$("#LoxoneDetails_s4lstatinterval").val(statmatch?.interval / 60);
	}
	else {
		$("#LoxoneDetails_s4lstatinterval").val("");
	}
	// The field cannot go below the minimum, and it says so when it does. Checked
	// when the popup opens too, not only on a change: a statistic configured
	// before the minimum was raised opens with a value that is no longer allowed.
	s4lIntervalOk();
	
	// Import now button
	if( statmatch ) {
		var importobj = imports.find(obj => {
		return obj.data?.msno == msno && obj.data?.uuid == uid && obj.data?.status?.status == "running" })
		if( importobj ) {
			$("#LoxoneDetails_s4lstatimportbutton")
			.addClass("ui-disabled");
		}
		else {
			$("#LoxoneDetails_s4lstatimportbutton")
			.removeClass("ui-disabled");
		}		
	}
	else {
		$("#LoxoneDetails_s4lstatimportbutton")
			.addClass("ui-disabled");
	}
	if( control.StatsType == 0 ) {
		$("#LoxoneDetails_s4lstatimportbutton")
			.addClass("ui-disabled");
	}
	
	// Live Data from Miniserver
	//
	// Skipped when the block is gone: the request would come back 404 and the
	// box is hidden anyway.
	if( blockGone ) {
		return;
	}

	$("#valuesLoxoneDetailsLive_title").html($('#lang_status_updating').text());
	liveTable = $("#valuesLoxoneDetailsLive_table");
	liveTable.empty();
	$.post( "ajax.cgi", { 
			action : "lxlquery",  
			uuid : uid,
			msno : control.msno,
	})
	.done(function(data){
		console.log("Response from ajax lxlquery", data);
		
		var dataStr;
		if( data.error == null && data?.code == "200" ) {
			$("#valuesLoxoneDetailsLive_title").html(`${$('#lang_label_live_data').text()} ${miniservers[control.msno].Name}`);
			
			// Get mapping for this control type
			var typeMappings = typeof data.mappings[control.Type.toUpperCase()] != "undefined" ? data.mappings[control.Type.toUpperCase()] : data.mappings["Default"];
			console.log("Mappings for "+control.Type, typeMappings); 
			
			
			for( var key in data.response ) {
				console.log("Output loop", key, data.response[key]);
				var outputKey = data.response[key].Key;
				var outputName = data.response[key].Name;
				
				// Find mapping for outputKey
				var mapKey = typeMappings.findIndex( element => element.lxlabel == outputName );
				data.response[key].mapString = mapKey != -1 ? (parseInt(typeMappings[mapKey].statpos)+1) : "";
				data.response[key].mapImg = data.response[key].mapString != "" ? icon( "import", data.response[key].mapString ) : "";
				
				// Special string for Default output
				if( outputKey == "Default" ) {
					data.response[key].localdesc = data.response[key].Unit ? data.response[key].Unit + " " : "";
					data.response[key].localdesc += $('#lang_hint_decimal_accuracy').text();
				} 
				else {
					try {
						data.response[key].localdesc = lookupOutputDescription( control.Type, outputName );
					} catch {
						data.response[key].localdesc = undefined;
					}
					data.response[key].localdesc = data.response[key].localdesc != undefined ? data.response[key].localdesc : "";
				}
				data.response[key].statChecked = statmatch?.outputs?.includes(outputKey) ? "checked" : "";
				data.response[key].statDisabled = statmatch?.active === "true" ? "" : "disabled";
				console.log("Output loop result", key, data.response[key]);
			}

			// All elements now have added metadara in the array, now we loop the array again
			
			var LoxOutputs = data.response;
			control.outputlabels = LoxOutputs.map( a => a.Name );
			control.outputkeys = LoxOutputs.map( a => a.Key );
			
			for( var key in LoxOutputs ) {
				var dataStr = `
					<tr>
						<td class="LoxoneDetails_td small" style="width:25px;">
							${data.response[key].mapString}${data.response[key].mapImg}
						</td>
						<td class="LoxoneDetails_td" style="width:120px;">
							<input type="checkbox" name="LoxoneDetails_s4loutput" data-role="none" class="s4lchange" value="${LoxOutputs[key].Key}" ${LoxOutputs[key].statChecked} ${LoxOutputs[key].statDisabled}>
							&nbsp;${LoxOutputs[key].Name}
						</td>
						<td class="LoxoneDetails_td" style="width:50px;">
							${LoxOutputs[key].Value}
						</td>
						<td class="LoxoneDetails_td small">
							${LoxOutputs[key].localdesc}
						</td>
					</tr>
				`;
				liveTable.append(dataStr);
			}
			
			// Table is finished
			
			// Finally, activate the active checkbox 
			// Background: If active=true, you always can disable the fetching
			//             But if active=false, we need to wait for the Loxone Outputs, otherwise we get empty outputs on save
			if( statmatch?.active != "true" && statmatch?.active != true ) {
				$("#LoxoneDetails_s4lstatactive")
				.prop('disabled', false)
				.checkboxradio('refresh');
			}
			
			// Done
			
		}
		else {
			console.log("LiveView done with error", data);
			liveTable.html( popupLoxoneDetails_LiveViewError(data) );
		}	
		$("#valuesLoxoneDetails").html(dataStr);
	})
	.fail(function(data){
		console.log("LiveView fail", data);
		liveTable.html( popupLoxoneDetails_LiveViewError(data) );
	});
	
}

// This function returns an error html if Detail Live data have errors
function popupLoxoneDetails_LiveViewError( data ) {

	$("#valuesLoxoneDetailsLive_title").html(`<span style="color:#f7443b;"><b>${$('#lang_error_live_data_title').text()}</b></span>`);
	
	dataStr = "";
	
	dataStr = `<tr class="LoxoneDetails_tr"><td class="LoxoneDetails_td">${$('#lang_label_information').text()}</td><td class="LoxoneDetails_td">${$('#lang_error_live_query').text()}</td></tr>`;
	
	if( data.code ) {
		dataStr += `<tr class="LoxoneDetails_tr"><td class="LoxoneDetails_td">${$('#lang_label_error').text()}</td><td class="LoxoneDetails_td">${data.code}</td></tr>`;
	}
	if( data.response ) {
		dataStr += `<tr class="LoxoneDetails_tr"><td class="LoxoneDetails_td">${$('#lang_label_original_response').text()}</td><td class="LoxoneDetails_td"><span class="small">${data.response}</span></td></tr>`;
	}
	
	console.log("popupLoxoneDetails_LiveViewError", data);
	
	return dataStr;

}

// Saves all filter properties
function saveFilters() {
	
	localStorage.setItem("s4l_loxone_filters", JSON.stringify(filters));
	// console.log("saveFilters", filters, localStorage.getItem("s4l_loxone_filters"));
}

function restoreFilters() {

	// console.log("restoreFilters", localStorage.getItem("s4l_loxone_filters"));
	
	try {
		filters = JSON.parse( localStorage.getItem("s4l_loxone_filters") );
			
		for( const [key, value] of Object.entries(filters)) {
			checkboxes = $(`input[type="radio"][id="${key}_${value}"]`);
			selects = $(`select[name="${key}"]`);
			
			// console.log("restore", key, value, checkboxes, selects);
			// console.log(key, value);
			
			if( checkboxes.length > 0 ) {
				// console.log("INPUT", checkboxes);
				$(checkboxes).attr("checked", "checked");
				$(`input[type="radio"][name="${key}"]`).checkboxradio("refresh");
			}
			else if( selects.length > 0 ) {
				// console.log("SELECT", $(selects), value);
				$(selects).val(value).selectmenu("refresh");
				if(value != "all")
					$(selects).closest('.ui-btn').addClass('filter-highlight');
			}
			else if( key == "filter_search" ) {
				$(`#${key}`).val( value );
				filterSearchString = value;
				if (filterSearchString != "") {
					// $('#filter_search').css({'backgroundColor':'#FFFF99'});
					$('#filter_search').addClass('filter-highlight');
					$('#filter_search').data("clear-btn", true);
				} else {
					// $('#filter_search').css({'backgroundColor':'white'});
					$('#filter_search').removeClass('filter-highlight');
					$('#filter_search').data("clear-btn", false);
				}

			}
		}
	} catch(e) {
		console.log("restoreFilters Exception catched (filters possibly empty)");
		filters = { };
	}
	
}

function scheduleImport( msno, uid ) {
	
	var control = statsconfigLoxone.find(obj => {
		return obj.uuid === uid && obj.msno == msno })
	console.log("scheduleImport", msno, uid, control );
	if( control ) {
		$("#LoxoneDetails_s4lstatimportbutton")
			.addClass("ui-disabled");
		// Element found in internal data
		$.post( "ajax.cgi", { 
			action : "scheduleimport",
			importtype : "full",
			uuid : uid,
			msno : msno,
			category : control.category,
			description: control.description,
			name : control.name,
			room: control.room,
			type : control.type,
			
		})
		.done(function(data){
			console.log(data);
		})
		.always(function(data){
			getImportSchedulerReport();
		});
	
	} 
	else {
		throw `scheduleImport: ${msno} and ${uid} not found in internal list`;
	}
}

function getImportSchedulerReport() {
	if( !timer ) {
		return;
	}
	if( getImportSchedulerReport_running == true ) {
		return;
	}
	getImportSchedulerReport_running = true;
	$.post( "ajax.cgi", { 
			action : "import_scheduler_report",  
	})
	.done(function(data){
		// console.log("import_scheduler_report done", data);
		imports = Object.keys(data.filelist)
		.map(key => ({file: key, data: data.filelist[key]}));
	
		updateReportTables(data);
	})
	.fail(function(data){
		console.log("import_scheduler_report fail", data);
	})
	.always(function(data){
		getImportSchedulerReport_running = false;
	});
	
}

function updateReportTables(data) {
	
	// Get IDs for Detail View Import status
	var detail_msno = $(".LoxoneDetails_table").data("msno");
	var detail_uuid = $(".LoxoneDetails_table").data("uid");
	$("#LoxoneDetails_importstatus").empty();
	
	// List view generation
	for( imp of imports ) { 
		var data = imp.data;
		var status = imp.data?.status;
		var state = data.status?.status;
		
		var msno = data.msno;
		var uuid = data.uuid;
		// console.log("updateReportTables", msno, uuid, state, status);
		
		// Find 
		var target_tr = $(`tr[data-uid=${uuid}][data-msno=${msno}]`);
		
		
		var target = target_tr.find('.importInfo');
		// console.log("target", target);
		// $(target).html("<b>Found!</b>");

		var endtime_dt = new Date(Math.round(status?.endtime*1000));
		var endtime = endtime_dt.toLocaleString();
		
		var finished_percent;
		var estimatedTimeLeft_min;
		var progress_html;
		
		var html = "";
		
		switch(state) {
			case "running": 
				finished_percent = Math.round (status?.stats?.record_count_finished / (status?.stats?.record_count_finished + status?.stats?.estimate_records_left) * 100 );
				finished_percent = !isNaN(finished_percent) ? finished_percent : 0;
				
				estimatedTimeLeft_min = status?.stats?.estimate_time_left_secs ? "("+Math.ceil((status?.stats?.estimate_time_left_secs/60)).toString()+" min. left)" : "Calculating...";
		
				progress_html = `
				<div class="progress-border">
					<div class="progress-fill" style="height:19px;width:${finished_percent}%">${finished_percent}%</div>
				</div>
				<span class="small grayed">${estimatedTimeLeft_min}</span>`;
				
				html+= progress_html;
				break;
			case "finished":
				// Icon and the time underneath. The word "finished" is what the
				// green tick already says, and it made the column twice as wide
				// as it needs to be.
				html+= icon( "ok", $('#lang_status_finished').text() + " " + endtime )
				     + `<span class="iconline grayed">${endtime}</span>`;
				break;

			case "error":
			case "dead":
				html+= icon( "warn", $('#lang_status_finished_error').text() + " " + endtime )
				     + `<span class="iconline grayed">${endtime}</span>`;
				break;
			case "scheduled":
				html+= icon( "queued", $('#lang_status_queued').text() );
				break;
		}
		
		// Update Detail View Import status
		if( detail_msno == msno && detail_uuid == uuid ) {
			$("#LoxoneDetails_importstatus").html(html);
		}
		
		$(target).html(html);
		
	}
	
}

// Validates a measurementname and returns a suggestion if not valid
// measurementname is the string to verify
// selfIndex is the index key in statsconfigLoxone of itself (otherwise it may find itself)
// Is the interval in the details popup at least the minimum from the System tab?
//
// Marks the field and shows the reason when it is not, and returns false so the
// caller can leave the value unsaved. An empty or disabled field is not a
// complaint - it means the statistic is off, and the checkbox handler fills a
// number in as soon as it is switched on.
function s4lIntervalOk() {
	var field = $("#LoxoneDetails_s4lstatinterval");
	var warn  = $("#LoxoneDetails_s4lstatintervalwarn");
	var row   = $("#LoxoneDetails_s4lstatintervalwarnrow");
	var min   = parseInt( $("#s4l_min_interval_minutes").text() );
	if( isNaN( min ) || min < 1 ) min = 1;

	var val = parseInt( field.val() );
	var bad = !field.prop("disabled") && !isNaN( val ) && val < min;

	if( bad ) {
		field.css({ "border-color": "#c0392b", "background-color": "#ffecec" });
		warn.text( $("#lang_stat_too_fast").text().replace( "__N__", min ) );
		// The row, not the text: it spans the table and must not appear as an
		// empty band while everything is in order.
		row.show();
	}
	else {
		field.css({ "border-color": "", "background-color": "" });
		warn.text("");
		row.hide();
	}
	return !bad;
}

function validateMeasurementname( measurementname, msno, uid ) {
	
	// Find own array index in statsconfigLoxone
	var selfIndex = statsconfigLoxone.findIndex( obj => { return obj.uuid === uid && obj.msno == msno })
	
	if( typeof measurementname === 'undefined' || measurementname == "" ) {
		// Check if statsconfigLoxone already knows name or description
		// console.log( "1st try: measurementname is undefined" );
		measurementname = statsconfigLoxone[selfIndex]?.description ? statsconfigLoxone[selfIndex].description : statsconfigLoxone[selfIndex]?.name;
	}
	console.log("measurementname", measurementname);
	var measurementnameDefault = measurementname;
	
	if( typeof measurementname === 'undefined') {
		console.log( "2st try: measurementname is undefined" );
		throw "measurementname is empty. Must be defined for validation.";
	}
	
	// Retrying different things
	var counter =-1;
	while(1) {
		counter++;
		// console.log("----------------", counter, "---------------");
		switch(counter) {
			case 0:
				break;
			case 1:
				if( statsconfigLoxone[selfIndex]?.name && measurementname == statsconfigLoxone[selfIndex].name) 
					measurementname = statsconfigLoxone[selfIndex].name;
				else
					continue;
				break;
			// Anyone with more than 20 blocks of the same name hit this wall -
			// the suffix search simply gave up (issue #132). 200 is still a
			// safeguard against an endless loop, but no longer a limit anybody
			// reaches in practice.
			case 200:
				throw `Could not find an alternative measurementname after ${counter} tries`;
			default:
				measurementname = measurementnameDefault+"_"+counter.toString();
		}
		
		// Check if measurementname is already defined
		var foundIndex = statsconfigLoxone.findIndex( function(obj, index) {
			// console.log("findIndex", measurementname, selfIndex, obj["measurementname"], index);
			if(selfIndex == index) { return false };
			if(obj["measurementname"] != measurementname) { return false; }
			return true;
		})
		
		// console.log("Try", counter, measurementname, foundIndex);
		
		if(foundIndex == -1) {
			break;
		}
	}
	
	// console.log("foundIndex", foundIndex);
	return measurementname.trim();
}


function clearTimer() {
	console.log("Timer cleared");
	window.clearInterval(timer);
	timer = false;
}

function setTimer() {
	console.log("Timer set");
	timer = window.setInterval(getImportSchedulerReport, timer_interval);
}

function restore_hints_hide() {
	
	try {
		hints_hide = JSON.parse( localStorage.getItem("s4l_loxone_hints_hide") );
		if( hints_hide == null ) {
			hints_hide = { };
		}
	} 
	catch(e) {
		console.log("restore_hints_hide", e);
		hints_hide = { };
	}
}

function hint_hide(hintid) {
	hints_hide[hintid] = true;
	$("#"+hintid).fadeOut();
	localStorage.setItem("s4l_loxone_hints_hide", JSON.stringify(hints_hide)); 
}


// Sort function for arrays of objects
// https://stackoverflow.com/a/4760279/3466839
// Usage: arrayOfObjects.sort(dynamicSortMultiple("Name", "-Surname"));

function dynamicSort(property) {
    var sortOrder = 1;
    if(property[0] === "-") {
        sortOrder = -1;
        property = property.substr(1);
    }
    return function (a,b) {
        /* next line works with strings and numbers, 
         * and you may want to customize it to your needs
         */
        var result = (a[property] < b[property]) ? -1 : (a[property] > b[property]) ? 1 : 0;
        return result * sortOrder;
    }
}

function dynamicSortMultiple() {
    /*
     * save the arguments object as it will be overwritten
     * note that arguments object is an array-like object
     * consisting of the names of the properties to sort by
     */
    var props = arguments;
    return function (obj1, obj2) {
        var i = 0, result = 0, numberOfProperties = props.length;
        /* try getting a different result from 0 (equal)
         * as long as we have extra properties to compare
         */
        while(result === 0 && i < numberOfProperties) {
            result = dynamicSort(props[i])(obj1, obj2);
            i++;
        }
        return result;
    }
}

// https://stackoverflow.com/a/22581382/3466839
function copyToClipboard(elem) {
	  // create hidden text element, if it doesn't already exist
    var targetId = "_hiddenCopyText_";
    var isInput = elem.tagName === "INPUT" || elem.tagName === "TEXTAREA";
    var origSelectionStart, origSelectionEnd;
    if (isInput) {
        // can just use the original source element for the selection and copy
        target = elem;
        origSelectionStart = elem.selectionStart;
        origSelectionEnd = elem.selectionEnd;
    } else {
        // must use a temporary form element for the selection and copy
        target = document.getElementById(targetId);
        if (!target) {
            var target = document.createElement("textarea");
            target.style.position = "absolute";
            target.style.left = "-9999px";
            target.style.top = "0";
            target.id = targetId;
            document.body.appendChild(target);
        }
        target.textContent = elem.textContent;
    }
    // select the content
    var currentFocus = document.activeElement;
    target.focus();
    target.setSelectionRange(0, target.value.length);
    
    // copy the selection
    var succeed;
    try {
    	  succeed = document.execCommand("copy");
    } catch(e) {
        succeed = false;
    }
    // restore original focus
    if (currentFocus && typeof currentFocus.focus === "function") {
        currentFocus.focus();
    }
    
    if (isInput) {
        // restore prior selection
        elem.setSelectionRange(origSelectionStart, origSelectionEnd);
    } else {
        // clear temporary content
        target.textContent = "";
    }
    return succeed;
}
