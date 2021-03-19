#!/usr/bin/perl
use warnings;
use strict;
use LoxBerry::System;
use File::Basename;
use XML::LibXML;
use JSON;

our $src_directory = '/tmp';

get_sourcefiles();

sub get_sourcefiles
{
	my @files = glob( $src_directory . '/HelpDesc_*.LxRes' );
	
	if( ! @files ) {
		print 'Copy C:\Program Files (x86)\Loxone\LoxoneConfig\HelpDesc_*.LxRes to /tmp'."\n";
		print "The script directly creates language files in\n";
		print "$lbptemplatedir/lang/ as loxelements*.ini\n";
		exit;
	}
	
	foreach my $fullpath (@files) {
		my ($file, $dirs) = File::Basename::fileparse($fullpath);
		my ($filename, $fileext) = split(/\./, $file);
		my ($prefix, $lang) = split( "_", $filename );
		
		my $langfilename = $lbptemplatedir.'/lang/loxelements_'.lc(substr($lang, 0, 2)).'.ini';
			
		print "$file: Lang $lang\n";
		my $destfile = File::Basename::dirname($fullpath).'/'.$filename.'.xml';
		unpack_file( $fullpath, $destfile);
		my $elements;
		if( ! -e $destfile ) {
			print "Could not find $destfile for parsing.\n";
			next;
		}
		$elements = parse_xml( $destfile );
		if( ! $elements ) {
			print "Could not parse XML of $destfile.\n";
			next;
		}
		
		# Create language file (INI style, only element names)
		my $ini = "[ELEMENTS]\n";
		foreach( sort keys %$elements ) {
			$ini .= $_.'="'.$elements->{$_}{localname}.'"'."\n";
		}
		eval {
			open(my $fh, '>', $langfilename);
			print $fh $ini;
			close $fh;
		};
		if( $@ ) {
			print "Error writing file $langfilename: $!\n";
		}
		else {
			print "File $langfilename written\n";
		}
		
		# Create language json file (json style, including outputs)
		my $langfilejsonname = $lbptemplatedir.'/lang/loxelements_'.lc(substr($lang, 0, 2)).'.json';
		eval {
			open(my $fh, '>', $langfilejsonname);
			print $fh to_json( $elements );
			close $fh;
		};
		if( $@ ) {
			print "Error writing file $langfilejsonname: $!\n";
		}
		else {
			print "File $langfilejsonname written\n";
		}
		
	}
}





sub unpack_file {
	my ($inputfile, $outputfile) = @_;
	
	`${LoxBerry::System::lbpbindir}/libs/Loxone/unpack_loxcc.py "$inputfile" "$outputfile"`;
}



sub parse_xml {
	
	my ($inputfile) = @_;

	my $xmlstr = LoxBerry::System::read_file( $inputfile );

	# Loxone uses a BOM, that cannot be handled by the XML Parser
	my $UTF8_BOM = chr(0xef) . chr(0xbb) . chr(0xbf);
	if(substr( $xmlstr, 0, 3) eq $UTF8_BOM) {
		$xmlstr = substr $xmlstr, 3;
	}
	$xmlstr = Encode::encode("utf8", $xmlstr);
	
	my $dom = XML::LibXML->load_xml(
		string => $xmlstr
	);

	my %elements;

	my @nodes = $dom->findnodes('//String[@Type="NA"]');
	
	foreach my $element ( @nodes ) {
		my $id = $element->{ID};
		my $locatename = $element->{Text};
		
		my (undef, $name, undef) = split( "_", $id );
		
		$elements{$name}{localname} = $locatename;
	}
	
	# Add Output descriptions
	my @elementnodes = $dom->findnodes('//String[@Type="OL"]');
	foreach my $ol ( @elementnodes ) {
		my $id = $ol->{ID};
		my (undef, $name, undef) = split( "_", $id );
		my $olname = $ol->{Name};
		my $oltext = $ol->{Text};
		print STDERR "  $id, $name, $olname, $oltext\n";
		$elements{$name}{OL}{$olname} = $oltext;
	}
	
	return \%elements;

}