# GUI i18n & MQTT Documentation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Internationalize the entire Stats4Lox GUI in 5 languages (DE/EN/NL/FR/ES) and add comprehensive MQTT Collector + LiveUpdate documentation with inline help.

**Architecture:** LoxBerry `readlanguage()` injects INI key-value pairs into HTML::Template as `<TMPL_VAR SECTION.KEY>`. JavaScript reads translated strings from hidden `<div>` elements rendered by the template. Each CGI script calls `readlanguage()` after creating the template and overrides the default Navbar names from `%L`.

**Tech Stack:** Perl CGI, HTML::Template, LoxBerry::Web::readlanguage(), JavaScript/jQuery, Vue.js (MQTT Collector page), INI language files

**Spec:** `docs/superpowers/specs/2026-03-29-i18n-gui-documentation-design.md`

---

## File Map

### New files
| File | Purpose |
|------|---------|
| `templates/lang/language_de.ini` | German translations (complete) |
| `templates/lang/language_en.ini` | English translations (complete, replaces existing) |
| `templates/lang/language_nl.ini` | Dutch (copy of EN) |
| `templates/lang/language_fr.ini` | French (copy of EN) |
| `templates/lang/language_es.ini` | Spanish (copy of EN) |

### Modified files
| File | Change |
|------|--------|
| `webfrontend/htmlauth/index.cgi` | Add readlanguage(), navbar translation |
| `webfrontend/htmlauth/main_loxone.cgi` | Add readlanguage(), navbar translation |
| `webfrontend/htmlauth/input_mqtt.cgi` | Add readlanguage(), navbar translation |
| `webfrontend/htmlauth/mqttlive_loxone.cgi` | Add readlanguage(), navbar translation |
| `webfrontend/htmlauth/output_influx.cgi` | Add navbar translation (readlanguage already exists) |
| `webfrontend/htmlauth/chartengines.cgi` | Add readlanguage(), navbar translation |
| `webfrontend/htmlauth/loxone_import_report.cgi` | Add readlanguage(), navbar translation |
| `webfrontend/htmlauth/logs.cgi` | Add readlanguage(), navbar translation |
| `templates/home.html` | Replace hardcoded strings with TMPL_VAR, add i18n divs |
| `templates/settings_loxone.html` | Replace hardcoded strings with TMPL_VAR, add i18n divs |
| `templates/input_mqtt.html` | Replace strings, add inline help + doc section |
| `templates/mqttlive_loxone.html` | Replace strings, add doc section |
| `templates/output_influx.html` | Replace remaining hardcoded string |
| `templates/chartengines.html` | Replace hardcoded strings with TMPL_VAR |
| `templates/loxone_import_report.html` | Replace hardcoded strings, add i18n divs |
| `webfrontend/htmlauth/js/home.js` | Read strings from i18n divs |
| `webfrontend/htmlauth/js/input_mqtt.js` | Read strings from i18n divs |
| `webfrontend/htmlauth/js/loxone_import_report.js` | Read strings from i18n divs |
| `webfrontend/htmlauth/js/settings_loxone.js` | Read strings from i18n divs |

---

## Task 1: Create language_en.ini (complete English)

**Files:**
- Create: `templates/lang/language_en.ini`

This replaces the existing minimal file with the complete set of all GUI strings.

- [ ] **Step 1: Write the complete English language file**

```ini
[COMMON]
LABEL_LOG="Logfile"
LABEL_LOGS="Logfiles"
BUTTON_OK="OK"
LABEL_PLUGINTITLE="Stats4Lox"
LABEL_ON="On"
LABEL_OFF="Off"
HINT_PLEASE_WAIT="One moment..."
ERROR_COULD_NOT_GET_DATA="Could not query the requested data."
YES="Yes"
NO="No"
MISSING="Missing"
BUTTON_HIDE="Hide"
BUTTON_SAVE_APPLY="Save and Apply"
BUTTON_DELETE="Delete"
STATUS_UPDATING="Updating..."

[NAVBAR]
HOME="Home"
LOXONE_IMPORT="Loxone and Import"
INPUTS_OUTPUTS="Inputs / Outputs"
CHART_ENGINES="Chart Engines"
LOGS="Logs"

[HOME]
STATUS_RUNNING="Running (PID __PID__)"
STATUS_STOPPED="Stopped"
STATUS_DISABLED="Disabled by config"
STATUS_FAILED="Failed"
BUTTON_RESTART="(Re)Start"
BUTTON_STOP="Stop"
STATUS_EXECUTING="Executing..."
STATUS_OK="OK"
STATUS_ERROR="Error"
STATUS_FAILED_DETAIL="Failed: __MSG__"

[INPUTSOUTPUTS]
TITLE_INFLUX_CONFIG="Influx Database Configuration"
LABEL_INFLUX_STORAGE_PATH="Database Storage:"
HINT_INFLUX_STORAGE_PATH="This is where Influx stores its database. Use an external USB storage device if possible."
BUTTON_SAVE="Save and Apply"
POPUP_SAVING_TITLE="Saving..."
HINT_SAVING="Activating your settings. This may take some time."
HINT_SAVING_PREPARING="Preparing config changes..."
HINT_SAVING_FAIL="Error while transmitting your request. Please refer to the latest logfile 'Config-Handler' and/or 'AJAX'."
HINT_SAVING_ERROR="There was a problem activating your settings. Please refer to the latest logfile."
HINT_SAVING_SUCCESS="Your new settings were saved and activated successfully."
HINT_OPEN_LOGFILE="Open Logfile"

[CHARTENGINES]
BUTTON_OPEN_GRAFANA="Open Grafana Webinterface"

[LOXONE]
HINT_SELECT_STATS_TITLE="Statistic Selection hint"
HINT_SELECT_STATS="Filter or search for Loxone elements you want to activate statistics for. Press the Details button to get live data from the Miniserver, and select the interval and outputs you want to record. Changes in the Details view are applied immediately (no Save button)."
LABEL_FILTER="Filter"
LABEL_MINISERVER="Miniserver"
LABEL_ALL_MINISERVERS="All Miniservers"
LABEL_ROOM="Room"
LABEL_ALL_ROOMS="All rooms"
LABEL_CATEGORY="Category"
LABEL_ALL_CATEGORIES="All categories"
LABEL_ELEMENT="Element"
LABEL_ALL_ELEMENTS="All elements"
LABEL_LOXONE_VISU="Loxone Visu"
LABEL_LOXONE_STAT="Loxone Statistic"
LABEL_S4L_STAT="Stats4Lox Statistic"
LABEL_ALL="All"
LABEL_DETAILS="Details"
LABEL_VISUALISATION="Visualisation"
LABEL_LOXONE_STATISTICS="Loxone Statistics"
LABEL_S4L_STATISTICS="Stats4Lox Statistics"
LABEL_ACTIVATE="activate"
LABEL_INTERVAL_MINUTES="Interval (minutes)"
LABEL_MEASUREMENT_NAME="Measurement Label in Statistic"
HINT_MEASUREMENT_NAME="This uniquely identifies data in your statistic. The field is mandatory. <b>If you change this, all further data will be stored to the new label.</b>"
LABEL_IMPORT_SELECTED="Import selected outputs from your Loxone Statistic"
HINT_IMPORT_BUTTON_TITLE="Import button hint"
HINT_IMPORT_BUTTON="To import your Loxone Statistics, you need to activate Stats4Lox Statistics and select outputs on the right. Loxone statistics only contain a subset of available outputs. A symbol on every output signals that this data will be imported to that output if checked. If you press Import Now, the import is queued and imported in the background."
BUTTON_IMPORT_NOW="Import Now"
TITLE_PROCESSING_ERRORS="Processing Errors"
TITLE_PROGRESS="Progress"
BUTTON_CLOSE="Close"

[IMPORTREPORT]
TITLE_PAGE="Statistic Import Report"
DESCRIPTION="This page shows all Loxone statistic imports that are running, waiting and have finished. The page refreshes automatically."
SECTION_RUNNING="Running"
SECTION_WAITING="Waiting"
SECTION_FINISHED="Finished"
SECTION_ERROR="Error"
SECTION_DEAD="Dead"
LABEL_STARTED="Started"
LABEL_PROGRESS="Progress"
LABEL_CURRENT_MONTH="Current month"
LABEL_ESTIMATED_END="Estimated end"
LABEL_FINISHED="Finished"
LABEL_FINISHED_ERROR="Finished (with error)"
LABEL_DURATION="Duration"
LABEL_IMPORTED_RECORDS="Imported records"
LABEL_ERROR_MONTH="Error on month"
LABEL_LAST_UPDATE="Last Update of Import"
LABEL_ERROR="Error"
BUTTON_OPEN_LOG="Open Logfile"
BUTTON_REIMPORT="Re-Import"
BUTTON_RETRY="Retry Import"
EMPTY_RUNNING="Currently no running imports."
EMPTY_WAITING="Currently no waiting imports."
EMPTY_FINISHED="No imports finished yet."
EMPTY_ERROR="No imports with errors."
EMPTY_DEAD="No dead imports."
POPUP_DELETE_TITLE="Delete Import Status?"
POPUP_DELETE_TEXT="This will completely delete the Import job (if not executed yet), or the status information of a finished Import. After deletion, Stats4Lox does not remember that you have imported that statistics."
POPUP_DELETE_NOTE="This does <i>not</i> touch your data in the database, the settings of activated statistic collection, and much less your statistics on your Miniserver."

[MQTTCOLLECTOR]
TITLE="MQTT Collector"
DESCRIPTION="Subscribe to MQTT topics that Stats4Lox should directly push to the Influx database."
PLACEHOLDER_TOPIC="Add new subscription"
LABEL_EXTRACT_NUMBERS="Extract Numbers"
LABEL_COLLECT_STRINGS="Collect Strings"
BUTTON_ADD_LINE="Add new line"
BUTTON_DELETE="Delete"
BUTTON_SHOW="Show"
ERR_INVALID_TOPIC="The syntax is not a valid MQTT subscription."
STATUS_UNSAVED="Unsaved changes"
STATUS_SAVED="Saved changes"
STATUS_SAVE_OK="Saved your changes."
ERR_SAVE_FAILED="Error saving: __MSG__"
HINT_TOPIC_INLINE="MQTT topic, e.g. <code>sensor/temperature</code> &mdash; Wildcards: <code>+</code> (single level), <code>#</code> (all sub-levels)"
HINT_EXTRACT_NUMBERS_INLINE="Tries to extract numeric values from strings, e.g. <code>12.4</code> from <code>12.4&deg;C</code>"
HINT_COLLECT_STRINGS_INLINE="Also stores text values in InfluxDB (not just numbers)"
DOC_TITLE="What is MQTT Collector?"
DOC_INTRO="With MQTT Collector you can store data from any MQTT device directly into your InfluxDB &mdash; without routing through the Loxone Miniserver. This is ideal for devices like Tasmota plugs, Shelly sensors, Hoymiles inverters or other MQTT-enabled devices."
DOC_PREREQ_TITLE="Prerequisites"
DOC_PREREQ="The <b>LoxBerry MQTT Gateway</b> plugin must be installed and configured. The MQTT broker must be running. Subscriptions in MQTT Gateway (forwarded to the Miniserver) are independent of subscriptions here."
DOC_HOWTO_TITLE="How to use"
DOC_HOWTO="<ol><li>Enter the desired MQTT topic in the input field (e.g. <code>tasmota/plug1/SENSOR</code>)</li><li>Select options: <b>Extract Numbers</b> and/or <b>Collect Strings</b></li><li>Click <b>Save and Apply</b></li><li>Data appears in InfluxDB under the topic's measurement name</li><li>In Grafana you can immediately use the data in dashboards</li></ol>"
DOC_WILDCARDS_TITLE="MQTT Topics &amp; Wildcards"
DOC_WILDCARDS="<ul><li><code>home/ground/temperature</code> &mdash; Exact topic, only this measurement</li><li><code>home/+/temperature</code> &mdash; All rooms on one level (e.g. ground, upper, basement)</li><li><code>home/#</code> &mdash; All topics below <code>home/</code></li><li><code>tasmota/+/SENSOR</code> &mdash; All Tasmota sensor data</li></ul>"
DOC_JSON_TITLE="JSON Payloads"
DOC_JSON="The Collector automatically detects JSON data and splits it into individual fields. Example:<br><code>{&quot;temperature&quot;:21.5, &quot;humidity&quot;:65}</code><br>becomes two separate values in InfluxDB: <code>temperature=21.5</code> and <code>humidity=65</code>. Nested JSON objects are also expanded. Boolean values (<code>true</code>/<code>false</code>) are automatically converted to <code>1</code>/<code>0</code>."
DOC_OPTIONS_TITLE="Options per topic"
DOC_OPTIONS="<ul><li><b>Extract Numbers:</b> When enabled, the Collector tries to extract numeric values from text strings. E.g. <code>12.4&deg;C</code> yields value <code>12.4</code>. Useful for devices that include units in their values.</li><li><b>Collect Strings:</b> By default only numeric values are stored. Enable this to also store text values in InfluxDB (InfluxDB supports strings as field values).</li></ul>"
DOC_DIFFERENCE_TITLE="Difference to MQTT LiveUpdate"
DOC_DIFFERENCE="<b>MQTT Collector:</b> Collects data from any MQTT device directly into InfluxDB. Devices do not need to be configured in the Loxone Miniserver.<br><b>MQTT LiveUpdate:</b> Receives real-time updates from Loxone blocks via MQTT. Data must be published by the Miniserver through MQTT Gateway following a specific topic schema."

[MQTTLIVE]
TITLE="MQTT LiveUpdate Data"
DESCRIPTION="This listing shows what data you have already submitted via MQTT LiveUpdate to your Loxone Statistics, and also if your publishes might miss the correct topic."
DESCRIPTION2="Below you'll find <i>all available outputs</i> of Loxone blocks that you have enabled, to directly copy/paste. An output gets enabled by enabling it in the Detail View of the Statistics configuration. See the <a href='https://www.loxwiki.eu/x/-YRWBQ' target='_blank'>LoxWiki step-by-step guide</a> for assistance."
LABEL_LIVE_STATE="MQTT Live State"
LABEL_TOPIC="Topic"
LABEL_CONNECTED="Connected"
LABEL_ERRORS="Errors"
TITLE_RECEIVED="Received updates"
HINT_COLOR="The color gives you advice when the last message arrived (the louder the latter)"
BUTTON_CLEAR="Clear Display"
TITLE_AVAILABLE_TOPICS="MQTT Live All Available Update Topics"
BUTTON_CREATE_TEMPLATE="Create Virtual Output Template"
DOC_TITLE="What is MQTT LiveUpdate?"
DOC_INTRO="The normal Statistics Grabber collects data at your defined interval (e.g. 5 or 10 minutes). Data that changes rapidly &mdash; like power metering or button presses &mdash; cannot be collected that way. With MQTT LiveUpdate, every change of a Loxone block output immediately sends the data to your Stats4Lox statistic."
DOC_PREREQ_TITLE="Prerequisites"
DOC_PREREQ="<ul><li>The <b>MQTT Gateway</b> plugin must be installed and configured</li><li>A <b>Virtual Output</b> to MQTT Gateway must be created in the Loxone Miniserver</li><li>The blocks to monitor must be connected to the Virtual Output</li></ul>"
DOC_HOWTO_TITLE="How to use"
DOC_HOWTO="<ol><li>Activate the desired statistic on the <b>Loxone and Import</b> page and select outputs</li><li>Copy the displayed MQTT topic from the list below</li><li>In Loxone Config, create a <b>Virtual Output Command</b> with this topic</li><li>Connect the desired block output (e.g. 'Current power') to the Virtual Output</li><li>Every value change is now reported live to Stats4Lox</li></ol><p>Tip: Use the <b>Create Virtual Output Template</b> button to generate an XML file you can import directly into Loxone Config.</p>"
DOC_DIFFERENCE_TITLE="Difference to MQTT Collector"
DOC_DIFFERENCE="<b>MQTT LiveUpdate:</b> For Loxone blocks. The Miniserver sends value changes via MQTT to Stats4Lox. Requires configuration in Loxone Config (Virtual Output).<br><b>MQTT Collector:</b> For any MQTT device (Tasmota, Shelly etc.). Devices send directly to the MQTT broker, Stats4Lox reads the topics."
```

- [ ] **Step 2: Commit**

```bash
git add templates/lang/language_en.ini
git commit -m "feat(i18n): create complete English language file"
```

---

## Task 2: Create language_de.ini (complete German)

**Files:**
- Create: `templates/lang/language_de.ini`

- [ ] **Step 1: Write the complete German language file**

```ini
[COMMON]
LABEL_LOG="Logdatei"
LABEL_LOGS="Logdateien"
BUTTON_OK="OK"
LABEL_PLUGINTITLE="Stats4Lox"
LABEL_ON="An"
LABEL_OFF="Aus"
HINT_PLEASE_WAIT="Einen Moment..."
ERROR_COULD_NOT_GET_DATA="Die angeforderten Daten konnten nicht abgerufen werden."
YES="Ja"
NO="Nein"
MISSING="Fehlt"
BUTTON_HIDE="Ausblenden"
BUTTON_SAVE_APPLY="Speichern und anwenden"
BUTTON_DELETE="Loeschen"
STATUS_UPDATING="Aktualisiere..."

[NAVBAR]
HOME="Startseite"
LOXONE_IMPORT="Loxone & Import"
INPUTS_OUTPUTS="Ein-/Ausgaenge"
CHART_ENGINES="Diagramme"
LOGS="Logs"

[HOME]
STATUS_RUNNING="Laeuft (PID __PID__)"
STATUS_STOPPED="Gestoppt"
STATUS_DISABLED="Per Konfiguration deaktiviert"
STATUS_FAILED="Fehlgeschlagen"
BUTTON_RESTART="(Neu)Start"
BUTTON_STOP="Stopp"
STATUS_EXECUTING="Wird ausgefuehrt..."
STATUS_OK="OK"
STATUS_ERROR="Fehler"
STATUS_FAILED_DETAIL="Fehlgeschlagen: __MSG__"

[INPUTSOUTPUTS]
TITLE_INFLUX_CONFIG="InfluxDB Konfiguration"
LABEL_INFLUX_STORAGE_PATH="Datenbank-Speicherort:"
HINT_INFLUX_STORAGE_PATH="Hier speichert InfluxDB die Datenbank. Verwenden Sie moeglichst ein externes USB-Speichergeraet."
BUTTON_SAVE="Speichern und anwenden"
POPUP_SAVING_TITLE="Speichern..."
HINT_SAVING="Einstellungen werden aktiviert. Dies kann einen Moment dauern."
HINT_SAVING_PREPARING="Konfigurations-Aenderungen werden vorbereitet..."
HINT_SAVING_FAIL="Fehler bei der Uebertragung. Bitte pruefen Sie die Logdatei 'Config-Handler' und/oder 'AJAX'."
HINT_SAVING_ERROR="Beim Aktivieren der Einstellungen ist ein Problem aufgetreten. Bitte pruefen Sie die Logdatei."
HINT_SAVING_SUCCESS="Einstellungen wurden erfolgreich gespeichert und aktiviert."
HINT_OPEN_LOGFILE="Logdatei oeffnen"

[CHARTENGINES]
BUTTON_OPEN_GRAFANA="Grafana Weboberflaeche oeffnen"

[LOXONE]
HINT_SELECT_STATS_TITLE="Hinweis zur Statistikauswahl"
HINT_SELECT_STATS="Filtern oder suchen Sie nach Loxone-Elementen, fuer die Sie Statistiken aktivieren moechten. Druecken Sie den Detail-Button, um Live-Daten vom Miniserver abzurufen, und waehlen Sie das Intervall und die Ausgaenge, die aufgezeichnet werden sollen. Aenderungen in der Detailansicht werden sofort uebernommen (kein Speichern-Button noetig)."
LABEL_FILTER="Filter"
LABEL_MINISERVER="Miniserver"
LABEL_ALL_MINISERVERS="Alle Miniserver"
LABEL_ROOM="Raum"
LABEL_ALL_ROOMS="Alle Raeume"
LABEL_CATEGORY="Kategorie"
LABEL_ALL_CATEGORIES="Alle Kategorien"
LABEL_ELEMENT="Element"
LABEL_ALL_ELEMENTS="Alle Elemente"
LABEL_LOXONE_VISU="Loxone Visu"
LABEL_LOXONE_STAT="Loxone Statistik"
LABEL_S4L_STAT="Stats4Lox Statistik"
LABEL_ALL="Alle"
LABEL_DETAILS="Details"
LABEL_VISUALISATION="Visualisierung"
LABEL_LOXONE_STATISTICS="Loxone Statistik"
LABEL_S4L_STATISTICS="Stats4Lox Statistik"
LABEL_ACTIVATE="aktivieren"
LABEL_INTERVAL_MINUTES="Intervall (Minuten)"
LABEL_MEASUREMENT_NAME="Measurement-Name in der Statistik"
HINT_MEASUREMENT_NAME="Dieser Name identifiziert die Daten eindeutig in Ihrer Statistik. Das Feld ist Pflicht. <b>Wenn Sie diesen Namen aendern, werden alle weiteren Daten unter dem neuen Namen gespeichert.</b>"
LABEL_IMPORT_SELECTED="Ausgewaehlte Ausgaenge aus Loxone-Statistik importieren"
HINT_IMPORT_BUTTON_TITLE="Hinweis zum Import"
HINT_IMPORT_BUTTON="Um Loxone-Statistiken zu importieren, muessen Sie <i>Stats4Lox Statistik</i> aktivieren und rechts Ausgaenge auswaehlen. Loxone-Statistiken enthalten nur eine Teilmenge der verfuegbaren Ausgaenge. Ein Symbol an jedem Ausgang zeigt an, ob diese Daten beim Import in diesen Ausgang uebernommen werden. Durch Klick auf 'Jetzt importieren' wird der Import in die Warteschlange gestellt und im Hintergrund ausgefuehrt."
BUTTON_IMPORT_NOW="Jetzt importieren"
TITLE_PROCESSING_ERRORS="Verarbeitungsfehler"
TITLE_PROGRESS="Fortschritt"
BUTTON_CLOSE="Schliessen"

[IMPORTREPORT]
TITLE_PAGE="Statistik-Import Bericht"
DESCRIPTION="Diese Seite zeigt alle Loxone-Statistik-Importe die laufen, warten und abgeschlossen sind. Die Seite aktualisiert sich automatisch."
SECTION_RUNNING="Laufend"
SECTION_WAITING="Wartend"
SECTION_FINISHED="Abgeschlossen"
SECTION_ERROR="Fehler"
SECTION_DEAD="Abgebrochen"
LABEL_STARTED="Gestartet"
LABEL_PROGRESS="Fortschritt"
LABEL_CURRENT_MONTH="Aktueller Monat"
LABEL_ESTIMATED_END="Voraussichtliches Ende"
LABEL_FINISHED="Abgeschlossen"
LABEL_FINISHED_ERROR="Abgeschlossen (mit Fehler)"
LABEL_DURATION="Dauer"
LABEL_IMPORTED_RECORDS="Importierte Datensaetze"
LABEL_ERROR_MONTH="Fehler bei Monat"
LABEL_LAST_UPDATE="Letztes Update des Imports"
LABEL_ERROR="Fehler"
BUTTON_OPEN_LOG="Logdatei oeffnen"
BUTTON_REIMPORT="Erneut importieren"
BUTTON_RETRY="Import wiederholen"
EMPTY_RUNNING="Derzeit keine laufenden Importe."
EMPTY_WAITING="Derzeit keine wartenden Importe."
EMPTY_FINISHED="Noch keine Importe abgeschlossen."
EMPTY_ERROR="Keine Importe mit Fehlern."
EMPTY_DEAD="Keine abgebrochenen Importe."
POPUP_DELETE_TITLE="Import-Status loeschen?"
POPUP_DELETE_TEXT="Damit wird der Import-<u>Auftrag</u> (falls noch nicht ausgefuehrt) oder die Statusinformation eines abgeschlossenen Imports vollstaendig geloescht. Stats4Lox merkt sich danach nicht mehr, dass diese Statistik importiert wurde."
POPUP_DELETE_NOTE="Dies hat <i>keinen</i> Einfluss auf Ihre Daten in der Datenbank, die Einstellungen der aktivierten Statistikerfassung oder Ihre Statistiken auf dem Miniserver."

[MQTTCOLLECTOR]
TITLE="MQTT Collector"
DESCRIPTION="Abonnieren Sie MQTT-Topics, deren Daten Stats4Lox direkt in die InfluxDB schreiben soll."
PLACEHOLDER_TOPIC="Neues Topic eintragen"
LABEL_EXTRACT_NUMBERS="Zahlen extrahieren"
LABEL_COLLECT_STRINGS="Strings sammeln"
BUTTON_ADD_LINE="Neue Zeile hinzufuegen"
BUTTON_DELETE="Loeschen"
BUTTON_SHOW="Anzeigen"
ERR_INVALID_TOPIC="Die Syntax ist kein gueltiges MQTT-Topic."
STATUS_UNSAVED="Ungespeicherte Aenderungen"
STATUS_SAVED="Aenderungen gespeichert"
STATUS_SAVE_OK="Aenderungen gespeichert."
ERR_SAVE_FAILED="Fehler beim Speichern: __MSG__"
HINT_TOPIC_INLINE="MQTT-Topic, z.B. <code>sensor/temperatur</code> &mdash; Wildcards: <code>+</code> (eine Ebene), <code>#</code> (alle Unterebenen)"
HINT_EXTRACT_NUMBERS_INLINE="Versucht Zahlenwerte aus Strings zu extrahieren, z.B. <code>12.4</code> aus <code>12.4&deg;C</code>"
HINT_COLLECT_STRINGS_INLINE="Speichert auch Text-Werte in InfluxDB (nicht nur Zahlen)"
DOC_TITLE="Was ist der MQTT Collector?"
DOC_INTRO="Mit dem MQTT Collector koennen Sie Daten von beliebigen MQTT-Geraeten direkt in Ihre InfluxDB speichern &mdash; ohne den Umweg ueber den Loxone Miniserver. Das ist ideal fuer Geraete wie Tasmota-Steckdosen, Shelly-Sensoren, Hoymiles-Wechselrichter oder andere MQTT-faehige Geraete."
DOC_PREREQ_TITLE="Voraussetzungen"
DOC_PREREQ="Das <b>LoxBerry MQTT Gateway</b> Plugin muss installiert und konfiguriert sein. Der MQTT Broker muss laufen. Subscriptions im MQTT Gateway (die an den Miniserver weitergeleitet werden) sind unabhaengig von den Subscriptions hier."
DOC_HOWTO_TITLE="So funktioniert's"
DOC_HOWTO="<ol><li>Tragen Sie das gewuenschte MQTT-Topic in das Eingabefeld ein (z.B. <code>tasmota/steckdose1/SENSOR</code>)</li><li>Waehlen Sie die Optionen: <b>Zahlen extrahieren</b> und/oder <b>Strings sammeln</b></li><li>Klicken Sie <b>Speichern und anwenden</b></li><li>Die Daten erscheinen in InfluxDB unter dem Measurement-Namen des Topics</li><li>In Grafana koennen Sie die Daten sofort in Dashboards verwenden</li></ol>"
DOC_WILDCARDS_TITLE="MQTT Topics &amp; Wildcards"
DOC_WILDCARDS="<ul><li><code>haus/eg/temperatur</code> &mdash; Exaktes Topic, nur diese eine Messung</li><li><code>haus/+/temperatur</code> &mdash; Alle Raeume auf einer Ebene (z.B. eg, og, keller)</li><li><code>haus/#</code> &mdash; Alle Topics unterhalb von <code>haus/</code></li><li><code>tasmota/+/SENSOR</code> &mdash; Alle Tasmota-Sensor-Daten</li></ul>"
DOC_JSON_TITLE="JSON-Payloads"
DOC_JSON="Der Collector erkennt JSON-Daten automatisch und splittet sie in einzelne Felder auf. Beispiel:<br><code>{&quot;temperature&quot;:21.5, &quot;humidity&quot;:65}</code><br>wird zu zwei separaten Werten in InfluxDB: <code>temperature=21.5</code> und <code>humidity=65</code>. Verschachtelte JSON-Objekte werden ebenfalls aufgeloest. Boolsche Werte (<code>true</code>/<code>false</code>) werden automatisch in <code>1</code>/<code>0</code> umgewandelt."
DOC_OPTIONS_TITLE="Optionen pro Topic"
DOC_OPTIONS="<ul><li><b>Zahlen extrahieren:</b> Wenn aktiviert, versucht der Collector Zahlenwerte aus Text-Strings zu lesen. Z.B. wird aus <code>12.4&deg;C</code> der Wert <code>12.4</code> extrahiert. Nuetzlich bei Geraeten, die Einheiten im Wert mitsenden.</li><li><b>Strings sammeln:</b> Standardmaessig werden nur numerische Werte gespeichert. Aktivieren Sie diese Option, um auch Text-Werte in InfluxDB zu speichern (InfluxDB unterstuetzt Strings als Feldwerte).</li></ul>"
DOC_DIFFERENCE_TITLE="Unterschied zu MQTT LiveUpdate"
DOC_DIFFERENCE="<b>MQTT Collector:</b> Sammelt Daten von beliebigen MQTT-Geraeten direkt in InfluxDB. Die Geraete muessen nicht im Loxone Miniserver konfiguriert sein.<br><b>MQTT LiveUpdate:</b> Empfaengt Echtzeit-Updates von Loxone-Bloecken ueber MQTT. Die Daten muessen vom Miniserver per MQTT Gateway veroeffentlicht werden und einem bestimmten Topic-Schema folgen."

[MQTTLIVE]
TITLE="MQTT LiveUpdate Daten"
DESCRIPTION="Diese Uebersicht zeigt, welche Daten Sie bereits per MQTT LiveUpdate an Ihre Loxone-Statistiken gesendet haben, und ob Ihre Publishes das richtige Topic treffen."
DESCRIPTION2="Unten finden Sie <i>alle verfuegbaren Ausgaenge</i> von Loxone-Bloecken, die Sie aktiviert haben, zum direkten Kopieren. Ein Ausgang wird aktiviert, indem Sie ihn in der Detailansicht der Statistik-Konfiguration einschalten. Weitere Informationen finden Sie in der <a href='https://www.loxwiki.eu/x/-YRWBQ' target='_blank'>LoxWiki Schritt-fuer-Schritt-Anleitung</a>."
LABEL_LIVE_STATE="MQTT Live Status"
LABEL_TOPIC="Topic"
LABEL_CONNECTED="Verbunden"
LABEL_ERRORS="Fehler"
TITLE_RECEIVED="Empfangene Updates"
HINT_COLOR="Die Farbe zeigt an, wann die letzte Nachricht eintraf (je kraeftiger, desto aktueller)"
BUTTON_CLEAR="Anzeige zuruecksetzen"
TITLE_AVAILABLE_TOPICS="MQTT Live Alle verfuegbaren Update-Topics"
BUTTON_CREATE_TEMPLATE="Virtuellen Ausgang Vorlage erstellen"
DOC_TITLE="Was ist MQTT LiveUpdate?"
DOC_INTRO="Der normale Statistik-Grabber sammelt Daten in Ihrem definierten Intervall (z.B. 5 oder 10 Minuten). Daten, die sich schnell aendern &mdash; wie Stromverbrauch oder Tastendruecke &mdash; koennen so nicht erfasst werden. Mit MQTT LiveUpdate senden Sie bei jeder Aenderung eines Loxone-Blockausgangs die Daten sofort an Ihre Stats4Lox-Statistik."
DOC_PREREQ_TITLE="Voraussetzungen"
DOC_PREREQ="<ul><li>Das <b>MQTT Gateway</b> Plugin muss installiert und konfiguriert sein</li><li>Im Loxone Miniserver muss ein <b>Virtueller Ausgang</b> zum MQTT Gateway erstellt werden</li><li>Die zu ueberwachenden Bloecke muessen mit dem Virtuellen Ausgang verbunden werden</li></ul>"
DOC_HOWTO_TITLE="So funktioniert's"
DOC_HOWTO="<ol><li>Aktivieren Sie die gewuenschte Statistik in der <b>Loxone & Import</b> Seite und waehlen Sie Ausgaenge</li><li>Kopieren Sie das angezeigte MQTT-Topic aus der Liste unten</li><li>Erstellen Sie im Loxone Config einen <b>Virtuellen Ausgang Befehl</b> mit diesem Topic</li><li>Verbinden Sie den gewuenschten Blockausgang (z.B. 'Aktuelle Leistung') mit dem Virtuellen Ausgang</li><li>Jede Wertaenderung wird nun live an Stats4Lox gemeldet</li></ol><p>Tipp: Nutzen Sie den Button <b>Virtuellen Ausgang Vorlage erstellen</b> um eine XML-Datei zu generieren, die Sie direkt in Loxone Config importieren koennen.</p>"
DOC_DIFFERENCE_TITLE="Unterschied zu MQTT Collector"
DOC_DIFFERENCE="<b>MQTT LiveUpdate:</b> Fuer Loxone-Bloecke. Der Miniserver sendet Wertaenderungen per MQTT an Stats4Lox. Erfordert Konfiguration im Loxone Config (Virtueller Ausgang).<br><b>MQTT Collector:</b> Fuer beliebige MQTT-Geraete (Tasmota, Shelly etc.). Die Geraete senden direkt an den MQTT Broker, Stats4Lox liest die Topics."
```

- [ ] **Step 2: Commit**

```bash
git add templates/lang/language_de.ini
git commit -m "feat(i18n): create complete German language file"
```

---

## Task 3: Create NL/FR/ES language files

**Files:**
- Create: `templates/lang/language_nl.ini`
- Create: `templates/lang/language_fr.ini`
- Create: `templates/lang/language_es.ini`

All three are copies of `language_en.ini`. LoxBerry falls back to EN for missing keys, but having explicit files allows the community to translate later.

- [ ] **Step 1: Copy language_en.ini to language_nl.ini, language_fr.ini, language_es.ini**

```bash
cp templates/lang/language_en.ini templates/lang/language_nl.ini
cp templates/lang/language_en.ini templates/lang/language_fr.ini
cp templates/lang/language_en.ini templates/lang/language_es.ini
```

- [ ] **Step 2: Commit**

```bash
git add templates/lang/language_nl.ini templates/lang/language_fr.ini templates/lang/language_es.ini
git commit -m "feat(i18n): add NL/FR/ES language files (EN copies for community translation)"
```

---

## Task 4: Add readlanguage() and navbar translation to all CGI scripts

**Files:**
- Modify: `webfrontend/htmlauth/index.cgi`
- Modify: `webfrontend/htmlauth/main_loxone.cgi`
- Modify: `webfrontend/htmlauth/input_mqtt.cgi`
- Modify: `webfrontend/htmlauth/mqttlive_loxone.cgi`
- Modify: `webfrontend/htmlauth/output_influx.cgi`
- Modify: `webfrontend/htmlauth/chartengines.cgi`
- Modify: `webfrontend/htmlauth/loxone_import_report.cgi`
- Modify: `webfrontend/htmlauth/logs.cgi`

Every CGI must: (1) call `readlanguage()` after creating the template, (2) override navbar names from `%L`, (3) use `%L` in `lbheader()`.

The key pattern is a shared block that goes into every CGI after template creation:

```perl
my %L = LoxBerry::Web::readlanguage($template, "language.ini");

# Translate navbar
$main::navbar{1}{Name} = $L{'NAVBAR.HOME'};
$main::navbar{10}{Name} = $L{'NAVBAR.LOXONE_IMPORT'};
$main::navbar{30}{Name} = $L{'NAVBAR.INPUTS_OUTPUTS'};
$main::navbar{40}{Name} = $L{'NAVBAR.CHART_ENGINES'};
$main::navbar{90}{Name} = $L{'NAVBAR.LOGS'};
```

- [ ] **Step 1: Modify index.cgi**

Replace the entire file content with:

```perl
#!/usr/bin/perl
use warnings;
use strict;
use LoxBerry::System;
use LoxBerry::Web;
use JSON;
use FindBin qw($Bin);
use lib "$Bin/../../../../bin/plugins/stats4lox/libs/";
use Globals;

my $template = HTML::Template->new(
    filename => "$lbptemplatedir/home.html",
    global_vars => 1,
    loop_context_vars => 1,
    die_on_bad_params => 0,
);

my %L = LoxBerry::Web::readlanguage($template, "language.ini");

$main::navbar{1}{Name} = $L{'NAVBAR.HOME'};
$main::navbar{10}{Name} = $L{'NAVBAR.LOXONE_IMPORT'};
$main::navbar{30}{Name} = $L{'NAVBAR.INPUTS_OUTPUTS'};
$main::navbar{40}{Name} = $L{'NAVBAR.CHART_ENGINES'};
$main::navbar{90}{Name} = $L{'NAVBAR.LOGS'};

LoxBerry::Web::lbheader($L{'COMMON.LABEL_PLUGINTITLE'} . " - " . $L{'NAVBAR.HOME'}, undef, undef);

$template->param( 'GRAFANA_URL', "http://" . LoxBerry::System::get_localip() . ":" . $Globals::grafana->{port} );

print $template->output();

LoxBerry::Web::lbfooter();
```

Note: `lbheader()` must come AFTER `readlanguage()` and AFTER navbar overrides, but template must be created BEFORE `readlanguage()`. The Globals.pm `use` sets up the initial navbar with English defaults, then CGI overrides.

- [ ] **Step 2: Modify main_loxone.cgi**

Replace with:

```perl
#!/usr/bin/perl
use warnings;
use strict;
use LoxBerry::System;
use LoxBerry::Web;
use JSON;
use FindBin qw($Bin);
use lib "$Bin/../../../../bin/plugins/stats4lox/libs/";
use Globals;

our $htmlhead="";
$htmlhead .= '<script type="application/javascript" src="js/loxone_sub_navbar.js"></script>';
$htmlhead .= '<script type="application/javascript" src="js/settings_loxone.js"></script>';

my $template = HTML::Template->new(
    filename => "$lbptemplatedir/settings_loxone.html",
    global_vars => 1,
    loop_context_vars => 1,
    die_on_bad_params => 0,
);

my %L = LoxBerry::Web::readlanguage($template, "language.ini");

$main::navbar{1}{Name} = $L{'NAVBAR.HOME'};
$main::navbar{10}{Name} = $L{'NAVBAR.LOXONE_IMPORT'};
$main::navbar{30}{Name} = $L{'NAVBAR.INPUTS_OUTPUTS'};
$main::navbar{40}{Name} = $L{'NAVBAR.CHART_ENGINES'};
$main::navbar{90}{Name} = $L{'NAVBAR.LOGS'};

LoxBerry::Web::lbheader($L{'COMMON.LABEL_PLUGINTITLE'} . " - " . $L{'NAVBAR.LOXONE_IMPORT'}, undef, undef);

my $lang = LoxBerry::System::lblanguage();
$template->param( 'LOXONE_ELEMENTS', LoxBerry::System::read_file( "$lbptemplatedir/lang/loxelements_$lang.json" ) );

my %miniservers = LoxBerry::System::get_miniservers();
$template->param( 'LOXONE_MINISERVERS', to_json( \%miniservers ) );

print $template->output();

LoxBerry::Web::lbfooter();
```

- [ ] **Step 3: Modify input_mqtt.cgi**

Replace with:

```perl
#!/usr/bin/perl
use warnings;
use strict;
use LoxBerry::System;
use LoxBerry::Web;
use JSON;
use FindBin qw($Bin);
use lib "$Bin/../../../../bin/plugins/stats4lox/libs/";
use Globals;

our $htmlhead="";
$htmlhead = '<script type="application/javascript" src="js/vue.global.js"></script>';
$htmlhead .= '<script type="application/javascript" src="js/inputs_outputs_sub_navbar.js"></script>';
$htmlhead .= '<script type="application/javascript" src="js/input_mqtt.js"></script>';
$main::navbar{30}{active} = 1;

my $template = HTML::Template->new(
    filename => "$lbptemplatedir/input_mqtt.html",
    global_vars => 1,
    loop_context_vars => 1,
    die_on_bad_params => 0,
);

my %L = LoxBerry::Web::readlanguage($template, "language.ini");

$main::navbar{1}{Name} = $L{'NAVBAR.HOME'};
$main::navbar{10}{Name} = $L{'NAVBAR.LOXONE_IMPORT'};
$main::navbar{30}{Name} = $L{'NAVBAR.INPUTS_OUTPUTS'};
$main::navbar{40}{Name} = $L{'NAVBAR.CHART_ENGINES'};
$main::navbar{90}{Name} = $L{'NAVBAR.LOGS'};

LoxBerry::Web::lbheader($L{'MQTTCOLLECTOR.TITLE'} . " - " . $L{'COMMON.LABEL_PLUGINTITLE'}, undef, undef);

$template->param("FINDERAVAILABLE", -e '/dev/shm/mqttfinder.json' ? "true" : "" );

print $template->output();

LoxBerry::Web::lbfooter();
```

- [ ] **Step 4: Modify mqttlive_loxone.cgi**

Replace with:

```perl
#!/usr/bin/perl
use warnings;
use strict;
use LoxBerry::System;
use LoxBerry::Web;
use LoxBerry::IO;
use JSON;
use FindBin qw($Bin);
use lib "$Bin/../../../../bin/plugins/stats4lox/libs/";
use Globals;

our $htmlhead="";
$htmlhead .= '<script type="application/javascript" src="js/loxone_sub_navbar.js"></script>';
$htmlhead .= '<script type="application/javascript" src="js/mqttlive_loxone.js"></script>';

$main::navbar{10}{active} = 1;

my $template = HTML::Template->new(
    filename => "$lbptemplatedir/mqttlive_loxone.html",
    global_vars => 1,
    loop_context_vars => 1,
    die_on_bad_params => 0,
);

my %L = LoxBerry::Web::readlanguage($template, "language.ini");

$main::navbar{1}{Name} = $L{'NAVBAR.HOME'};
$main::navbar{10}{Name} = $L{'NAVBAR.LOXONE_IMPORT'};
$main::navbar{30}{Name} = $L{'NAVBAR.INPUTS_OUTPUTS'};
$main::navbar{40}{Name} = $L{'NAVBAR.CHART_ENGINES'};
$main::navbar{90}{Name} = $L{'NAVBAR.LOGS'};

LoxBerry::Web::lbheader($L{'COMMON.LABEL_PLUGINTITLE'} . " - MQTT LiveUpdate", undef, undef);

my $lang = LoxBerry::System::lblanguage();
my $mqttcred = LoxBerry::IO::mqtt_connectiondetails();

$template->param( 'MQTTLIVEDATA', LoxBerry::System::read_file( "$Globals::stats4lox->{s4ltmp}/mqttlive_uidata.json" ) );
$template->param( 'STATSJSON', LoxBerry::System::read_file( "$lbpconfigdir/stats.json" ) );
$template->param( 'MQTTGATEWAY_HOSTNAME',  lbhostname() );
$template->param( 'MQTTGATEWAY_UDPINPORT', $mqttcred->{udpinport} );

print $template->output();

LoxBerry::Web::lbfooter();
```

- [ ] **Step 5: Modify output_influx.cgi**

This file already has `readlanguage()`. Add navbar translation and fix `lbheader()`:

```perl
#!/usr/bin/perl
use warnings;
use strict;
use LoxBerry::System;
use LoxBerry::Web;
use LoxBerry::Storage;
use LoxBerry::JSON;
use FindBin qw($Bin);
use lib "$Bin/../../../../bin/plugins/stats4lox/libs/";
use Globals;

our $htmlhead="";
$htmlhead .= '<script type="application/javascript" src="js/inputs_outputs_sub_navbar.js"></script>';

my $template = HTML::Template->new(
    filename => "$lbptemplatedir/output_influx.html",
    global_vars => 1,
    loop_context_vars => 1,
    die_on_bad_params => 0,
);

# Language
my %L = LoxBerry::Web::readlanguage($template, "language.ini");

$main::navbar{1}{Name} = $L{'NAVBAR.HOME'};
$main::navbar{10}{Name} = $L{'NAVBAR.LOXONE_IMPORT'};
$main::navbar{30}{Name} = $L{'NAVBAR.INPUTS_OUTPUTS'};
$main::navbar{40}{Name} = $L{'NAVBAR.CHART_ENGINES'};
$main::navbar{90}{Name} = $L{'NAVBAR.LOGS'};

LoxBerry::Web::lbheader($L{'COMMON.LABEL_PLUGINTITLE'} . " - " . $L{'NAVBAR.INPUTS_OUTPUTS'}, undef, undef);

# Load config
my $cfgfile = $lbpconfigdir . "/stats4lox.json";
my $jsonobj = LoxBerry::JSON->new();
my $cfg = $jsonobj->open(filename => $cfgfile);

# Form preparation
$template->param( 'INFLUX_STORAGE_PATH',  LoxBerry::Storage::get_storage_html( formid => 'influxstoragepath', custom_folder => 1, readwriteonly => 1, show_browse => 1, data_mini => 1, type_all => 1, currentpath => $cfg->{'influx'}->{'db_storage'} ) );

print $template->output();

LoxBerry::Web::lbfooter();

exit;
```

- [ ] **Step 6: Modify chartengines.cgi**

Replace with:

```perl
#!/usr/bin/perl
use warnings;
use strict;
use LoxBerry::System;
use LoxBerry::Web;
use JSON;
use FindBin qw($Bin);
use lib "$Bin/../../../../bin/plugins/stats4lox/libs/";
use Globals;

my $template = HTML::Template->new(
    filename => "$lbptemplatedir/chartengines.html",
    global_vars => 1,
    loop_context_vars => 1,
    die_on_bad_params => 0,
);

my %L = LoxBerry::Web::readlanguage($template, "language.ini");

$main::navbar{1}{Name} = $L{'NAVBAR.HOME'};
$main::navbar{10}{Name} = $L{'NAVBAR.LOXONE_IMPORT'};
$main::navbar{30}{Name} = $L{'NAVBAR.INPUTS_OUTPUTS'};
$main::navbar{40}{Name} = $L{'NAVBAR.CHART_ENGINES'};
$main::navbar{90}{Name} = $L{'NAVBAR.LOGS'};

LoxBerry::Web::lbheader($L{'COMMON.LABEL_PLUGINTITLE'} . " - " . $L{'NAVBAR.CHART_ENGINES'}, undef, undef);

$template->param( 'GRAFANA_URL', "http://" . LoxBerry::System::get_localip() . ":" . $Globals::grafana->{port} );

print $template->output();

LoxBerry::Web::lbfooter();
```

- [ ] **Step 7: Modify loxone_import_report.cgi**

Replace with:

```perl
#!/usr/bin/perl
use warnings;
use strict;
use LoxBerry::System;
use LoxBerry::Web;
use JSON;
use FindBin qw($Bin);
use lib "$Bin/../../../../bin/plugins/stats4lox/libs/";
use Globals;

our $htmlhead="";
$htmlhead .= '<script type="application/javascript" src="js/loxone_sub_navbar.js"></script>';
$htmlhead .= '<script type="application/javascript" src="js/loxone_import_report.js"></script>';

$main::navbar{10}{active} = 1;

my $template = HTML::Template->new(
    filename => "$lbptemplatedir/loxone_import_report.html",
    global_vars => 1,
    loop_context_vars => 1,
    die_on_bad_params => 0,
);

my %L = LoxBerry::Web::readlanguage($template, "language.ini");

$main::navbar{1}{Name} = $L{'NAVBAR.HOME'};
$main::navbar{10}{Name} = $L{'NAVBAR.LOXONE_IMPORT'};
$main::navbar{30}{Name} = $L{'NAVBAR.INPUTS_OUTPUTS'};
$main::navbar{40}{Name} = $L{'NAVBAR.CHART_ENGINES'};
$main::navbar{90}{Name} = $L{'NAVBAR.LOGS'};

LoxBerry::Web::lbheader($L{'IMPORTREPORT.TITLE_PAGE'} . " - " . $L{'COMMON.LABEL_PLUGINTITLE'}, undef, undef);

my $lang = LoxBerry::System::lblanguage();

my %miniservers = LoxBerry::System::get_miniservers();
$template->param( 'LOXONE_MINISERVERS', to_json( \%miniservers ) );

print $template->output();

LoxBerry::Web::lbfooter();
```

- [ ] **Step 8: Modify logs.cgi**

Replace with:

```perl
#!/usr/bin/perl
use warnings;
use strict;
use LoxBerry::System;
use LoxBerry::Web;
require "$lbpbindir/libs/Globals.pm";

my $template = HTML::Template->new(
	filename => "$lbptemplatedir/logs.html",
	global_vars => 1,
	loop_context_vars => 1,
	die_on_bad_params => 0,
);

my %L = LoxBerry::Web::readlanguage($template, "language.ini");

$main::navbar{1}{Name} = $L{'NAVBAR.HOME'};
$main::navbar{10}{Name} = $L{'NAVBAR.LOXONE_IMPORT'};
$main::navbar{30}{Name} = $L{'NAVBAR.INPUTS_OUTPUTS'};
$main::navbar{40}{Name} = $L{'NAVBAR.CHART_ENGINES'};
$main::navbar{90}{Name} = $L{'NAVBAR.LOGS'};

LoxBerry::Web::lbheader($L{'COMMON.LABEL_PLUGINTITLE'} . " - " . $L{'NAVBAR.LOGS'}, "https://loxwiki.eu", undef);

$template->param('LOGLIST_HTML', LoxBerry::Web::loglist_html());
print $template->output();

LoxBerry::Web::lbfooter();
```

- [ ] **Step 9: Commit**

```bash
git add webfrontend/htmlauth/index.cgi webfrontend/htmlauth/main_loxone.cgi webfrontend/htmlauth/input_mqtt.cgi webfrontend/htmlauth/mqttlive_loxone.cgi webfrontend/htmlauth/output_influx.cgi webfrontend/htmlauth/chartengines.cgi webfrontend/htmlauth/loxone_import_report.cgi webfrontend/htmlauth/logs.cgi
git commit -m "feat(i18n): add readlanguage() and navbar translation to all CGI scripts"
```

---

## Task 5: Internationalize home.html + home.js

**Files:**
- Modify: `templates/home.html`
- Modify: `webfrontend/htmlauth/js/home.js`

- [ ] **Step 1: Replace hardcoded strings in home.html with TMPL_VAR and add i18n divs**

The home page has service status boxes with hardcoded button labels and status text. Replace all hardcoded strings and add hidden divs for JavaScript.

Replace the full content of `templates/home.html` with:

```html
<script type="text/javascript" src="./js/home.js"></script>

<style>
.datahidden {
	display:none;
}

.small {
	font-size:70%;
}

.middle {
	font-size:120%;
}

.bold {
	font-weight: bold;
}

.grayed {
	color: gray;
}

.center {
	text-align: center;
}

.grid {
	display: grid;
	grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
	grid-column-gap: 15px;
	grid-row-gap: 15px;
}
.box {
	border: 1px solid black;
}

.margin {
	margin: 10px;
}

.status {
	padding: 10px;
	box-sizing: border-box;
	border-radius: 5px 5px 5px 5px;
	margin: 10px;
	background: #dfdfdf;
	border: 1px solid #7E7E7E;
}

</style>

<!-- i18n strings for JavaScript -->
<div class="datahidden" id="i18n_status_running"><TMPL_VAR HOME.STATUS_RUNNING></div>
<div class="datahidden" id="i18n_status_stopped"><TMPL_VAR HOME.STATUS_STOPPED></div>
<div class="datahidden" id="i18n_status_disabled"><TMPL_VAR HOME.STATUS_DISABLED></div>
<div class="datahidden" id="i18n_status_failed"><TMPL_VAR HOME.STATUS_FAILED></div>
<div class="datahidden" id="i18n_status_updating"><TMPL_VAR COMMON.STATUS_UPDATING></div>
<div class="datahidden" id="i18n_status_executing"><TMPL_VAR HOME.STATUS_EXECUTING></div>
<div class="datahidden" id="i18n_status_ok"><TMPL_VAR HOME.STATUS_OK></div>
<div class="datahidden" id="i18n_status_error"><TMPL_VAR HOME.STATUS_ERROR></div>
<div class="datahidden" id="i18n_status_failed_detail"><TMPL_VAR HOME.STATUS_FAILED_DETAIL></div>

<div class="grid">
	<div class="box">
		<object data="<TMPL_VAR GRAFANA_URL>/d-solo/ff725681-27a4-408c-9491-772415f41412/plugin-home?orgId=1&refresh=60s&from=now-24h&to=now&theme=light&panelId=5" width="99%"></object>
	</div>
	<div class="box">
		<object data="<TMPL_VAR GRAFANA_URL>/d-solo/ff725681-27a4-408c-9491-772415f41412/plugin-home?orgId=1&refresh=60s&from=now-24h&to=now&theme=light&panelId=2" width="99%"></object>
	</div>
	<div class="box">
		<object data="<TMPL_VAR GRAFANA_URL>/d-solo/ff725681-27a4-408c-9491-772415f41412/plugin-home?orgId=1&refresh=60s&from=now-24h&to=now&theme=light&panelId=4" width="99%"></object>
	</div>
</div>

<br>

<div class="grid">
	<div class="box">
		<div class="center middle bold margin">Telegraf</div>
		<div class="status center" id="telegraf_status"><TMPL_VAR COMMON.STATUS_UPDATING></div>
		<a href="#" onclick="service('starttelegraf');return false;"
			class="ui-btn ui-corner-all margin ui-icon-check ui-btn-icon-left"><TMPL_VAR HOME.BUTTON_RESTART></a>
		<a href="#" onclick="service('stoptelegraf');return false;"
			class="ui-btn ui-corner-all margin ui-icon-delete ui-btn-icon-left"><TMPL_VAR HOME.BUTTON_STOP></a>
		<div class="center margin" id="telegraf_hint">&nbsp;</div>
	</div>
	<div class="box">
		<div class="center middle bold margin">InfluxDB</div>
		<div class="status center" id="influx_status"><TMPL_VAR COMMON.STATUS_UPDATING></div>
		<a href="#" onclick="service('startinfluxdb');return false;"
			class="ui-btn ui-corner-all margin ui-icon-check ui-btn-icon-left"><TMPL_VAR HOME.BUTTON_RESTART></a>
		<a href="#" onclick="service('stopinfluxdb');return false;"
			class="ui-btn ui-corner-all margin ui-icon-delete ui-btn-icon-left"><TMPL_VAR HOME.BUTTON_STOP></a>
		<div class="center margin" id="influx_hint">&nbsp;</div>
	</div>
	<div class="box">
		<div class="center middle bold margin">Grafana</div>
		<div class="status center" id="grafana-server_status"><TMPL_VAR COMMON.STATUS_UPDATING></div>
		<a href="#" onclick="service('startgrafana-server');return false;"
			class="ui-btn ui-corner-all margin ui-icon-check ui-btn-icon-left"><TMPL_VAR HOME.BUTTON_RESTART></a>
		<a href="#" onclick="service('stopgrafana-server');return false;"
			class="ui-btn ui-corner-all margin ui-icon-delete ui-btn-icon-left"><TMPL_VAR HOME.BUTTON_STOP></a>
		<div class="center margin" id="grafana-server_hint">&nbsp;</div>
	</div>
	<div class="box">
		<div class="center middle bold margin">MQTT Live/Collector</div>
		<div class="status center" id="mqttlive_status"><TMPL_VAR COMMON.STATUS_UPDATING></div>
		<a href="#" onclick="service('startmqttlive');return false;"
			class="ui-btn ui-corner-all margin ui-icon-check ui-btn-icon-left"><TMPL_VAR HOME.BUTTON_RESTART></a>
		<a href="#" onclick="service('stopmqttlive');return false;"
			class="ui-btn ui-corner-all margin ui-icon-delete ui-btn-icon-left"><TMPL_VAR HOME.BUTTON_STOP></a>
		<div class="center margin" id="mqttlive_hint">&nbsp;</div>
	</div>
</div>
```

- [ ] **Step 2: Update home.js to read from i18n divs**

Replace the full content of `webfrontend/htmlauth/js/home.js` with:

```javascript
$(function() {

	setInterval(function(){ servicestatus(); }, 5000);
	servicestatus();

});

// Read i18n strings from hidden divs
var i18n = {
	running: document.getElementById('i18n_status_running').textContent,
	stopped: document.getElementById('i18n_status_stopped').textContent,
	disabled: document.getElementById('i18n_status_disabled').textContent,
	failed: document.getElementById('i18n_status_failed').textContent,
	updating: document.getElementById('i18n_status_updating').textContent,
	executing: document.getElementById('i18n_status_executing').textContent,
	ok: document.getElementById('i18n_status_ok').textContent,
	error: document.getElementById('i18n_status_error').textContent,
	failedDetail: document.getElementById('i18n_status_failed_detail').textContent
};

// State
function servicestatus(update) {

	if (update) {
		$("#telegraf_status").attr("style", "background:#dfdfdf").html(i18n.updating);
		$("#influx_status").attr("style", "background:#dfdfdf").html(i18n.updating);
		$("#grafana-server_status").attr("style", "background:#dfdfdf").html(i18n.updating);
		$("#mqttlive_status").attr("style", "background:#dfdfdf").html(i18n.updating);
	}

	$.ajax( {
			url:  'ajax.cgi',
			type: 'POST',
			data: {
				action: 'servicestatus'
			}
		} )
	.fail(function( data ) {
		console.log( "Servicestatus Fail", data );
		$("#telegraf_status").attr("style", "background:#dfdfdf; color:red").html(i18n.failed);
		$("#influx_status").attr("style", "background:#dfdfdf; color:red").html(i18n.failed);
		$("#grafana-server_status").attr("style", "background:#dfdfdf; color:red").html(i18n.failed);
		$("#mqttlive_status").attr("style", "background:#dfdfdf; color:red").html(i18n.failed);
	})
	.done(function( data ) {
		console.log( "Servicestatus Success", data );
		if (data.telegraf) {
			$("#telegraf_status").attr("style", "background:#32DE00; color:black").html(i18n.running.replace('__PID__', data.telegraf));
		} else {
			$("#telegraf_status").attr("style", "background:#FF6339; color:black").html(i18n.stopped);
		}
		if (data.influx) {
			$("#influx_status").attr("style", "background:#32DE00; color:black").html(i18n.running.replace('__PID__', data.influx));
		} else {
			$("#influx_status").attr("style", "background:#FF6339; color:black").html(i18n.stopped);
		}
		if (data.grafanaserver) {
			$("#grafana-server_status").attr("style", "background:#32DE00; color:black").html(i18n.running.replace('__PID__', data.grafanaserver));
		} else {
			$("#grafana-server_status").attr("style", "background:#FF6339; color:black").html(i18n.stopped);
		}
		if (data.mqttlive == 'disabled') {
			$("#mqttlive_status").attr("style", "background:#ffff00; color:black").html(i18n.disabled);
		} else if (data.mqttlive) {
			$("#mqttlive_status").attr("style", "background:#32DE00; color:black").html(i18n.running.replace('__PID__', data.mqttlive));
		} else {
			$("#mqttlive_status").attr("style", "background:#FF6339; color:black").html(i18n.stopped);
		}
	})
	.always(function( data ) {
		console.log( "Servicestatus Finished", data );
	});
}

// Start / Stop Services
function service(command) {
	var service;

	if ( command == "starttelegraf" || command == "stoptelegraf" ) {
		service = "telegraf";
	}
	if ( command == "startinfluxdb" || command == "stopinfluxdb" ) {
		service = "influx";
	}
	if ( command == "startgrafana-server" || command == "stopgrafana-server" ) {
		service = "grafana-server";
	}
	if ( command == "startmqttlive" || command == "stopmqttlive" ) {
		service = "mqttlive";
	}

	$("#" + service + "_hint").attr("style", "color:blue").html(i18n.executing);
	$.ajax( {
			url:  'ajax.cgi',
			type: 'POST',
			data: {
				action: command
			}
		} )
	.fail(function( data ) {
		console.log( "Service " + command + " Fail", data );
		$("#" + service + "_hint").attr("style", "color:red").html(i18n.failedDetail.replace('__MSG__', data.statusText));
	})
	.done(function( data ) {
		console.log( "Service " + command + " Success", data );
		$("#" + service + "_hint").attr("style", "color:green").html(i18n.ok);
	})
	.always(function( data ) {
		if (data != 0) {
			$("#" + service + "_hint").attr("style", "color:red").html(i18n.error);
		}
		console.log( "Service " + command + " Finished", data );
		servicestatus(1);
	});
}
```

- [ ] **Step 3: Commit**

```bash
git add templates/home.html webfrontend/htmlauth/js/home.js
git commit -m "feat(i18n): internationalize home page and service status"
```

---

## Task 6: Internationalize output_influx.html and chartengines.html

**Files:**
- Modify: `templates/output_influx.html`
- Modify: `templates/chartengines.html`

- [ ] **Step 1: Replace hardcoded title in output_influx.html**

In `templates/output_influx.html`, replace the hardcoded `<h2>`:

```html
<!-- OLD -->
<h2>Influx Database Configuration</h2>

<!-- NEW -->
<h2><TMPL_VAR INPUTSOUTPUTS.TITLE_INFLUX_CONFIG></h2>
```

No other changes needed — this file already uses TMPL_VAR for all other strings.

- [ ] **Step 2: Replace hardcoded strings in chartengines.html**

In `templates/chartengines.html`, replace:

```html
<!-- OLD -->
<a href="<TMPL_VAR GRAFANA_URL>" class="ui-btn ui-corner-all" target="_blank">Open Grafana Webinterface</a>

<!-- NEW -->
<a href="<TMPL_VAR GRAFANA_URL>" class="ui-btn ui-corner-all" target="_blank"><TMPL_VAR CHARTENGINES.BUTTON_OPEN_GRAFANA></a>
```

- [ ] **Step 3: Commit**

```bash
git add templates/output_influx.html templates/chartengines.html
git commit -m "feat(i18n): internationalize InfluxDB config and chart engines pages"
```

---

## Task 7: Internationalize input_mqtt.html with documentation

**Files:**
- Modify: `templates/input_mqtt.html`
- Modify: `webfrontend/htmlauth/js/input_mqtt.js`

This is the core documentation improvement task.

- [ ] **Step 1: Replace input_mqtt.html content**

Replace the content from line 119 (after `</style>`) to end of file:

```html
<div class="datahidden" id="mqttgateway_hostname"><TMPL_VAR MQTTGATEWAY_HOSTNAME></div>
<div class="datahidden" id="mqttgateway_udpinport"><TMPL_VAR MQTTGATEWAY_UDPINPORT></div>

<!-- i18n strings for JavaScript -->
<div class="datahidden" id="i18n_err_invalid_topic"><TMPL_VAR MQTTCOLLECTOR.ERR_INVALID_TOPIC></div>
<div class="datahidden" id="i18n_status_unsaved"><TMPL_VAR MQTTCOLLECTOR.STATUS_UNSAVED></div>
<div class="datahidden" id="i18n_status_saved"><TMPL_VAR MQTTCOLLECTOR.STATUS_SAVED></div>
<div class="datahidden" id="i18n_status_save_ok"><TMPL_VAR MQTTCOLLECTOR.STATUS_SAVE_OK></div>
<div class="datahidden" id="i18n_err_save_failed"><TMPL_VAR MQTTCOLLECTOR.ERR_SAVE_FAILED></div>
<div class="datahidden" id="i18n_placeholder_topic"><TMPL_VAR MQTTCOLLECTOR.PLACEHOLDER_TOPIC></div>
<div class="datahidden" id="i18n_btn_delete"><TMPL_VAR MQTTCOLLECTOR.BUTTON_DELETE></div>
<div class="datahidden" id="i18n_btn_show"><TMPL_VAR MQTTCOLLECTOR.BUTTON_SHOW></div>
<div class="datahidden" id="i18n_label_extract_numbers"><TMPL_VAR MQTTCOLLECTOR.LABEL_EXTRACT_NUMBERS></div>
<div class="datahidden" id="i18n_label_collect_strings"><TMPL_VAR MQTTCOLLECTOR.LABEL_COLLECT_STRINGS></div>

<h3><TMPL_VAR MQTTCOLLECTOR.TITLE></h3>
<p>
    <TMPL_VAR MQTTCOLLECTOR.DESCRIPTION>
</p>

<!-- Inline help for topic field -->
<p class="small grayed"><TMPL_VAR MQTTCOLLECTOR.HINT_TOPIC_INLINE></p>

<!-- Hints: MQTT Collector documentation -->
<div id="hint_inputmqtt_intro" class="hintbox" style="display:none;">
    <b><TMPL_VAR MQTTCOLLECTOR.DOC_TITLE></b><br>
    <p><TMPL_VAR MQTTCOLLECTOR.DOC_INTRO></p>

    <b><TMPL_VAR MQTTCOLLECTOR.DOC_PREREQ_TITLE></b>
    <p><TMPL_VAR MQTTCOLLECTOR.DOC_PREREQ></p>

    <b><TMPL_VAR MQTTCOLLECTOR.DOC_HOWTO_TITLE></b>
    <p><TMPL_VAR MQTTCOLLECTOR.DOC_HOWTO></p>

    <b><TMPL_VAR MQTTCOLLECTOR.DOC_WILDCARDS_TITLE></b>
    <p><TMPL_VAR MQTTCOLLECTOR.DOC_WILDCARDS></p>

    <b><TMPL_VAR MQTTCOLLECTOR.DOC_JSON_TITLE></b>
    <p><TMPL_VAR MQTTCOLLECTOR.DOC_JSON></p>

    <b><TMPL_VAR MQTTCOLLECTOR.DOC_OPTIONS_TITLE></b>
    <p><TMPL_VAR MQTTCOLLECTOR.DOC_OPTIONS></p>

    <b><TMPL_VAR MQTTCOLLECTOR.DOC_DIFFERENCE_TITLE></b>
    <p><TMPL_VAR MQTTCOLLECTOR.DOC_DIFFERENCE></p>

    <a href="#" class="ui-btn ui-btn-inline ui-mini" onclick="hint_hide('hint_inputmqtt_intro');"><TMPL_VAR COMMON.BUTTON_HIDE></a>
</div>

	<div style="display:none" id="isFinderAvailable"><TMPL_VAR FINDERAVAILABLE></div>

	<div id="subscriptionList">
	<div style="display:flex;flex-wrap:wrap">
		<div v-for="(subscription, index) in subscriptions" class="topicline" style="flex-basis:100%;width:100%" >

			<div style="display:flex;flex-wrap:wrap;">
				<div style="flex:10 1 0;">
					<input v-model="subscription.id" :placeholder="placeholderTopic" v-on:input="validate(index, $event)">
				</div>
				<div style="padding:3px;flex:0 0;">
					<button data-mini="true" data-inline="true" v-on:click="this.subscriptions.splice(index, 1);this.errors.splice(index,1);changedMsg();">{{btnDelete}}</button>
				</div>
				<div v-show="finderAvailable" style="padding:3px;flex:0 0;">
					<button data-mini="true" data-inline="true" v-on:click="openFinder(index)">{{btnShow}}</button>
				</div>

			</div>

			<div class="topicerror">{{errors[index]}}</div>

			<div style="display:flex;flex-wrap:wrap;">

				<div style="padding:3px;">
					<input type="checkbox" v-on:change="changedMsg();" v-model="subscription.extractNumbers" data-role="none"> {{labelExtractNumbers}}
					<span class="small grayed">(<TMPL_VAR MQTTCOLLECTOR.HINT_EXTRACT_NUMBERS_INLINE>)</span>
				</div>

				<div style="padding:3px;">
					<input type="checkbox" data-role="none"
					v-on:change="changedMsg();" v-model="subscription.collectStrings"> {{labelCollectStrings}}
					<span class="small grayed">(<TMPL_VAR MQTTCOLLECTOR.HINT_COLLECT_STRINGS_INLINE>)</span>
				</div>
			</div>

		</div>
	</div>
	<div style="height:12px;padding:3px" v-html="statusLine"></div>
	<button data-inline="true" v-on:click="subscriptions.push( {  } )"><TMPL_VAR MQTTCOLLECTOR.BUTTON_ADD_LINE></button>
	<button data-inline="true" v-on:click="saveApply();"><TMPL_VAR COMMON.BUTTON_SAVE_APPLY></button>
	</div>
```

- [ ] **Step 2: Update input_mqtt.js to read i18n strings**

In `webfrontend/htmlauth/js/input_mqtt.js`, add i18n object reading at the top of the `$(function() {...})` block, and update the Vue data/methods:

Replace the entire `varSubscriptions` object (lines 13-83) with:

```javascript
	// Read i18n strings
	var mqtt_i18n = {
		errInvalidTopic: document.getElementById('i18n_err_invalid_topic').textContent,
		statusUnsaved: document.getElementById('i18n_status_unsaved').textContent,
		statusSaved: document.getElementById('i18n_status_saved').textContent,
		statusSaveOk: document.getElementById('i18n_status_save_ok').textContent,
		errSaveFailed: document.getElementById('i18n_err_save_failed').textContent,
		placeholderTopic: document.getElementById('i18n_placeholder_topic').textContent,
		btnDelete: document.getElementById('i18n_btn_delete').textContent,
		btnShow: document.getElementById('i18n_btn_show').textContent,
		labelExtractNumbers: document.getElementById('i18n_label_extract_numbers').textContent,
		labelCollectStrings: document.getElementById('i18n_label_collect_strings').textContent
	};

	varSubscriptions = {

		data() {
			return {
				subscriptions: [],
				errors: [],
				statusLine: "",
				finderAvailable: document.getElementById('isFinderAvailable').innerHTML == 'true' ? true : false,
				placeholderTopic: mqtt_i18n.placeholderTopic,
				btnDelete: mqtt_i18n.btnDelete,
				btnShow: mqtt_i18n.btnShow,
				labelExtractNumbers: mqtt_i18n.labelExtractNumbers,
				labelCollectStrings: mqtt_i18n.labelCollectStrings
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
					this.errors[index] = mqtt_i18n.errInvalidTopic;
				} else {
					this.errors.splice(index, 1);
				}
				this.changedMsg();
			},

			changedMsg() {
				this.statusLine='<span style="color:blue">' + mqtt_i18n.statusUnsaved + '</span>';
			},

			savedMsg() {
				this.statusLine='<span style="color:green">' + mqtt_i18n.statusSaved + '</span>';
			},


			saveApply() {
				console.log("Save and Apply");
				let formData = new FormData();
				formData.append('action', 'update_mqttsubscriptions');
				formData.append('subscriptions', JSON.stringify( this.subscriptions ) );
				const requestOptions = {
					method: "POST",
					body: formData
				};
				var self=this;
				fetch('ajax.cgi', requestOptions)
				.then( function(response) {
					console.log(response);
					if( response.ok != true ) {
						self.statusLine='<span style="color:red">' + mqtt_i18n.errSaveFailed.replace('__MSG__', response.statusText) + '</span>';
					}
					else {
						self.statusLine='<span style="color:green">' + mqtt_i18n.statusSaveOk + '</span>';
					}
				});
			},

			openFinder(index) {
				console.log("Open finder with index", index);
				window.open('/admin/system/mqtt-finder.cgi?e&q='+encodeURIComponent(this.subscriptions[index].id), 'mqttfinder');
			}
		},
		mounted() { this.getMqttSubscriptions(); }

	};
```

- [ ] **Step 3: Commit**

```bash
git add templates/input_mqtt.html webfrontend/htmlauth/js/input_mqtt.js
git commit -m "feat(i18n): internationalize MQTT Collector page with comprehensive documentation"
```

---

## Task 8: Internationalize mqttlive_loxone.html with documentation

**Files:**
- Modify: `templates/mqttlive_loxone.html`

- [ ] **Step 1: Replace hardcoded strings in mqttlive_loxone.html**

Replace from line 109 (after `</style>`) to end of file:

```html
<div class="datahidden" id="mqttlivedata_json">
    <TMPL_VAR MQTTLIVEDATA>
</div>
<div class="datahidden" id="statsjson_json">
    <TMPL_VAR STATSJSON>
</div>
<div class="datahidden" id="mqttgateway_hostname"><TMPL_VAR MQTTGATEWAY_HOSTNAME></div>
<div class="datahidden" id="mqttgateway_udpinport"><TMPL_VAR MQTTGATEWAY_UDPINPORT></div>


<h3><TMPL_VAR MQTTLIVE.TITLE></h3>
<p>
    <TMPL_VAR MQTTLIVE.DESCRIPTION>
</p>
<p>
    <TMPL_VAR MQTTLIVE.DESCRIPTION2>
</p>


<!-- Hints: MQTT LiveUpdate documentation -->
<div id="hint_mqttliveupdate_intro" class="hintbox" style="display:none;">
    <b><TMPL_VAR MQTTLIVE.DOC_TITLE></b><br>
    <p><TMPL_VAR MQTTLIVE.DOC_INTRO></p>

    <b><TMPL_VAR MQTTLIVE.DOC_PREREQ_TITLE></b>
    <p><TMPL_VAR MQTTLIVE.DOC_PREREQ></p>

    <b><TMPL_VAR MQTTLIVE.DOC_HOWTO_TITLE></b>
    <p><TMPL_VAR MQTTLIVE.DOC_HOWTO></p>

    <b><TMPL_VAR MQTTLIVE.DOC_DIFFERENCE_TITLE></b>
    <p><TMPL_VAR MQTTLIVE.DOC_DIFFERENCE></p>

    <a href="#" class="ui-btn ui-btn-inline ui-mini" onclick="hint_hide('hint_mqttliveupdate_intro');"><TMPL_VAR COMMON.BUTTON_HIDE></a>
</div>

<h3 class="popuptitle" style="margin:10px 0 0 0;"><TMPL_VAR MQTTLIVE.LABEL_LIVE_STATE></h3>

    <div style="display:flex; flex-wrap:wrap; justify-content:space-evenly; border:1px solid gray;background-color:#f4f4f4;margin:0 0 10 0;">
        <div class="mqttlivestate">
            <span class="small grayed"><TMPL_VAR MQTTLIVE.LABEL_TOPIC></span><br>
            <span id="mqttlivestate_broker_basetopic">&nbsp;</span>
        </div>
        <div class="mqttlivestate">
            <span class="small grayed"><TMPL_VAR MQTTLIVE.LABEL_CONNECTED></span><br>
            <span id="mqttlivestate_broker_connected">&nbsp;</span>
        </div>
        <div class="mqttlivestate">
            <span class="small grayed"><TMPL_VAR MQTTLIVE.LABEL_ERRORS></span><br>
            <span id="mqttlivestate_broker_error">&nbsp;</span>
        </div>
    </div>

    <h3 class="popuptitle" style="margin:10px 0 0 0;"><TMPL_VAR MQTTLIVE.TITLE_RECEIVED></h3>
    <!-- Table -->
    <div id="mqttlivediv" style="margin:auto;">


    </div>
    <div style="margin:auto;width:95%">
        <p class="bitsmall grayed"><i><TMPL_VAR MQTTLIVE.HINT_COLOR></i></p>
        <a href="#" class="ui-btn ui-btn-inline ui-mini clearuidataButton"><TMPL_VAR MQTTLIVE.BUTTON_CLEAR></a>
    </div>

    <h3 class="popuptitle" style="margin:10px 0 0 0;"><TMPL_VAR MQTTLIVE.TITLE_AVAILABLE_TOPICS></h3>
        <a href="#" download="Stats4Lox-MQTT-Gateway.xml" class="ui-btn ui-btn-inline ui-mini createVirtualOutputTemplateButton"><TMPL_VAR MQTTLIVE.BUTTON_CREATE_TEMPLATE></a>
        <div id="availabletopicsdiv" style="margin:auto;">


        </div>
```

- [ ] **Step 2: Commit**

```bash
git add templates/mqttlive_loxone.html
git commit -m "feat(i18n): internationalize MQTT LiveUpdate page with comprehensive documentation"
```

---

## Task 9: Internationalize settings_loxone.html

**Files:**
- Modify: `templates/settings_loxone.html`

- [ ] **Step 1: Replace hardcoded strings in settings_loxone.html**

This file has many hardcoded strings in the filter section and detail popup. Replace all user-visible text with TMPL_VAR. Add i18n hidden divs for labels used by `settings_loxone.js`.

Key replacements (apply all):

```
"Statistic Selection hint" → <TMPL_VAR LOXONE.HINT_SELECT_STATS_TITLE>
"Filter or search for Loxone elements..." → <TMPL_VAR LOXONE.HINT_SELECT_STATS>
"Filter" → <TMPL_VAR LOXONE.LABEL_FILTER>
"Miniserver" (in filter label) → <TMPL_VAR LOXONE.LABEL_MINISERVER>
"All Miniservers" → <TMPL_VAR LOXONE.LABEL_ALL_MINISERVERS>
"Room" → <TMPL_VAR LOXONE.LABEL_ROOM>
"All rooms" → <TMPL_VAR LOXONE.LABEL_ALL_ROOMS>
"Category" → <TMPL_VAR LOXONE.LABEL_CATEGORY>
"All categories" → <TMPL_VAR LOXONE.LABEL_ALL_CATEGORIES>
"Element" → <TMPL_VAR LOXONE.LABEL_ELEMENT>
"All elements" → <TMPL_VAR LOXONE.LABEL_ALL_ELEMENTS>
"Loxone Visu" → <TMPL_VAR LOXONE.LABEL_LOXONE_VISU>
"Loxone Statistic" → <TMPL_VAR LOXONE.LABEL_LOXONE_STAT>
"Stats4Lox Statistic" → <TMPL_VAR LOXONE.LABEL_S4L_STAT>
"All" (radio buttons) → <TMPL_VAR LOXONE.LABEL_ALL>
"On" → <TMPL_VAR COMMON.LABEL_ON>
"Off" → <TMPL_VAR COMMON.LABEL_OFF>
"Details" → <TMPL_VAR LOXONE.LABEL_DETAILS>
"Close" → <TMPL_VAR LOXONE.BUTTON_CLOSE>
"Miniserver" (in detail popup) → <TMPL_VAR LOXONE.LABEL_MINISERVER>
"Visualisation" → <TMPL_VAR LOXONE.LABEL_VISUALISATION>
"Loxone Statistics" → <TMPL_VAR LOXONE.LABEL_LOXONE_STATISTICS>
"Stats4Lox Statistics" → <TMPL_VAR LOXONE.LABEL_S4L_STATISTICS>
"activate" → <TMPL_VAR LOXONE.LABEL_ACTIVATE>
"Interval (minutes)" → <TMPL_VAR LOXONE.LABEL_INTERVAL_MINUTES>
"Measurement Label in Statistic" → <TMPL_VAR LOXONE.LABEL_MEASUREMENT_NAME>
"This uniquely identifies..." → <TMPL_VAR LOXONE.HINT_MEASUREMENT_NAME>
"Import selected outputs..." → <TMPL_VAR LOXONE.LABEL_IMPORT_SELECTED>
"Import button hint:" → <TMPL_VAR LOXONE.HINT_IMPORT_BUTTON_TITLE>
"To import your Loxone..." → <TMPL_VAR LOXONE.HINT_IMPORT_BUTTON>
"Import Now" → <TMPL_VAR LOXONE.BUTTON_IMPORT_NOW>
"Processing Errors" → <TMPL_VAR LOXONE.TITLE_PROCESSING_ERRORS>
"Progress" → <TMPL_VAR LOXONE.TITLE_PROGRESS>
"Hide" (all instances) → <TMPL_VAR COMMON.BUTTON_HIDE>
```

Also add i18n hidden divs at the top (after `<div class="datahidden" id="miniservers_json">...</div>`):

```html
<!-- i18n strings for settings_loxone.js -->
<div class="datahidden" id="i18n_label_miniserver"><TMPL_VAR LOXONE.LABEL_MINISERVER></div>
<div class="datahidden" id="i18n_label_visualisation"><TMPL_VAR LOXONE.LABEL_VISUALISATION></div>
<div class="datahidden" id="i18n_label_loxone_statistics"><TMPL_VAR LOXONE.LABEL_LOXONE_STATISTICS></div>
<div class="datahidden" id="i18n_label_s4l_statistics"><TMPL_VAR LOXONE.LABEL_S4L_STATISTICS></div>
<div class="datahidden" id="i18n_label_activate"><TMPL_VAR LOXONE.LABEL_ACTIVATE></div>
<div class="datahidden" id="i18n_label_interval_minutes"><TMPL_VAR LOXONE.LABEL_INTERVAL_MINUTES></div>
<div class="datahidden" id="i18n_label_measurement_name"><TMPL_VAR LOXONE.LABEL_MEASUREMENT_NAME></div>
<div class="datahidden" id="i18n_button_import_now"><TMPL_VAR LOXONE.BUTTON_IMPORT_NOW></div>
```

- [ ] **Step 2: Commit**

```bash
git add templates/settings_loxone.html
git commit -m "feat(i18n): internationalize Loxone settings page"
```

---

## Task 10: Internationalize loxone_import_report.html + loxone_import_report.js

**Files:**
- Modify: `templates/loxone_import_report.html`
- Modify: `webfrontend/htmlauth/js/loxone_import_report.js`

- [ ] **Step 1: Replace hardcoded strings in loxone_import_report.html**

Replace from line 98 (after `</style>`) to end with:

```html
<div class="datahidden" id="miniservers_json"><TMPL_VAR LOXONE_MINISERVERS></div>

<!-- i18n strings for loxone_import_report.js -->
<div class="datahidden" id="i18n_label_miniserver"><TMPL_VAR LOXONE.LABEL_MINISERVER></div>
<div class="datahidden" id="i18n_label_started"><TMPL_VAR IMPORTREPORT.LABEL_STARTED></div>
<div class="datahidden" id="i18n_label_progress"><TMPL_VAR IMPORTREPORT.LABEL_PROGRESS></div>
<div class="datahidden" id="i18n_label_current_month"><TMPL_VAR IMPORTREPORT.LABEL_CURRENT_MONTH></div>
<div class="datahidden" id="i18n_label_estimated_end"><TMPL_VAR IMPORTREPORT.LABEL_ESTIMATED_END></div>
<div class="datahidden" id="i18n_label_finished"><TMPL_VAR IMPORTREPORT.LABEL_FINISHED></div>
<div class="datahidden" id="i18n_label_finished_error"><TMPL_VAR IMPORTREPORT.LABEL_FINISHED_ERROR></div>
<div class="datahidden" id="i18n_label_duration"><TMPL_VAR IMPORTREPORT.LABEL_DURATION></div>
<div class="datahidden" id="i18n_label_imported_records"><TMPL_VAR IMPORTREPORT.LABEL_IMPORTED_RECORDS></div>
<div class="datahidden" id="i18n_label_error_month"><TMPL_VAR IMPORTREPORT.LABEL_ERROR_MONTH></div>
<div class="datahidden" id="i18n_label_last_update"><TMPL_VAR IMPORTREPORT.LABEL_LAST_UPDATE></div>
<div class="datahidden" id="i18n_label_error"><TMPL_VAR IMPORTREPORT.LABEL_ERROR></div>
<div class="datahidden" id="i18n_btn_open_log"><TMPL_VAR IMPORTREPORT.BUTTON_OPEN_LOG></div>
<div class="datahidden" id="i18n_btn_reimport"><TMPL_VAR IMPORTREPORT.BUTTON_REIMPORT></div>
<div class="datahidden" id="i18n_btn_retry"><TMPL_VAR IMPORTREPORT.BUTTON_RETRY></div>
<div class="datahidden" id="i18n_btn_delete"><TMPL_VAR COMMON.BUTTON_DELETE></div>
<div class="datahidden" id="i18n_empty_running"><TMPL_VAR IMPORTREPORT.EMPTY_RUNNING></div>
<div class="datahidden" id="i18n_empty_waiting"><TMPL_VAR IMPORTREPORT.EMPTY_WAITING></div>
<div class="datahidden" id="i18n_empty_finished"><TMPL_VAR IMPORTREPORT.EMPTY_FINISHED></div>
<div class="datahidden" id="i18n_empty_error"><TMPL_VAR IMPORTREPORT.EMPTY_ERROR></div>
<div class="datahidden" id="i18n_empty_dead"><TMPL_VAR IMPORTREPORT.EMPTY_DEAD></div>
<div class="datahidden" id="i18n_status_updating"><TMPL_VAR COMMON.STATUS_UPDATING></div>


<!-- Delete popup -->
<div data-role="popup" id="popupDeleteImport" data-dismissible="false" style="max-width:400px">
	<div style="padding: 20px 20px;">
		<h4 class="ui-title popuptitle"><TMPL_VAR IMPORTREPORT.POPUP_DELETE_TITLE></h4>
		<div id="deleteImportText">
			<p>
				<span id="popupDeleteImport_uid"></span><br>
				<span id="popupDeleteImport_name"></span><br>
			<p>
				<TMPL_VAR IMPORTREPORT.POPUP_DELETE_TEXT>
			</p>
			<p>
				<TMPL_VAR IMPORTREPORT.POPUP_DELETE_NOTE>
			</p>

		</div>
	</div>
</div>

<p><TMPL_VAR IMPORTREPORT.DESCRIPTION></p>

<div data-role="collapsible" data-collapsed="false" id="coll_running" data-mini="true" data-inset="false" class="coll_heading_running">
	<h4><TMPL_VAR IMPORTREPORT.SECTION_RUNNING></h4>
	<div>
		<table class="importreport_table importreport_table_running" id="data_importreport_running">
			<tbody>
			<tr><td><TMPL_VAR COMMON.STATUS_UPDATING></td></tr>
			</tbody>
		</table>
	</div>
</div>

<div data-role="collapsible" data-collapsed="false" id="coll_scheduled" data-mini="true" data-inset="false" class="coll_heading_scheduled">
    <h4><TMPL_VAR IMPORTREPORT.SECTION_WAITING></h4>
   <div>
		<table class="importreport_table importreport_table_scheduled" id="data_importreport_scheduled">
			<tbody>
			<tr><td><TMPL_VAR COMMON.STATUS_UPDATING></td></tr>
			</tbody>
		</table>
	</div>
</div>

<div data-role="collapsible" data-collapsed="false" id="coll_finished" data-mini="true" data-inset="false" class="coll_heading_finished">
    <h4><TMPL_VAR IMPORTREPORT.SECTION_FINISHED></h4>
    <div>
		<table class="importreport_table importreport_table_finished" id="data_importreport_finished">
			<tbody>
			<tr><td><TMPL_VAR COMMON.STATUS_UPDATING></td></tr>
			</tbody>
		</table>
	</div>
</div>

<div data-role="collapsible" data-collapsed="false" id="coll_error" data-mini="true" data-inset="false" class="coll_heading_error">
    <h4><TMPL_VAR IMPORTREPORT.SECTION_ERROR></h4>
    <div>
		<table class="importreport_table importreport_table_error" id="data_importreport_error">
			<tbody>
			<tr><td><TMPL_VAR COMMON.STATUS_UPDATING></td></tr>
			</tbody>
		</table>
	</div>
</div>


<div data-role="collapsible" data-collapsed="false" id="coll_dead" data-mini="true" data-inset="false" class="coll_heading_dead">
    <h4><TMPL_VAR IMPORTREPORT.SECTION_DEAD></h4>
    <div>
		<table class="importreport_table importreport_table_dead" id="data_importreport_dead">
			<tbody>
			<tr><td><TMPL_VAR COMMON.STATUS_UPDATING></td></tr>
			</tbody>
		</table>
	</div>
</div>

<!-- Table -->
<div class="datahidden" id="reportstablediv">
</div>
```

- [ ] **Step 2: Update loxone_import_report.js to read i18n strings**

Add at the top of the file (before `let miniservers;`):

```javascript
// i18n strings - read after DOM is ready
var ir_i18n = {};
```

Then inside `$(function() {...})`, add right after `restore_hints_hide()`:

```javascript
	// Read i18n strings from hidden divs
	ir_i18n = {
		miniserver: document.getElementById('i18n_label_miniserver').textContent,
		started: document.getElementById('i18n_label_started').textContent,
		progress: document.getElementById('i18n_label_progress').textContent,
		currentMonth: document.getElementById('i18n_label_current_month').textContent,
		estimatedEnd: document.getElementById('i18n_label_estimated_end').textContent,
		finished: document.getElementById('i18n_label_finished').textContent,
		finishedError: document.getElementById('i18n_label_finished_error').textContent,
		duration: document.getElementById('i18n_label_duration').textContent,
		importedRecords: document.getElementById('i18n_label_imported_records').textContent,
		errorMonth: document.getElementById('i18n_label_error_month').textContent,
		lastUpdate: document.getElementById('i18n_label_last_update').textContent,
		error: document.getElementById('i18n_label_error').textContent,
		btnOpenLog: document.getElementById('i18n_btn_open_log').textContent,
		btnReimport: document.getElementById('i18n_btn_reimport').textContent,
		btnRetry: document.getElementById('i18n_btn_retry').textContent,
		btnDelete: document.getElementById('i18n_btn_delete').textContent,
		emptyRunning: document.getElementById('i18n_empty_running').textContent,
		emptyWaiting: document.getElementById('i18n_empty_waiting').textContent,
		emptyFinished: document.getElementById('i18n_empty_finished').textContent,
		emptyError: document.getElementById('i18n_empty_error').textContent,
		emptyDead: document.getElementById('i18n_empty_dead').textContent,
		updating: document.getElementById('i18n_status_updating').textContent
	};
```

Then in `updateReportTables()`, replace all hardcoded strings with `ir_i18n.*` references. Key replacements in the template literals:

```
"Miniserver" → ${ir_i18n.miniserver}
"Started" → ${ir_i18n.started}
"Progress" → ${ir_i18n.progress}
"Current month" → ${ir_i18n.currentMonth}
"Estimated end" → ${ir_i18n.estimatedEnd}
"Finished" → ${ir_i18n.finished}
"Finished (with error)" → ${ir_i18n.finishedError}
"Duration" → ${ir_i18n.duration}
"Imported records" → ${ir_i18n.importedRecords}
"Error on month" → ${ir_i18n.errorMonth}
"Last Update of Import" → ${ir_i18n.lastUpdate}
"Error" → ${ir_i18n.error}
"Open Logfile" → ${ir_i18n.btnOpenLog}
"Re-Import" → ${ir_i18n.btnReimport}
"Retry Import" → ${ir_i18n.btnRetry}
"Delete" → ${ir_i18n.btnDelete}
"Currently no running imports." → ${ir_i18n.emptyRunning}
"Currently no waiting imports." → ${ir_i18n.emptyWaiting}
"No imports finished yet." → ${ir_i18n.emptyFinished}
"No imports with errors." → ${ir_i18n.emptyError}
"No dead imports." → ${ir_i18n.emptyDead}
```

- [ ] **Step 3: Commit**

```bash
git add templates/loxone_import_report.html webfrontend/htmlauth/js/loxone_import_report.js
git commit -m "feat(i18n): internationalize import report page"
```

---

## Task 11: Final review and PR commit

- [ ] **Step 1: Verify all files are consistent**

Check that:
- All TMPL_VAR keys used in templates exist in both language_en.ini and language_de.ini
- All i18n div IDs in templates match the getElementById calls in JS files
- No hardcoded English strings remain in templates (except technical terms)

```bash
# Find any remaining hardcoded English in templates (excluding CSS, scripts, TMPL_VAR)
grep -n "Updating\.\.\." templates/*.html
grep -n "Running" templates/*.html
grep -n "Stopped" templates/*.html
grep -n "Hide" templates/*.html
```

- [ ] **Step 2: Final commit if any fixes needed**

```bash
git add -A
git commit -m "fix(i18n): address review findings"
```

- [ ] **Step 3: Create PR**

```bash
gh pr create --title "feat: GUI internationalization (DE/EN/NL/FR/ES) + MQTT documentation" --body "$(cat <<'EOF'
## Summary
- Complete GUI internationalization in 5 languages (DE primary, EN fallback, NL/FR/ES stubs)
- Comprehensive MQTT Collector documentation with inline help, step-by-step guide, wildcard examples, JSON payload explanation
- Comprehensive MQTT LiveUpdate documentation with setup guide and difference explanation
- All pages translated: Home, Loxone & Import, Inputs/Outputs, Chart Engines, Logs, Import Report

## Changes
- **5 new language files** (templates/lang/language_XX.ini)
- **8 CGI scripts** updated with readlanguage() and translated navbar
- **7 HTML templates** converted from hardcoded English to TMPL_VAR
- **4 JavaScript files** updated to read translated strings from i18n divs

## Technical approach
- Uses LoxBerry's built-in readlanguage() with INI language files
- JavaScript reads translations from hidden divs rendered by HTML::Template
- NL/FR/ES are EN copies — community can translate later, EN fallback works automatically

## Test plan
- [ ] Verify German GUI on LoxBerry with `de` language setting
- [ ] Verify English fallback on LoxBerry with `en` language setting
- [ ] Verify MQTT Collector documentation displays correctly
- [ ] Verify MQTT LiveUpdate documentation displays correctly
- [ ] Verify all service status messages on home page
- [ ] Verify import report labels and status messages
- [ ] Verify navbar shows translated names on all pages

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```
