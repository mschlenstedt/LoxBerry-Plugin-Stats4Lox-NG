use strict;
use warnings;
use JSON;

package LangUpdate;

# Keeps the Loxone element language files up to date without a plugin release.
#
# The files in templates/lang/loxelements_*.{json,ini} describe the blocks of
# Loxone Config. Until now every new Loxone Config release meant: run
# create_element_langfiles.pl by hand, commit, publish a release, and every user
# has to install it. Four steps, four opportunities to forget one.
#
# The plugin now fetches them itself. The counterpart is the GitHub workflow
# .github/workflows/update-language-files.yml, which regenerates the files in
# the repository whenever Loxone publishes a new Config.
#
# How a change is detected: one call to the GitHub contents API returns the blob
# SHA of every file in the directory. The same SHA is computed locally, and only
# files that actually differ are downloaded. No version file that anyone could
# forget to bump, and a single request for the whole directory.

our $REPO   = "mschlenstedt/LoxBerry-Plugin-Stats4Lox-NG";
our $BRANCH = "main";
our $DIR    = "templates/lang";

# Do not ask GitHub more often than this. The unauthenticated API allows 60
# requests per hour and IP, and new Loxone Config releases appear a few times a
# year - checking once a day is plenty.
our $INTERVAL = 24 * 60 * 60;

#####################################################
# git blob SHA of a file, exactly as GitHub reports it
#####################################################
# sha1( "blob " + bytecount + "\0" + content )
sub blob_sha
{
	my ($file) = @_;
	return undef if( ! -f $file );

	my $content;
	eval {
		open( my $fh, '<:raw', $file ) or die "$!\n";
		local $/;
		$content = <$fh>;
		close $fh;
	};
	return undef if( $@ or !defined $content );

	require Digest::SHA;
	return Digest::SHA::sha1_hex( "blob " . length($content) . "\0" . $content );
}

#####################################################
# Checks GitHub and downloads changed language files
#####################################################
# Named arguments:
#   log    LoxBerry::Log object (optional)
#   dir    target directory, defaults to the plugin's lang template directory
#   state  path of the file holding the time of the last check
#   force  ignore the interval
#
# Returns the number of updated files, or undef when nothing was done.
#
# Deliberately never fatal: no internet, GitHub down, a rate limit hit - all of
# that leaves the installation exactly as it was. The language files are a
# convenience, not a prerequisite for the plugin to run.

sub update
{
	my %args = @_;
	my $log  = $args{log};

	my $dir = $args{dir} || ( $LoxBerry::System::lbptemplatedir . "/lang" );
	if( ! -d $dir ) {
		$log->DEB("LangUpdate: $dir does not exist - skipped") if ($log);
		return undef;
	}

	my $statefile = $args{state} || ( $LoxBerry::System::lbpdatadir . "/langupdate.json" );

	# Interval
	if( !$args{force} ) {
		my $last = 0;
		eval {
			open( my $fh, '<', $statefile ) or die "$!\n";
			local $/;
			my $s = JSON::decode_json( <$fh> );
			close $fh;
			$last = $s->{lastcheck} || 0;
		};
		if( $last and (time() - $last) < $INTERVAL ) {
			$log->DEB("LangUpdate: last check was " . int((time()-$last)/60) . " minutes ago - skipped") if ($log);
			return undef;
		}
	}

	# The timestamp is written BEFORE the request. Otherwise a permanently
	# failing check - no internet, for instance - would hit GitHub on every
	# single page load.
	eval {
		open( my $fh, '>', $statefile ) or die "$!\n";
		print {$fh} JSON::encode_json( { lastcheck => time() } );
		close $fh;
	};

	my $list = fetch_json( "https://api.github.com/repos/$REPO/contents/$DIR?ref=$BRANCH", $log );
	if( ref($list) ne 'ARRAY' ) {
		$log->DEB("LangUpdate: could not read the file list from GitHub") if ($log);
		return undef;
	}

	my $updated = 0;
	my $checked = 0;
	foreach my $entry ( @$list ) {
		next if( ref($entry) ne 'HASH' );
		next if( ($entry->{type} // '') ne 'file' );
		next if( ($entry->{name} // '') !~ /^loxelements_[a-z]{2}\.(?:json|ini)$/ );
		next if( !$entry->{sha} or !$entry->{download_url} );

		$checked++;
		my $local = "$dir/$entry->{name}";
		my $mine  = blob_sha( $local );
		next if( defined $mine and $mine eq $entry->{sha} );

		if( download_file( $entry->{download_url}, $local, $entry->{name}, $log ) ) {
			$updated++;
			$log->OK("LangUpdate: $entry->{name} updated") if ($log);
		}
	}

	if( $updated ) {
		$log->OK("LangUpdate: $updated of $checked language files updated from GitHub") if ($log);
	}
	else {
		$log->INF("LangUpdate: language files are up to date ($checked checked)") if ($log);
	}
	return $updated;
}

#####################################################
# Downloads one file, checks it, and swaps it in atomically
#####################################################
# A half written or corrupt language file would break the element names in the
# web interface, so the content is verified before it replaces anything: valid
# UTF-8 throughout, and for .json also valid JSON with at least one entry.

sub download_file
{
	my ($url, $target, $name, $log) = @_;

	require LWP::UserAgent;
	my $ua = LWP::UserAgent->new( timeout => 20, agent => "Stats4Lox" );
	my $resp = $ua->get( $url );
	if( !$resp->is_success ) {
		$log->WARN("LangUpdate: $name could not be downloaded: " . $resp->status_line) if ($log);
		return 0;
	}

	my $content = $resp->decoded_content( charset => 'none' );
	if( !defined $content or $content eq '' ) {
		$log->WARN("LangUpdate: $name arrived empty") if ($log);
		return 0;
	}

	require Encode;
	my $chars = eval { Encode::decode( 'UTF-8', $content, Encode::FB_CROAK() | Encode::LEAVE_SRC() ) };
	if( !defined $chars ) {
		$log->WARN("LangUpdate: $name is not valid UTF-8 - discarded") if ($log);
		return 0;
	}

	if( $name =~ /\.json$/ ) {
		my $data = eval { JSON::decode_json( $content ) };
		if( ref($data) ne 'HASH' or !%{$data} ) {
			$log->WARN("LangUpdate: $name is not usable JSON - discarded") if ($log);
			return 0;
		}
	}

	my $tmp = "$target.tmp.$$";
	my $ok = eval {
		open( my $fh, '>:raw', $tmp ) or die "$!\n";
		print {$fh} $content or die "$!\n";
		close $fh or die "$!\n";
		rename( $tmp, $target ) or die "$!\n";
		1;
	};
	if( !$ok ) {
		unlink $tmp;
		$log->WARN("LangUpdate: $name could not be written: $@") if ($log);
		return 0;
	}
	return 1;
}

sub fetch_json
{
	my ($url, $log) = @_;

	require LWP::UserAgent;
	my $ua = LWP::UserAgent->new( timeout => 20, agent => "Stats4Lox" );
	my $resp = $ua->get( $url, 'Accept' => 'application/vnd.github+json' );
	if( !$resp->is_success ) {
		# 403 here is almost always the rate limit, which is not an error worth
		# alarming anyone about - the next check simply happens a day later.
		$log->DEB("LangUpdate: GitHub answered " . $resp->status_line) if ($log);
		return undef;
	}
	my $data = eval { JSON::decode_json( $resp->decoded_content( charset => 'none' ) ) };
	return $@ ? undef : $data;
}

1;
