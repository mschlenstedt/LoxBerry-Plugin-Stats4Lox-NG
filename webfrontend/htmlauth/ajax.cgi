#!/usr/bin/perl
use warnings;
use strict;
use LoxBerry::System;
use LoxBerry::Log;
use CGI;
use JSON;
use FindBin qw($Bin);
use lib "$Bin/../../../../bin/plugins/REPLACELBPPLUGINDIR/libs/";
use Globals;

my $error;
my $response;
my $cgi = CGI->new;
my $q = $cgi->Vars;

# Every branch below compares $q->{action} with "eq". Without a defined value a
# request without an action parameter produced a warning for each of them in
# the webserver error log.
$q->{action} = '' if( !defined $q->{action} );

# nofile: this CGI is called constantly - on every page load, for live values,
# for the service status. Each call produced its own log file, so the Logfiles
# overview filled up with dozens of AJAX entries that nobody ever reads.
#
# Nothing is lost: with stderr the messages still land in the webserver error
# log, which is where you look when a CGI misbehaves anyway.
my $log = LoxBerry::Log->new (
    name => 'AJAX',
	nofile => 1,
	stderr => 1,
	loglevel => 7
);

LOGSTART "Request $q->{action}";

## getloxplan
if( $q->{action} eq "getloxplan" ) {
	require Loxone::GetLoxplan;
	require Loxone::ParseXML;
	require LoxBerry::IO;
	
	my $msno = $q->{msno};
	LOGTITLE "getloxplan Miniserver $msno";

	# Piggybacked on this request on purpose: it is the moment the user works
	# with the block list, so that is when the element names should be current.
	# LangUpdate throttles itself to one check a day and never fails hard - if
	# GitHub cannot be reached, everything stays as it is.
	eval {
		require LangUpdate;
		LangUpdate::update( log => $log );
	};
	LOGDEB "Language file check failed: $@" if( $@ );
	
	my %miniservers = LoxBerry::System::get_miniservers();
	
	if( ! defined $miniservers{$msno} ) {
		$error = "Miniserver not defined";
	}
	else {
		
		## Get Serials of Miniservers
		## Serials are used for matching of LoxBerry MSNO to "real" Miniservers in LoxPlan
		my %ms_serials;
		
		$log->INF("Checking MS$msno");
		if( $miniservers{$msno}{UseCloudDNS} and $miniservers{$msno}{CloudURL} ) {
			# CloudDNS has serial defined in LoxBerry
			$ms_serials{$msno} = uc( $miniservers{$msno}{CloudURL} );
			$log->OK("MS $msno: Locally stored serial:  $ms_serials{$msno}");
		}
		else {	
			# Fetch serial from Miniserver
			my ($response) = LoxBerry::IO::mshttp_call2($msno, "/jdev/cfg/mac");
			# print STDERR $response;
			eval {
				my $responseobj=JSON::from_json( $response );
				my $sn = $responseobj->{LL}->{value};
				$sn =~ tr/://d;
				$ms_serials{$msno} = uc( $sn );
				$log->OK("MS$msno: Aquired serial from MS: $ms_serials{$msno}");
			};
			if( $@ ) {
				$log->ERR("Could not aquire MAC from Miniserver $msno: $@");
			}
		}
		
		if( !defined $ms_serials{$msno} ) {
			$log->WARN("MS$msno: Could not get serial, therefore matching of Miniserver may fail");
		}
		
		my $Loxplanfile = "$Globals::stats4lox->{s4ltmp}/s4l_loxplan_ms$msno.Loxone";
		my $loxplanjson = "$Globals::stats4lox->{loxplanjsondir}/ms".$msno.".json";

		# Manual mode (issue #101).
		#
		# Loxone occasionally produces a LoxPLAN this plugin cannot unpack or
		# parse. A user can repair the XML by hand, but until now there was no
		# way to get the repaired file in. In manual mode nothing is fetched from
		# the Miniserver: the uploaded file is the source.
		#
		# The upload is kept in the data directory and not in s4ltmp - that one
		# is a ramdisk and would lose the file on every reboot, and a manually
		# repaired LoxPLAN is not something anyone wants to upload twice.
		my $manual = ( ($Globals::loxone->{loxplansource} // 'auto') eq 'manual' ) ? 1 : 0;
		if( $manual ) {
			my $upload = manual_loxplan_file( $msno );
			LOGINF "Manual mode: using the uploaded Loxone configuration";

			if( ! -e $upload ) {
				$error = "Miniserver $msno: No Loxone configuration uploaded yet.";
			}
			else {
				# Parsed again only when the upload is newer than the result -
				# the parse takes seconds and the file only changes on upload.
				my $needparse = ( ! -e $loxplanjson )
				              || ( ( stat($upload) )[9] > ( stat($loxplanjson) )[9] )
				              || loxplanjson_incomplete( $loxplanjson );
				if( !$needparse ) {
					LOGINF "The parsed result is newer than the upload - using it";
				}
				else {
					LOGOK "Parsing the uploaded Loxone configuration";
					my $loxplan = Loxone::ParseXML::loxplan2json(
						filename => $upload,
						msno => $msno,
						output => $loxplanjson,
						log => $log,
						# No remote timestamp in manual mode - loxplan2json then
						# records the file's own date.
						remoteTimestamp => undef,
						ms_serials => \%ms_serials
					);
					if( !$loxplan ) {
						$error = "Miniserver $msno: Could not parse the uploaded Loxone configuration.";
					}
				}

				# Does the upload belong to this Miniserver at all?
				#
				# Nothing forces a user to pick the right file. If the LoxPLAN of
				# a different Miniserver is uploaded, the serial/host matching
				# finds nothing, every block ends up without an msno, and the
				# overview is simply empty - with no hint as to why. In automatic
				# mode this cannot happen, the file comes from that Miniserver.
				if( !$error and -e $loxplanjson ) {
					my $match = 0;
					eval {
						my $j = decode_json( LoxBerry::System::read_file($loxplanjson) );
						$match = grep { defined $_->{msno} and $_->{msno} eq $msno }
						         values %{ $j->{miniservers} // {} };
					};
					if( !$match ) {
						$error = "Miniserver $msno: The uploaded Loxone configuration belongs to a different Miniserver.";
						LOGCRIT $error;
					}
				}
			}

		}
		else {

		my $remoteTimestamp;
		eval {
			$remoteTimestamp = Loxone::GetLoxplan::checkLoxplanUpdate( $msno, $loxplanjson, $log );
		};
		my $checkfailed = $@;

		# Note: "ne" on an undefined value warns. checkLoxplanUpdate returns
		# undef when the local copy is up-to-date.
		if( $checkfailed or defined $remoteTimestamp or loxplanjson_incomplete( $loxplanjson ) ) {
			LOGINF "Loxplan file not up-to-date. Fetching from Miniserver";

			# Every failure has to reach the user. Previously the return
			# values of both calls were discarded, this CGI answered HTTP 200
			# with a stale or empty json, and the web interface kept waiting
			# on "Fetching Loxone Config from Miniservers..." forever.
			unlink $Loxplanfile;
			my $fetched = Loxone::GetLoxplan::getLoxplan(
				ms => $msno,
				log => $log
			);

			if( !$fetched or ! -e $Loxplanfile ) {
				$error = "Miniserver $msno: Could not fetch the Loxone configuration.";
			}
			else {
				LOGOK "Loxplan for MS$msno found, parsing now...";
				my $loxplan = Loxone::ParseXML::loxplan2json(
					filename => $Loxplanfile,
					msno => $msno,
					output => $loxplanjson,
					log => $log,
					remoteTimestamp => $remoteTimestamp,
					ms_serials => \%ms_serials
				);
				if( !$loxplan ) {
					$error = "Miniserver $msno: Could not parse the Loxone configuration.";
				}
			}

		} else {
			LOGINF "Loxplan file is up-to-date. Using local copy";

			# The lookup table for outputs that Loxone reports as a bare UUID is
			# built while the LoxPLAN is being parsed - which does not happen
			# when the configuration is unchanged. Without this an existing
			# installation would never get the file, because after an upgrade the
			# configuration is by definition up-to-date and the parse is skipped.
			my $statenames = Loxone::ParseXML::stateNamesFile( $loxplanjson );
			if( $statenames and ! -e $statenames ) {
				LOGINF "Output name table is missing - creating it now";
				Loxone::ParseXML::writeStateNames( msno => $msno, output => $loxplanjson,
				                                   loxplan => $Loxplanfile, log => $log );
			}
		}

		} # end of automatic mode

		# Both modes answer with the parsed configuration.
		#
		# This used to sit inside the automatic branch. The manual mode parsed
		# the uploaded file correctly but left $response unset, so this CGI fell
		# through to the "action unknown" case and answered HTTP 501 - the web
		# interface reported a failure although everything had worked.
		if( !$error ) {
			if( -e $loxplanjson ) {
				$response = LoxBerry::System::read_file($loxplanjson);
			} else {
				$error = "Miniserver $msno: Could not fetch the Loxone configuration.";
			}
		}

	}

}

# Where a manually uploaded Loxone configuration is kept for a Miniserver.
#
# In the data directory, not in s4ltmp: that one is a ramdisk on LoxBerry and
# would drop the file on every reboot - and a LoxPLAN somebody repaired by hand
# is not something they want to upload again after a power cut.
sub manual_loxplan_file
{
	my ($msno) = @_;
	return "$lbpdatadir/loxplan_ms${msno}.Loxone";
}

# Is there a manually uploaded configuration at all?
#
# The setting is one for the whole plugin while the uploads are per Miniserver,
# so a single file is enough to make manual mode work for that Miniserver.
# Does the stored ms<n>.json still lack something a newer version writes?
#
# The page list is new (issue #20). An installation whose LoxPLAN has not changed
# since the upgrade would never parse again, so the page filter would stay
# incomplete until somebody happens to touch Loxone Config. Forcing one rebuild
# when the key is missing settles it. A file that cannot be decoded counts as
# incomplete as well - re-parsing is the right answer for that too.
sub loxplanjson_incomplete
{
	my ($file) = @_;
	return 0 if( ! -e $file );
	my $complete = 0;
	eval {
		my $j = decode_json( LoxBerry::System::read_file($file) );
		$complete = ( ref($j->{pages}) eq 'HASH' ) ? 1 : 0;
	};
	return $complete ? 0 : 1;
}

sub have_manual_loxplan
{
	my %ms = LoxBerry::System::get_miniservers();
	foreach my $n ( keys %ms ) {
		return 1 if( -e manual_loxplan_file( $n ) );
	}
	return 0;
}

## saveloxplansource - auto or manual (issue #101)
##
## Its own action and not a section of savepluginconfig: that one forks and
## answers before the child has written anything, and the page switches the
## upload field on right afterwards. Nothing has to be reconfigured here, so
## there is no reason to go through the config handler either.
if( $q->{action} eq "saveloxplansource" ) {
	require LoxBerry::JSON;
	my $wanted = ( defined $q->{loxplansource} and $q->{loxplansource} eq 'manual' ) ? 'manual' : 'auto';

	# Manual mode is only stored once there is a file to read.
	#
	# Clicking the radio button is not a decision yet - it only opens the upload
	# field. If it were stored right away and the user then walked away without
	# uploading anything, the plugin would be left in a mode with no
	# configuration at all: every page load would fail with "nothing uploaded
	# yet". So the switch stays a state of the page, and reloading it comes back
	# up in automatic mode until an upload has actually arrived.
	my $v = ( $wanted eq 'manual' and !have_manual_loxplan() ) ? 'auto' : $wanted;

	my $obj = LoxBerry::JSON->new();
	my $cfg = $obj->open( filename => $stats4loxconfig, lockexclusive => 1, locktimeout => 10 );
	if( !$cfg ) {
		$error = "Could not open stats4lox.json";
	}
	else {
		$cfg->{loxone}->{loxplansource} = $v;
		$obj->write();
		$Globals::loxone->{loxplansource} = $v;
		LOGOK "Loxone configuration source set to $v"
		      . ( $v ne $wanted ? " ($wanted was asked for, but nothing has been uploaded yet)" : "" );
		$response = JSON::encode_json( { loxplansource => $v, requested => $wanted } );
	}
}

## loxplaninfo - is a manual file there, and how old is it
if( $q->{action} eq "loxplaninfo" ) {
	my %out = ( loxplansource => $Globals::loxone->{loxplansource} // 'auto', files => {} );
	my %ms = LoxBerry::System::get_miniservers();
	foreach my $n ( sort { $a <=> $b } keys %ms ) {
		my $f = manual_loxplan_file( $n );
		$out{files}->{$n} = ( -e $f )
			? { exists => 1, size => ( -s $f ), mtime => ( stat($f) )[9] }
			: { exists => 0 };
	}
	$response = JSON::encode_json( \%out );
}

## uploadloxplan - takes a Loxone configuration from the user (issue #101)
if( $q->{action} eq "uploadloxplan" ) {
	my $msno = $q->{msno};
	my $fh = $cgi->upload('loxplanfile');

	if( !$msno ) {
		$error = "No Miniserver given";
	}
	elsif( !$fh ) {
		$error = "No file received";
	}
	else {
		my $target = manual_loxplan_file( $msno );
		my $tmp = "$target.upload";

		my $bytes = 0;
		if( open( my $out, '>', $tmp ) ) {
			binmode $out;
			my $buf;
			while( my $n = read( $fh, $buf, 65536 ) ) { print {$out} $buf; $bytes += $n }
			close $out;
		}
		else {
			$error = "Could not write $tmp: $!";
		}

		if( !$error and $bytes == 0 ) {
			$error = "The uploaded file is empty";
			unlink $tmp;
		}

		# Only a look at the content decides, not the file name: users rename
		# things, and a wrong file here would leave the plugin without a usable
		# configuration. Accepted is what getLoxplan produces as well - the
		# unpacked XML - because that is what a user can repair by hand.
		if( !$error ) {
			my $head = '';
			if( open( my $in, '<', $tmp ) ) { read( $in, $head, 512 ); close $in }
			if( $head !~ /<\?xml/ or $head !~ /<C\b|LoxCONFIG|<Project/i ) {
				$error = "This is not an unpacked Loxone configuration (expected the XML, i.e. a .Loxone file)";
				unlink $tmp;
			}
		}

		if( !$error ) {
			# Only replaces the previous file once the new one is complete and
			# has passed the check.
			if( rename( $tmp, $target ) ) {
				LOGOK "Loxone configuration for MS$msno uploaded ($bytes bytes)";
				# The parse decides by timestamp, so the old result has to be
				# older than the new upload - which rename guarantees.
				$response = JSON::encode_json( { uploaded => 1, bytes => $bytes } );
			}
			else {
				$error = "Could not store the file: $!";
				unlink $tmp;
			}
		}
	}
}

## getstatsconfig
if( $q->{action} eq "getstatsconfig" ) {
	if ( -e $statsconfig ) {
		$response = LoxBerry::System::read_file($statsconfig);
		if( !$response ) {
			$response = "{ }";
		}
	}
	else {
		$response = "{ }";
	}
}

## updatestat
# An interval for a Loxone statistic, never shorter than the minimum from the
# System tab. 0 stays 0 - that is how a statistic that is switched off is stored.
sub s4l_clamp_interval
{
	my ($v) = @_;
	return 0 if( !defined $v or $v !~ /^\d+$/ );
	return 0 if( $v + 0 == 0 );
	my $min = Globals::loxone_min_interval();
	return ( $v + 0 < $min ) ? $min : $v + 0;
}

if( $q->{action} eq "updatestat" ) {
	require LoxBerry::JSON;
	my $jsonobjcfg = LoxBerry::JSON->new();
	# locktimeout, because without one the lock is taken blocking and this is a
	# CGI: a request would wait for as long as anything else holds the file, with
	# nothing to show the user. Ten seconds is far more than any writer here needs -
	# the slow part of this handler, provisioning the dashboard, was measured at
	# 0.06 s for a block with three outputs.
	my $cfg = $jsonobjcfg->open(filename => $statsconfig, lockexclusive => 1, locktimeout => 10);
	my @searchresult = ( $cfg and ref($cfg->{loxone}) eq 'ARRAY' )
		? $jsonobjcfg->find( $cfg->{loxone}, "\$_->{uuid} eq \"".$q->{uuid}."\"" )
		: ();
	my $elemKey = $searchresult[0];
	my $element = $cfg->{loxone}[$elemKey] if( defined $elemKey );
	
	my @outputs;
	if ( defined $q->{outputs} ) {
		@outputs = split(",", $q->{outputs});
	}
	else {
		@outputs = ();
	}
	
	my @outputlabels;
	if( $q->{outputlabels} ne "" ) {
		@outputlabels = split(",", $q->{outputlabels});
	} 
	
	my @outputkeys;
	if( $q->{outputkeys} ne "" ) {
		@outputkeys = split(",", $q->{outputkeys});
	} 
	
	
	my $measurementname = $q->{measurementname};
	if( !$measurementname ) {
		if( defined $element->{measurementname} and $element->{measurementname} ne "" ) {
			$measurementname = $element->{measurementname};
		}
		else {
			$measurementname = $q->{description} ne "" ? $q->{description} : $q->{name};
		}
	}
	
	my %updatedelement = (
		name => $q->{name},
		description => $q->{description},
		uuid => $q->{uuid},
		type => $q->{type},
		category => $q->{category},
		room => $q->{room},
		# Never below the minimum from the System tab. The page marks the field
		# red and refuses to send it, so this only catches a page that was open
		# before the minimum was raised - but that page would otherwise write an
		# interval the grabber may not poll with.
		interval => s4l_clamp_interval( $q->{interval} ),
		active => defined $q->{active} ? $q->{active} : "false",
		msno => $q->{msno},
		measurementname => $measurementname,
		outputs => \@outputs,
		grafana => $element->{grafana}, 
		# url => $q->{uuid}
	);
	$updatedelement{outputlabels} = \@outputlabels if(@outputlabels);
	$updatedelement{outputkeys} = \@outputkeys if(@outputkeys);
	# The element is rebuilt from scratch here, so anything not listed above is
	# lost. 'grafana' is carried over in the list; the status recorded by the
	# grabber has to be carried over as well - otherwise changing an interval
	# would quietly clear the error state and start the counting again.
	$updatedelement{status} = $element->{status} if( $element->{status} );
	
	
	# Validation
	my @errors;
	push @errors, "stats.json could not be opened or locked" if( !$cfg or ref($cfg->{loxone}) ne 'ARRAY' );
	# Outputs are useless without the labels to title their panels by, and
	# provisionDashboard would have deleted the existing panels before finding that
	# out. Rejected here so the caller gets an answer instead of an error page.
	push @errors, "outputs given without matching outputkeys and outputlabels"
		if( @outputs and ( !@outputkeys or scalar @outputkeys != scalar @outputlabels ) );
	push @errors, "name must be defined" if( ! $updatedelement{name} );
	push @errors, "uuid must be defined" if( ! $updatedelement{uuid} );
	push @errors, "msno must be defined" if( ! $updatedelement{msno} );
	# push @errors, "url must be defined" if( ! $updatedelement{url} );
	push @errors, "active must be defined" if( ! $updatedelement{active} );

	if( ! @errors ) {
		require GrafanaS4L;
		GrafanaS4L::provisionDashboard( \%updatedelement );
	}
	
	
	# Insert/Update element in stats array. Only touched when the file is actually
	# there - a failed lock left $cfg undef, and writing into that would have died
	# in the middle of the response.
	if( ! @errors ) {
		if( defined $elemKey ) {
			# This is an update of an existing element
			$cfg->{loxone}[$elemKey] = \%updatedelement;
		}
		else {
			# Add a new entry to stats.json
			push @{$cfg->{loxone}}, \%updatedelement;
		}
	}
	
	if( ! @errors ) {
		# The changes are valid
		$jsonobjcfg->write();
		undef $jsonobjcfg;
		$response = to_json( \%updatedelement );
	}
	else {
		# The element is invalid
		$error = "Invalid input data: " . join(". ", @errors);
	}
	
}
	
## lxlquery
if( $q->{action} eq "lxlquery" ) {
	require "$lbpbindir/libs/Stats4Lox.pm";
	my ($code, $data) = Stats4Lox::msget_value( $q->{msno}, $q->{uuid} );

	# What an import would actually write for this block (issue #74).
	#
	# This used to hand out $Globals::ImportMapping and let the browser work it
	# out. That table knows ENERGY, FRONIUS and a Default entry matching the
	# output called "Default" - which every block has - so the list marked a
	# column 1 on every block in the house, whether or not any statistics are
	# switched on in the Miniserver. Meanwhile the import derives its mapping per
	# block and the statistics groups name their columns themselves, so the
	# numbers described nothing that was going to happen.
	my $import = { statistics => 0, recording => 0, fields => [] };
	eval {
		require Loxone::Import;
		$import = Loxone::Import::importFields(
			msno => $q->{msno}, uuid => $q->{uuid}, log => $log,
			# Already fetched above - a block that answers with nothing but
			# Default needs them to be read correctly.
			livenames => [ map { $_->{Name} } @{ $data // [] } ] );
	};
	LOGWARN "lxlquery: could not determine the import fields: $@" if( $@ );

	my %response = (
		msno => $q->{msno},
		uuid => $q->{uuid},
		code => $code,
		response => $data,
		# Whether the Miniserver records anything for this block at all, and the
		# fields an import would fill. Empty list with statistics=1 is possible:
		# the block records, but nothing could be resolved to an output.
		hasstatistics => $import->{statistics} ? 1 : 0,
		isrecording => $import->{recording} ? 1 : 0,
		# Named when the mapping had to be taken from another block of the same
		# kind - an assumption the user is in a position to check.
		borrowedfrom => $import->{borrowedfrom},
		importfields => $import->{fields},
	);
	$response = encode_json( \%response );
}

## import_scheduler_report
if( $q->{action} eq "import_scheduler_report" ) {

	if( ! -e $Globals::stats4lox->{s4ltmp}."/s4l_import_scheduler.json" ) {
		system("$lbpbindir/import_scheduler.pl > $lbplogdir/import_scheduler.log 2>&1 &");
	}
	my $checktime = time();
	while( ! -e $Globals::stats4lox->{s4ltmp}."/s4l_import_scheduler.json" and time() < ($checktime+5) ) {
		# Wait up to 5 seconds
	}
	if( -e $Globals::stats4lox->{s4ltmp}."/s4l_import_scheduler.json" ) {
		$response = LoxBerry::System::read_file( $Globals::stats4lox->{s4ltmp}."/s4l_import_scheduler.json" );
	}
}

## scheduleimport
if( $q->{action} eq "scheduleimport" and $q->{msno} and $q->{uuid} ) {
	my $msno = $q->{msno};
	my $uuid = $q->{uuid};
	createImportFolder();
	my $importfile = $Globals::stats4lox->{importstatusdir}."/import_${msno}_${uuid}.json";
	
	if( $q->{importtype} eq "full" ) {
		
		unlink $importfile;
		require LoxBerry::JSON;
		my $jsonobjimport = LoxBerry::JSON->new();
		my $import = $jsonobjimport->open(filename => $importfile, lockexclusive => 1);
		$import->{msno} = $msno;
		$import->{uuid} = $uuid;
		$import->{name} = $q->{name};
		$import->{status} = "scheduled";
		$jsonobjimport->write();
		
	}
	
	# Start the Import Scheduler
	system("$lbpbindir/import_scheduler.pl > $lbplogdir/import_scheduler.log 2>&1 &");
	
	sleep 1;
	
	# Respond with scheduled file
	$response = LoxBerry::System::read_file( $importfile );
	
}

## deleteimport
if( $q->{action} eq "deleteimport" and $q->{msno} and $q->{uuid} ) {
	my $msno = $q->{msno};
	my $uuid = $q->{uuid};
	createImportFolder();
	my $importfile = $Globals::stats4lox->{importstatusdir}."/import_${msno}_${uuid}.json";
	
	if( ! -e $importfile ) {
		unlink "$importfile.log";
		$response = "{ }";
		system("$lbpbindir/import_scheduler.pl > $lbplogdir/import_scheduler.log 2>&1 &");
		sleep 1;
	}
	else {
		require LoxBerry::JSON;
		my $jsonobjimport = LoxBerry::JSON->new();
		my $import = $jsonobjimport->open(filename => $importfile, lockexclusive => 1, locktimeout => 10);
		if( ! $import or $import->{status} eq "running" ) {
			$error = "Cannot lock import $msno / $uuid or import is currently running";
		}
		else {
			unlink $importfile;
			unlink "$importfile.log";
			$response = "{ }";
			system("$lbpbindir/import_scheduler.pl > $lbplogdir/import_scheduler.log 2>&1 &");
			sleep 1;
		}
	}
}

## deletestat - gets rid of a statistic
##
## Two cases, and the entry itself decides which one applies - not the caller:
##
##   The block is gone from the Miniserver (status 404). Then the entry is
##   removed from stats.json and its panels from the dashboard; there is nothing
##   left it could belong to.
##
##   The block still exists. Then the entry is only switched off. Removing it
##   would throw away the measurement name, the chosen outputs and the interval,
##   and the user would have to set all of it up again to switch the statistic
##   back on. The panels stay for the same reason - update_dashboards.pl builds
##   them regardless of whether a statistic is active.
##
## The measurements in InfluxDB are only removed when the user explicitly asks
## for it, in both cases - they are the history, and the history usually
## outlives the reason the statistic was set up.
if( $q->{action} eq "deletestat" and $q->{msno} and $q->{uuid} ) {
	require LoxBerry::JSON;
	my $msno = $q->{msno};
	my $uuid = $q->{uuid};
	my $dropdata = ( defined $q->{dropdata} and $q->{dropdata} eq "true" ) ? 1 : 0;

	my $obj = LoxBerry::JSON->new();
	my $cfg = $obj->open( filename => $statsconfig, lockexclusive => 1, locktimeout => 10 );
	if( !$cfg or ref($cfg->{loxone}) ne 'ARRAY' ) {
		$error = "Could not open stats.json";
	}
	else {
		my ($index) = grep {
			     $cfg->{loxone}[$_]->{uuid} eq $uuid
			 and $cfg->{loxone}[$_]->{msno} eq $msno
		} 0 .. $#{ $cfg->{loxone} };

		if( !defined $index ) {
			$error = "Statistic $msno / $uuid not found";
		}
		else {
			my $element = $cfg->{loxone}[$index];
			my $measurement = $element->{measurementname};

			# The entry decides, not the caller: only a block the Miniserver no
			# longer knows is removed outright.
			my $gone = ( $element->{status} and $element->{status}->{error}
			             and $element->{status}->{error} eq '404' ) ? 1 : 0;
			my $mode = $gone ? 'removed' : 'deactivated';
			LOGINF "Statistic $msno / $uuid ($element->{name}): $mode";

			my @panel_ids = ();
			if( $gone ) {
				# Panels first: the ids live on the entry we are about to remove.
				@panel_ids = ( defined $element->{grafana}->{panels} )
				           ? values %{ $element->{grafana}->{panels} } : ();
				if( @panel_ids ) {
					eval {
						require Grafana;
						Grafana->deletePanelFromDashboard(
							"$Globals::grafana->{s4l_provisioning_dir}/dashboards/defaultDashboard.json",
							\@panel_ids );
						LOGOK "Removed " . scalar(@panel_ids) . " panels from the dashboard";
					};
					LOGERR "Could not remove the panels: $@" if( $@ );
				}
				splice @{ $cfg->{loxone} }, $index, 1;
				$obj->write();
				LOGOK "Statistic removed from stats.json";
			}
			else {
				# Switched off, everything else kept: measurement name, outputs
				# and interval are what the user configured, and they would all
				# have to be entered again to switch it back on. A status from a
				# previous failure goes, it describes a state that no longer
				# applies to a statistic nobody fetches.
				$element->{active} = "false";
				delete $element->{status};
				$obj->write();
				LOGOK "Statistic switched off, entry and panels kept";
			}

			# Only the series of this block, addressed by its uuid tag - several
			# statistics can share a measurement name, and dropping the whole
			# measurement would take the others with it.
			my $dropped = 0;
			if( $dropdata and $measurement ) {
				my $bin = "$lbpbindir/s4linflux";
				my $db = $Globals::influx->{influxdatabase} // 'stats4lox';
				my $sql = "DELETE FROM \"$measurement\" WHERE \"uuid\"='$uuid'";
				# quotemeta on the whole argument, no quotes of our own around
				# it - measurement names contain spaces and umlauts.
				my $cmd = "$bin -database " . quotemeta($db) . " -execute " . quotemeta($sql);
				my $out = `$cmd 2>&1`;
				if( $? == 0 ) { $dropped = 1; LOGOK "Measurements of $uuid deleted from $measurement" }
				else          { LOGERR "Could not delete the measurements: $out" }
			}

			# The import state file has no owner any more - but only when the
			# entry itself is gone. A statistic that was merely switched off
			# keeps its import history.
			if( $gone ) {
				createImportFolder();
				my $importfile = $Globals::stats4lox->{importstatusdir}."/import_${msno}_${uuid}.json";
				unlink $importfile     if( -e $importfile );
				unlink "$importfile.log" if( -e "$importfile.log" );
			}

			$response = JSON::encode_json( {
				deleted => 1,
				mode    => $mode,
				panels  => scalar(@panel_ids),
				dropped => $dropped,
			} );
		}
	}
}

## resetstatstatus - clears the recorded status so the grabber tries again
if( $q->{action} eq "resetstatstatus" and $q->{msno} and $q->{uuid} ) {
	require LoxBerry::JSON;
	my $obj = LoxBerry::JSON->new();
	my $cfg = $obj->open( filename => $statsconfig, lockexclusive => 1, locktimeout => 10 );
	if( !$cfg or ref($cfg->{loxone}) ne 'ARRAY' ) {
		$error = "Could not open stats.json";
	}
	else {
		my $found = 0;
		foreach my $e ( @{ $cfg->{loxone} } ) {
			next if( $e->{uuid} ne $q->{uuid} or $e->{msno} ne $q->{msno} );
			delete $e->{status};
			$found = 1;
			last;
		}
		if( !$found ) {
			$error = "Statistic $q->{msno} / $q->{uuid} not found";
		}
		else {
			$obj->write();
			LOGOK "Status of $q->{msno} / $q->{uuid} reset";
			$response = '{ "reset": 1 }';
		}
	}
}

## getmqttlivedata
if( $q->{action} eq "getmqttlivedata" ) {
	if ( -e $Globals::stats4lox->{s4ltmp}."/mqttlive_uidata.json" ) {
		$response = LoxBerry::System::read_file($Globals::stats4lox->{s4ltmp}."/mqttlive_uidata.json");
		if( !$response ) {
			$response = "{ }";
		}
	}
	else {
		$response = "{ }";
	}
}

## mqttlive_clearuidata
if( $q->{action} eq "mqttlive_clearuidata" ) {
	my $basetopic = $q->{basetopic};
	if( !$basetopic ) {
		$error = "No base topic sent with request";
		$log->ERR($error);
		# Jump out
	}
	else {
		require LoxBerry::IO;
		my $mqttcred = LoxBerry::IO::mqtt_connectiondetails();
		if( ! $mqttcred ) {
			$error = "Could not get MQTT Connection details - MQTT Gateway installed?";
			$log->WARN($error);
			# Jump out
		}
		else {
			eval {
				if( ! $mqttcred->{brokerport} ) {
					$mqttcred->{brokerport} = "1883";
				}
				
				require Net::MQTT::Simple;
				$ENV{MQTT_SIMPLE_ALLOW_INSECURE_LOGIN} = 1;
				my $mqtt = Net::MQTT::Simple->new($mqttcred->{brokeraddress});
				if($mqttcred->{brokeruser}) {
					$mqtt->login($mqttcred->{brokeruser}, $mqttcred->{brokerpass});
				}
				$mqtt->publish("$basetopic/command", "clearuidata");
			};
			if( $@ ) {
				$error = "Exception sending $basetopic/command=clearuidata: $@";
				$log->ERR($error);
			}
		}
	}
	$response = "{ }";
}

# Raising the plugin log level to debug and then restarting a service is what
# somebody does who wants to see what that service says. So the diagnostic
# logging follows along instead of hiding behind a second switch further away.
#
# Deliberately NOT marked as set by hand: cron.reboot switches this off again on
# the next reboot, so a log level nobody remembers cannot keep the services
# writing forever. The switch under Settings is marked and survives.
sub s4l_servicelog_follow_loglevel
{
	require ServiceLog;
	return if( !ServiceLog::follow_loglevel() );
	LOGINF "Plugin log level is debug - switching the diagnostic logging of the services on";
	system("sudo $lbpbindir/config-handler.pl servicelog >/dev/null 2>&1");
	return;
}


## starttelegraf
if( $q->{action} eq "starttelegraf" ) {
	s4l_servicelog_follow_loglevel();
	system ("sudo systemctl enable telegraf >/dev/null 2>&1");
	system ("sudo systemctl restart telegraf >/dev/null 2>&1");
	$response = $?;
}

## stoptelegraf
if( $q->{action} eq "stoptelegraf" ) {
	system ("sudo systemctl disable telegraf >/dev/null 2>&1");
	system ("sudo systemctl stop telegraf >/dev/null 2>&1");
	$response = $?;
}

## startinfluxdb
if( $q->{action} eq "startinfluxdb" ) {
	s4l_servicelog_follow_loglevel();
	system ("sudo systemctl enable influxdb >/dev/null 2>&1");
	system ("sudo systemctl restart influxdb >/dev/null 2>&1");
	$response = $?;
}

## stopinfluxdb
if( $q->{action} eq "stopinfluxdb" ) {
	system ("sudo systemctl disable influxdb >/dev/null 2>&1");
	system ("sudo systemctl stop influxdb >/dev/null 2>&1");
	$response = $?;
}

## startgrafana-server
if( $q->{action} eq "startgrafana-server" ) {
	s4l_servicelog_follow_loglevel();
	system ("sudo systemctl enable grafana-server >/dev/null 2>&1");
	system ("sudo systemctl restart grafana-server >/dev/null 2>&1");
	$response = $?;
}

## stopgrafana-server
if( $q->{action} eq "stopgrafana-server" ) {
	system ("sudo systemctl disable grafana-server >/dev/null 2>&1");
	system ("sudo systemctl stop grafana-server >/dev/null 2>&1");
	$response = $?;
}

## startmqttlive
if( $q->{action} eq "startmqttlive" ) {
	system ("pkill -f mqttlive.php >/dev/null 2>&1");

	my $jsonobj = LoxBerry::JSON->new();
	my $cfg = $jsonobj->open(filename => $stats4loxconfig, lockexclusive => 1);
	$cfg->{stats4lox}->{mqttlive_active} = "True";
	$jsonobj->write();
	undef $jsonobj;

	system ("$lbpbindir/mqtt/mqttlive.php >> $lbplogdir/mqttlive.log 2>&1 &");
	$response = $?;
}

## stopmqttlive
if( $q->{action} eq "stopmqttlive" ) {
	my $jsonobj = LoxBerry::JSON->new();
	my $cfg = $jsonobj->open(filename => $stats4loxconfig, lockexclusive => 1);
	$cfg->{stats4lox}->{mqttlive_active} = "False";
	$jsonobj->write();
	undef $jsonobj;
	
	system ("pkill -f mqttlive.php >/dev/null 2>&1");
	if ($? < 3 || $? eq "15") { # Don't know why it give 15 as Exit Code back - on cmd it is 0, 1 or 2.
		$response = 0;
	} else {
		$response = $?;
	}
}

## servicestatus
if( $q->{action} eq "servicestatus" ) {
	
	my $telegrafstat = `pgrep -f /usr/bin/telegraf`;
	my $influxstat = `pgrep -f /usr/bin/influxd`;
	my $grafanastat = `pgrep -f /usr/share/grafana/bin/grafana`;
	my $mqttlivestat;
	
	if( is_disabled( $Globals::stats4lox->{mqttlive_active} ) ) {
		$mqttlivestat = 'disabled';
	}
	else {
		$mqttlivestat = `pgrep -f mqttlive.php`;
	}
	
	my %response = (
		telegraf => $telegrafstat,
		influx => $influxstat,
		grafanaserver => $grafanastat,
		mqttlive => $mqttlivestat,
	);
	chomp (%response);
	$response = encode_json( \%response );
}

## getpluginconfig
if( $q->{action} eq "getpluginconfig" ) {
	if ( -e $stats4loxconfig ) {
		$response = LoxBerry::System::read_file($stats4loxconfig);
		if( !$response ) {
			$response = "{ }";
		}
	}
	else {
		$response = "{ }";
	}
}

## savepluginconfig
if( $q->{action} eq "savepluginconfig" ) {
	require LoxBerry::JSON;
	my $errors = 0;
	my $cfgfile = $lbpconfigdir . "/stats4lox.json";
	my $jsonobj = LoxBerry::JSON->new();
	my $cfg = $jsonobj->open(filename => $cfgfile);
	if (!$cfg) {
		$errors++;
	}
	
	# Without the following workaround
	# the script cannot be executed as
	# background process via CGI
	my $pid = fork();
	$errors++ if !defined $pid;
	if ($pid == 0) {
		# do this in the child
		open STDIN, "< /dev/null";
		open STDOUT, "> /dev/null";
		open STDERR, "> /dev/null";

		# Output: Influx
		if ( $q->{'section'} eq "influx" ) {
			$cfg->{'influx'}->{'db_storage'} = $q->{'influx_db_storage'};
			$jsonobj->write();
			system ("sudo $lbpbindir/config-handler.pl influx >/dev/null 2>&1");
		}

		# Diagnostic logging of the services
		if ( $q->{'section'} eq "servicelog" ) {
			my $on = ( defined $q->{'servicelogging'} and $q->{'servicelogging'} eq "true" ) ? 1 : 0;
			$cfg->{'stats4lox'}->{'servicelogging'} = $on ? "True" : "False";
			$jsonobj->write();
			# Set here on purpose, so a reboot leaves it alone - unlike logging
			# that switched itself on because of the debug log level.
			require ServiceLog;
			ServiceLog::set_manual( $on );
			system ("sudo $lbpbindir/config-handler.pl servicelog >/dev/null 2>&1");
		}

	} # End Child process

	$response = '{ "error":' . $errors . '}';
}

##
## The shortest polling interval of the Loxone statistics (System tab)
##
## One setting with three consequences: Telegraf asks the grabber that often, the
## grabber gets three seconds less than Telegraf's timeout to answer, and no
## statistic may be polled more often than this.
##
## The statistics that are already faster are RAISED, not refused. A minimum that
## leaves the exceptions in place is not a minimum, and the user is told how many
## were changed.
if( $q->{action} eq "mininterval_save" ) {
	my $iv = $q->{interval} // '';
	my %ok = map { $_ => 1 } @Globals::LOXONE_MIN_INTERVALS;

	if( $iv !~ /^\d+$/ or !$ok{ $iv + 0 } ) {
		$error = "Interval '$iv' was not offered";
	}
	else {
		$iv += 0;
		require LoxBerry::JSON;
		my $raised = 0;

		# Both files are written inside their own block, and the block matters.
		#
		# LoxBerry::JSON keeps the file handle - and with it the exclusive lock -
		# for as long as the object lives. The config handler is started with a
		# fork further down, the child inherits every open descriptor, and a lock
		# inherited that way is still held after the parent is gone. The child
		# then waited for a lock it was holding itself: two root processes stuck
		# for good, and stats.json and stats4lox.json locked against everybody
		# else. Measured on the test box, and the only way out of it was a reboot.
		{
			my $obj = LoxBerry::JSON->new();
			my $cfg = $obj->open( filename => $stats4loxconfig, lockexclusive => 1, locktimeout => 10 );
			if( !$cfg ) {
				$error = "Could not open the configuration";
			}
			else {
				$cfg->{loxone}->{min_interval} = $iv;
				$obj->write();
				LOGOK "Shortest polling interval set to ${iv}s";
			}
		}

		# The statistics that are faster than that. Inactive ones too: they would
		# otherwise come back with an interval nobody may set any more the moment
		# somebody switches them on.
		#
		# An interval of 0 counts as too fast - it means "every cycle", which is as
		# fast as Telegraf asks.
		if( !$error ) {
			my $sobj = LoxBerry::JSON->new();
			my $st = $sobj->open( filename => $statsconfig, lockexclusive => 1, locktimeout => 10 );
			if( !$st ) {
				LOGWARN "stats.json could not be opened - the statistics were not adjusted";
			}
			elsif( ref($st->{loxone}) eq 'ARRAY' ) {
				foreach my $e ( @{ $st->{loxone} } ) {
					my $cur = $e->{interval};
					next if( defined $cur and $cur =~ /^\d+$/ and $cur + 0 >= $iv );
					# Written back as a string, which is how every other interval
					# in this file is stored - a number here and a string there
					# would be a difference nothing else in the plugin expects.
					$e->{interval} = "$iv";
					$raised++;
				}
				$sobj->write() if( $raised );
				LOGOK "$raised statistics raised to ${iv}s" if( $raised );
			}
		}

		if( !$error ) {
			# Telegraf's interval and timeout, and a restart. In the background:
			# the restart takes a moment and the page should not wait for it. Both
			# JSON objects are gone by now - see above.
			my $pid = fork();
			if( defined $pid and $pid == 0 ) {
				open STDIN,  "< /dev/null";
				open STDOUT, "> /dev/null";
				open STDERR, "> /dev/null";
				system( "sudo $lbpbindir/config-handler.pl grabber >/dev/null 2>&1" );
				exit 0;
			}

			$response = JSON::encode_json( {
				saved    => 1,
				interval => $iv + 0,
				raised   => $raised + 0,
				telegraf => $iv - 3,
				grabber  => $iv - 5,
			} );
		}
	}
}

##
## The Miniserver's own vital signs (Data sources -> Miniserver)
##
## Nothing is restarted and no config handler is involved: grabber_miniserver.cgi
## is called by Telegraf once a minute and reads the configuration every time, so
## the next round already uses what was saved here.
if( $q->{action} eq "miniserver_save" ) {
	my $iv = $q->{interval} // '';
	# Against the list the page was given, plus whatever is configured right now -
	# the page keeps a hand-edited value selectable, so it has to survive a save.
	my %ok = map { $_ => 1 }
		( @Globals::GRABBER_INTERVALS, int( $Globals::miniserver->{interval} || 300 ) );

	# The selection, checked against the catalogue. An empty list is refused: the
	# grabber cannot tell it apart from "never chosen" and would collect the
	# default set, so saving it would quietly do the opposite of what it says.
	my %known = map { $_->{key} => 1 } @Globals::MINISERVER_METRICS;
	my $metrics = eval { JSON::decode_json( $q->{metrics} // '[]' ) };
	my @clean;
	if( ref($metrics) eq 'ARRAY' ) {
		@clean = grep { $known{$_} } @$metrics;
	}

	if( $iv !~ /^\d+$/ or !$ok{ $iv + 0 } ) {
		$error = "Interval '$iv' was not offered";
	}
	elsif( ref($metrics) ne 'ARRAY' ) {
		$error = "The list of values is missing or malformed";
	}
	elsif( scalar @clean != scalar @$metrics ) {
		$error = "The list of values contains something that was not offered";
	}
	elsif( !scalar @clean ) {
		$error = "No value selected";
	}
	else {
		require LoxBerry::JSON;
		my $obj = LoxBerry::JSON->new();
		# locktimeout for the same reason as everywhere else in this file: without
		# one the lock is taken blocking, and this is a CGI.
		my $cfg = $obj->open( filename => $stats4loxconfig, lockexclusive => 1, locktimeout => 10 );
		if( !$cfg ) {
			$error = "Could not open the configuration";
		}
		else {
			my $on = is_enabled( $q->{active} ) ? "True" : "False";
			$cfg->{miniserver}->{active}   = $on;
			$cfg->{miniserver}->{interval} = $iv + 0;
			$cfg->{miniserver}->{metrics}  = \@clean;
			$obj->write();

			# The grabber notes per Miniserver when it is next due. Shortening the
			# interval would otherwise take effect only after the OLD one had run
			# out - up to an hour of a page claiming it polls every minute while
			# nothing arrives. Dropping the note makes every Miniserver due at once.
			unlink( $Globals::miniserver_memfile ) if( -e $Globals::miniserver_memfile );

			LOGOK "Miniserver grabber saved (active $on, interval ${iv}s, "
				. scalar(@clean) . " values)";
			$response = '{ "saved": 1 }';
		}
	}
}

## miniserver_live - what every Miniserver answers right now
#
# The whole catalogue, not the selection: the table exists to show what is on
# offer, and an endpoint this firmware does not know is part of that answer.
#
# Two dozen requests per Miniserver, which is why this is a button and not
# something the page does when it opens.
if( $q->{action} eq "miniserver_live" ) {
	require Stats4Lox;
	my %ms = LoxBerry::System::get_miniservers();
	my @out;
	foreach my $msno ( sort { $a <=> $b } keys %ms ) {
		my ($values, $errors) = Stats4Lox::miniserver_metric_values( $msno, \@Globals::MINISERVER_METRICS );
		push @out, {
			msno   => $msno + 0,
			name   => ( $ms{$msno}{Name} // '' ),
			values => $values,
			errors => $errors,
		};
		LOGINF "Miniserver $msno answered " . scalar( keys %$values ) . " values, "
			. scalar( keys %$errors ) . " endpoints not available";
	}
	$response = JSON::encode_json( { miniservers => \@out } );
}

##
## The LoxBerrys and what they report about themselves (Data sources -> LoxBerry)
##
## The list of machines, the interval and the selection, in one save. Nothing is
## restarted: grabber_loxberry.cgi reads the configuration on every call.
if( $q->{action} eq "loxberry_save" ) {
	my $iv = $q->{interval} // '';
	my %ok = map { $_ => 1 }
		( @Globals::GRABBER_INTERVALS, int( $Globals::loxberry->{interval} || 900 ) );

	my %known = map { $_->{key} => 1 } @Globals::LOXBERRY_METRICS;
	my $metrics = eval { JSON::decode_json( $q->{metrics} // '[]' ) };
	my @cleanm;
	@cleanm = grep { $known{$_} } @$metrics if( ref($metrics) eq 'ARRAY' );

	# The addresses. Only what an address may contain - letters, digits, dots,
	# hyphens and an optional port - because this string is put into a URL that
	# the plugin then fetches. Duplicates and empty entries are dropped rather
	# than refused; the page has already dropped them, this is the second line.
	my $hosts = eval { JSON::decode_json( $q->{hosts} // '[]' ) };
	my (@cleanh, %seenh, $badhost);
	if( ref($hosts) eq 'ARRAY' ) {
		foreach my $a ( @$hosts ) {
			next if( ref($a) or !defined $a );
			$a =~ s/^\s+//; $a =~ s/\s+$//;
			next if( $a eq '' );
			if( $a !~ /^[A-Za-z0-9][A-Za-z0-9\.\-]*(:\d{1,5})?$/ ) { $badhost = $a; last }
			next if( $seenh{ lc $a }++ );
			push @cleanh, { address => $a };
		}
	}

	if( $iv !~ /^\d+$/ or !$ok{ $iv + 0 } ) {
		$error = "Interval '$iv' was not offered";
	}
	elsif( ref($metrics) ne 'ARRAY' or ref($hosts) ne 'ARRAY' ) {
		$error = "The list of values or of hosts is missing or malformed";
	}
	elsif( defined $badhost ) {
		$error = "'$badhost' is not an address";
	}
	elsif( scalar @cleanm != scalar @$metrics ) {
		$error = "The list of values contains something that was not offered";
	}
	elsif( !scalar @cleanm ) {
		$error = "No value selected";
	}
	else {
		require LoxBerry::JSON;
		my $obj = LoxBerry::JSON->new();
		my $cfg = $obj->open( filename => $stats4loxconfig, lockexclusive => 1, locktimeout => 10 );
		if( !$cfg ) {
			$error = "Could not open the configuration";
		}
		else {
			my $on = is_enabled( $q->{active} ) ? "True" : "False";
			$cfg->{loxberry}->{active}   = $on;
			$cfg->{loxberry}->{interval} = $iv + 0;
			$cfg->{loxberry}->{metrics}  = \@cleanm;
			$cfg->{loxberry}->{hosts}    = \@cleanh;
			$obj->write();

			# The grabber's note of when each host is next due. Without dropping
			# it, a shortened interval would take effect only after the old one
			# had run out, and a machine that was just added would wait for it.
			unlink( $Globals::loxberry_memfile ) if( -e $Globals::loxberry_memfile );

			# Answer with the list as it was stored, so the page can redraw from
			# what the server accepted rather than from what was typed.
			$Globals::loxberry->{hosts} = \@cleanh;
			my @rows = map {
				{ address => $_->{address}, own => ( $_->{own} ? 1 : 0 ), label => $_->{tag} }
			} Globals::loxberry_hosts();

			LOGOK "LoxBerry grabber saved (active $on, interval ${iv}s, "
				. scalar(@cleanm) . " values, " . scalar(@cleanh) . " additional hosts)";
			$response = JSON::encode_json( { saved => 1, hosts => \@rows } );
		}
	}
}

## loxberry_check - does every configured LoxBerry answer with Linfo data?
#
# Asked right after saving. A mistyped address is worth finding out about now
# rather than in a week, when a graph is empty and nobody knows why.
if( $q->{action} eq "loxberry_check" ) {
	require Stats4Lox;
	my @out;
	foreach my $h ( Globals::loxberry_hosts() ) {
		my ($values, $err) = Stats4Lox::linfo_metric_values( $h->{url}, \@Globals::LOXBERRY_METRICS );
		push @out, {
			address => $h->{address},
			ok      => $err ? JSON::false : JSON::true,
			count   => scalar( keys %$values ),
			error   => ( $err // '' ),
		};
		LOGINF "LoxBerry $h->{address}: " . ( $err ? $err : scalar( keys %$values ) . " values" );
	}
	$response = JSON::encode_json( { hosts => \@out } );
}

## loxberry_live - what every configured LoxBerry reports right now
#
# The whole catalogue, not the selection: the table is there to show what is on
# offer, and a value this machine does not report is part of that answer.
if( $q->{action} eq "loxberry_live" ) {
	require Stats4Lox;
	my @out;
	foreach my $h ( Globals::loxberry_hosts() ) {
		my ($values, $err, $name) = Stats4Lox::linfo_metric_values( $h->{url}, \@Globals::LOXBERRY_METRICS );
		push @out, {
			address => $h->{address},
			# What the table calls it, and what goes into the database as the host
			# tag - "localhost" is how this machine is reached, not what it is.
			label   => ( $h->{tag} // $h->{address} ),
			name    => ( $name // '' ),
			values  => $values,
			error   => ( $err // '' ),
		};
	}
	$response = JSON::encode_json( { hosts => \@out } );
}

##
## InfluxDB credentials (issue #45)
##
## The password is handed out and changed only against a valid SecurePIN. The
## page hides the form until the PIN has been entered, but that is presentation
## - anyone can call this CGI directly, so the check is repeated here. The PIN
## travels with each request; the page keeps it in sessionStorage, the same way
## the LoxBerry MQTT widget does.
sub s4l_secpin_ok
{
	my $pin = shift;
	return 0 if( !defined $pin or $pin eq '' );
	my $res = LoxBerry::System::check_securepin( $pin );
	return ( !defined $res or $res == 0 ) ? 1 : 0;
}

## influx_getcred - user name and password, for the System page
if( $q->{action} eq "influx_getcred" ) {
	if( !s4l_secpin_ok( $q->{secpin} ) ) {
		LOGWARN "influx_getcred without a valid SecurePIN - refused";
		$error = "SecurePIN required";
	}
	else {
		require LoxBerry::JSON;
		my $obj = LoxBerry::JSON->new();
		my $c = $obj->open( filename => $stats4loxcredentials, readonly => 1 );
		$response = JSON::encode_json( {
			user     => ( $c ? $c->{influx}->{influxdbuser} : '' ) // '',
			password => ( $c ? $c->{influx}->{influxdbpass} : '' ) // '',
		} );
	}
}

## influx_passstatus - progress of a running password change
if( $q->{action} eq "influx_passstatus" ) {
	my $statfile = $Globals::stats4lox->{s4ltmp} . "/influxpass-status.json";
	$response = ( -e $statfile ) ? LoxBerry::System::read_file($statfile) : undef;
	$response = '{ }' if( !$response );
}

## influx_setpassword - sets a new password, or repairs a lost one
if( $q->{action} eq "influx_setpassword" ) {
	if( !s4l_secpin_ok( $q->{secpin} ) ) {
		LOGWARN "influx_setpassword without a valid SecurePIN - refused";
		$error = "SecurePIN required";
	}
	else {
		my $pw = $q->{password} // '';
		# Checked here as well as in the script: quotes and backslashes cannot
		# survive InfluxQL and the shell in between, and a mangled password
		# would lock the plugin out of its own database.
		if( $pw ne '' and $pw =~ /['"\\\s]/ ) {
			$error = "The password must not contain quotes, backslashes or spaces";
		}
		elsif( $pw ne '' and length($pw) < 8 ) {
			$error = "The password must be at least 8 characters long";
		}
		else {
			# Runs for a while - stopping and starting InfluxDB is part of the
			# fallback route - so it goes into the background and the page polls
			# the status file, the same mechanism the backup uses.
			#
			# Marked as running before forking: between the click and the first
			# line the script writes there is a gap, and in it the file would
			# still say "finished" from the previous run.
			my $statfile = $Globals::stats4lox->{s4ltmp} . "/influxpass-status.json";
			if( open( my $sfh, '>', $statfile ) ) {
				print {$sfh} '{"running":1,"message":"","time":' . time() . '}';
				close $sfh;
			}

			my $arg = ( $pw eq '' ) ? "--generate" : "--password " . quotemeta($pw);
			my $pid = fork();
			if( !defined $pid ) {
				$error = "Could not start the password change";
			}
			elsif( $pid == 0 ) {
				open STDIN,  "< /dev/null";
				open STDOUT, "> /dev/null";
				open STDERR, "> /dev/null";
				system( "sudo $lbpbindir/s4l_influxpass.pl set $arg" );
				exit 0;
			}
			else {
				$response = '{ "started": 1 }';
			}
		}
	}
}

##
## Influx page
##
## Split into three requests on purpose. Measured on 134 measurements: the
## overview costs 0.4 s, the timestamps 4.5 s, and counting the values 23.5 s.
## Putting all of that into one request would mean staring at an empty page for
## half a minute.

# stats.json read as characters, not as bytes.
#
# LoxBerry::JSON hands back byte strings, while the measurement names coming out
# of InfluxDB are decoded characters. Comparing the two directly fails for every
# name with an umlaut - "Alkalinität" from the database would never match
# "Alkalinit\xc3\xa4t" from the configuration.
sub s4l_stats_by_measurement
{
	my %out;
	open( my $fh, '<:raw', $statsconfig ) or return \%out;
	local $/;
	my $raw = <$fh>;
	close $fh;
	my $cfg = eval { JSON::decode_json( $raw ) };
	return \%out if( $@ or ref($cfg->{loxone}) ne 'ARRAY' );

	foreach my $e ( @{ $cfg->{loxone} } ) {
		next if( !$e->{measurementname} );
		$out{ $e->{measurementname} } = {
			uuid   => $e->{uuid},
			msno   => $e->{msno},
			name   => $e->{name},
			active => ( defined $e->{active} and $e->{active} eq 'true' ) ? 1 : 0,
			# The status the grabber recorded - the same source the Loxone page
			# uses, so both pages say the same thing about a statistic.
			error  => ( $e->{status} and $e->{status}->{error} ) ? $e->{status}->{error} : undef,
		};
	}
	return \%out;
}

## influx_overview - everything that is cheap to know
if( $q->{action} eq "influx_overview" ) {
	require InfluxInfo;
	my $names  = InfluxInfo::measurements();
	my $fields = InfluxInfo::fieldkeys();
	my $srcs   = InfluxInfo::sources();
	my $tags   = InfluxInfo::uuids();
	my $plan   = InfluxInfo::loxplan_uuids();
	my $system = InfluxInfo::system_measurements();
	my $stats  = s4l_stats_by_measurement();

	my @out;
	foreach my $n ( @$names ) {
		my $s = $stats->{$n};
		my @tag_uuids = @{ $tags->{$n} // [] };
		# Is a block behind this measurement still part of the Loxone
		# configuration we read in? Only asked for measurements without an entry
		# - for the others stats.json and the grabber's status say more.
		my $inplan = ( grep { $plan->{$_} } @tag_uuids ) ? 1 : 0;

		push @out, {
			name     => $n,
			fields   => $fields->{$n} // [],
			sources  => $srcs->{$n}   // [],
			# configured: there is an entry in stats.json using this name
			configured => $s ? 1 : 0,
			active     => $s ? $s->{active} : 0,
			error      => ( $s and $s->{error} ) ? $s->{error} : undef,
			uuid       => $s ? $s->{uuid} : undef,
			msno       => $s ? $s->{msno} : undef,
			blockname  => $s ? $s->{name} : undef,
			# for a measurement without an entry
			hasuuid    => scalar(@tag_uuids) ? 1 : 0,
			inplan     => $inplan,
			system     => $system->{$n} ? 1 : 0,
		};
	}

	# Deliberately nothing about statistics that have no measurement.
	#
	# That looks like a useful counterpart to the table, and it is not: right
	# after a statistic is switched on it is normal for a while, so the notice
	# would cry wolf for a whole interval. And the case that does mean something
	# belongs on the Loxone page, where the grabber already records a status per
	# statistic - not on a page about the contents of the database. It would not
	# even catch the interesting failure: if Telegraf stops, every measurement
	# stays in place with its old data and nothing here would notice.
	$response = JSON::encode_json( {
		measurements => \@out,
		database     => $Globals::influx->{influxdatabase} // 'stats4lox',
	} );
}

## influx_timestamps - first and last value of every measurement
if( $q->{action} eq "influx_timestamps" ) {
	require InfluxInfo;
	my $names = InfluxInfo::measurements();
	$response = JSON::encode_json( { timestamps => InfluxInfo::timestamps($names) } );
}

## influx_count - how many values, for one measurement or for all of them
if( $q->{action} eq "influx_count" ) {
	require InfluxInfo;
	my $names;
	if( defined $q->{name} and $q->{name} ne '' ) {
		# One name, and only if it really exists - the value ends up in a query.
		my $all = InfluxInfo::measurements();
		my $wanted = $q->{name};
		require Encode;
		$wanted = Encode::decode( 'UTF-8', $wanted, Encode::FB_DEFAULT() | Encode::LEAVE_SRC() );
		$names = [ grep { $_ eq $wanted } @$all ];
		$error = "Unknown measurement" if( !@$names );
	}
	else {
		$names = InfluxInfo::measurements();
	}
	$response = JSON::encode_json( { counts => InfluxInfo::valuecount($names) } ) if( !$error );
}

## influx_drop - removes a measurement, and on request switches its statistic off
if( $q->{action} eq "influx_drop" and defined $q->{name} and $q->{name} ne '' ) {
	require InfluxInfo;
	require Encode;
	my $wanted = Encode::decode( 'UTF-8', $q->{name}, Encode::FB_DEFAULT() | Encode::LEAVE_SRC() );

	# Only a measurement that is really there - the name goes into a DROP.
	my $all = InfluxInfo::measurements();
	if( !grep { $_ eq $wanted } @$all ) {
		$error = "Unknown measurement";
	}
	else {
		# Switching the statistic off first, then dropping. The other way round
		# the grabber could write the measurement again in the second between
		# the two - it runs every minute.
		my $deactivated = 0;
		if( defined $q->{deactivate} and $q->{deactivate} eq 'true' ) {
			my $stats = s4l_stats_by_measurement();
			my $s = $stats->{$wanted};
			if( $s and $s->{uuid} ) {
				require LoxBerry::JSON;
				my $obj = LoxBerry::JSON->new();
				my $cfg = $obj->open( filename => $statsconfig, lockexclusive => 1, locktimeout => 10 );
				if( $cfg and ref($cfg->{loxone}) eq 'ARRAY' ) {
					foreach my $e ( @{ $cfg->{loxone} } ) {
						next if( $e->{uuid} ne $s->{uuid} or $e->{msno} ne $s->{msno} );
						$e->{active} = "false";
						delete $e->{status};
						$deactivated = 1;
						last;
					}
					$obj->write() if( $deactivated );
					LOGOK "Statistic $s->{msno} / $s->{uuid} switched off before dropping the measurement"
						if( $deactivated );
				}
			}
		}

		my $dropped = InfluxInfo::drop_measurement( $wanted );
		if( $dropped ) { LOGOK "Measurement dropped: $q->{name}" }
		else           { LOGERR "Could not drop the measurement: $q->{name}" }
		$response = JSON::encode_json( { dropped => $dropped, deactivated => $deactivated } );
	}
}

##
## Backup
##
## Everything here runs s4l_backup.pl through sudo - the script needs root for
## influxd and for the service restarts. The sudoers rule covers exactly this
## one script.

# The archive names come back from the browser, so they are checked before they
# are handed to a root script: only our own name pattern, and only inside the
# configured storage directory. Returns the checked path or undef.
sub s4l_backup_file
{
	my ($wanted) = @_;
	return undef if( !$wanted );

	require File::Basename;
	my $name = File::Basename::basename($wanted);
	return undef if( $name !~ /^stats4lox_\d{8}_\d{6}\.(?:tar|tar\.gz|tar\.xz|zip|7z)$/ );

	my $dir = $Globals::backup->{storagepath};
	return undef if( !$dir );
	# Compare the resolved directory, not the string - a path with ".." in it
	# must not be able to point somewhere else.
	require Cwd;
	my $realdir = Cwd::realpath($dir) // return undef;
	my $realwanted = Cwd::realpath( File::Basename::dirname($wanted) ) // return undef;
	return undef if( $realwanted ne $realdir );

	return "$realdir/$name";
}

sub s4l_backup_bin { return "sudo $lbpbindir/s4l_backup.pl" }

# The page polls the status file to find out when the script is done. Between
# the click and the first line the script writes there is a gap of a second or
# two - and in that gap the file still holds "running: 0" from the last run, so
# the page would report success immediately. Marked as running before forking.
sub s4l_backup_status_reset
{
	my ($step) = @_;
	my $dir = $Globals::stats4lox->{s4ltmp};
	require File::Path;
	File::Path::make_path($dir) if( ! -d $dir );
	my $statfile = "$dir/backup-status.json";
	if( open( my $fh, '>', $statfile ) ) {
		print {$fh} '{"running":1,"step":"'.$step.'","message":"","time":' . time() . '}';
		close $fh;
	}
	return;
}

## backup_list
if( $q->{action} eq "backup_list" ) {
	my $dir = $Globals::backup->{storagepath};
	if( !$dir or ! -d $dir ) {
		$response = '{ "backups": [], "nostorage": 1 }';
	}
	else {
		$response = `@{[ s4l_backup_bin() ]} list --target "$dir" 2>/dev/null`;
		$response = '{ "backups": [] }' if( !$response or $response !~ /\S/ );
	}
}

## backup_check - may a restore go ahead, and where would the database land
if( $q->{action} eq "backup_check" ) {
	my $f = s4l_backup_file( $q->{file} );
	if( !$f ) {
		$response = '{ "ok": 0, "error": "Unknown archive" }';
	}
	else {
		$response = `@{[ s4l_backup_bin() ]} check --file "$f" 2>/dev/null`;
		$response = '{ "ok": 0, "error": "The check produced no answer" }' if( !$response or $response !~ /\S/ );
	}
}

## backup_status
if( $q->{action} eq "backup_status" ) {
	my $statfile = $Globals::stats4lox->{s4ltmp} . "/backup-status.json";
	$response = ( -e $statfile ) ? LoxBerry::System::read_file($statfile) : undef;
	$response = '{ }' if( !$response );
}

## backup_create
if( $q->{action} eq "backup_create" ) {
	my $dir = $Globals::backup->{storagepath};
	if( !$dir or ! -d $dir ) {
		$error = "No storage location configured";
	}
	else {
		# The backup takes minutes - the browser must not wait for it. The
		# status file is what the page polls.
		s4l_backup_status_reset("preparing");
		my $pid = fork();
		if( !defined $pid ) {
			$error = "Could not start the backup";
		}
		elsif( $pid == 0 ) {
			open STDIN,  "< /dev/null";
			open STDOUT, "> /dev/null";
			open STDERR, "> /dev/null";
			system( s4l_backup_bin() . " create --scheduled" );
			exit 0;
		}
		else {
			$response = '{ "started": 1 }';
		}
	}
}

## backup_restore
if( $q->{action} eq "backup_restore" ) {
	my $f = s4l_backup_file( $q->{file} );
	if( !$f ) {
		$error = "Unknown archive";
	}
	else {
		my $dbopt = ( $q->{dbpath} ) ? " --dbpath " . quotemeta( $q->{dbpath} ) : "";
		# --force is only passed on when the page has shown the warning about an
		# existing database and the user confirmed it.
		my $forceopt = ( defined $q->{force} and $q->{force} eq "true" ) ? " --force" : "";
		s4l_backup_status_reset("preparing");
		my $pid = fork();
		if( !defined $pid ) {
			$error = "Could not start the restore";
		}
		elsif( $pid == 0 ) {
			open STDIN,  "< /dev/null";
			open STDOUT, "> /dev/null";
			open STDERR, "> /dev/null";
			system( s4l_backup_bin() . " restore --file " . quotemeta($f) . $dbopt . $forceopt );
			exit 0;
		}
		else {
			$response = '{ "started": 1 }';
		}
	}
}

## backup_delete
if( $q->{action} eq "backup_delete" ) {
	my $f = s4l_backup_file( $q->{file} );
	if( !$f ) {
		$error = "Unknown archive";
	}
	else {
		system( s4l_backup_bin() . " delete --file " . quotemeta($f) . " >/dev/null 2>&1" );
		$response = ( -e $f ) ? '{ "deleted": 0 }' : '{ "deleted": 1 }';
	}
}

## savebackupconfig
if( $q->{action} eq "savebackupconfig" ) {
	require LoxBerry::JSON;
	my $errors = 0;
	my $jsonobj = LoxBerry::JSON->new();
	my $cfg = $jsonobj->open( filename => $stats4loxconfig );
	if( !$cfg ) {
		$errors++;
	}
	else {
		$cfg->{backup}->{storagepath} = $q->{storagepath} // '';
		$cfg->{backup}->{compression} = $q->{compression} // 'gzip';
		$cfg->{backup}->{keep}        = $q->{keep} // 3;
		$cfg->{backup}->{schedule}->{active} = $q->{scheduleactive} // 'False';
		$cfg->{backup}->{schedule}->{repeat} = $q->{repeat} // 1;
		$cfg->{backup}->{schedule}->{time}   = $q->{timef} // '03:00';
		# The reference week for "every n weeks". Set on every save, so changing
		# the schedule starts the cycle now instead of continuing an old one the
		# user can no longer see.
		my @now = localtime();
		$cfg->{backup}->{schedule}->{since} =
			sprintf( "%04d-%02d-%02d", $now[5]+1900, $now[4]+1, $now[3] );
		foreach my $d ( qw( mon tue wed thu fre sat sun ) ) {
			$cfg->{backup}->{schedule}->{$d} = $q->{$d} // 'False';
		}
		$jsonobj->write();

		$errors++ if( !s4l_write_crontab( $cfg->{backup} ) );
	}
	$response = '{ "error":' . $errors . '}';
}

# Writes the schedule as a crontab, in the same way the LoxBerry backup widget
# does it: build the file with Config::Crontab, then let installcrontab.sh put
# it in place - that is the only path a plugin has into ~/system/cron/cron.d.
sub s4l_write_crontab
{
	my ($b) = @_;

	require Config::Crontab;
	require LoxBerry::System;

	# The crontab is named after the plugin, and the name may carry a suffix if
	# another plugin claimed it first - so it is read, not assumed.
	my $pdata = LoxBerry::System::plugindata();
	my $pname = $pdata ? $pdata->{PLUGINDB_NAME} : undef;
	if( !$pname ) {
		LOGERR "Could not determine the plugin name - crontab not written";
		return 0;
	}

	my $tmp = "/tmp/crontab_stats4lox_$$.txt";
	unlink $tmp if( -e $tmp );
	my $ct = Config::Crontab->new( -file => $tmp );

	my @dow;
	push @dow, "0" if( is_enabled( $b->{schedule}->{sun} ) );
	push @dow, "1" if( is_enabled( $b->{schedule}->{mon} ) );
	push @dow, "2" if( is_enabled( $b->{schedule}->{tue} ) );
	push @dow, "3" if( is_enabled( $b->{schedule}->{wed} ) );
	push @dow, "4" if( is_enabled( $b->{schedule}->{thu} ) );
	push @dow, "5" if( is_enabled( $b->{schedule}->{fre} ) );
	push @dow, "6" if( is_enabled( $b->{schedule}->{sat} ) );

	my $block = Config::Crontab::Block->new();
	$block->last( Config::Crontab::Comment->new(
		-data => '## Stats4Lox Backup - do not change manually. Your changes will be overwritten!' ) );
	$block->last( Config::Crontab::Env->new( -name => 'MAILTO', -value => '""' ) );

	if( is_enabled( $b->{schedule}->{active} ) and scalar @dow ) {
		my ($hour, $minute) = split( /:/, $b->{schedule}->{time} // '03:00' );
		$hour   = 0 if( !$hour   or $hour   eq "00" );
		$minute = 0 if( !$minute or $minute eq "00" );
		$hour   += 0;
		$minute += 0;

		# cron cannot express "every n weeks". The obvious workaround - a shell
		# prefix computing days since a reference date - does not survive here:
		# cron runs commands through /bin/sh, which is dash on LoxBerry and has
		# no [[ ]], and every unescaped % in a crontab command is turned into a
		# newline, which kills any "date +%s". So cron only gets weekday and
		# time, and "--cron" lets the script decide whether this week is due.
		#
		# installcrontab.sh rewrites " root " to " loxberry ", and the script
		# itself insists on root - hence sudo, which the plugin's sudoers rule
		# allows without a password.
		$block->last( Config::Crontab::Event->new(
			-minute  => $minute,
			-hour    => $hour,
			-dow     => join( ",", @dow ),
			-command => "loxberry sudo $lbpbindir/s4l_backup.pl create --cron > /dev/null 2>&1" ) );
	}

	$ct->last($block);
	$ct->write;

	my $rc = system( "sudo $lbhomedir/sbin/installcrontab.sh " . quotemeta($pname)
	                 . " " . quotemeta($tmp) . " >/dev/null 2>&1" );
	unlink $tmp;
	if( $rc != 0 ) {
		LOGERR "installcrontab.sh failed (rc $rc)";
		return 0;
	}
	LOGOK "Backup schedule written to the crontab";
	return 1;
}

## config-handler-status
if( $q->{action} eq "config-handler-status" ) {
	my $section = $q->{section};
	my $statfile = $Globals::stats4lox->{s4ltmp} . "/config-handler-status.json";
	if ( -e $statfile ) {
		$response = LoxBerry::System::read_file($statfile);
	}
	if ( !$response | !$section ) {
		$response = "{ }";
	}
}

## update_mqttsubscriptions
if( $q->{action} eq "update_mqttsubscriptions" ) {
	# The subscriptions are received via POST in form field 'subscriptions' as json
	
	my $subscriptions = from_json( $q->{subscriptions} );
	
	use Data::Dumper;
	LOGDEB "ajax subscriptions: " . $q->{subscriptions};
	# LOGDEB Dumper(\$subscriptions);
	
	# Remove empty elements
	while( my ($index, $subscription) = each @{$subscriptions} ) {
		LOGDEB $index . " " . $subscription;
		if( !defined $subscription->{id} or $subscription->{id} eq "" ) {
			LOGDEB "Removing empty subscription line (index $index)";
			delete @{$subscriptions}[$index];
		}
	}
	
	# LOGDEB Dumper(\$subscriptions);
	require LoxBerry::JSON;
	my $jsonobjcfg = LoxBerry::JSON->new();
	# Same reason as in updatestat: without a locktimeout the lock is taken
	# blocking, and a CGI that waits without end shows the user nothing at all.
	my $cfg = $jsonobjcfg->open(filename => $statsconfig, lockexclusive => 1, locktimeout => 10);
	if( !$cfg ) {
		$error = "Could not open stats.json";
	}
	else {
		$cfg->{mqtt}->{subscriptions} = $subscriptions;
		$jsonobjcfg->write();
		$response = '{ }';
	}


}



#####################################
# Manage Response and error
#####################################

##
## Retention and downsampling (issue #44)
##
## All four go through bin/s4l_retention.pl. No sudo: the script only talks to
## InfluxDB, with the credentials from cred.json, exactly as the InfluxDB page
## already does.
##
## The order the page uses is save, preview, apply - and preview reads the SAVED
## configuration rather than taking the form fields as parameters. That is safe
## because the configuration on its own does nothing: not one line outside
## s4l_retention.pl reads $Globals::retention, so a saved but unapplied setting is
## a draft and nothing else. It also means a user who previews, takes fright and
## leaves finds their entries again instead of an empty form.

sub s4l_retention_bin { return "$lbpbindir/s4l_retention.pl" }

## retention_get - the configuration and what the page may offer
if( $q->{action} eq "retention_get" ) {
	require LoxBerry::JSON;

	# The largest interval the grabber writes with, for the warning next to the
	# downsampling interval. From stats.json plus the two system grabbers.
	my $grabber = 0;
	foreach my $g ( $Globals::miniserver, $Globals::loxberry ) {
		next if( !is_enabled( $g->{active} ) );
		$grabber = $g->{interval} if( ( $g->{interval} // 0 ) > $grabber );
	}
	my $obj = LoxBerry::JSON->new();
	my $st  = $obj->open( filename => $statsconfig, readonly => 1 );
	if( $st and ref($st->{loxone}) eq 'ARRAY' ) {
		foreach my $e ( @{ $st->{loxone} } ) {
			next if( !is_enabled( $e->{active} ) );
			$grabber = $e->{interval} if( ( $e->{interval} // 0 ) > $grabber );
		}
	}

	$response = JSON::encode_json( {
		retention        => $Globals::retention,
		intervals        => \@Globals::RETENTION_INTERVALS,
		durations        => \@Globals::RETENTION_DURATIONS,
		# Forced numeric. The intervals come out of stats.json as strings, and the
		# page treats a zero as "no grabber configured" - a string "0" is truthy
		# in JavaScript and would announce a warning about an interval of zero
		# minutes.
		grabber_interval => $grabber + 0,
	} );
}

# The settings out of a request, checked against the lists the page was given.
# A value that is not on them was not offered, so it did not come from the form.
# Returns ( $settings, $error ).
sub s4l_retention_from_request
{
	my ($q) = @_;
	my %interval_ok = map { $_ => 1 } @Globals::RETENTION_INTERVALS;
	my %duration_ok = map { $_ => 1 } ( @Globals::RETENTION_DURATIONS, '' );

	my $stages = eval { JSON::decode_json( $q->{stages} // '[]' ) };
	return ( undef, "The stage list is missing or has the wrong length" )
		if( ref($stages) ne 'ARRAY' or scalar @$stages != scalar @{ $Globals::retention->{stages} } );
	return ( undef, "Unknown retention duration" )
		if( !$duration_ok{ $q->{duration} // '' } or ( $q->{duration} // '' ) eq '' );

	my @clean;
	for( my $i = 0; $i < scalar @$stages; $i++ ) {
		my $s  = $stages->[$i];
		my $iv = ( $i == 0 ) ? 'raw' : ( $s->{interval} // '' );
		return ( undef, "Unknown interval $iv" )  if( $i > 0 and !$interval_ok{$iv} );
		return ( undef, "Unknown duration" )      if( !$duration_ok{ $s->{duration} // '' } );
		push @clean, {
			# Stage 1 is the raw data and is always on
			active   => ( $i == 0 or is_enabled( $s->{active} ) ) ? "True" : "False",
			interval => $iv,
			duration => $s->{duration} // '',
		};
	}

	return ( {
		duration     => $q->{duration},
		downsampling => is_enabled( $q->{downsampling} ) ? "True" : "False",
		stages       => \@clean,
	}, undef );
}

## retention_save - writes the settings, changes nothing in the database
if( $q->{action} eq "retention_save" ) {
	my ($set, $err) = s4l_retention_from_request( $q );
	if( $err ) { $error = $err }
	else {
		require LoxBerry::JSON;
		my $obj = LoxBerry::JSON->new();
		# locktimeout for the same reason as everywhere else in this file:
		# without one the lock is taken blocking, and this is a CGI.
		my $cfg = $obj->open( filename => $stats4loxconfig, lockexclusive => 1, locktimeout => 10 );
		if( !$cfg ) {
			$error = "Could not open the configuration";
		}
		else {
			$cfg->{retention}->{$_} = $set->{$_} foreach ( keys %$set );
			$obj->write();
			LOGOK "Retention settings saved (duration $set->{duration}, downsampling $set->{downsampling})";
			$response = '{ "saved": 1 }';
		}
	}
}

## retention_preview - what an apply would do, and what it would cost
#
# Reads nothing and writes nothing. If the request carries settings they are
# passed to the script with --config and the answer describes THOSE; without them
# it describes what is saved.
#
# It used to save the form first and then preview what had just been saved. That
# made a button called "Preview" write to the configuration, and it left the user
# with the honest question of what a saved-but-never-applied setting even is.
# Nothing outside the script reads it, so the answer was "nothing" - but a button
# should not need that explanation.
if( $q->{action} eq "retention_preview" ) {
	my $opts = '';
	if( defined $q->{stages} ) {
		my ($set, $err) = s4l_retention_from_request( $q );
		if( $err ) { $error = $err }
		else       { $opts = ' --config ' . quotemeta( JSON::encode_json( $set ) ) }
	}
	if( !$error ) {
		# Seconds, not minutes: the timestamps of every measurement in every policy
		# are asked for, about 2.2 s per policy on 146 measurements.
		$response = `@{[ s4l_retention_bin() ]} preview$opts 2>/dev/null`;
		$response = '{ "ok": 0, "error": "The preview produced no answer" }' if( !$response or $response !~ /\S/ );
	}
}

## retention_apply - carries the settings out, in the background
if( $q->{action} eq "retention_apply" ) {
	# backfill and force are the two ways out of the warning the page shows:
	# condense the history first, or accept the loss. Neither is a default.
	my $opts = '';
	$opts .= ' --backfill' if( ( $q->{backfill} // '' ) eq 'true' );
	$opts .= ' --force'    if( ( $q->{force}    // '' ) eq 'true' );
	# Carrying on where a run that was cut short stopped. The script checks for
	# itself that the settings still match the ones that run started with.
	$opts .= ' --resume'   if( ( $q->{resume}   // '' ) eq 'true' );

	# Marked as running before forking. Between the click and the first line the
	# script writes there is a gap of a second or two, and in that gap the page
	# would read the finished status of the previous run and report success - the
	# same trap the backup page fell into.
	require File::Path;
	File::Path::make_path( $Globals::stats4lox->{s4ltmp} ) if( ! -d $Globals::stats4lox->{s4ltmp} );
	if( open( my $fh, '>', $Globals::stats4lox->{s4ltmp} . "/retention-status.json" ) ) {
		print {$fh} '{"running":1,"step":"starting","current":"","total":0,"done":0,"error":"","time":' . time() . '}';
		close $fh;
	}

	my $pid = fork();
	if( !defined $pid ) {
		$error = "Could not start the retention run";
	}
	elsif( $pid == 0 ) {
		open STDIN,  "< /dev/null";
		open STDOUT, "> /dev/null";
		open STDERR, "> /dev/null";
		system( s4l_retention_bin() . " apply" . $opts );
		exit 0;
	}
	else {
		LOGOK "Retention run started$opts";
		$response = '{ "started": 1 }';
	}
}

## retention_status - what the run is doing, polled by the page
#
# The file alone cannot answer the question the page needs answered. It says
# "running: 1" just as loudly after a power cut as during a run, and the page
# would then block for ever waiting for a process that is gone.
#
# So the process is asked as well. The file carries the pid; if that pid is no
# longer there, the run was interrupted and the page has to offer a way on
# instead of a spinner.
#
# The file lives in s4ltmp, which is a ramdisk - after a reboot it is gone, and
# the page starts clean without anybody having to remove anything.
if( $q->{action} eq "retention_status" ) {
	my $statfile = $Globals::stats4lox->{s4ltmp} . "/retention-status.json";
	my $raw = ( -e $statfile ) ? LoxBerry::System::read_file($statfile) : undef;
	my $st  = ( $raw and $raw =~ /\S/ ) ? eval { JSON::decode_json($raw) } : undef;

	# After a reboot the ramdisk is empty, and that is exactly when a run that was
	# cut short has to be noticed. The resume point on the card outlives it.
	my $prog = {};
	{
		my $pf = $LoxBerry::System::lbpdatadir . "/retention-progress.json";
		if( -e $pf ) {
			my $p = eval { JSON::decode_json( LoxBerry::System::read_file($pf) // '' ) };
			$prog = $p if( ref($p) eq 'HASH' and ref($p->{cursor}) eq 'HASH' );
		}
	}

	if( ref($st) ne 'HASH' and %$prog ) {
		# Nothing in the ramdisk, but a run left a resume point behind
		$response = JSON::encode_json( {
			running => 0, interrupted => 1, step => $prog->{step},
			done => $prog->{done}, total => $prog->{total},
		} );
	}
	elsif( ref($st) ne 'HASH' ) {
		$response = '{ "running": 0 }';
	}
	else {
		if( $st->{running} and $st->{pid} ) {
			# /proc and not kill(0, $pid).
			#
			# kill 0 answers "does it exist AND may I signal it", and those are two
			# questions. For a process belonging to another user it says no while
			# the process is running perfectly well - the page would then offer to
			# resume a run that is in full swing. The directory in /proc exists for
			# every process on the machine and needs no permission to look at.
			my $alive = ( $st->{pid} =~ /^\d+$/ and -d "/proc/$st->{pid}" ) ? 1 : 0;
			$st->{interrupted} = 1 if( !$alive );
			$st->{running} = 0    if( !$alive );
		}
		# The ramdisk may also be simply out of date - a reboot wipes it, and the
		# plugin writes a fresh one on the next unrelated action. A resume point
		# on the card outlives all of that and settles the question.
		if( !$st->{running} and !$st->{interrupted} and %$prog ) {
			$st->{interrupted} = 1;
			$st->{done}  = $prog->{done};
			$st->{total} = $prog->{total};
		}
		$response = JSON::encode_json( $st );
	}
}

if( defined $response and !defined $error ) {
	print "Status: 200 OK\r\n";
	print "Content-type: application/json; charset=utf-8\r\n\r\n";
	print $response;
	LOGOK "Parameters ok - responding with HTTP 200";
}
elsif ( defined $error and $error ne "" ) {
	print "Status: 500 Internal Server Error\r\n";
	print "Content-type: application/json; charset=utf-8\r\n\r\n";
	print to_json( { error => $error } );
	LOGCRIT "$error - responding with HTTP 500";
}
else {
	print "Status: 501 Not implemented\r\n";
	print "Content-type: application/json; charset=utf-8\r\n\r\n";
	$error = "Action ".$q->{action}." unknown";
	LOGCRIT "Method not implemented - responding with HTTP 501";
	print to_json( { error => $error } );
}

sub createImportFolder
{
	if( ! -d $Globals::stats4lox->{importstatusdir} ) {
		`mkdir --parents "$Globals::stats4lox->{importstatusdir}"`;
	}
}

END {
	LOGEND if($log);
}
