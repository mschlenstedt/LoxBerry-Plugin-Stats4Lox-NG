let miniservers;
let miniservers_used = [];
let rooms;
let rooms_used;
let categories;
let categories_used = [];
let controls;
let statsconfig;
let statsconfigLoxone;
let controlstable = "";
let elementTypes_used = [];

let filters = [];

$(function() {
	miniservers = JSON.parse( $("#miniservers").text() );
	getLoxplan();
	
	// Create filter radio bindings
	$('.filter_radio, .filter_select').bind( "change", function(event, ui){
		var filter_parent = event.currentTarget.name;
		console.log( "filter_select", event, ui );
		
		if( event.currentTarget.nodeName == "INPUT" ) {
			var filterval = $("input[name='"+filter_parent+"']:checked").val();
		}
		if( event.currentTarget.nodeName == "SELECT" ) {
			var filterval = $("#"+filter_parent+" option:selected").val();
		}
		
		console.log("Filter parent", filter_parent, filterval);
		filters[filter_parent] = filterval;
		
		// After changing the filter, recreate the table
		updateTable();
	});
	// Bind rows
	// Create S4L Stat change bindings
	jQuery(document).on('focusout','.s4lchange',function (event, ui) {
		target = event.target;
		uid = $(target).closest('tr').data("uid");
		var control = controls.find( obj => { return obj.UID === uid })
		
		var is_active; 
		var interval = parseInt($(target).val());
		if( interval == "" || interval <= 0 ) {
			$(target).val("");
			interval = 0;
			is_active = "false";
		} else {
			is_active = "true";
		}
		console.log( "s4lchange", event, ui, uid, control, interval, is_active );
		
		
		
		$.post( "ajax.cgi", { 
			action : "updatestat",  
			name : control.Title,
			description :control.Desc,
			uuid : uid,
			type : control.Type,
			category : control.Category,
			room: control.Place,
			interval: interval,
			active: is_active,
			msno : control.msno,
			outputs : "0"
		})
			.done(function(data){
				if( is_active == "true" ) 
					$(target).closest('div').addClass("s4l_interval_highlight");
				else
					$(target).closest('div').removeClass("s4l_interval_highlight");
			});
			
		
		
		
		
	});
	
	
});

function getLoxplan() {
	$("#popupProgress").popup("open");
	var msupdateTextPre = "Fetching Loxone Config from Miniservers...";
	$("#progressState").html(msupdateTextPre);
	
	// Get elements of all Miniservers
	var async_request=[];
	var responses=[];
	for (msno in miniservers) {
		async_request.push(
			$.post( "ajax.cgi", { action : "getloxplan", msno : msno }, function(data){
				console.log(data);
				responses.push(data);
			})
		);
	}
	async_request.push(
		$.post( "ajax.cgi", { action : "getstatsconfig" }, function(data){
			statsconfig = data;
			statsconfigLoxone = Object.values( statsconfig.loxone );
		})
	)
				
	
	$.when.apply( null, async_request).done( function(){
		$("#progressState").html("Preparing controls...");
		consolidateLoxPlan( responses );
		$("#progressState").html("Generating display...");
		updateTable();
		$("#popupProgress").popup("close");
		$("#progressState").html("");
		
	});
}

function consolidateLoxPlan( data ) {

	for (const [key, msobj] of Object.entries(data)) {
	  rooms = $.extend( rooms, data[key].rooms );
	  rooms_used = $.extend( rooms_used, data[key].rooms_used );
	  categories = $.extend( categories, data[key].categories );
	  categories_used = $.extend( categories_used, data[key].categories_used );
	  miniservers_used = $.extend ( miniservers_used, data[key].miniservers );
	  elementTypes_used = elementTypes_used.concat( data[key].elementTypes );
	  if( typeof controls == "undefined" ) 
		controls = data[key].controls;
	  else
		controls = Object.assign( controls, data[key].controls );
	}
	
	// Create array from controls object
	controls = Object.values(controls);
	
	// Uniquify elementTypes_used
	elementTypes_used = elementTypes_used.filter( function(item, pos) {
		return elementTypes_used.indexOf(item) == pos;
	})
	elementTypes_used.sort();
	miniservers_used.sort();
	
	// console.log("controls array", controls);
	
// console.log("Controls", controls);
	
	var rooms_tmp = [];
	for (var roomid in rooms) {
		if(! roomid in rooms_used ) continue; 
		rooms_tmp.push([rooms[roomid], roomid]);
	}
	rooms = rooms_tmp.sort();
	
	var cat_tmp = [];
	for (var catid in categories) {
		if(! catid in categories_used ) continue; 
		cat_tmp.push([categories[catid], catid]);
	}
	categories = cat_tmp.sort();
	
	generateFilter();
	
}

function generateFilter() {

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
	
	// Add used elements to options in native language
	var elementsArr = [];
	for( var key in elementTypes_used ) {
		var ucKey =  typeof elementTypes_used[key] !== "undefined" ? elementTypes_used[key].toUpperCase() : "undefined";
		elementsArr.push( [ ucKey, typeof loxone_elements[ucKey] !== "undefined" ? loxone_elements[ucKey] : ucKey ] );
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
	
	controlstable += `
	<table class="controlstable">
	<tr>
		<th>MS</th>
		<th>Name (Type)</th>
		<th>Location</th>
		<th>Infos</th>
		<th>Statistics</th>
	</tr>
	`;
	
}

function createTableEnd() {
	controlstable += `</table>`;
}

function createTableBody() {

	for( elementno in controls ) {
		element = controls[elementno];
		
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
		var statmatch = statsconfigLoxone.find(obj => {
			return obj.uuid === element.UID
		})
		if( typeof filters["filter_s4lstat"] !== "undefined" && filters["filter_s4lstat"] != "all") {
			if( filters["filter_s4lstat"] == "on" && typeof statmatch === "undefined" ) continue;
			if( filters["filter_s4lstat"] == "off" && typeof statmatch !== "undefined" ) continue;
		}
		
		
		//
		// Create row section
		//
		
		controlstable += `<tr class="controlstable_tr" data-uid="${element.UID}">`;
		
		// Miniserver
		controlstable += `<td>${element.msno}</td>`;
		
		// Name (Type)
		controlstable += `<td>${element.Title}`;
		if(typeof element.Desc != "undefined" && element.Desc != "" ) 
			controlstable += `<br>${element.Desc}`;
		var TypeLocal = loxone_elements[ element.Type.toUpperCase() ];
		controlstable += `<br><span class="small">${TypeLocal}</span>`;
		
		
		// Location
		controlstable += `<td>${element.Place}
			<br>${element.Category}
			</td>`;
		
		// Info section
		controlstable += `<td></td>`;
		
		// Statistics
		controlstable += `<td>`;
		
		
		let highlightclass = "";
		if (statmatch != undefined) {
			// controlstable += "Statistics enabled";
			s4l_interval = statmatch.interval/60;
			highlightclass = "s4l_interval_highlight";
		}
		else {
			s4l_interval = "";
			// controlstable += "Not enabled";
		}
		
		controlstable += `
			 
			<label for="s4l_interval" data-mini="true">Interval (minutes)</label>
			<div class="ui-input-text ui-body-inherit ui-corner-all ui-shadow-inset ui-input-has-clear ${highlightclass}">
				<input type="number" data-clear-btn="true" name="s4l_interval" pattern="[0-9]*" value="${s4l_interval}" class="s4lchange" min="0" max="9999">
				<a href="#" tabindex="-1" aria-hidden="true" class="ui-input-clear ui-btn ui-icon-delete ui-btn-icon-notext ui-corner-all ui-input-clear-hidden" title="Clear text">Clear text</a>
			</div>`;
		
		
		
		controlstable += `</td>`;
		
		// End of row
		
		controlstable += `</tr>`;
		
	}
	
}
