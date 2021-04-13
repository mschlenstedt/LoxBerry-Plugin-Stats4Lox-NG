let mqttlivedata = [];
let mqttlivestate = {};
let mqttliveobjlist;

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
	
	// // Bind Import Now button
	// jQuery(document).on('click', '.rescheduleImportButton', function(event, ui){
		// var target = event.target.closest("tr");
		// var filekey = $(target).data("filekey");
		// console.log("bind rescheduleImportButton", event.target, target, filekey);
		// rescheduleImport("full", filekey);
	// });
	
	// // Bind Delete Import button
	// jQuery(document).on('click', '.deleteImportButton', function(event, ui){
		// var target = event.target.closest("tr");
		// var filekey = $(target).data("filekey");
		// console.log("bind deleteImportButton", event.target, target, filekey);
		// deleteImport(filekey, true);
	// });
	
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
				valkey = Object.keys(topic.data.values[0])[0];
				value = topic.data.values[0][valkey];
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
			html+= `	<div style="flex:5 5 60%;padding:5px;">`;
			html+= `		<span class="bitsmall">${topic.data.originaltopic}</span><br>`;
			html+= `		<span class="small grayed">Value &raquo;</span><span class="bitsmall"><b>${value}</b></span><span class="small grayed">&laquo;</span>`;
			html+= `	</div>`;
			
			if( !topic.data?.error) {
			
				
				html+= `	<div style="flex:2 2 50%;padding:5px;">`;
				html+= `		<span class="bitsmall">${topic.data.name}</span><br>`;
				html+= `		<span class="small grayed">${topic.data.room}/${topic.data.category}</span>`;
				html+= `	</div>`;
			}
			else
			{
				html+= `	<div style="flex:2 2 50%;padding:5px;color:red;" class="bitsmall">`;
				html+= `		${topic.data.error}`;
				html+= `	</div>`;
			}	
			
			html+= `	<div style="flex:3 2 15%;padding:5px;" class="bitsmall">`;
			html+= `		${arrived}`;
			html+= `	</div>`;
		
			
			html+= `</div>`;

		}
	}
	$("#mqttlivediv").html(html);
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