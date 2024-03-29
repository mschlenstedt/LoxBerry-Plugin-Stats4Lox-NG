let miniservers;
let miniservers_used = [];
let rooms;
let rooms_used;
let categories;
let categories_used = [];
let controls = [];
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
	getLoxplan();
	
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
	
	// Bind Import Now button
	jQuery(document).on('click', '#LoxoneDetails_s4lstatimportbutton', function(event, ui){
		target = event.target;
		uid = $(target).data("uid");
		msno = $(target).data("msno");
		scheduleImport(msno, uid);
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
			
			try {
				statsconfig = data;
				statsconfigLoxone = Object.values( statsconfig.loxone );
			}
			catch(e) {
				// $("#progress_errors").append( "<p>Could not get stats.json data. Assuming empty stats.json</p>");
				// $("#box_progress_errors").fadeIn();
				console.log( "statsconfigLoxone seems to be empty" );
				statsconfigLoxone = [];
			}
		})
	)
				
	
	$.when.apply( null, async_request).done( function(){
		$("#progressState").html("Preparing controls...");
		consolidateLoxPlan( responses );
		$("#progressState").html("Generating display...");
		updateTable();
		$("#popupProgress").popup("close");
		$("#progressState").html("");
		setTimer();
		getImportSchedulerReport();
		
		
	});
}

function consolidateLoxPlan( data ) {

	for (const [key, msobj] of Object.entries(data)) {
	  
	  if( data[key]?.error ) {
		console.log( "Error", data[key] );
		$("#progress_errors").append( "<p>"+data[key]?.error+"</p>" );
		$("#box_progress_errors").fadeIn();
	  }
	  
	  
	  rooms = $.extend( rooms, data[key].rooms );
	  rooms_used = $.extend( rooms_used, data[key].rooms_used );
	  categories = $.extend( categories, data[key].categories );
	  categories_used = $.extend( categories_used, data[key].categories_used );
	  miniservers_used = $.extend ( miniservers_used, data[key].miniservers );
	  elementTypes_used = elementTypes_used.concat( data[key].elementTypes );
	  
	  if( typeof data[key].controls !== "undefined" ) {
	     console.log( "controls from key", key, Object.keys(data[key].controls).length );
		 var objarr = Object.values( data[key].controls );
		 controls = controls.concat( objarr );
	  }
	
	}
	
	// Sort controls by Title
	controls = controls.filter ( control => control.msno > 0 ); // Filter controls not on an MS in LoxBerry
	controls.sort( dynamicSortMultiple( "Title" ) );
	
	// Uniquify elementTypes_used
	elementTypes_used = elementTypes_used.filter( function(item, pos) {
		return elementTypes_used.indexOf(item) == pos;
	})
	elementTypes_used.sort();
	
	// Uniquify categories_used
	// categories_used = categories_used.filter( function(item, pos) {
		// return categories_used.indexOf(item) == pos;
	// })

	miniservers_used = Object.values( miniservers_used );
	miniservers_used = miniservers_used.filter( item => item.msno > 0 ); // Filter MS that are not in LoxBerry
	miniservers_used.sort( dynamicSort( "msno" ) );

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
		if(categories_used.includes(catid)) {
			cat_tmp.push([categories[catid], catid]);
		}
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
	
	controlstable += `
	<table class="controlstable">
	<tr>
		<th>MS</th>
		<th>Name (Type)</th>
		<th>Location</th>
		<th>Statistics</th>
		<th>Import</th>
	</tr>
	`;
	
}

function createTableEnd() {
	controlstable += `</table>`;
}

function createTableBody() {

	var filterSearchStr_lc = filterSearchString.toLowerCase();

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
		var statmatchkey = statsconfigLoxone.findIndex(obj => {
			return obj.uuid === element.UID && obj.msno == element.msno
		})
		var statmatch = statsconfigLoxone[statmatchkey];
		if( typeof filters["filter_s4lstat"] !== "undefined" && filters["filter_s4lstat"] != "all") {
			if( filters["filter_s4lstat"] == "on" && ( typeof statmatch === "undefined" || statmatch.active !== "true" ) ) continue;
			if( filters["filter_s4lstat"] == "off" && typeof statmatch !== "undefined" &&  statmatch.active === "true" ) continue;
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
		
		controlstable += `<tr class="controlstable_tr" data-uid="${element.UID}" data-msno="${element.msno}">`;
		
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
		controlstable += `<td class="center" style="min-width:150px">`;
		var checkedImg = `<img src="images/checkbox_checked_20.png">`;
		var uncheckedImg = `<img src="images/checkbox_unchecked_20.png">`;
		var statDisplay;
		if (statmatch?.active === "true" ) {
			statDisplay = "";
			s4l_interval = statmatch.interval/60;
		}
		else {
			statDisplay = "display:none;";
			s4l_interval = "";
			
			// controlstable += "Not enabled";
		}

		controlstable += `<div class="statdata" id="statskey-${statmatchkey}" style="${statDisplay}">`;
			// controlstable += "Statistics enabled";
			
		controlstable += checkedImg;
		controlstable += `&nbsp;<span name="s4l_interval">${s4l_interval}</span> minutes`;
		controlstable += `</div>`;
		
		controlstable += `</td>`;

		// Import section
		controlstable += `
		<td class="importInfo" style="min-width:100px">
		
		
		</td>`;

		// Button section
		controlstable += `
			<td>
			<a href="#" class="ui-btn ui-icon-eye ui-corner-all ui-mini ui-btn-inline btnLoxoneDetails">Settings</a>
			</td>`;
		
		
		
		// End of row
		
		controlstable += `</tr>`;
		
	}
	
}

function popupLoxoneDetails( uid, msno ) {
	$("#popupLoxoneDetails").popup("option","positionTo","window"); 
	$("#popupLoxoneDetails").popup("open");
	if(hints_hide?.hint_importbutton != true) {
		$("#hint_importbutton").show();
	}
	//$("#contentLoxoneDetails #valuesLoxoneDetails").empty();
	var control = controls.find( obj => { return obj.UID === uid && obj.msno == msno })
	
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
	
	$("#LoxoneDetails_typelabel").text("Type");
	var TypeLocal = loxone_elements[control.Type?.toUpperCase()]?.localname;
	if(typeof TypeLocal == "undefined") 
		TypeLocal = control.Type?.toUpperCase();
	$("#LoxoneDetails_type").text(TypeLocal);
	$("#LoxoneDetails_typehover").prop("title", control.Type);
	
	
	$("#LoxoneDetails_miniserver").text(miniservers[control.msno].Name+' ('+control.msno+')');
	
	$("#LoxoneDetails_pagelabel").text(loxone_elements['PAGE'].localname);
	$("#LoxoneDetails_page").html( control.Page ? control.Page : "&nbsp;" );
	
	// Icons
	var isLoxVisu = control.Visu === "true" ? true : false;
	var checkedImg = `<img src="images/checkbox_checked_20.png">`;
	var uncheckedImg = `<img src="images/checkbox_unchecked_20.png">`;
	
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
	
	$("#valuesLoxoneDetailsLive_title").html("Updating data...");
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
			$("#valuesLoxoneDetailsLive_title").html(`Live Data from Miniserver ${miniservers[control.msno].Name}`);
			
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
				data.response[key].mapImg = data.response[key].mapString != "" ? `<img src="images/import_icon.png" style="vertical-align:text-top;">` : "";
				
				// Special string for Default output
				if( outputKey == "Default" ) {
					data.response[key].localdesc = data.response[key].Unit ? data.response[key].Unit + " " : "";
					data.response[key].localdesc += "(Decimal accuracy possibly limited. Use AQ/Q instead if available.)";
				} 
				else {
					try {
						data.response[key].localdesc = loxone_elements[control.Type?.toUpperCase()]?.OL[outputName];
					} catch {
						data.response[key].localdesc == undefined;
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

	$("#valuesLoxoneDetailsLive_title").html(`<span style="color:#f7443b;"><b>Error getting Live data</b></span>`);
	
	dataStr = "";
	
	dataStr = `<tr class="LoxoneDetails_tr"><td class="LoxoneDetails_td">Information</td><td class="LoxoneDetails_td">Could not query Live data. Possibly S4L has no permissions to this block, or the block isself has no data to return.</td></tr>`;
	
	if( data.code ) {
		dataStr += `<tr class="LoxoneDetails_tr"><td class="LoxoneDetails_td">Error</td><td class="LoxoneDetails_td">${data.code}</td></tr>`;
	}
	if( data.response ) {
		dataStr += `<tr class="LoxoneDetails_tr"><td class="LoxoneDetails_td">Original response</td><td class="LoxoneDetails_td"><span class="small">${data.response}</span></td></tr>`;
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
				html+= `<img src="images/checkbox_checked_20.png"> <span class="small grayed">Finished ${endtime}</span>`;
				break;
				
			case "error":
			case "dead":
				html+= `
					<img src="images/checkbox_alert_20.png"> <span class="small grayed">Finished with error ${endtime}</span>`;
				break;
			case "scheduled":
				html+= `<img src="images/checkbox_scheduled_20.png"> <span class="small grayed">Queued</span>`;
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
			case 20:
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
