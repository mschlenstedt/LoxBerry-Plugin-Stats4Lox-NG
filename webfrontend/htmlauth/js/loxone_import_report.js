let miniservers;
let miniservers_used = [];

let hints_hide = {};

let imports = [];

let timer;

$(function() {
	
	restore_hints_hide();
	if(hints_hide?.hint_activatestatistics != true) {
		$("#hint_activatestatistics").show();
	}
	
	miniservers = JSON.parse( $("#miniservers_json").text() );

	getImportSchedulerReport();
	
	timer = window.setInterval(getImportSchedulerReport, 1000);

	
});
	
	
function getImportSchedulerReport() {
	$.post( "ajax.cgi", { 
			action : "import_scheduler_report",  
	})
	.done(function(data){
		console.log("import_scheduler_report done", data);
		updateReportTables(data);
	})
	.fail(function(data){
		console.log("import_scheduler_report fail", data);
	});
	
}

function updateReportTables(data) {
	
	
	// imports = Object.values(data.filelist);
	// imports.sort( dynamicSortMultiple( "msno", "uuid" ) );
	
	imports = Object.keys(data.filelist)
		.map(key => ({file: key, data: data.filelist[key]}));
	
	var count_running = Object.keys(data.states?.running).length;
	var count_scheduled = Object.keys(data.states?.scheduled).length;
	var count_finished = Object.keys(data.states?.finished).length;
	var count_error = Object.keys(data.states?.error).length;
	var count_dead = Object.keys(data.states?.dead).length;

	var hR = "";
	var hS = "";
	var hF = "";
	var hE = "";
	var hD = "";
	
	// debugger;
	
	for( imp of imports ) {
		
		var status = imp.data.status;
		
		var starttime_dt = new Date(Math.round(status?.starttime*1000));
		var starttime = starttime_dt.toLocaleString('en-GB', { hour:'numeric', minute:'numeric', second:'numeric', hour12:false } );
			
		var endtime_dt = new Date(Math.round(status?.endtime*1000));
		var endtime = endtime_dt.toLocaleString('en-GB', { hour:'numeric', minute:'numeric', second:'numeric', hour12:false } );
		
		var statustime_dt = new Date(Math.round(status?.statustime*1000));
		var statustime = statustime_dt.toLocaleString('en-GB', { hour:'numeric', minute:'numeric', second:'numeric', hour12:false } );
		
		
		if( data.states?.running[imp.file] ) {
			
			
			var finished_percent = Math.round (status?.stats?.record_count_finished / (status?.stats?.record_count_finished + status?.stats?.estimate_records_left) * 100 );
			finished_percent = !isNaN(finished_percent) ? finished_percent : 0;
			
			var starttime_dt = new Date(Math.round(status?.starttime*1000));
			var starttime = starttime_dt.toLocaleString('en-GB', { hour:'numeric', minute:'numeric', second:'numeric', hour12:false } );
			
			var estimatedEnd_dt = new Date(Math.round((status?.starttime+status?.stats?.duration_time_secs+status?.stats?.estimate_time_left_secs)*1000));
			estimatedEnd = estimatedEnd_dt.toLocaleString('en-GB', { hour:'numeric', minute:'numeric', second:'numeric', hour12:false } );
			
			var current = status?.current != null ? status?.current.substr(0,4) + '/' + status?.current.substr(4,2) : "";
			
			hR+=`
			<tr>
				<td>
					<span class="small grayed">Miniserver</span><br>
					${imp.data.msno}
				</td>
				<td>
					${status.name}<br>
					<span class="small grayed">${imp.data.uuid}</span>
				</td>
				<td>
					<span class="small grayed">Started</span><br>
					${starttime}
				</td>
				<td style="min-width:80px;">
					<span class="small grayed">Progress</span><br>
					<div class="progress-border">
						<div class="progress-fill" style="height:15px;width:${finished_percent}%">${finished_percent}%</div>
					</div>
				</td>
				<td>
					<span class="small grayed">Current month</span><br>
					${current}
				</td>
				<td>
					<span class="small grayed">Estimated end</span><br>
					${estimatedEnd}
				</td>
			</tr>`;
		}
		else if ( data.states?.scheduled[imp.file] ) {
			
			
			hS+=`
			<tr>
				<td>
					<span class="small grayed">Miniserver</span><br>
					${imp.data.msno}
				</td>
				<td>
					${status.name}<br>
					<span class="small grayed">${imp.data.uuid}</span>
				</td>
			</tr>
			`;
			
		}
		else if ( data.states?.finished[imp.file] ) {

			var duration = status.duration ? Math.ceil(status.duration/60).toString()+" Min." : "N/A"; 
			var records = status?.stats?.record_count_finished ? status?.stats?.record_count_finished.toString().replace(/\B(?=(\d{3})+(?!\d))/g, ".") : "";
			
			hF+=`
			<tr>
				<td>
					<span class="small grayed">Miniserver</span><br>
					${imp.data.msno}
				</td>
				<td>
					${status.name}<br>
					<span class="small grayed">${imp.data.uuid}</span>
				</td>
				<td>
					<span class="small grayed">Started</span><br>
					${starttime}
				</td>
				<td>
					<span class="small grayed">Finished</span><br>
					${endtime}
				</td>
				<td>
					<span class="small grayed">Duration</span><br>
					${duration}
				</td>
				<td>
					<span class="small grayed">Imported records</span><br>
					${records}
				</td>
			</tr>
			`;
		
		
		
		
		
		}
		else if ( data.states?.error[imp.file] ) {
		
			var duration = imp.data.duration ? Math.ceil(imp.data.duration/60) : ""; 
			var records = status?.stats?.record_count_finished ? status?.stats?.record_count_finished.toString().replace(/\B(?=(\d{3})+(?!\d))/g, ".") : "";
			
			var current = status?.current != null ? status?.current.substr(0,4) + '/' + status?.current.substr(4,2) : "";
			
			hE+=`
			<tr>
				<td>
					<span class="small grayed">Miniserver</span><br>
					${imp.data.msno}
				</td>
				<td>
					${status.name}<br>
					<span class="small grayed">${imp.data.uuid}</span>
				</td>
				<td>
					<span class="small grayed">Started</span><br>
					${starttime}
				</td>
				<td>
					<span class="small grayed">Finished (with error)</span><br>
					${endtime}
				</td>
				<td>
					<span class="small grayed">Error on month</span><br>
					${current}
				</td>
			</tr>
			`;
			
			
			
		
		}
		else if ( data.states?.dead[imp.file] ) {
			
			
			hD+=`
			<tr>
				<td>
					<span class="small grayed">Miniserver</span><br>
					${imp.data.msno}
				</td>
				<td>
					${status.name}<br>
					<span class="small grayed">${imp.data.uuid}</span>
				</td>
				<td>
					<span class="small grayed">Started</span><br>
					${starttime}
				</td>
				<td>
					<span class="small grayed">Last Update of Import</span><br>
					${statustime}
				</td>
				<td>
					<span class="small grayed">Error on month</span><br>
					${current}
				</td>
			</tr>
			`;
		
		
		}
	}
	
	if( !hR ) {
		hR = `<tr><td>Currently no running imports.</td></tr>`
	}
	if( !hS ) {
		hS = `<tr><td>Currently no waiting imports.</td></tr>`
	}
	if( !hF ) {
		hF = `<tr><td>No imports finished yet.</td></tr>`
	}
	if( !hE ) {
		hE = `<tr><td>No imports with errors.</td></tr>`
	}
	if( !hD ) {
		hD = `<tr><td>No dead imports.</td></tr>`
	}
	
	
	$("#data_importreport_running tbody").empty().html(hR);
	$("#data_importreport_scheduled tbody").empty().html(hS);
	$("#data_importreport_finished tbody").empty().html(hF);
	$("#data_importreport_error tbody").empty().html(hE);
	$("#data_importreport_dead tbody").empty().html(hD);

	
	
	
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