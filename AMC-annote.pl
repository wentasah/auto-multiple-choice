#! /usr/bin/perl
#
# Copyright (C) 2009-2015 Alexis Bienvenue <paamc@passoire.fr>
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

use Gtk2;
use Cairo;

use List::Util qw(min max sum);

use AMC::Path;
use AMC::Basic;
use AMC::Exec;
use AMC::Gui::Avancement;
use AMC::NamesFile;
use AMC::Data;
use AMC::DataModule::capture qw/:zone :position/;
use AMC::DataModule::layout qw/:flags/;
use AMC::Substitute;

use encoding 'utf8';

my $cr_dir="";
my $rep_projet='';
my $rep_projets='';
my $fichnotes='';
my $fich_bareme='';
my $id_file='';

my $seuil=0.1;
my $seuil_up=1.0;

my $data_dir='';

my $taille_max="1000x1500";
my $qualite_jpg="65";

my $debug='';

my $progress=1;
my $progress_id='';

my $line_width=2;
my @o_symbols=();
my $annote_indicatives='';
my $position='marge';
my $ecart=1;
my $ecart_marge=1.5;
my $pointsize_rel=60;

my $chiffres_significatifs=4;

my $verdict='TOTAL : %S/%M => %s/%m';
my $verdict_question_cancelled='"X"';
my $verdict_question='';

my $font_name='FreeSans';
my $rtl='';
my $test_font_size=100;

my $fich_noms='';
my $noms_encodage='utf-8';
my $csv_build_name='';

my $changes_only=1;

# cle : "a_cocher-cochee"
my %symboles=(
    '0-0'=>{qw/type none/},
    '0-1'=>{qw/type circle color red/},
    '1-0'=>{qw/type mark color red/},
    '1-1'=>{qw/type mark color blue/},
);

@ARGV=unpack_args(@ARGV);

GetOptions("cr=s"=>\$cr_dir,
	   "projet=s",\$rep_projet,
	   "projets=s",\$rep_projets,
	   "data=s"=>\$data_dir,
	   "id-file=s"=>\$id_file,
	   "debug=s"=>\$debug,
	   "taille-max=s"=>\$taille_max,
	   "qualite=s"=>\$qualite_jpg,
	   "progression=s"=>\$progress,
	   "progression-id=s"=>\$progress_id,
	   "line-width=s"=>\$line_width,
	   "symbols=s"=>\@o_symbols,
	   "indicatives=s"=>\$annote_indicatives,
	   "position=s"=>\$position,
	   "pointsize-nl=s"=>\$pointsize_rel,
	   "ecart=s"=>\$ecart,
	   "ecart-marge=s"=>\$ecart_marge,
	   "ch-sign=s"=>\$chiffres_significatifs,
	   "verdict=s"=>\$verdict,
	   "verdict-question=s"=>\$verdict_question,
	   "verdict-question-cancelled=s"=>\$verdict_question_cancelled,
	   "fich-noms=s"=>\$fich_noms,
	   "noms-encodage=s"=>\$noms_encodage,
	   "csv-build-name=s"=>\$csv_build_name,
	   "font=s"=>\$font_name,
	   "rtl!"=>\$rtl,
	   "changes-only!"=>\$changes_only,
	   );

set_debug($debug);

print (("*"x60)."\n");
print "* WARNING: AMC-annote is now obsolete\n* Please move to AMC-annotate\n";
print (("*"x60)."\n");

for(split(/,/,join(',',@o_symbols))) {
    if(/^([01]-[01]):(none|circle|mark|box)(?:\/([\#a-z0-9]+))?$/) {
	$symboles{$1}={type=>$2,color=>$3};
    } else {
	die "Bad symbol syntax: $_";
    }
}

my $commandes=AMC::Exec::new("AMC-annote");
$commandes->signalise();

$cr_dir=$rep_projet."/cr" if(! $cr_dir);

if(! -d $cr_dir) {
    attention("No CR directory: $cr_dir");
    die "No CR directory: $cr_dir";
}

my $noms='';

if($fich_noms) {
    $noms=AMC::NamesFile::new($fich_noms,
			      "encodage"=>$noms_encodage,
			      "identifiant"=>$csv_build_name);

    debug "Keys in names file: ".join(", ",$noms->heads());
}

# ---

sub color_rgb {
    my ($s)=@_;
    my $col=Gtk2::Gdk::Color->parse($s);
    return($col->red/65535,$col->green/65535,$col->blue/65535);
}

my $avance=AMC::Gui::Avancement::new($progress,'id'=>$progress_id);

my $data=AMC::Data->new($data_dir);
my $capture=$data->module('capture');
my $scoring=$data->module('scoring');
my $assoc=$data->module('association');
my $layout=$data->module('layout');

$seuil=$scoring->variable_transaction('darkness_threshold');
$seuil_up=$scoring->variable_transaction('darkness_threshold_up');

#################################

sub milieu_cercle {
    my $zoneid=shift;
    return($capture->sql_row($capture->statement('zoneCenter'),
			     $zoneid,POSITION_BOX));
}

sub cercle_coors {
    my ($context,$zoneid,$color)=@_;
    my ($x,$y)=milieu_cercle($zoneid);
    my $t=sqrt($capture->zone_dist2($zoneid,$x,$y));
    $context->set_source_rgb(color_rgb($color));
    $context->new_path;
    $context->arc($x,$y,$t,0,360);
    $context->stroke;
}

sub croix_coors {
    my ($context,$zoneid,$color)=@_;
    $context->set_source_rgb(color_rgb($color));
    $context->new_path;
    for my $i (1,2) {
	$context->move_to($capture->zone_corner($zoneid,$i));
	$context->line_to($capture->zone_corner($zoneid,$i+2));
    }
    $context->stroke;
}

sub boite_coors {
    my ($context,$zoneid,$color)=@_;
    my @pts="";
    $context->set_source_rgb(color_rgb($color));
    $context->new_path;
    $context->move_to($capture->zone_corner($zoneid,1));
    for my $i (2..4) {
	$context->line_to($capture->zone_corner($zoneid,$i));
    }
    $context->close_path;
    $context->stroke;
}

my $delta=1;

$capture->begin_read_transaction('PAGE');

my $annotate_source_change=$capture->variable('annotate_source_change');

my @pages=@{$capture->dbh
	      ->selectall_arrayref($capture->statement('pages'),
				   {Slice => {}})};

$capture->end_transaction('PAGE');

$delta=1/(1+$#pages) if($#pages>=0);
$n_processed_pages=0;

my %ok_students=();

# a) first case: these numbers are given by --id-file option

if($id_file) {

  open(NUMS,$id_file);
  while(<NUMS>) {
    chomp;
    if(/^[0-9]+(:[0-9]+)?$/) {
      $ok_students{$_}=1;
    }
  }
  close(NUMS);

}

my $subst=AMC::Substitute::new('names'=>$noms,
			       'scoring'=>$scoring,
			       'assoc'=>$assoc,
			       'name'=>'',
			       'chsign'=>$chiffres_significatifs,
			       );

print "* Annotation\n";

 PAGE: for my $p (@pages) {
  my @spc=map { $p->{$_} } (qw/student page copy/);

  if($id_file && !$ok_students{studentids_string($spc[0],$spc[2])}) {
    next PAGE;
  }

  if($changes_only && $p->{'timestamp_annotate'}>$annotate_source_change) {
    my $f=$p->{'annotated'};
    if(-f "$cr_dir/corrections/jpg/$f") {
      print "Skipping page ".pageids_string(@spc). " (up to date)\n";
      debug "Skipping page ".pageids_string(@spc). " (up to date)";
      next PAGE;
    }
  }

  debug "Analyzing ".pageids_string(@spc);

  my $scan=$p->{'src'};

  debug "Scan file: $scan";

  if($rep_projet) {
    $scan=proj2abs({'%PROJET',$rep_projet,
		    '%PROJETS',$rep_projets,
		    '%HOME'=>$ENV{'HOME'},
		   },
		   $scan);
  }

  my $scan_f=$scan;

  $scan_f =~ s/\[[0-9]+\]$//;

  if(-f $scan_f) {

    # ONE SCAN FILE

    # read scan file (converting to PNG)
    debug "Reading $scan";
    open(CONV,"-|",magick_module("convert"),$scan,"png:-");
    my $surface = Cairo::ImageSurface
      ->create_from_png_stream(
			       sub {
				 my ($cb_data,$length)=@_;
				 read CONV,$data,$length;
				 return($data);
			       });
    close(CONV);

    my $context = Cairo::Context->create ($surface);
    $context->set_line_width($line_width);

    my $lay=Pango::Cairo::create_layout($context);

    # adjusts text size...
    my $l0=Pango::Cairo::create_layout($context);
    $l0->set_font_description (Pango::FontDescription->from_string ($font_name.' '.$test_font_size));
    $l0->set_text('H');
    my ($text_x,$text_y)=$l0->get_pixel_size();
    my $page_width=$surface->get_width;
    my $page_height=$surface->get_height;
    debug "Scan height: $page_height";
    my $target_y=$page_height/$pointsize_rel;
    debug "Target TY: $target_y";
    my $font_size=int($test_font_size*$target_y/$text_y);
    debug "Font size: $font_size";

    $lay->set_font_description (Pango::FontDescription->from_string ($font_name.' '.$font_size));
    $lay->set_text('H');
    ($text_x,$text_y)=$lay->get_pixel_size();

    my ($x_ppem, $y_ppem, $ascender, $descender, $width, $height, $max_advance);

    my $idf=pageids_string(@spc,'path'=>1);

    print "Annotating $scan (sheet $idf)...\n";

    my %question=();

    $capture->begin_read_transaction('xSTD');

    # print global mark and name on the page

    if($p->{'page'}==1 || $capture->zones_count(@spc,ZONE_NAME)) {
      my $text=$subst->substitute($verdict,@spc[0,2]);

      $lay->set_text($text);
      $context->set_source_rgb(color_rgb('red'));
      if($rtl) {
	my ($tx,$ty)=$lay->get_pixel_size;
	$context->move_to($page_width-$text_x-$tx,$text_y*.7);
      } else {
	$context->move_to($text_x,$text_y*.7);
      }
      Pango::Cairo::show_layout($context,$lay);
    }

    #########################################
    # signs around each box

    my $sth=$capture->statement('pageZones');
    $sth->execute(@spc,ZONE_BOX);
  BOX: while(my $b=$sth->fetchrow_hashref) {

      my $p_strategy=$scoring->unalias($p->{'student'});
      my $q=$b->{'id_a'};
      my $r=$b->{'id_b'};
      my $indic=$scoring->indicative($p_strategy,$q);

      next BOX if($indic && !$annote_indicatives);

      # to be ticked?
      my $bonne=$scoring->correct_answer($p_strategy,$q,$r);

      # ticked on this scan?
      my $cochee=$capture->ticked($p->{'student'},$p->{'copy'},
				  $q,$r,$seuil,$seuil_up);

      debug "Q=$q R=$r $bonne-$cochee";

      my $sy=$symboles{"$bonne-$cochee"};

      if($debug) {
	for my $i (1..4) {
	  debug(sprintf("Corner $i: (%.2f,%.2f)",
			$capture->zone_corner($b->{'zoneid'},$i)));
	}
      }

      if(!($layout->get_box_flags($p->{'student'},$q,$r,BOX_ROLE_ANSWER)
		  & BOX_FLAGS_DONTANNOTATE)) {
	if($sy->{type} eq 'circle') {
	  cercle_coors($context,$b->{'zoneid'},$sy->{color});
	} elsif($sy->{type} eq 'mark') {
	  croix_coors($context,$b->{'zoneid'},$sy->{color});
	} elsif($sy->{type} eq 'box') {
	  boite_coors($context,$b->{'zoneid'},$sy->{color});
	} elsif($sy->{type} eq 'none') {
	} else {
	  debug "Unknown symbol type ($bonne-$cochee): $sy->{type}";
	}
      }

      # pour avoir la moyenne des coors pour marquer la note de
      # la question

      $question{$q}={} if(!$question{$q});
      my @mil=milieu_cercle($b->{'zoneid'});
      push @{$question{$q}->{'x'}},$mil[0];
      push @{$question{$q}->{'y'}},$mil[1];
    }

    #########################################
    # write questions scores

    if($position ne 'none') {
    QUEST: for my $q (keys %question) {
	next QUEST if($scoring->indicative($p_strategy,$q));
	my $x;

	my $result=$scoring->question_result(@spc[0,2],$q);

	my $text;

	if($result->{'why'} =~ /c/i) {
	  $text=$verdict_question_cancelled;
	} else {
	  $text=$verdict_question;
	}

	$text =~ s/\%[S]/$result->{'score'}/g;
	$text =~ s/\%[M]/$result->{'max'}/g;
	$text =~ s/\%[W]/$result->{'why'}/g;
	$text =~ s/\%[s]/$subst->format_note($result->{'score'})/ge;
	$text =~ s/\%[m]/$subst->format_note($result->{'max'})/ge;

	my $te=eval($text);
	if($@) {
	  debug "Annotation: $text";
	  debug "Evaluation error $@";
	} else {
	  $text=$te;
	}

	$lay->set_text($text);
	my ($tx,$ty)=$lay->get_pixel_size;

	# mean of the y coordinate of all boxes
	my $y=sum(@{$question{$q}->{'y'}})/(1+$#{$question{$q}->{'y'}})-$ty/2;

	if($position eq 'marge') {
	  # scores written in one margin
	  if($rtl) {
	    $x=$page_width-$ecart_marge*$text_x-$tx;
	  } else {
	    $x=$ecart_marge*$text_x;
	  }
	} elsif($position eq 'case') {
	  # scores written at the left of the boxes
	  if($rtl) {
	    $x=max(@{$question{$q}->{'x'}}) + $ecart*$text_x ;
	  } else {
	    $x=min(@{$question{$q}->{'x'}}) - $ecart*$text_x - $tx;
	  }
	} elsif($position eq 'marges') {
	  # scores written in one of the margins (left or right),
	  # depending on the position of the boxes. This mode is often
	  # used when the subject is in a 2-column layout.

	  # fist extract the y coordinates of the boxes in the left column
	  my $left=1;
	  my @y=map { $question{$q}->{'y'}->[$_] } grep { $rtl xor ( $question{$q}->{'x'}->[$_] <= $page_width/2 ) } (0..$#{$question{$q}->{'x'}} );
	  if(!@y) {
	    # if empty, use the right column
	    $left=0;
	    @y=map { $question{$q}->{'y'}->[$_] } grep { $rtl xor ( $question{$q}->{'x'}->[$_] > $page_width/2 ) } (0..$#{$question{$q}->{'x'}} );
	  }

	  # set the x-position to the right margin
	  if($left xor $rtl) {
	    $x=$ecart_marge*$text_x;
	  } else {
	    $x=$page_width-$ecart_marge*$text_x-$tx;
	  }
	  # set the y-position to the mean of y coordinates of the
	  # boxes in the corresponding column
	  $y=sum(@y)/(1+$#y)-$ty/2;
	} else {
	  debug "Annotation : position invalide : $position";
	  $x=$ecart_marge*$text_x;
	}

	$context->set_source_rgb(color_rgb('red'));
	$context->move_to($x,$y);
	Pango::Cairo::show_layout($context,$lay);
      }
    }

    $capture->end_transaction('xSTD');

    # WRITE TO FILE

    $context->show_page;

    my $out_file="page-$idf.jpg";

    debug "Saving annotated scan to $cr_dir/corrections/jpg/$out_file";

    my @args=();

    if($qualite_jpg) {
      if($qualite_jpg =~ /^[0-9]+$/) {
	push @args,"-quality",$qualite_jpg;
      } else {
	debug "WARNING: non-numeric --qualite argument, ignored ($qualite_jpg)";
      }
    }

    if($taille_max) {
      if($taille_max =~ /^[0-9]*x?[0-9]*$/) {
	push @args,"-geometry",$taille_max;
      } else {
	debug "WARNING: malformed --taille-max argument, ignored ($taille_max)";
      }
    }

    open(CONV,"|-",magick_module("convert"),"png:-",
	 @args,
	 "$cr_dir/corrections/jpg/$out_file");
    $surface->write_to_png_stream(
				  sub {
				    my ($cb_data,$data)=@_;
				    print CONV $data;
				  });
    close(CONV);

    $capture->begin_transaction('ANNf');
    $capture->set_annotated(@spc,$out_file);
    $capture->end_transaction('ANNf');

    $n_processed_pages++;

  } else {
    print "No scan for page ".pageids_string(@spc).":$scan_f\n";
    debug "No scan: $scan_f";
  }

  $avance->progres($delta);
}

# stores state parameter to know all sheets have been annotated

$capture->begin_transaction('Aend');
$capture->variable('annotate_source_change',0);
$capture->end_transaction('Aend');

print "VAR: n_processed=$n_processed_pages\n";

$avance->fin();

