#!/usr/bin/perl
#
# Generates the Loxone element definitions (templates/lang/loxelements_*.ini
# and .json) from the language resources of an installed Loxone Config.
#
# MAINTAINER BUILD STEP - this does not run on user systems. The generated
# files are committed and shipped with the plugin. Run it after a new major
# Loxone Config release.
#
#   perl bin/create_element_langfiles.pl [--src <dir>] [--out <dir>]
#                                        [--lang <code>] [--dry-run]
#
# --src   directory holding the tdc_*.LxRes files. Defaults to the usual
#         Loxone Config installation path, then /tmp.
# --out   target directory, defaults to templates/lang next to this script.
#
# Runs with a plain Perl - no XML::LibXML and no Python needed, so it can be
# executed directly on the machine where Loxone Config is installed.
#
# Format note: up to Loxone Config ~13 the resources were called
# HelpDesc_*.LxRes and contained <String Type="NA"> / <String Type="OL">
# elements. Since then they are called tdc_*.LxRes and contain a <TechDoc>
# tree of <FunctionBlock> with <IOGroup>/<IO> children. Only the new format is
# supported; the old one has not existed for years.
#
# The existing files are MERGED, never replaced: Loxone has dropped many older
# blocks from its documentation, and their names must not get lost.

use strict;
use warnings;
use File::Basename;
use File::Spec;
use Getopt::Long;
use JSON::PP;

my $scriptdir = dirname( File::Spec->rel2abs(__FILE__) );

my $src;
my $out     = "$scriptdir/../templates/lang";
my $onlylang;
my $dryrun  = 0;
GetOptions(
    'src=s'   => \$src,
    'out=s'   => \$out,
    'lang=s'  => \$onlylang,
    'dry-run' => \$dryrun,
) or die "Invalid arguments\n";

# Loxone language code -> plugin language code.
# Only the languages the plugin already ships are generated; further resources
# are reported at the end so they can be added deliberately.
my %LANG = (
    CAT => 'ca', CHS => 'ch', CSY => 'cs', DEU => 'de', ENU => 'en',
    ESN => 'es', FRA => 'fr', HUN => 'hu', ITA => 'it', NLD => 'nl',
    NOR => 'no', PLK => 'pl', ROM => 'ro', RUS => 'ru', SKY => 'sk',
);

# ---------------------------------------------------------------- source dir
# Note: glob() splits its pattern on whitespace, which breaks on paths like
# "C:/Program Files (x86)/...". opendir has no such problem.
sub find_resources {
    my ($dir) = @_;
    return () if( !defined $dir or !-d $dir );
    opendir( my $dh, $dir ) or return ();
    my @f = sort grep { /^tdc_[A-Za-z]+\.LxRes$/i } readdir($dh);
    closedir $dh;
    return map { "$dir/$_" } @f;
}

if( !defined $src ) {
    foreach my $cand ( 'C:/Program Files (x86)/Loxone/LoxoneConfig',
                       'C:/Program Files/Loxone/LoxoneConfig',
                       '/tmp' ) {
        if( find_resources($cand) ) { $src = $cand; last }
    }
}
if( !defined $src or !find_resources($src) ) {
    print "No tdc_*.LxRes found.\n\n";
    print "Point --src at the Loxone Config installation, for example\n";
    print "  perl $0 --src \"C:/Program Files (x86)/Loxone/LoxoneConfig\"\n\n";
    print "or copy the tdc_*.LxRes files there and use --src <dir>.\n";
    exit 1;
}
print "Source     : $src\n";
print "Target     : $out\n";
print "Mode       : " . ($dryrun ? "dry run, nothing is written" : "writing") . "\n\n";

# ---------------------------------------------------------------- unpacking
sub unpack_lxres {
    my ($file) = @_;
    my $dest = File::Spec->catfile( File::Spec->tmpdir(), basename($file) . ".xml" );
    my $unpacker = "$scriptdir/libs/Loxone/unpack_loxcc.pl";
    my @cmd = ( $^X, $unpacker, $file, $dest );
    system( @cmd );
    if( $? != 0 or ! -s $dest ) {
        print "  !! could not unpack $file\n";
        return;
    }
    open( my $fh, '<:raw', $dest ) or return;
    local $/;
    my $content = <$fh>;
    close $fh;
    unlink $dest;
    # strip a UTF-8 BOM
    my $BOM = chr(0xef).chr(0xbb).chr(0xbf);
    $content = substr($content, 3) if( substr($content,0,3) eq $BOM );

    # Decode to characters.
    #
    # Without this the resource stays a byte string, and everything downstream
    # goes wrong twice over:
    #
    #   1. JSON::PP->utf8->encode() encodes those bytes a SECOND time when the
    #      file is written. "ü" (C3 BC) turned into "Ã¼" (C3 83 C2 BC), which is
    #      what users saw in the web interface as "Berechnung stÃ¼ndlich".
    #   2. cleantext() cuts overlong descriptions with substr(..., 0, 250).
    #      On bytes that cuts in the middle of a multi byte character and
    #      leaves a dangling first byte behind - an unrepairable string.
    #
    # With characters, substr counts characters and can no longer split one.
    require Encode;
    $content = Encode::decode( 'UTF-8', $content );
    return $content;
}

# ---------------------------------------------------------------- text clean
# Loxone markup: $$BR$$ line break, $$LINK::url@@text$$ hyperlink.
sub cleantext {
    my ($t) = @_;
    return '' if( !defined $t );
    $t =~ s/\$\$LINK::[^@]*\@\@(.*?)\$\$/$1/g;   # keep the link text
    $t =~ s/\$\$BR\$\$.*$//s;                     # first line only
    $t =~ s/\$\$[A-Za-z0-9_:.\/@-]*\$\$//g;       # drop remaining markup
    $t =~ s/&lt;/</g; $t =~ s/&gt;/>/g; $t =~ s/&amp;/&/g; $t =~ s/&quot;/"/g;
    # some descriptions use HTML line breaks instead of the $$BR$$ markup
    $t =~ s/<br\s*\/?>.*$//is;
    $t =~ s/<[^>]{1,20}>//g;
    $t =~ s/\s+/ /g;
    $t =~ s/^\s+|\s+$//g;
    $t = substr($t, 0, 250) if( length($t) > 250 );
    return $t;
}

sub attrs {
    my ($s) = @_;
    my %a;
    while( $s =~ /([A-Za-z_][A-Za-z0-9_]*)\s*=\s*"([^"]*)"/g ) { $a{$1} = $2 }
    return \%a;
}

# Collects the IO templates of the document.
#
# Many outputs are not spelled out at the block but reference a template:
#   <IO Id="2" TemplateId="MeterTot" />
# and the definition sits elsewhere in the file:
#   <IO Id="517003" TemplateId="MeterTot" Name="OMr" ShortName="Mr"
#       Description="Zählerstand" />
# Without resolving these, blocks like MeterPUni end up with a single output
# instead of nine.
sub collect_templates {
    my ($xml) = @_;
    my %tpl;
    while( $xml =~ m{<IO\b([^>]*?)/?>}gs ) {
        my $a = attrs($1);
        my $tid = $a->{TemplateId};
        next if( !defined $tid or $tid eq '' );
        # a definition carries a description; keep the first complete one
        next if( !defined $a->{Description} and !defined $a->{ShortDescription} );
        next if( exists $tpl{$tid} and defined $tpl{$tid}->{Description} );
        $tpl{$tid} = $a;
    }
    return \%tpl;
}

# ------------------------------------------------------------------ TechDoc
# Returns { TYPE => { localname, controltype, OL => {...}, outputs => [...] } }
sub parse_techdoc {
    my ($xml) = @_;
    my %elements;
    my $tpl = collect_templates($xml);

    while( $xml =~ m{<FunctionBlock\b([^>]*?)(?:/>|>(.*?)</FunctionBlock>)}gs ) {
        my ($attrstr, $body) = ($1, $2);
        my $a = attrs($attrstr);
        next if( !defined $a->{LxType} or $a->{LxType} eq '' );

        my $key = uc( $a->{LxType} );
        my %e = (
            localname   => cleantext( $a->{Name} ),
            controltype => $a->{ControlType},
            OL          => {},
            outputs     => [],
        );

        if( defined $body ) {
            while( $body =~ m{<IOGroup\b([^>]*)>(.*?)</IOGroup>}gs ) {
                my ($gattr, $gbody) = ($1, $2);
                my $ga = attrs($gattr);
                next if( ($ga->{Type} // '') ne 'Output' );

                while( $gbody =~ m{<IO\b([^>]*?)/?>}gs ) {
                    my $own = attrs($1);

                    # Resolve a template reference: template attributes first,
                    # the block's own attributes overlay them (its Id is the
                    # position within the block and must win).
                    my $io = $own;
                    if( defined $own->{TemplateId} and $tpl->{ $own->{TemplateId} } ) {
                        my %merged = ( %{ $tpl->{ $own->{TemplateId} } }, %{$own} );
                        $io = \%merged;
                    }

                    # placeholder entries such as TemplateId="APICONNECTOR"
                    next if( !defined $io->{Name} and !defined $io->{ShortName} );

                    my $text = cleantext( $io->{Description} );
                    $text = cleantext( $io->{ShortDescription} ) if( $text eq '' );

                    # OL is keyed by label. Both the old label (Name) and the
                    # current one (ShortName) are registered, because a
                    # Miniserver reports the current one while older
                    # measurements and mappings still use the old one.
                    foreach my $label ( $io->{Name}, $io->{ShortName} ) {
                        next if( !defined $label or $label eq '' );
                        $e{OL}->{$label} = $text if( $text ne '' );
                    }

                    push @{ $e{outputs} }, {
                        id        => $io->{Id},
                        name      => $io->{Name},
                        shortname => $io->{ShortName},
                        desc      => $text,
                    };
                }
            }
        }
        $elements{$key} = \%e;
    }
    return \%elements;
}

# --------------------------------------------------------------------- main
my @files = find_resources($src);
printf("Found %d resource files\n\n", scalar @files);

my %stat;
my @skipped;

foreach my $file ( @files ) {
    my $base = basename($file);
    my ($loxlang) = $base =~ /^tdc_([A-Z]+)\.LxRes$/i;
    if( !defined $loxlang ) { next }
    $loxlang = uc $loxlang;

    if( !$LANG{$loxlang} ) { push @skipped, $loxlang; next }
    my $lang = $LANG{$loxlang};
    next if( defined $onlylang and $lang ne $onlylang );

    my $xml = unpack_lxres($file);
    if( !$xml ) { next }

    my $new = parse_techdoc($xml);

    # merge with what is already there
    my $jsonfile = "$out/loxelements_$lang.json";
    my $existing = {};
    if( -s $jsonfile ) {
        open( my $fh, '<:raw', $jsonfile ) or die "$jsonfile: $!";
        local $/;
        my $raw = <$fh>;
        close $fh;
        eval { $existing = JSON::PP->new->utf8->decode($raw) } or $existing = {};
    }

    my ($added, $updated) = (0,0);
    foreach my $key ( keys %{$new} ) {
        if( exists $existing->{$key} ) { $updated++ } else { $added++ }
        my $e = $existing->{$key} ||= {};
        $e->{localname}   = $new->{$key}->{localname} if( $new->{$key}->{localname} ne '' );
        $e->{controltype} = $new->{$key}->{controltype} if( defined $new->{$key}->{controltype} );
        $e->{outputs}     = $new->{$key}->{outputs};
        $e->{OL} ||= {};
        foreach my $l ( keys %{ $new->{$key}->{OL} } ) {
            $e->{OL}->{$l} = $new->{$key}->{OL}->{$l};
        }
    }
    my $kept = scalar(keys %{$existing}) - $added - $updated;

    printf("%-4s (%s): %3d types in the resource | %3d updated, %3d added, %3d kept -> %d total\n",
           $lang, $loxlang, scalar(keys %{$new}), $updated, $added, $kept, scalar(keys %{$existing}));
    $stat{$lang} = { added => $added, updated => $updated, kept => $kept };

    next if( $dryrun );

    # .json
    open( my $jf, '>:raw', $jsonfile ) or die "$jsonfile: $!";
    print $jf JSON::PP->new->utf8->canonical->encode($existing);
    close $jf;

    # .ini (element names only, as before)
    #
    # Written through an encoding layer, not raw: the names are character
    # strings now. Written raw they would come out as latin-1, which is exactly
    # how the shipped .ini files became invalid UTF-8.
    my $inifile = "$out/loxelements_$lang.ini";
    open( my $inf, '>:encoding(UTF-8)', $inifile ) or die "$inifile: $!";
    print $inf "[ELEMENTS]\n";
    foreach my $key ( sort keys %{$existing} ) {
        my $n = $existing->{$key}->{localname};
        next if( !defined $n or $n eq '' );
        $n =~ s/"/'/g;
        print $inf $key . '="' . $n . '"' . "\n";
    }
    close $inf;
}

if( @skipped ) {
    my %u; $u{$_}=1 for @skipped;
    print "\nResources present but not generated (no plugin language assigned): "
          . join(", ", sort keys %u) . "\n";
    print "Add them to %LANG in this script if they are wanted.\n";
}
print "\nDone.\n";
