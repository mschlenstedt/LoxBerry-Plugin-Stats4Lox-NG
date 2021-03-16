let miniservers;
let rooms;
let rooms_used;
let categories;
let categories_used = [];
let controls;
let statsconfig;
let statsconfigLoxone;
let controlstable = "";

$(function() {
	miniservers = JSON.parse( $("#miniservers").text() );
	getLoxplan();
	
	
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
	  if( typeof controls == "undefined" ) 
		controls = data[key].controls;
	  else
		controls = Object.assign( controls, data[key].controls );
	}
	
	// Create array from controls object
	controls = Object.values(controls);
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
	updateTable();
}

function generateFilter() {

	// Add Miniservers to options
	
	for( const [key, msobj] of Object.entries(miniservers) ) {
		$('#filter_miniserver').append(
		`<option value="${key}">(${key}) ${msobj.Name}</option>`); 
	}

	for( obj of rooms ) {
		// console.log(obj);
		$('#filter_room').append(
		`<option value="${obj[1]}">${obj[0]}</option>`); 
	}

	for( obj of categories ) {
		// console.log(obj);
		$('#filter_category').append(
		`<option value="${obj[1]}">${obj[0]}</option>`); 
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
		console.log(element);
		
		// Filter section
		
		// To do: Skip to next if any of the filters apply 
		
		//
		// Create row section
		//
		
		controlstable += `<tr class="controlstable_tr">`;
		
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
		
		// Info statistics
		controlstable += `<td>`;
		var statmatch = statsconfigLoxone.find(obj => {
			return obj.uuid === element.UID
		})
		
		if (statmatch != undefined) {
			controlstable += "Statistics enabled";
		}
		else {
			controlstable += "Statistics not enabled";
		}
		controlstable += `</td>`;
		
		// End of row
		
		controlstable += `</tr>`;
		
		
		
		
		
	}
	
}
