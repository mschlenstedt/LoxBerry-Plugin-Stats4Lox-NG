let hints_hide = {};

var varSubscriptions;

$(function() {
	
	restore_hints_hide();
	if(hints_hide?.hint_inputmqtt_intro != true) {
		$("#hint_inputmqtt_intro").show();
	}
	
	
	varSubscriptions = {
	  
		data() {
			return {
				subscriptions: [],
				errors: [],
				statusLine: "",
				finderAvailable: document.getElementById('isFinderAvailable').innerHTML == 'true' ? true : false /* Pure JS */
			}
		},
		methods: {
		  
			getMqttSubscriptions() {
				  fetch('ajax.cgi?action=getstatsconfig')
					.then( response => response.json() )
					.then( data => ( this.subscriptions = data?.mqtt?.subscriptions ? data?.mqtt?.subscriptions : [] ) )
					.then( data => this.subscriptions.push( {  } ) );
					
			},
			
			validate(index, event) {
				console.log("Validate", index, event);
				if( validateTopic(this.subscriptions[index].id) != true ) {
					this.errors[index] = "The syntax is not a valid MQTT subscription.";
				} else {
					this.errors.splice(index, 1);
				}
				this.changedMsg();
			},
			
			changedMsg() {
				this.statusLine='<span style="color:blue">Unsaved changes</span>';
			},
			
			savedMsg() {
				this.statusLine='<span style="color:green">Saved changes</span>';
			},
			
			
			saveApply() {
				console.log("Save and Apply");
				// As ajax.cgi requests a form (not a raw json), we need to send the json data in a form
				let formData = new FormData();
				formData.append('action', 'update_mqttsubscriptions');
				formData.append('subscriptions', JSON.stringify( this.subscriptions ) );
				const requestOptions = {
					method: "POST",
					// headers: { "Content-Type" : "application/json" },
					body: formData
				};
				var self=this;
				fetch('ajax.cgi', requestOptions)
				.then( function(response) {
					console.log(response);
					if( response.ok != true ) {
						self.statusLine='<span style="color:red">Error saving:' + response.statusText +'</span>';
					}
					else {
						self.statusLine='<span style="color:green">Saved your changes.</span>';
					}
				});
			},
			
			openFinder(index) {
				console.log("Open finder with index", index);
				window.open('/admin/system/tools/mqttfinder.cgi?e&q='+encodeURIComponent(this.subscriptions[index].id), 'mqttfinder');
			}
		},
		mounted() { this.getMqttSubscriptions(); }
	  
	};
	
	Vue.createApp(varSubscriptions).mount('#subscriptionList');
	
	

});

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

function validateTopic(topic) {

	// console.log(topic);
	// Returns true on errors
	var parts = topic.split('/'),
	i = 0;

	for (i = 0; i < parts.length; i++) {
		if ('+' === parts[i]) {
			continue;
		}
		if ('#' === parts[i] ) {
			// for Rule #2
			return i === parts.length - 1;
		}

		if ( -1 !== parts[i].indexOf('+') || -1 !== parts[i].indexOf('#')) {
			return false;
		}
	}
	return true;
}