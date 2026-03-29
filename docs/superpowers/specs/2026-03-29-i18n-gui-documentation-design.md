# Design: GUI-Lokalisierung & Dokumentationsverbesserung

## Zusammenfassung

Vollstaendige Internationalisierung (i18n) der Stats4Lox-NG Plugin-GUI in 5 Sprachen (DE, EN, NL, FR, ES) sowie umfassende Verbesserung der MQTT Collector und MQTT LiveUpdate Dokumentation direkt in der GUI. Ergebnis wird als Pull Request bereitgestellt.

## Sprachen

| Code | Sprache | Umfang |
|------|---------|--------|
| `de` | Deutsch | Vollstaendig (primaere Sprache) |
| `en` | Englisch | Vollstaendig (Fallback) |
| `nl` | Niederlaendisch | Initial Kopie von EN, spaeter uebersetzbar |
| `fr` | Franzoesisch | Initial Kopie von EN, spaeter uebersetzbar |
| `es` | Spanisch | Initial Kopie von EN, spaeter uebersetzbar |

LoxBerry-Fallback-Kette: Benutzersprache -> EN -> Hardcoded.

## Technisches Pattern

Folgt dem etablierten LoxBerry-Plugin i18n-Pattern (vgl. Weather4Lox):

### 1. Sprachdateien (INI-Format)

Pfad: `templates/lang/language_XX.ini`

```ini
[SECTION]
KEY="Wert"
```

Prefixe: `LABEL_` (Labels), `HINT_` (Hilfe), `ERR_` (Fehler), `OK_` (Erfolg), `BUTTON_` (Buttons), `STATUS_` (Statusmeldungen), `TITLE_` (Ueberschriften), `DOC_` (Dokumentation)

### 2. CGI-Skripte

Template MUSS vor `readlanguage()` erstellt werden:

```perl
my $template = HTML::Template->new(
    filename => "$lbptemplatedir/xxx.html",
    global_vars => 1,
    loop_context_vars => 1,
    die_on_bad_params => 0,
);
my %L = LoxBerry::Web::readlanguage($template, "language.ini");
```

### 3. HTML-Templates

Hardcoded Strings werden durch Template-Variablen ersetzt:

```html
<!-- vorher -->
<h3>MQTT Collector</h3>

<!-- nachher -->
<h3><TMPL_VAR MQTTCOLLECTOR.TITLE></h3>
```

### 4. JavaScript-Strings

Werden via Template-Variablen in Hidden-Divs eingebettet, die JS lesen kann:

```html
<!-- Template -->
<div class="datahidden" id="i18n_status_running"><TMPL_VAR HOME.STATUS_RUNNING></div>

<!-- JavaScript -->
var txt_running = document.getElementById('i18n_status_running').textContent;
```

### 5. Navbar-Uebersetzung

`Globals.pm` kann Navbar nicht uebersetzen (wird vor `readlanguage()` geladen). Stattdessen: Jedes CGI-Skript ueberschreibt die Navbar-Namen nach `readlanguage()`:

```perl
$main::navbar{1}{Name} = $L{'NAVBAR.HOME'};
$main::navbar{10}{Name} = $L{'NAVBAR.LOXONE_IMPORT'};
# ... etc.
```

---

## Sektionen der Sprachdateien

### [COMMON]

Gemeinsame, seitenuebergreifende Strings.

| Key | DE | EN |
|-----|----|----|
| `LABEL_PLUGINTITLE` | `"Stats4Lox"` | `"Stats4Lox"` |
| `LABEL_LOG` | `"Logdatei"` | `"Logfile"` |
| `LABEL_LOGS` | `"Logdateien"` | `"Logfiles"` |
| `BUTTON_OK` | `"OK"` | `"OK"` |
| `LABEL_ON` | `"An"` | `"On"` |
| `LABEL_OFF` | `"Aus"` | `"Off"` |
| `HINT_PLEASE_WAIT` | `"Einen Moment..."` | `"One moment..."` |
| `ERROR_COULD_NOT_GET_DATA` | `"Die angeforderten Daten konnten nicht abgerufen werden."` | `"Could not query the requested data."` |
| `YES` | `"Ja"` | `"Yes"` |
| `NO` | `"Nein"` | `"No"` |
| `MISSING` | `"Fehlt"` | `"Missing"` |
| `BUTTON_HIDE` | `"Ausblenden"` | `"Hide"` |
| `BUTTON_SAVE_APPLY` | `"Speichern und anwenden"` | `"Save and Apply"` |
| `BUTTON_DELETE` | `"Loeschen"` | `"Delete"` |
| `STATUS_UPDATING` | `"Aktualisiere..."` | `"Updating..."` |

### [NAVBAR]

| Key | DE | EN |
|-----|----|----|
| `HOME` | `"Startseite"` | `"Home"` |
| `LOXONE_IMPORT` | `"Loxone & Import"` | `"Loxone and Import"` |
| `INPUTS_OUTPUTS` | `"Ein-/Ausgaenge"` | `"Inputs / Outputs"` |
| `CHART_ENGINES` | `"Diagramme"` | `"Chart Engines"` |
| `LOGS` | `"Logs"` | `"Logs"` |

### [HOME]

Service-Status Seite (home.html + home.js).

| Key | DE | EN |
|-----|----|----|
| `STATUS_RUNNING` | `"Laeuft (PID __PID__)"` | `"Running (PID __PID__)"` |
| `STATUS_STOPPED` | `"Gestoppt"` | `"Stopped"` |
| `STATUS_DISABLED` | `"Per Konfiguration deaktiviert"` | `"Disabled by config"` |
| `STATUS_FAILED` | `"Fehlgeschlagen"` | `"Failed"` |
| `BUTTON_RESTART` | `"(Neu)Start"` | `"(Re)Start"` |
| `BUTTON_STOP` | `"Stopp"` | `"Stop"` |
| `STATUS_EXECUTING` | `"Wird ausgefuehrt..."` | `"Executing..."` |
| `STATUS_OK` | `"OK"` | `"OK"` |
| `STATUS_ERROR` | `"Fehler"` | `"Error"` |
| `STATUS_FAILED_DETAIL` | `"Fehlgeschlagen: __MSG__"` | `"Failed: __MSG__"` |

Platzhalter `__PID__` und `__MSG__` werden per JavaScript ersetzt.

### [INPUTSOUTPUTS]

InfluxDB-Konfigurationsseite (output_influx.html).

| Key | DE | EN |
|-----|----|----|
| `LABEL_INFLUX_STORAGE_PATH` | `"Datenbank-Speicherort:"` | `"Database Storage:"` |
| `HINT_INFLUX_STORAGE_PATH` | `"Hier speichert InfluxDB die Datenbank. Verwenden Sie moeglichst ein externes USB-Speichergeraet."` | `"This is where Influx stores its database. Use an external USB storage device if possible."` |
| `BUTTON_SAVE` | `"Speichern und anwenden"` | `"Save and Apply"` |
| `POPUP_SAVING_TITLE` | `"Speichern..."` | `"Saving..."` |
| `HINT_SAVING` | `"Einstellungen werden aktiviert. Dies kann einen Moment dauern."` | `"Activating your settings. This may take some time."` |
| `HINT_SAVING_PREPARING` | `"Konfigurations-Aenderungen werden vorbereitet..."` | `"Preparing config changes..."` |
| `HINT_SAVING_FAIL` | `"Fehler bei der Uebertragung. Bitte pruefen Sie die Logdatei 'Config-Handler' und/oder 'AJAX'."` | `"Error while transmitting your request. Please refer to the latest logfile 'Config-Handler' and/or 'AJAX'."` |
| `HINT_SAVING_ERROR` | `"Beim Aktivieren der Einstellungen ist ein Problem aufgetreten. Bitte pruefen Sie die Logdatei."` | `"There was a problem activating your settings. Please refer to the latest logfile."` |
| `HINT_SAVING_SUCCESS` | `"Einstellungen wurden erfolgreich gespeichert und aktiviert."` | `"Your new settings were saved and activated successfully."` |
| `HINT_OPEN_LOGFILE` | `"Logdatei oeffnen"` | `"Open Logfile"` |
| `TITLE_INFLUX_CONFIG` | `"InfluxDB Konfiguration"` | `"Influx Database Configuration"` |

### [CHARTENGINES]

Grafana-Seite (chartengines.html).

| Key | DE | EN |
|-----|----|----|
| `BUTTON_OPEN_GRAFANA` | `"Grafana Weboberflaeche oeffnen"` | `"Open Grafana Webinterface"` |

### [LOXONE]

Loxone-Einstellungen und Import (settings_loxone.html).

| Key | DE | EN |
|-----|----|----|
| `HINT_SELECT_STATS_TITLE` | `"Hinweis zur Statistikauswahl"` | `"Statistic Selection hint"` |
| `HINT_SELECT_STATS` | `"Filtern oder suchen Sie nach Loxone-Elementen, fuer die Sie Statistiken aktivieren moechten. Druecken Sie den Detail-Button, um Live-Daten vom Miniserver abzurufen, und waehlen Sie das Intervall und die Ausgaenge, die aufgezeichnet werden sollen. Aenderungen in der Detailansicht werden sofort uebernommen (kein Speichern-Button noetig)."` | `"Filter or search for Loxone elements you want to activate statistics for. Press the Details button to get live data from the Miniserver, and select the interval and outputs you want to record. Changes in the Details view are applied immediately (no Save button)."` |
| `LABEL_FILTER` | `"Filter"` | `"Filter"` |
| `LABEL_MINISERVER` | `"Miniserver"` | `"Miniserver"` |
| `LABEL_ALL_MINISERVERS` | `"Alle Miniserver"` | `"All Miniservers"` |
| `LABEL_ROOM` | `"Raum"` | `"Room"` |
| `LABEL_ALL_ROOMS` | `"Alle Raeume"` | `"All rooms"` |
| `LABEL_CATEGORY` | `"Kategorie"` | `"Category"` |
| `LABEL_ALL_CATEGORIES` | `"Alle Kategorien"` | `"All categories"` |
| `LABEL_ELEMENT` | `"Element"` | `"Element"` |
| `LABEL_ALL_ELEMENTS` | `"Alle Elemente"` | `"All elements"` |
| `LABEL_LOXONE_VISU` | `"Loxone Visu"` | `"Loxone Visu"` |
| `LABEL_LOXONE_STAT` | `"Loxone Statistik"` | `"Loxone Statistic"` |
| `LABEL_S4L_STAT` | `"Stats4Lox Statistik"` | `"Stats4Lox Statistic"` |
| `LABEL_ALL` | `"Alle"` | `"All"` |
| `LABEL_DETAILS` | `"Details"` | `"Details"` |
| `LABEL_VISUALISATION` | `"Visualisierung"` | `"Visualisation"` |
| `LABEL_S4L_STATISTICS` | `"Stats4Lox Statistik"` | `"Stats4Lox Statistics"` |
| `LABEL_ACTIVATE` | `"aktivieren"` | `"activate"` |
| `LABEL_INTERVAL_MINUTES` | `"Intervall (Minuten)"` | `"Interval (minutes)"` |
| `LABEL_MEASUREMENT_NAME` | `"Measurement-Name in der Statistik"` | `"Measurement Label in Statistic"` |
| `HINT_MEASUREMENT_NAME` | `"Dieser Name identifiziert die Daten eindeutig in Ihrer Statistik. Das Feld ist Pflicht. <b>Wenn Sie diesen Namen aendern, werden alle weiteren Daten unter dem neuen Namen gespeichert.</b>"` | `"This uniquely identifies data in your statistic. The field is mandatory. <b>If you change this, all further data will be stored to the new label.</b>"` |
| `LABEL_IMPORT_SELECTED` | `"Ausgewaehlte Ausgaenge aus Loxone-Statistik importieren"` | `"Import selected outputs from your Loxone Statistic"` |
| `HINT_IMPORT_BUTTON_TITLE` | `"Hinweis zum Import"` | `"Import button hint"` |
| `HINT_IMPORT_BUTTON` | `"Um Loxone-Statistiken zu importieren, muessen Sie <i>Stats4Lox Statistik</i> aktivieren und rechts Ausgaenge auswaehlen. Loxone-Statistiken enthalten nur eine Teilmenge der verfuegbaren Ausgaenge. Ein Symbol an jedem Ausgang zeigt an, ob diese Daten beim Import in diesen Ausgang uebernommen werden. Durch Klick auf 'Jetzt importieren' wird der Import in die Warteschlange gestellt und im Hintergrund ausgefuehrt."` | `"To import your Loxone Statistics, you need to activate Stats4Lox Statistics and select outputs on the right. Loxone statistics only contain a subset of available outputs. A symbol on every output signals that this data will be imported to that output if checked. If you press Import Now, the import is queued and imported in the background."` |
| `BUTTON_IMPORT_NOW` | `"Jetzt importieren"` | `"Import Now"` |
| `TITLE_PROCESSING_ERRORS` | `"Verarbeitungsfehler"` | `"Processing Errors"` |
| `TITLE_PROGRESS` | `"Fortschritt"` | `"Progress"` |
| `BUTTON_CLOSE` | `"Schliessen"` | `"Close"` |

### [IMPORTREPORT]

Import-Bericht Seite (loxone_import_report.html + loxone_import_report.js).

| Key | DE | EN |
|-----|----|----|
| `TITLE_PAGE` | `"Statistik-Import Bericht"` | `"Statistic Import Report"` |
| `DESCRIPTION` | `"Diese Seite zeigt alle Loxone-Statistik-Importe die laufen, warten und abgeschlossen sind. Die Seite aktualisiert sich automatisch."` | `"This page shows all Loxone statistic imports that are running, waiting and have finished. The page refreshes automatically."` |
| `SECTION_RUNNING` | `"Laufend"` | `"Running"` |
| `SECTION_WAITING` | `"Wartend"` | `"Waiting"` |
| `SECTION_FINISHED` | `"Abgeschlossen"` | `"Finished"` |
| `SECTION_ERROR` | `"Fehler"` | `"Error"` |
| `SECTION_DEAD` | `"Abgebrochen"` | `"Dead"` |
| `LABEL_STARTED` | `"Gestartet"` | `"Started"` |
| `LABEL_PROGRESS` | `"Fortschritt"` | `"Progress"` |
| `LABEL_CURRENT_MONTH` | `"Aktueller Monat"` | `"Current month"` |
| `LABEL_ESTIMATED_END` | `"Voraussichtliches Ende"` | `"Estimated end"` |
| `LABEL_FINISHED` | `"Abgeschlossen"` | `"Finished"` |
| `LABEL_FINISHED_ERROR` | `"Abgeschlossen (mit Fehler)"` | `"Finished (with error)"` |
| `LABEL_DURATION` | `"Dauer"` | `"Duration"` |
| `LABEL_IMPORTED_RECORDS` | `"Importierte Datensaetze"` | `"Imported records"` |
| `LABEL_ERROR_MONTH` | `"Fehler bei Monat"` | `"Error on month"` |
| `LABEL_LAST_UPDATE` | `"Letztes Update des Imports"` | `"Last Update of Import"` |
| `LABEL_ERROR` | `"Fehler"` | `"Error"` |
| `BUTTON_OPEN_LOG` | `"Logdatei oeffnen"` | `"Open Logfile"` |
| `BUTTON_REIMPORT` | `"Erneut importieren"` | `"Re-Import"` |
| `BUTTON_RETRY` | `"Import wiederholen"` | `"Retry Import"` |
| `EMPTY_RUNNING` | `"Derzeit keine laufenden Importe."` | `"Currently no running imports."` |
| `EMPTY_WAITING` | `"Derzeit keine wartenden Importe."` | `"Currently no waiting imports."` |
| `EMPTY_FINISHED` | `"Noch keine Importe abgeschlossen."` | `"No imports finished yet."` |
| `EMPTY_ERROR` | `"Keine Importe mit Fehlern."` | `"No imports with errors."` |
| `EMPTY_DEAD` | `"Keine abgebrochenen Importe."` | `"No dead imports."` |
| `POPUP_DELETE_TITLE` | `"Import-Status loeschen?"` | `"Delete Import Status?"` |
| `POPUP_DELETE_TEXT` | `"Damit wird der Import-<u>Auftrag</u> (falls noch nicht ausgefuehrt) oder die Statusinformation eines abgeschlossenen Imports vollstaendig geloescht. Stats4Lox merkt sich danach nicht mehr, dass diese Statistik importiert wurde."` | `"This will completely delete the Import job (if not executed yet), or the status information of a finished Import. After deletion, Stats4Lox does not remember that you have imported that statistics."` |
| `POPUP_DELETE_NOTE` | `"Dies hat <i>keinen</i> Einfluss auf Ihre Daten in der Datenbank, die Einstellungen der aktivierten Statistikerfassung oder Ihre Statistiken auf dem Miniserver."` | `"This does not touch your data in the database, the settings of activated statistic collection, and much less your statistics on your Miniserver."` |

### [MQTTCOLLECTOR]

MQTT Collector Seite (input_mqtt.html + input_mqtt.js) -- Kernbereich der Doku-Verbesserung.

| Key | DE | EN |
|-----|----|----|
| `TITLE` | `"MQTT Collector"` | `"MQTT Collector"` |
| `DESCRIPTION` | `"Abonnieren Sie MQTT-Topics, deren Daten Stats4Lox direkt in die InfluxDB schreiben soll."` | `"Subscribe to MQTT topics that Stats4Lox should directly push to the Influx database."` |
| `PLACEHOLDER_TOPIC` | `"Neues Topic eintragen"` | `"Add new subscription"` |
| `LABEL_EXTRACT_NUMBERS` | `"Zahlen extrahieren"` | `"Extract Numbers"` |
| `LABEL_COLLECT_STRINGS` | `"Strings sammeln"` | `"Collect Strings"` |
| `BUTTON_ADD_LINE` | `"Neue Zeile hinzufuegen"` | `"Add new line"` |
| `BUTTON_DELETE` | `"Loeschen"` | `"Delete"` |
| `BUTTON_SHOW` | `"Anzeigen"` | `"Show"` |
| `ERR_INVALID_TOPIC` | `"Die Syntax ist kein gueltiges MQTT-Topic."` | `"The syntax is not a valid MQTT subscription."` |
| `STATUS_UNSAVED` | `"Ungespeicherte Aenderungen"` | `"Unsaved changes"` |
| `STATUS_SAVED` | `"Aenderungen gespeichert"` | `"Saved changes"` |
| `STATUS_SAVE_OK` | `"Aenderungen gespeichert."` | `"Saved your changes."` |
| `ERR_SAVE_FAILED` | `"Fehler beim Speichern: __MSG__"` | `"Error saving: __MSG__"` |

**Inline-Hilfe (direkt bei den Feldern):**

| Key | DE | EN |
|-----|----|----|
| `HINT_TOPIC_INLINE` | `"MQTT-Topic, z.B. <code>sensor/temperatur</code> -- Wildcards: <code>+</code> (eine Ebene), <code>#</code> (alle Unterebenen)"` | `"MQTT topic, e.g. <code>sensor/temperature</code> -- Wildcards: <code>+</code> (single level), <code>#</code> (all sub-levels)"` |
| `HINT_EXTRACT_NUMBERS_INLINE` | `"Versucht Zahlenwerte aus Strings zu extrahieren, z.B. <code>12.4</code> aus <code>12.4C</code>"` | `"Tries to extract numeric values from strings, e.g. <code>12.4</code> from <code>12.4C</code>"` |
| `HINT_COLLECT_STRINGS_INLINE` | `"Speichert auch Text-Werte in InfluxDB (nicht nur Zahlen)"` | `"Also stores text values in InfluxDB (not just numbers)"` |

**Ausfuehrliche Dokumentation (ausklappbarer Bereich):**

| Key | DE | EN |
|-----|----|----|
| `DOC_TITLE` | `"Was ist der MQTT Collector?"` | `"What is MQTT Collector?"` |
| `DOC_INTRO` | `"Mit dem MQTT Collector koennen Sie Daten von beliebigen MQTT-Geraeten direkt in Ihre InfluxDB speichern -- ohne den Umweg ueber den Loxone Miniserver. Das ist ideal fuer Geraete wie Tasmota-Steckdosen, Shelly-Sensoren, Hoymiles-Wechselrichter oder andere MQTT-faehige Geraete."` | `"With MQTT Collector you can store data from any MQTT device directly into your InfluxDB -- without routing through the Loxone Miniserver. This is ideal for devices like Tasmota plugs, Shelly sensors, Hoymiles inverters or other MQTT-enabled devices."` |
| `DOC_PREREQ_TITLE` | `"Voraussetzungen"` | `"Prerequisites"` |
| `DOC_PREREQ` | `"Das <b>LoxBerry MQTT Gateway</b> Plugin muss installiert und konfiguriert sein. Der MQTT Broker muss laufen. Subscriptions im MQTT Gateway (die an den Miniserver weitergeleitet werden) sind unabhaengig von den Subscriptions hier."` | `"The <b>LoxBerry MQTT Gateway</b> plugin must be installed and configured. The MQTT broker must be running. Subscriptions in MQTT Gateway (forwarded to the Miniserver) are independent of subscriptions here."` |
| `DOC_HOWTO_TITLE` | `"So funktioniert's"` | `"How to use"` |
| `DOC_HOWTO` | `"<ol><li>Tragen Sie das gewuenschte MQTT-Topic in das Eingabefeld ein (z.B. <code>tasmota/steckdose1/SENSOR</code>)</li><li>Waehlen Sie die Optionen: <b>Zahlen extrahieren</b> und/oder <b>Strings sammeln</b></li><li>Klicken Sie <b>Speichern und anwenden</b></li><li>Die Daten erscheinen in InfluxDB unter dem Measurement-Namen des Topics</li><li>In Grafana koennen Sie die Daten sofort in Dashboards verwenden</li></ol>"` | `"<ol><li>Enter the desired MQTT topic in the input field (e.g. <code>tasmota/plug1/SENSOR</code>)</li><li>Select options: <b>Extract Numbers</b> and/or <b>Collect Strings</b></li><li>Click <b>Save and Apply</b></li><li>Data appears in InfluxDB under the topic's measurement name</li><li>In Grafana you can immediately use the data in dashboards</li></ol>"` |
| `DOC_WILDCARDS_TITLE` | `"MQTT Topics & Wildcards"` | `"MQTT Topics & Wildcards"` |
| `DOC_WILDCARDS` | `"<ul><li><code>haus/eg/temperatur</code> -- Exaktes Topic, nur diese eine Messung</li><li><code>haus/+/temperatur</code> -- Alle Raeume auf einer Ebene (z.B. eg, og, keller)</li><li><code>haus/#</code> -- Alle Topics unterhalb von <code>haus/</code></li><li><code>tasmota/+/SENSOR</code> -- Alle Tasmota-Sensor-Daten</li></ul>"` | `"<ul><li><code>home/ground/temperature</code> -- Exact topic, only this measurement</li><li><code>home/+/temperature</code> -- All rooms on one level (e.g. ground, upper, basement)</li><li><code>home/#</code> -- All topics below <code>home/</code></li><li><code>tasmota/+/SENSOR</code> -- All Tasmota sensor data</li></ul>"` |
| `DOC_JSON_TITLE` | `"JSON-Payloads"` | `"JSON Payloads"` |
| `DOC_JSON` | `"Der Collector erkennt JSON-Daten automatisch und splittet sie in einzelne Felder auf. Beispiel:<br><code>{\"temperature\":21.5, \"humidity\":65}</code><br>wird zu zwei separaten Werten in InfluxDB: <code>temperature=21.5</code> und <code>humidity=65</code>. Verschachtelte JSON-Objekte werden ebenfalls aufgeloest. Boolsche Werte (<code>true</code>/<code>false</code>) werden automatisch in <code>1</code>/<code>0</code> umgewandelt."` | `"The Collector automatically detects JSON data and splits it into individual fields. Example:<br><code>{\"temperature\":21.5, \"humidity\":65}</code><br>becomes two separate values in InfluxDB: <code>temperature=21.5</code> and <code>humidity=65</code>. Nested JSON objects are also expanded. Boolean values (<code>true</code>/<code>false</code>) are automatically converted to <code>1</code>/<code>0</code>."` |
| `DOC_OPTIONS_TITLE` | `"Optionen pro Topic"` | `"Options per topic"` |
| `DOC_OPTIONS` | `"<ul><li><b>Zahlen extrahieren:</b> Wenn aktiviert, versucht der Collector Zahlenwerte aus Text-Strings zu lesen. Z.B. wird aus <code>12.4C</code> der Wert <code>12.4</code> extrahiert. Nuetzlich bei Geraeten, die Einheiten im Wert mitsenden.</li><li><b>Strings sammeln:</b> Standardmaessig werden nur numerische Werte gespeichert. Aktivieren Sie diese Option, um auch Text-Werte in InfluxDB zu speichern (InfluxDB unterstuetzt Strings als Feldwerte).</li></ul>"` | `"<ul><li><b>Extract Numbers:</b> When enabled, the Collector tries to extract numeric values from text strings. E.g. <code>12.4C</code> yields value <code>12.4</code>. Useful for devices that include units in their values.</li><li><b>Collect Strings:</b> By default only numeric values are stored. Enable this to also store text values in InfluxDB (InfluxDB supports strings as field values).</li></ul>"` |
| `DOC_DIFFERENCE_TITLE` | `"Unterschied zu MQTT LiveUpdate"` | `"Difference to MQTT LiveUpdate"` |
| `DOC_DIFFERENCE` | `"<b>MQTT Collector:</b> Sammelt Daten von beliebigen MQTT-Geraeten direkt in InfluxDB. Die Geraete muessen nicht im Loxone Miniserver konfiguriert sein.<br><b>MQTT LiveUpdate:</b> Empfaengt Echtzeit-Updates von Loxone-Bloecken ueber MQTT. Die Daten muessen vom Miniserver per MQTT Gateway veroeffentlicht werden und einem bestimmten Topic-Schema folgen."` | `"<b>MQTT Collector:</b> Collects data from any MQTT device directly into InfluxDB. Devices do not need to be configured in the Loxone Miniserver.<br><b>MQTT LiveUpdate:</b> Receives real-time updates from Loxone blocks via MQTT. Data must be published by the Miniserver through MQTT Gateway following a specific topic schema."` |

### [MQTTLIVE]

MQTT LiveUpdate Seite (mqttlive_loxone.html + mqttlive_loxone.js).

| Key | DE | EN |
|-----|----|----|
| `TITLE` | `"MQTT LiveUpdate Daten"` | `"MQTT LiveUpdate Data"` |
| `DESCRIPTION` | `"Diese Uebersicht zeigt, welche Daten Sie bereits per MQTT LiveUpdate an Ihre Loxone-Statistiken gesendet haben, und ob Ihre Publishes das richtige Topic treffen."` | `"This listing shows what data you have already submitted via MQTT LiveUpdate to your Loxone Statistics, and also if your publishes might miss the correct topic."` |
| `DESCRIPTION2` | `"Unten finden Sie <i>alle verfuegbaren Ausgaenge</i> von Loxone-Bloecken, die Sie aktiviert haben, zum direkten Kopieren. Ein Ausgang wird aktiviert, indem Sie ihn in der Detailansicht der Statistik-Konfiguration einschalten. Weitere Informationen finden Sie in der <a href=\"https://www.loxwiki.eu/x/-YRWBQ\" target=\"_blank\">LoxWiki Schritt-fuer-Schritt-Anleitung</a>."` | `"Below you'll find <i>all available outputs</i> of Loxone blocks that you have enabled, to directly copy/paste. An output gets enabled by enabling it in the Detail View of the Statistics configuration. See the <a href=\"https://www.loxwiki.eu/x/-YRWBQ\" target=\"_blank\">LoxWiki step-by-step guide</a> for assistance."` |
| `LABEL_LIVE_STATE` | `"MQTT Live Status"` | `"MQTT Live State"` |
| `LABEL_TOPIC` | `"Topic"` | `"Topic"` |
| `LABEL_CONNECTED` | `"Verbunden"` | `"Connected"` |
| `LABEL_ERRORS` | `"Fehler"` | `"Errors"` |
| `TITLE_RECEIVED` | `"Empfangene Updates"` | `"Received updates"` |
| `HINT_COLOR` | `"Die Farbe zeigt an, wann die letzte Nachricht eintraf (je kraeftiger, desto aktueller)"` | `"The color gives you advice when the last message arrived (the louder the latter)"` |
| `BUTTON_CLEAR` | `"Anzeige zuruecksetzen"` | `"Clear Display"` |
| `TITLE_AVAILABLE_TOPICS` | `"MQTT Live Alle verfuegbaren Update-Topics"` | `"MQTT Live All Available Update Topics"` |
| `BUTTON_CREATE_TEMPLATE` | `"Virtuellen Ausgang Vorlage erstellen"` | `"Create Virtual Output Template"` |

**Ausfuehrliche Dokumentation (ausklappbarer Bereich):**

| Key | DE | EN |
|-----|----|----|
| `DOC_TITLE` | `"Was ist MQTT LiveUpdate?"` | `"What is MQTT LiveUpdate?"` |
| `DOC_INTRO` | `"Der normale Statistik-Grabber sammelt Daten in Ihrem definierten Intervall (z.B. 5 oder 10 Minuten). Daten, die sich schnell aendern -- wie Stromverbrauch oder Tastendruecke -- koennen so nicht erfasst werden. Mit MQTT LiveUpdate senden Sie bei jeder Aenderung eines Loxone-Blockausgangs die Daten sofort an Ihre Stats4Lox-Statistik."` | `"The normal Statistics Grabber collects data at your defined interval (e.g. 5 or 10 minutes). Data that changes rapidly -- like power metering or button presses -- cannot be collected that way. With MQTT LiveUpdate, every change of a Loxone block output immediately sends the data to your Stats4Lox statistic."` |
| `DOC_PREREQ_TITLE` | `"Voraussetzungen"` | `"Prerequisites"` |
| `DOC_PREREQ` | `"<ul><li>Das <b>MQTT Gateway</b> Plugin muss installiert und konfiguriert sein</li><li>Im Loxone Miniserver muss ein <b>Virtueller Ausgang</b> zum MQTT Gateway erstellt werden</li><li>Die zu ueberwachenden Bloecke muessen mit dem Virtuellen Ausgang verbunden werden</li></ul>"` | `"<ul><li>The <b>MQTT Gateway</b> plugin must be installed and configured</li><li>A <b>Virtual Output</b> to MQTT Gateway must be created in the Loxone Miniserver</li><li>The blocks to monitor must be connected to the Virtual Output</li></ul>"` |
| `DOC_HOWTO_TITLE` | `"So funktioniert's"` | `"How to use"` |
| `DOC_HOWTO` | `"<ol><li>Aktivieren Sie die gewuenschte Statistik in der <b>Loxone & Import</b> Seite und waehlen Sie Ausgaenge</li><li>Kopieren Sie das angezeigte MQTT-Topic aus der Liste unten</li><li>Erstellen Sie im Loxone Config einen <b>Virtuellen Ausgang Befehl</b> mit diesem Topic</li><li>Verbinden Sie den gewuenschten Blockausgang (z.B. 'Aktuelle Leistung') mit dem Virtuellen Ausgang</li><li>Jede Wertaenderung wird nun live an Stats4Lox gemeldet</li></ol><p>Tipp: Nutzen Sie den Button <b>Virtuellen Ausgang Vorlage erstellen</b> um eine XML-Datei zu generieren, die Sie direkt in Loxone Config importieren koennen.</p>"` | `"<ol><li>Activate the desired statistic on the <b>Loxone and Import</b> page and select outputs</li><li>Copy the displayed MQTT topic from the list below</li><li>In Loxone Config, create a <b>Virtual Output Command</b> with this topic</li><li>Connect the desired block output (e.g. 'Current power') to the Virtual Output</li><li>Every value change is now reported live to Stats4Lox</li></ol><p>Tip: Use the <b>Create Virtual Output Template</b> button to generate an XML file you can import directly into Loxone Config.</p>"` |
| `DOC_DIFFERENCE_TITLE` | `"Unterschied zu MQTT Collector"` | `"Difference to MQTT Collector"` |
| `DOC_DIFFERENCE` | `"<b>MQTT LiveUpdate:</b> Fuer Loxone-Bloecke. Der Miniserver sendet Wertaenderungen per MQTT an Stats4Lox. Erfordert Konfiguration im Loxone Config (Virtueller Ausgang).<br><b>MQTT Collector:</b> Fuer beliebige MQTT-Geraete (Tasmota, Shelly etc.). Die Geraete senden direkt an den MQTT Broker, Stats4Lox liest die Topics."` | `"<b>MQTT LiveUpdate:</b> For Loxone blocks. The Miniserver sends value changes via MQTT to Stats4Lox. Requires configuration in Loxone Config (Virtual Output).<br><b>MQTT Collector:</b> For any MQTT device (Tasmota, Shelly etc.). Devices send directly to the MQTT broker, Stats4Lox reads the topics."` |

---

## Zu aendernde Dateien

### Neue Dateien (5)

| Datei | Beschreibung |
|-------|-------------|
| `templates/lang/language_de.ini` | Deutsche Uebersetzung (vollstaendig) |
| `templates/lang/language_en.ini` | Englische Uebersetzung (vollstaendig, ersetzt bestehende) |
| `templates/lang/language_nl.ini` | Niederlaendisch (Kopie EN) |
| `templates/lang/language_fr.ini` | Franzoesisch (Kopie EN) |
| `templates/lang/language_es.ini` | Spanisch (Kopie EN) |

### Zu aendernde Dateien (16)

**CGI-Skripte (8):**

| Datei | Aenderung |
|-------|-----------|
| `webfrontend/htmlauth/index.cgi` | readlanguage() + Navbar-Uebersetzung + lbheader mit %L |
| `webfrontend/htmlauth/main_loxone.cgi` | readlanguage() + Navbar-Uebersetzung |
| `webfrontend/htmlauth/input_mqtt.cgi` | readlanguage() + Navbar-Uebersetzung |
| `webfrontend/htmlauth/mqttlive_loxone.cgi` | readlanguage() + Navbar-Uebersetzung |
| `webfrontend/htmlauth/output_influx.cgi` | readlanguage() + Navbar-Uebersetzung |
| `webfrontend/htmlauth/chartengines.cgi` | readlanguage() + Navbar-Uebersetzung |
| `webfrontend/htmlauth/loxone_import_report.cgi` | readlanguage() + Navbar-Uebersetzung |
| `webfrontend/htmlauth/logs.cgi` | readlanguage() + Navbar-Uebersetzung |

**HTML-Templates (7):**

| Datei | Aenderung |
|-------|-----------|
| `templates/home.html` | Alle Strings -> TMPL_VAR, i18n Hidden-Divs fuer JS |
| `templates/settings_loxone.html` | Alle Strings -> TMPL_VAR, i18n Hidden-Divs fuer JS |
| `templates/input_mqtt.html` | Strings -> TMPL_VAR, Inline-Hilfe + Doku-Bereich neu |
| `templates/mqttlive_loxone.html` | Strings -> TMPL_VAR, Doku-Bereich neu |
| `templates/output_influx.html` | Strings -> TMPL_VAR (teilweise bereits vorhanden) |
| `templates/chartengines.html` | Strings -> TMPL_VAR |
| `templates/loxone_import_report.html` | Strings -> TMPL_VAR, i18n Hidden-Divs fuer JS |

**JavaScript (4):**

| Datei | Aenderung |
|-------|-----------|
| `webfrontend/htmlauth/js/home.js` | Hardcoded Strings -> Lesen aus i18n Hidden-Divs |
| `webfrontend/htmlauth/js/input_mqtt.js` | Hardcoded Strings -> Lesen aus i18n Hidden-Divs |
| `webfrontend/htmlauth/js/loxone_import_report.js` | Hardcoded Strings -> Lesen aus i18n Hidden-Divs |
| `webfrontend/htmlauth/js/mqttlive_loxone.js` | Hardcoded Strings -> Lesen aus i18n Hidden-Divs (falls Strings vorhanden) |

**Konfiguration (1):**

| Datei | Aenderung |
|-------|-----------|
| `bin/libs/Globals.pm` | Navbar bleibt als Default-Fallback, wird per CGI ueberschrieben |

**Hinweis zu settings_loxone.js (1.178 Zeilen):**

`settings_loxone.js` generiert grosse Teile des HTML dynamisch (Tabellen, Detail-Popups). Die Strings in dieser Datei (Labels wie "Miniserver", "Place", "Category", "Type", Visu/Stat-Labels etc.) muessen ebenfalls ueber i18n Hidden-Divs aus `settings_loxone.html` gelesen werden. Da diese Datei sehr umfangreich ist, werden die Hidden-Divs im Template angelegt und die JS-Datei Schritt fuer Schritt umgestellt.

Daher wird `settings_loxone.js` in die JS-Liste aufgenommen:

| Datei | Aenderung |
|-------|-----------|
| `webfrontend/htmlauth/js/settings_loxone.js` | Hardcoded Strings -> Lesen aus i18n Hidden-Divs |

### Nicht geaendert

- `webfrontend/htmlauth/ajax.cgi` -- Backend, keine User-sichtbaren Strings
- `templates/lang/loxelements_*.json` -- Bereits uebersetzt, nicht betroffen

---

## MQTT Collector Dokumentations-Layout

```
+-------------------------------------------------------+
| MQTT Collector                           [TITLE]       |
| Abonnieren Sie MQTT-Topics...           [DESCRIPTION]  |
+-------------------------------------------------------+
| (i) MQTT-Topic, z.B. sensor/temp...    [HINT_INLINE]  |
| [____topic eingabe____]  [Loeschen] [Anzeigen]         |
|   [ ] Zahlen extrahieren (i) Hilfetext                 |
|   [ ] Strings sammeln    (i) Hilfetext                 |
+-------------------------------------------------------+
| [Neue Zeile] [Speichern und anwenden]                  |
+-------------------------------------------------------+
|                                                        |
| v Was ist der MQTT Collector? (ausklappbar)             |
|   - Einleitung                                         |
|   - Voraussetzungen                                    |
|   - So funktioniert's (Schritt-fuer-Schritt)           |
|   - MQTT Topics & Wildcards (mit Beispielen)           |
|   - JSON-Payloads (mit Beispiel)                       |
|   - Optionen pro Topic                                 |
|   - Unterschied zu MQTT LiveUpdate                     |
+-------------------------------------------------------+
```

---

## Regeln fuer Uebersetzungen

1. **Technische Begriffe bleiben Englisch:** MQTT, Topic, Collector, LiveUpdate, InfluxDB, Grafana, Telegraf, Miniserver, Measurement, Dashboard, Broker, JSON, Payload
2. **GUI-Elemente werden uebersetzt:** Buttons, Labels, Statusmeldungen, Hilfetexte, Fehlermeldungen
3. **NL/FR/ES sind initial EN-Kopien** -- die LoxBerry Community kann diese spaeter uebersetzen
4. **Platzhalter-Pattern:** `__PID__`, `__MSG__` werden per JavaScript durch tatsaechliche Werte ersetzt
