let mqttlivedata = [];
let mqttlivestate = {};
let mqttliveobjlist;
let statsconfig;
let statsconfigLoxone;

let hints_hide = {};


let timer = false;
let timer_interval = 1000;
let getmqttlivedata_running = false;

$(function() {
	
	restore_hints_hide();
	if(hints_hide?.hint_mqttliveupdate_intro != true) {
		$("#hint_mqttliveupdate_intro").show();
	}
	
	// miniservers = JSON.parse( $("#miniservers_json").text() );

	setTimer();
	getMqttliveData();
	createStatsjsonTable();
	
	// Bind Copy Clipboard button
	jQuery(document).on('click', '.copyClipboard', function(event, ui){
		var target = $(this).next('input');
		$(target).removeClass("datahidden");
		target[0].select();
		document.execCommand("copy");
		$(target).addClass("datahidden");
		
		return;
		console.log("Copy target", target[0]);
		copyToClipboard(target[0]);
	});
	
	// Bind Clear UI Data ("Clear Display") button
	jQuery(document).on('click', '.clearuidataButton', function(event, ui){
		$.post( "ajax.cgi", { 
			action : "mqttlive_clearuidata",
			basetopic: mqttlivestate?.broker_basetopic
		})
	});
	
});
	
	
function getMqttliveData() {
	if( !timer ) {
		return;
	}
	if( getmqttlivedata_running == true ) {
		return;
	}
	
	if (getSelectedText()) {
		// Do nothing if text is selected
		return; 
	}
	
	getmqttlivedata_running = true;
	$.post( "ajax.cgi", { 
			action : "getmqttlivedata",  
	})
	.done(function(data){
		// console.log("import_scheduler_report done", data);
		if( data.topics ) {
			mqttlivedata = Object.keys(data.topics)
			.map(key => ({topic: key, data: data.topics[key]}));
			mqttlivedata.sort( dynamicSortMultiple("topic"));
			
		} else {
			mqttlivedata = undefined;
		}
		
		if( data.state ) {
			mqttlivestate = data.state;
		} else {
			mqttlivestate = undefined;
		}
	
		updateTables();
	})
	.fail(function(data){
		console.log("getMqttliveData fail", data);
	})
	.always(function(data){
		getmqttlivedata_running = false;
	});
	
}

function updateTables() {
	
	if (getSelectedText()) {
				// console.log("Text is selected");
	return; }
	
	
	if( mqttlivestate ) {
		// Update mqttlive state
		$("#mqttlivestate_broker_basetopic").html(mqttlivestate?.broker_basetopic);
		
		if( mqttlivestate?.broker_connected == true ) {
			broker_connected = "Connected";
			$("#mqttlivestate_broker_connected").css( "color", "green" );
		} 
		else {
			broker_connected = "Not connected";
			$("#mqttlivestate_broker_connected").css( "color", "red" );
		}
		$("#mqttlivestate_broker_connected").html(broker_connected);
		
		if( mqttlivestate?.broker_error ) {
			$("#mqttlivestate_broker_error").html(mqttlivestate?.broker_error).css( "color", "red" );
		} else {
			$("#mqttlivestate_broker_error").empty();
		}
			
	
	}
	
	// Update mqttlive topics
	if( !mqttlivedata ) {
		html = `<p>No data arrived yet :-(</p>`;
	}
	else {
		html = ``;
		for( topic of mqttlivedata ) {
			
			if( topic.data.values[0] ) {
				outputlabel = topic.data.values[0].key;
				outputdata = topic.data.values[0].value;
			}
			var arrived_dt = new Date(Math.round(topic.data.timestamp_epoch*1000));
			var arrived = arrived_dt.toLocaleString();
			
			timedelta = (Date.now() - topic.data.timestamp_epoch*1000) / 1000;
			
			if( timedelta < 4 ) backgroundcolor="#ffff00";
			else if( timedelta < 8 ) backgroundcolor="#ebec52";
			else if( timedelta < 12 ) backgroundcolor="#d8d876";
			else if ( timedelta < 20 ) backgroundcolor="#dbd880";
			else if ( timedelta < 28 ) backgroundcolor="#ddd889";
			else if ( timedelta < 36 ) backgroundcolor="#dfd893";
			else if ( timedelta < 44 ) backgroundcolor="#e1d89d";
			else if ( timedelta < 52 ) backgroundcolor="#e2d9a6";
			else if ( timedelta < 62 ) backgroundcolor="#e2d9b0";
			else if ( timedelta < 120 ) backgroundcolor="#e1dac3";
			else if ( timedelta < 240 ) backgroundcolor="#e0dbcd";
			else if ( timedelta < 300 ) backgroundcolor="#dedcd7";
			else backgroundcolor = "#efefef";
			
			
			html+= `<div style="display:flex;justify-content:center;margin:5px 0 5px 0;border: 1px solid #dedede;background-color:${backgroundcolor};">`;
			html+= `	<div style="flex:5 5 40%;padding:5px;">`;
			html+= `		<span class="small grayed">Received Topic / Value</span><br>`;
			html+= `		<span class="bitsmall">${topic.data.originaltopic}</span><br>`;
			html+= `		<span class="small grayed">&raquo;</span><span class="bitsmall"><b>${outputdata}</b></span><span class="small grayed">&laquo;</span>`;
			html+= `	</div>`;
			
			if( !topic.data?.error) {
				// No error
				html+= `	<div style="flex:1 10 2%;padding:5px;">`;
				html+= `		<span class="small grayed">Miniserver</span><br>
								<span class="bitsmall">${topic.data.msno}</span>`;
				html+= `	</div>`;
				
				
				html+= `	<div style="flex:3 5 15%;padding:5px;">`;
				html+= `		<span class="small grayed">Measurement Name</span><br>`;
				html+= `		<span class="bitsmall">${topic.data.measurementname}</span><br>`;
				html+= `	</div>`;
				
				
				html+= `	<div style="flex:2 2 15%;padding:5px;">`;
				html+= `		<span class="small grayed">Name / Room / Category</span><br>`;
				html+= `		<span class="bitsmall">${topic.data.name}</span><br>`;
				html+= `		<span class="small">${topic.data.room} / ${topic.data.category}</span>`;
				html+= `	</div>`;
			}
			else {
				// Error 
				html+= `	<div style="flex:2 2 50%;padding:5px;color:red;" class="bitsmall">`;
				html+= `		${topic.data.error}`;
				html+= `	</div>`;
			}	
			
			html+= `	<div style="flex:3 2 15%;padding:5px;">`;
			html+= `		<span class="small grayed">Last arrived</span><br>`;
				html+= `	<span class="bitsmall">${arrived}</span>`;
			html+= `	</div>`;
		
			
			html+= `</div>`;

		}
	}
	$("#mqttlivediv").html(html);
}

function createStatsjsonTable()
{
	
	// Read stats.json from hidden div
	try {
		statsconfig = JSON.parse( $("#statsjson_json").text() );
	} 
	catch(e) {
		console.log("stats.json not parsable");
		return;
	}
	console.log("stats.json", statsconfig);
	
	try {
		statsconfigLoxone = Object.values( statsconfig.loxone );
	}
	catch(e) {
		console.log( "statsconfigLoxone seems to be empty" );
		statsconfigLoxone = [];
	}
	
	// Sort statsconfigLoxone by Name
	statsconfigLoxone.sort( dynamicSortMultiple( "Name" ) );
	
	console.log("statsconfigLoxone", statsconfigLoxone);
	
	// Read mqttlive data from hidden div to get basetopic
	try {
		liveconfig = JSON.parse( $("#mqttlivedata_json").text() );
	}
	catch(e) {
		console.log("mqtt live data not parsable");
		return;
	}
	
	console.log("mqtt live", liveconfig);
	
	var basetopic = liveconfig.state.broker_basetopic;
	
	
	// Available Topics HTML
	var html = "";
	
	for( element of statsconfigLoxone ) {
		
		// If no outputs are defined, skip
		if( element["outputs"].length == 0)
			continue;
		
		// Create Flexbox container
		html+= `<div style="display:flex;flex-wrap:wrap;justify-content:center;margin:5px 0 5px 0;border: 1px solid #dedede;">`;
		
		// Name / Description
		description = element.description ? element.description : "";
		html+= `	<div style="flex:5 5 10%;padding:3px;">`;
		html+= `	<span class="small grayed">Name</span><br>	
					${element.name}<br>
					<i>${description}</i>`;
		html+= `	</div>`;
		
		// Miniserver name
		html+= `	<div style="flex:1 10 2%;padding:3px;">`;
		html+= `	<span class="small grayed">Miniserver</span><br>	
					${element.msno}`;
		html+= `	</div>`;
		
		// Measurement name
		html+= `	<div style="flex:1 10 10%;padding:3px;">`;
		html+= `	<span class="small grayed">Measurement Name</span><br>	
					${element.measurementname}`;
		html+= `	</div>`;
		
		// Room/Category name
		html+= `	<div style="flex:1 10 10%;padding:3px;">`;
		html+= `	<span class="small grayed">Room / Category</span><br>	
					${element.room} / ${element.category}`;
		html+= `	</div>`;
		
		// Topics
		html+= `	<div style="flex:5 1 30%;padding:3px;">`;
		html+= `	<span class="small grayed">Available Topics</span><br>`;
		html+= `	<span class="bitsmall">`;
		
		if( !element.outputkeys || !element.outputlabels )
			html+= `<span style="color:red">stats.json misses outputkeys and/or outputlabels</span>`;
		else {
			
			for( output of element.outputs ) {
				console.log("output loop", output );
				// Get the index of output out of outputkeys
				labelindex = element.outputkeys.indexOf( output );
				// Get the label of that index of outputlabels
				label = element.outputlabels[labelindex];
				
				var measurementname_safe = element.measurementname.replaceAll( /[ \/#]/g, '_');
				livetopic = `${basetopic}/${element.msno}/${measurementname_safe}/${label}`;
				valconstant = `&lt;v.3&gt;`;
				html += `<div style="white-space: nowrap;">`
				html += `<b>${label}</b>: publish ${livetopic} <i>${valconstant}</i>`;
				html += `<a href="#" class="ui-mini ui-btn ui-shadow ui-icon-clipboard ui-btn-inline copyClipboard" style="padding:1px;font-size:86%;height:15px;width:32px;">Copy</a>`;
				html += `<input type="text" value="publish ${livetopic} ${valconstant}" class="datahidden">`;
				
				// html += `&nbsp;<a href="#" data-inline="true" class="ui-btn ui-shadow ui-mini ui-btn-inline">Clipboard</a>`;
				html += `</div>`
				
			}
		}

		html+= `	</span>`;
		
		html+= `	</div>`;
		
		
		
		// Close flexbox container
		html+= `</div>`;
		
		
	}

	$("#availabletopicsdiv").html(html);
	
}


function clearTimer() {
	console.log("Timer cleared");
	window.clearInterval(timer);
	timer = false;
}

function setTimer() {
	console.log("Timer set");
	timer = window.setInterval(getMqttliveData, timer_interval);
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

function getSelectedText() {
	var text = "";
		if (typeof window.getSelection != "undefined") {
			text = window.getSelection().toString();
		} else if (typeof document.selection != "undefined" && document.selection.type == "Text") {
		text = document.selection.createRange().text;
	}
	return text;
}