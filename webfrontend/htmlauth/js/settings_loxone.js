let miniservers;
let rooms;
let rooms_used;
let categories;
let categories_used = [];
let controls;

$(function() {
	miniservers = JSON.parse( $("#miniservers").text() );
	getLoxplan();
	
	
});

function getLoxplan() {
	$("#popupProgress").popup("open");
	$("#progressState").html("Fetching Loxone Config from Miniservers");
	
	// Get elements of all Miniservers
	var async_request=[];
	var responses=[];
	for (msno in miniservers) {
		async_request.push(
			$.post( "ajax.cgi", { action : "getloxplan", msno : msno }, function(data){
				console.log("Updated ", msno);
				responses.push(data);
			})
		);
	}
	
	$.when.apply( null, async_request).done( function(){
		$("#progressState").html("Prepare for displaying");
		consolidateLoxPlan( responses );
		$("#popupProgress").popup("close");
		// $("#progressState").html("");
		
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
