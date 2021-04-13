$(function() {
	
	navbarHtml = "";
	navbarHtml += `
	<div data-role="navbar" class="ui-navbar" role="navigation" id="s4l_main_nav">
		<ul class="ui-grid-d">
		
			<li class="ui-block-a ui-select ui-link" style="vertical-align: top;">
				<!-- <div class="ui-select ui-link"> -->
					<div id="select-native-1-button" class="ui-btn ui-icon-carat-d ui-btn-icon-right"  style="margin:0 !important"><span>The 1st Option</span>
						<select class="ui-mini" name="select-native-1" id="select-native-1">
							<option value="1">The 1st Option</option>
							<option value="2">The 2nd Option</option>
							<option value="3">The 3rd Option</option>
							<option value="4">The 4th Option</option>
						</select>
					</div>
				<!-- </div> -->
			</li>
			<li class="ui-block-b"><a href="#" class="ui-btn ui-link">LoxBerry</a></li>
			<li class="ui-block-c"><a href="#" class="ui-btn ui-link">Miniserver</a></li>
			<li class="ui-block-d"><a href="#" class="ui-btn ui-link">MQTT</a></li>
			<li class="ui-block-d"><a href="#" class="ui-btn ui-link">Settings</a></li>
		</ul>
	</div>
	`;
	
	navbarHtml += `
	<div data-role="navbar" class="ui-navbar" role="navigation" id="s4l_sub_nav">
		<ul class="ui-grid-d">
			<li class="ui-block-a"><a href="#" class="ui-btn-active ui-link ui-btn">Statistic Selection</a></li>
			<li class="ui-block-b"><a href="#" class="ui-btn ui-link ui-btn">Import Report</a></li>
			<li class="ui-block-c"><a href="#" class="ui-btn ui-link ui-btn">MQTT Live</a></li>
		</ul>
	</div>
	`;

	$(`[data-role="header"]`).after(navbarHtml);




});

/*
<div data-role="navbar" class="ui-navbar" role="navigation">	<ul class="ui-grid-d"> <li class="ui-block-a"><div style="position:relative"><div class="notifyBlueNavBar" id="notifyBlueNavBar10" style="display: none">0</div><div class="notifyRedNavBar" id="notifyRedNavBar10" style="display: none">0</div><a href="index.cgi" class="ui-btn-active ui-link ui-btn">Settings</a></div></li> <li class="ui-block-b"><div style="position:relative"><div class="notifyBlueNavBar" id="notifyBlueNavBar20" style="display: none">0</div><div class="notifyRedNavBar" id="notifyRedNavBar20" style="display: none">0</div><a href="index.cgi?form=subscriptions" class="ui-link ui-btn">Subscriptions</a></div></li> <li class="ui-block-c"><div style="position:relative"><div class="notifyBlueNavBar" id="notifyBlueNavBar30" style="display: none">0</div><div class="notifyRedNavBar" id="notifyRedNavBar30" style="display: none">0</div><a href="index.cgi?form=conversions" class="ui-link ui-btn">Conversions</a></div></li> <li class="ui-block-d"><div style="position:relative"><div class="notifyBlueNavBar" id="notifyBlueNavBar40" style="display: none">0</div><div class="notifyRedNavBar" id="notifyRedNavBar40" style="display: none">0</div><a href="index.cgi?form=topics" class="ui-link ui-btn">Incoming overview</a></div></li> <li class="ui-block-e"><div style="position:relative"><div class="notifyBlueNavBar" id="notifyBlueNavBar90" style="display: none">0</div><div class="notifyRedNavBar" id="notifyRedNavBar90" style="display: none">0</div><a href="index.cgi?form=logs" class="ui-link ui-btn">Transformers &amp; Logs</a></div></li>	</ul></div>
*/