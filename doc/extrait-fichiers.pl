#! /usr/bin/perl
#
# Copyright (C) 2008-2016 Alexis Bienvenue <paamc@passoire.fr>
#
# This file is part of Auto-Multiple-Choice
#
# Auto-Multiple-Choice is free software: you can redistribute it
# and/or modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation, either version 2 of
# the License, or (at your option) any later version.
#
# Auto-Multiple-Choice is distributed in the hope that it will be
# useful, but WITHOUT ANY WARRANTY; without even the implied warranty
# of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with Auto-Multiple-Choice.  If not, see
# <http://www.gnu.org/licenses/>.

use Getopt::Long;
use XML::LibXML;
use Encode;
use Archive::Tar;

my $liste='';

GetOptions("liste=s"=>\$liste,
	  );

my $tar_opts={uid=>0,gid=>0,uname=>'root',gname=>'root',mtime=>1420066800};

my @fichiers=@ARGV;

open(LOG,">$liste") if($liste);

for my $f (@fichiers) {

    print "*** File $f\n";

    my $parser = XML::LibXML->new();
    my $xp=$parser->parse_file($f);

    my $lang='';
    my @articles= $xp->findnodes('/article')->get_nodelist;
    if($articles[0] && $articles[0]->findvalue('@lang')) {
	$lang=$articles[0]->findvalue('@lang');
	$lang =~ s/[.-].*//;
	print "  I lang=$lang\n";
    }

    my $nodeset = $xp->findnodes('//programlisting');

    foreach my $node ($nodeset->get_nodelist) {

	my $id=$node->findvalue('@id');
	my $ex=$node->textContent();

	if($id =~ /^(modeles)-(.*)\.(tex|txt)$/) {

	    my $rep=$1;
	    $rep.="/$lang" if($lang);
	    my $name=$2;
	    my $ext=$3;
	    my $code_name=$name;

	    print "  * extracting $rep/$code_name\n";

	    my $desc='Doc / sample LaTeX file';

	    my $parent=$node->parentNode();
	    foreach my $fr ($parent->childNodes()) {
		if($fr->nodeName() == '#comment') {
		    my $c=$fr->toString();
		    if($c =~ /^<!--\s*NAME:\s*(.*)\n\s*DESC:\s*((?:.|\n)*)-->$/) {
			$name=$1;
			$desc=$2;
			print "    embedded description / N=$name\n";
		    }
		}
	    }

	    my $tar = Archive::Tar->new;

	    $tar->add_data("$code_name.$ext",encode_utf8($ex),$tar_opts);
            $tar->chmod("$code_name.$ext",'0644');
	    $tar->add_data("description.xml",
			   encode_utf8('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<description>
  <title>'.$name.'</title>
  <text>'.$desc.'</text>
</description>
'),$tar_opts
                          );
            $tar->chmod("description.xml",'0644');
	    my $opts='<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<projetAMC>
  <texsrc>%PROJET/'.$code_name.'.'.$ext.'</texsrc>
';
	    if($ext eq 'tex') {
	      $opts .= '  <moteur_latex_b>pdflatex</moteur_latex_b>
';
	    } else {
	      $opts .= '  <filter>plain</filter>
';
	    }
	    $opts .= '</projetAMC>
';
	    $tar->add_data("options.xml",
			   encode_utf8($opts),$tar_opts);
            $tar->chmod("options.xml",'0644');
	    $tar->write("$rep/$code_name.tgz", COMPRESS_GZIP);

	    print LOG "$rep/$code_name.tgz\n" if($liste);

	}
    }

}

close(LOG) if($liste);


