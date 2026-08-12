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
				loadingLabel: document.getElementById('lang_status_loading').textContent,
				noDataLabel: document.getElementById('lang_no_topics').textContent,
				topicsFoundLabel: document.getElementById('lang_topics_found').textContent,
				selectedLabel: document.getElementById('lang_selected').textContent,
				allImportedLabel: document.getElementById('lang_all_imported').textContent,
				placeholderNew: document.getElementById('lang_placeholder_new').textContent,
				deleteLabel: document.getElementById('lang_button_delete').textContent,
				showLabel: document.getElementById('lang_button_show').textContent,
				extractNumbersLabel: document.getElementById('lang_extract_numbers').textContent,
				collectStringsLabel: document.getElementById('lang_collect_strings').textContent,
				jsonExpandLabel: document.getElementById('lang_json_expand').textContent,
				addLineLabel: document.getElementById('lang_button_add_line').textContent,
				saveApplyLabel: document.getElementById('lang_button_save_apply').textContent
			}
		},
		methods: {
		  
			getMqttSubscriptions() {
				  var self = this;
				  fetch('ajax.cgi?action=getstatsconfig')
					.then( response => response.json() )
					.then( data => ( this.subscriptions = data?.mqtt?.subscriptions ? data?.mqtt?.subscriptions : [] ) )
					.then( data => this.subscriptions.push( {  } ) )
					// Fetch what is arriving under each subscription right away.
					// The page is about what a topic delivers, and having to press
					// a button on every line first only hides that.
					//
					// One after another, not all at once: every request reads the
					// finder snapshot, 340 kB of it, and a page with a dozen
					// subscriptions would ask for all of them in the same instant.
					.then( function() {
						var pending = self.subscriptions.filter( s => s.id );
						(function next() {
							var s = pending.shift();
							if( !s ) return;
							self.loadTree( s ).finally( next );
						})();
					});
			},
			
			validate(index, event) {
				console.log("Validate", index, event);
				if( validateTopic(this.subscriptions[index].id) != true ) {
					this.errors[index] = document.getElementById('lang_error_invalid_topic').textContent;
				} else {
					this.errors.splice(index, 1);
				}
				this.changedMsg();
			},
			
			changedMsg() {
				this.statusLine='<span style="color:blue">' + document.getElementById('lang_status_unsaved').textContent + '</span>';
			},
			
			savedMsg() {
				this.statusLine='<span style="color:green">' + document.getElementById('lang_status_saved').textContent + '</span>';
			},
			
			
			saveApply() {
				console.log("Save and Apply");
				// As ajax.cgi requests a form (not a raw json), we need to send the json data in a form
				// Only what belongs in the configuration. The tree, its loading
				// state and the topic count live on the same objects for
				// convenience, and a subscription like "weather4lox/#" carries
				// 2142 topics with their payloads - none of that has any business
				// in stats.json, which the collector re-reads on every change.
				let toSave = this.subscriptions.map( function(s) {
					let out = { id: s.id };
					if( s.extractNumbers ) out.extractNumbers = s.extractNumbers;
					if( s.collectStrings ) out.collectStrings = s.collectStrings;
					if( s.jsonExpand ) out.jsonExpand = s.jsonExpand;
					if( Array.isArray(s.selection) && s.selection.length ) out.selection = s.selection;
					return out;
				});

				let formData = new FormData();
				formData.append('action', 'update_mqttsubscriptions');
				formData.append('subscriptions', JSON.stringify( toSave ) );
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
						self.statusLine='<span style="color:red">' + document.getElementById('lang_status_save_error').textContent + ' ' + response.statusText +'</span>';
					}
					else {
						self.statusLine='<span style="color:green">' + document.getElementById('lang_status_saved').textContent + '</span>';
					}
				});
			},
			
			// Show what is currently arriving under this subscription.
			//
			// This used to open the MQTT Gateway's finder in another window,
			// which meant leaving the page to find out what a topic delivers.
			// The data comes from the same finder snapshot, but the tree is
			// built here - and it is where the values to import are ticked.
			// "Fetch data" fetches - it does not toggle.
			//
			// It used to close the tree when one was already open, which was
			// right while the tree only appeared on demand. Since the page loads
			// every subscription by itself, a tree is always open by then: the
			// first click closed it and only the second one showed fresh data.
			toggleTree(index) {
				this.loadTree( this.subscriptions[index] );
			},

			loadTree(sub) {
				sub.treeOpen = true;
				sub.treeLoading = true;
				sub.treeError = "";
				// The old tree stays up while the new one is fetched. Clearing it
				// first made the values vanish on every click, and on a failed
				// request they would not have come back at all.

				return fetch('ajax.cgi?action=mqtt_topicdata&topic=' + encodeURIComponent(sub.id))
				.then( function(r) { return r.json(); } )
				.then( function(data) {
					sub.treeLoading = false;
					if( data.nofinder ) {
						sub.treeError = document.getElementById('lang_error_nofinder').textContent;
						return;
					}
					sub.topicCount = data.topics.length;
					sub.tree = buildTopicTree( data.topics, sub.id );
				})
				.catch( function(e) {
					sub.treeLoading = false;
					sub.treeError = String(e);
				});
			},

			// An empty selection means everything is imported - so everything is
			// ticked. The ticks show what the collector actually writes, not what
			// happens to be written down in the configuration.
			hasSelection(sub) {
				return Array.isArray(sub.selection) && sub.selection.length > 0;
			},

			isSelected(sub, topic, field) {
				if( !this.hasSelection(sub) ) return true;
				var sel = sub.selection;
				for( var i = 0; i < sel.length; i++ ) {
					if( sel[i].topic !== topic ) continue;
					if( field === null || field === undefined ) {
						if( !sel[i].field ) return true;
					}
					else if( sel[i].field === field || !sel[i].field ) return true;
				}
				return false;
			},

			// Turn "everything" into an explicit list, because the first thing
			// unticked has to leave the rest in place. Only done on the first
			// change - a subscription nobody touched keeps its empty selection,
			// and "weather4lox/#" does not write 2142 entries into stats.json for
			// no reason.
			materialize(sub) {
				if( this.hasSelection(sub) ) return;
				var leaves = [];
				( sub.tree || [] ).forEach( function(n) { collectLeaves(n, leaves); } );
				sub.selection = leaves.map( function(l) { return { topic: l.topic }; } );
			},

			// Back to an empty selection once everything is ticked again, so the
			// configuration says "all of it" instead of listing it.
			simplify(sub) {
				var leaves = [];
				( sub.tree || [] ).forEach( function(n) { collectLeaves(n, leaves); } );
				if( !leaves.length ) return;
				var self = this;
				var complete = leaves.every( function(l) {
					return sub.selection.some( function(s) { return s.topic === l.topic && !s.field; } );
				});
				if( complete && sub.selection.length === leaves.length ) sub.selection = [];
			},

			// leaf carries the topic and, with JSON Expand on, its fields.
			toggleSelect(sub, leaf, field) {
				this.materialize(sub);
				var topic = leaf.topic;
				var on = this.isSelected(sub, topic, field);

				if( field === null || field === undefined ) {
					// The topic as a whole - its single fields go with it
					sub.selection = sub.selection.filter( function(s) { return s.topic !== topic; } );
					if( !on ) sub.selection.push( { topic: topic } );
				}
				else {
					// Unticking one field of a topic that counts as a whole means
					// the others stay: write them out first.
					var whole = sub.selection.some( function(s) { return s.topic === topic && !s.field; } );
					if( whole ) {
						sub.selection = sub.selection.filter( function(s) { return s.topic !== topic; } );
						( leaf.json || [] ).forEach( function(f) {
							sub.selection.push( { topic: topic, field: f.key } );
						});
					}
					if( on ) {
						sub.selection = sub.selection.filter( function(s) {
							return !( s.topic === topic && s.field === field ); } );
					}
					else if( !sub.selection.some( function(s) { return s.topic === topic && s.field === field; } ) ) {
						sub.selection.push( { topic: topic, field: field } );
					}
					// All fields back on - say "whole topic" again
					var fields = ( leaf.json || [] ).map( function(f) { return f.key; } );
					var picked = sub.selection.filter( function(s) { return s.topic === topic && s.field; } );
					if( fields.length && picked.length === fields.length ) {
						sub.selection = sub.selection.filter( function(s) { return s.topic !== topic; } );
						sub.selection.push( { topic: topic } );
					}
				}

				this.simplify(sub);
				this.changedMsg();
			},

			// Everything under one branch at once. Only leaves carry state, so
			// this walks down to them.
			toggleBranch(sub, node) {
				var leaves = [];
				collectLeaves( node, leaves );
				var allOn = leaves.every( l => this.isSelected(sub, l.topic, null) );
				var self = this;
				leaves.forEach( function(l) {
					if( self.isSelected(sub, l.topic, null) === allOn ) {
						self.toggleSelect(sub, l, null);
					}
				});
			},

			branchState(sub, node) {
				var leaves = [];
				collectLeaves( node, leaves );
				if( !leaves.length ) return 'none';
				var on = leaves.filter( l => this.isSelected(sub, l.topic, null) ).length;
				return on === 0 ? 'none' : ( on === leaves.length ? 'all' : 'some' );
			},

			// Switching JSON Expand off drops the field selections with it. They
			// are invisible from then on, and leaving them in place would go on
			// filtering silently - the tree would show a topic as fully selected
			// while the service still wrote only two of its values.
			jsonExpandChanged(sub) {
				if( !sub.jsonExpand && Array.isArray(sub.selection) ) {
					sub.selection = sub.selection.filter( function(s) { return !s.field; } );
				}
				this.changedMsg();
			},

			selectionCount(sub) {
				return Array.isArray(sub.selection) ? sub.selection.length : 0;
			}
		},
		mounted() { this.getMqttSubscriptions(); }
	  
	};
	
	const app = Vue.createApp(varSubscriptions);

	// One node of the topic tree, rendering itself for its children.
	//
	// Registered as a component and not written into the page template because
	// it has to nest to an unknown depth - a subscription like "weather4lox/#"
	// covers 2142 topics on the test installation, which is only readable as a
	// tree of its levels.
	app.component('topic-node', {
		name: 'topic-node',
		props: [ 'node', 'sub', 'root' ],
		emits: [ 'changed' ],
		data() { return { open: false }; },
		computed: {
			branch() { return this.root.branchState(this.sub, this.node); }
		},
		methods: {
			sel( field ) { this.root.toggleSelect(this.sub, this.node, field); },
			isSel( field ) { return this.root.isSelected(this.sub, this.node.topic, field); },
			toggleBranch() { this.root.toggleBranch(this.sub, this.node); }
		},
		template: `
		<div class="s4l-tn">
			<div v-if="node.children" class="s4l-tn-branch">
				<span class="s4l-tn-arrow" v-on:click="open = !open">{{ open ? '▼' : '▶' }}</span>
				<input type="checkbox" data-role="none" class="s4l-tn-cb"
				       :checked="branch === 'all'"
				       :indeterminate.prop="branch === 'some'"
				       v-on:change="toggleBranch()">
				<span class="s4l-tn-name" v-on:click="open = !open">{{ node.name }}</span>
				<span class="s4l-tn-meta">{{ node.leafCount }}</span>
			</div>
			<div v-else class="s4l-tn-leaf">
				<input type="checkbox" data-role="none" class="s4l-tn-cb"
				       :checked="isSel(null)"
				       v-on:change="sel(null)">
				<span class="s4l-tn-name">{{ node.name }}</span>
				<span class="s4l-tn-value">{{ node.short }}</span>
			</div>

			<div v-if="open && node.children" class="s4l-tn-children">
				<topic-node v-for="c in node.children" :key="c.path"
				            :node="c" :sub="sub" :root="root"></topic-node>
			</div>

			<!-- Shown when JSON Expand is on for the subscription - it applies to
			     every payload below it, so there is nothing to open per topic. -->
			<div v-if="sub.jsonExpand && node.json" class="s4l-tn-children">
				<div v-for="f in node.json" :key="f.key" class="s4l-tn-leaf">
					<input type="checkbox" data-role="none" class="s4l-tn-cb"
					       :checked="isSel(f.key)"
					       v-on:change="sel(f.key)">
					<span class="s4l-tn-name">{{ f.key }}</span>
					<span class="s4l-tn-value">{{ f.value }}</span>
				</div>
			</div>
		</div>`
	});

	app.mount('#subscriptionList');
	
	

});

// Build a tree of topic levels out of the flat list the finder delivers.
//
// The levels the subscription itself names are not repeated - a subscription to
// "weather4lox/#" would otherwise put every one of its 2142 topics under a
// single branch called "weather4lox" that has to be opened first.
//
// A leaf carries the last payload. If that payload is JSON, its values are
// flattened with the SAME rule the collector uses (full path, underscore
// separated, array indices included) - the names ticked here have to be the
// names it writes.
function buildTopicTree( topics, subscription ) {

	// How many levels of the subscription are fixed - those are skipped
	var fixed = 0;
	var parts = String(subscription).split('/');
	for( var i = 0; i < parts.length; i++ ) {
		if( parts[i] === '+' || parts[i] === '#' ) break;
		fixed++;
	}

	var root = { children: [], byName: {} };

	topics.forEach( function(t) {
		var levels = t.topic.split('/').slice(fixed);
		if( !levels.length ) levels = [ t.topic ];
		var node = root;
		var path = '';
		for( var i = 0; i < levels.length; i++ ) {
			path = path ? path + '/' + levels[i] : levels[i];
			var last = ( i === levels.length - 1 );
			if( last ) {
				node.children.push( makeLeaf( levels[i], path, t ) );
			}
			else {
				if( !node.byName[ levels[i] ] ) {
					var branch = { name: levels[i], path: path, children: [], byName: {}, leafCount: 0 };
					node.byName[ levels[i] ] = branch;
					node.children.push( branch );
				}
				node = node.byName[ levels[i] ];
			}
		}
	});

	countLeaves( root );
	return root.children;
}

function makeLeaf( name, path, t ) {
	var leaf = { name: name, path: path, topic: t.topic, value: t.payload, json: null };
	leaf.short = ( t.payload === null || t.payload === undefined ) ? ''
	           : ( String(t.payload).length > 60 ? String(t.payload).substring(0,60) + '…' : String(t.payload) );

	// Same test the collector makes: valid JSON that decodes to a structure
	try {
		var parsed = JSON.parse( t.payload );
		if( parsed !== null && typeof parsed === 'object' ) {
			var flat = flattenPayload( parsed, '' );
			var keys = Object.keys( flat );
			if( keys.length ) {
				leaf.json = keys.map( function(k) {
					var v = String( flat[k] );
					return { key: k, value: v.length > 40 ? v.substring(0,40) + '…' : v };
				});
			}
		}
	}
	catch(e) { /* not JSON - a plain value */ }

	return leaf;
}

// The JavaScript twin of flatten() in mqttlive.php. Both have to produce the
// same names, otherwise a ticked field would never match a written one.
function flattenPayload( value, prefix ) {
	var out = {};
	Object.keys( value ).forEach( function(key) {
		var path = ( prefix === '' ) ? String(key) : prefix + '_' + key;
		var v = value[key];
		if( v !== null && typeof v === 'object' ) {
			var sub = flattenPayload( v, path );
			Object.keys(sub).forEach( function(k) { out[k] = sub[k]; } );
		}
		else {
			out[path] = v;
		}
	});
	return out;
}

function collectLeaves( node, out ) {
	if( node.children ) { node.children.forEach( function(c) { collectLeaves(c, out); } ); }
	else { out.push( node ); }
}

function countLeaves( node ) {
	if( !node.children ) return 1;
	var n = 0;
	node.children.forEach( function(c) { n += countLeaves(c); } );
	node.leafCount = n;
	return n;
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
