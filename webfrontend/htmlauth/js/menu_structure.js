
var menu = 
[
	{ name: "Loxone",
	  submenu:
		[ 
			{ name: "Statistics", url: "index.cgi", help: "http://loxwiki.eu" },
			{ name: "Import Report", url: "loxone_import_report.cgi" },
			{ name: "MQTT Live", url: "mqttlive_loxone.cgi" } 
		]
	},
	{ name: "Outputs",
	  submenu: 
		[ 
			{ name: "Influx", url: "influx.cgi" } 
		]
	},
	{ name: "Inputs",
      submenu:
		[
			{ name: "Miniserver", url: "miniserver.cgi" },
			{ name: "MQTT", url: "mqtt.cgi" }
		]
	},
	{ name: "Settings",
	  submenu: 
		[ 
			{ name: "Settings", url: "settings.cgi" } 
		]
	}
]
;


$(function() {
	infobody = $("#infopanel .ui-body-a");
	console.log(menu);
	
	menuhtml = "";
	menuhtml += iterateMenuRecursive( menu );
	
	$(infobody).html( menuhtml );
	$("#structurednavigation0").navbar();
	
});

function iterateMenuRecursive( menu, level = 0 )
{
	//if( level == 0) {
		menuhtml = `<div id="structurednavigation${level}">`;
	//}
	for( element of menu ) {
		console.log(element, level);
		menuhtml += `<div>`;
		divspacer = level*10;
		
		
		if( element.url ) {
			target = element.target ? element.target : "_self";
			elementdisplay = `<a href="${element.url}" target="${target}" class="ui-btn ui-btn-icon-right ui-icon-carat-r" style="margin:0;">${element.name}</a>`
		}
		else {
			elementdisplay = element.name;
		}
		menuhtml += `<span class="">${elementdisplay}</span>`;
		
		if( element.submenu ) {
			menuhtml += iterateMenuRecursive( element.submenu, level+1 );
		}
		menuhtml += `</div>`;
	}
	
	if( level == 0 ) {
		menuhtml += `</div>`;
	}
	return menuhtml;
	
}