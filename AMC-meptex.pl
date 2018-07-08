#! /usr/bin/perl
#
# Copyright (C) 2011-2017 Alexis Bienvenue <paamc@passoire.fr>
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
use Encode;

use AMC::Basic;
use AMC::Gui::Avancement;
use AMC::Data;

use AMC::DataModule::layout ':flags';

my $src;
my $data_dir;
my $dpi=300;

my $progress;
my $progress_id;
my $debug;

GetOptions("src=s"=>\$src,
	   "data=s"=>\$data_dir,
	   "progression-id=s"=>\$progress_id,
	   "progression=s"=>\$progress,
	   "debug=s"=>\$debug,
    );

die "No src file $src" if(! -f $src);
die "No data dir $data_dir" if(! -d $data_dir);

set_debug($debug);

my $avance=AMC::Gui::Avancement::new($progress,'id'=>$progress_id);

my $data=AMC::Data->new($data_dir);
my $layout=$data->module('layout');
my $capture=$data->module('capture');

my $timestamp=time();

# how much units in one inch ?
%u_in_one_inch=('in'=>1,
		'cm'=>2.54,
		'mm'=>25.4,
		'pt'=>72.27,
		'sp'=>65536*72.27,
    );

# association code_in_amc_file => BOX_ROLE_*
my %role=(
	  'case'=>BOX_ROLE_ANSWER,
	  'casequestion'=>BOX_ROLE_QUESTIONONLY,
	  'score'=>BOX_ROLE_SCORE,
	  'scorequestion'=>BOX_ROLE_SCOREQUESTION,
	 );

sub read_inches {
    my ($dim)=@_;
    if($dim =~ /^\s*([+-]?[0-9]*\.?[0-9]*)\s*([a-zA-Z]+)\s*$/) {
	if($u_in_one_inch{$2}) {
	    return($1 / $u_in_one_inch{$2});
	} else {
	    die "Unknown unity: $2 ($dim)";
	}
    } else {
	die "Unknown dim: $dim";
    }
}

sub ajoute {
    my ($ar,$val)=@_;
    if(@$ar) {
	$ar->[0]=$val if($ar->[0]>$val && $val);
	$ar->[1]=$val if($ar->[1]<$val && $val);
    } else {
	$ar->[0]=$val if($val);
	$ar->[1]=$val if($val);
    }
}

my @pages=();
my @flags=();
my @pre_assoc=();
my $cases;
my $page_number=0;
my %with_vars=();

sub add_flag {
  my ($x,$flag)=@_;
  if($x =~ /^([0-9]+),([0-9]+)$/) {
    my ($student,$question)=($1,$2);
    my $f;
    if(@flags) {
      my $lf=$flags[$#flags];
      if($lf->{'student'}==$student && $lf->{'question'}==$question) {
	$lf->{'flags'} |= $flag;
	return;
      }
    }
    push @flags,{'student'=>$student,'question'=>$question,'flags'=>$flag};
  } else {
    debug "ERROR: flag which question? <$x>";
  }
}

debug "Reading $src...";

open(SRC,$src) or die "Unable to open $src : $!";
while(<SRC>) {
    if(/\\page\{([^\}]+)\}\{([^\}]+)\}\{([^\}]+)\}/) {
	my $id=$1;
	my $dx=$2;
	my $dy=$3;
	$page_number++;
	$cases={};
	push @pages,{-id=>$id,-p=>$page_number,
		     -dim_x=>read_inches($dx),-dim_y=>read_inches($dy),
		     -cases=>$cases};
    }
    if(/\\tracepos\{(.+?)\}\{([+-]?[0-9.]+[a-z]*)\}\{([+-]?[0-9.]+[a-z]*)\}(?:\{([a-zA-Z]*)\})?$/) {
	my $i=$1;
	my $x=read_inches($2);
	my $y=read_inches($3);
	my $shape=$4;
	$i =~ s/^[0-9]+\/[0-9]+://;
	$cases->{$i}={'bx'=>[],'by'=>[],'flags'=>0,'shape'=>''}
	  if(!$cases->{$i});
	ajoute($cases->{$i}->{'bx'},$x);
	ajoute($cases->{$i}->{'by'},$y);
	if($cases->{$i}->{'shape'} &&
	   $cases->{$i}->{'shape'} ne $shape) {
	  debug "WARNING: different shapes for a single box ($i)";
	} else {
	  $cases->{$i}->{'shape'}=$shape;
	  if($shape eq 'oval') {
	    $cases->{$i}->{'flags'} |= BOX_FLAGS_SHAPE_OVAL;
	  }
	}
    }
    if(/\\boxchar\{(.+)\}\{(.*)\}$/) {
      my $i=$1;
      my $char=$2;
      $i =~ s/^[0-9]+\/[0-9]+://;
      $cases->{$i}={'bx'=>[],'by'=>[],'flags'=>0,'shape'=>''}
        if(!$cases->{$i});
      $cases->{$i}->{char}=$char;
    }
    if(/\\dontscan\{(.*)\}/) {
      add_flag($1,BOX_FLAGS_DONTSCAN);
    }
    if(/\\dontannotate\{(.*)\}/) {
      add_flag($1,BOX_FLAGS_DONTANNOTATE);
    }
    if(/\\association\{([0-9]+)\}\{(.*)\}/) {
      push @pre_assoc,[$1,$2];
    }
    if(/\\with\{(.+?)=(.*)\}/) {
      $build_vars{$1}=$2;
    }
}
close(SRC);

sub bbox {
    my ($c)=@_;
    return($c->{'bx'}->[0],$c->{'bx'}->[1],
	   $c->{'by'}->[1],$c->{'by'}->[0]);
}

sub center {
    my ($c,$xy)=@_;
    return(($c->{$xy}->[0]+$c->{$xy}->[1])/2);
}

my $delta=(@pages ? 1/(1+$#pages) : 0);

$layout->begin_transaction('MeTe');
$layout->clear_mep;
$layout->clear_variables('build:%');
for my $k (keys %build_vars) {
  $layout->variable("build:$k",$build_vars{$k});
}
annotate_source_change($capture);

debug "Pre-association...";

for my $pa (@pre_assoc) {
  $layout->new_association(@$pa);
}

debug "Writing to database...";

PAGE: for my $p (@pages) {

    my $diametre_marque=0;
    my $dmn=0;

  KEY: for my $k (keys %{$p->{-cases}}) {
      for(0..1) {
	  $p->{-cases}->{$k}->{'bx'}->[$_] *= $dpi;
	  $p->{-cases}->{$k}->{'by'}->[$_] = $dpi*($p->{-dim_y} - $p->{-cases}->{$k}->{'by'}->[$_]);
      }

      if($k =~ /position[HB][GD]$/) {
	  for my $dir ('bx','by') {
	      $diametre_marque+=abs($p->{-cases}->{$k}->{$dir}->[1]-$p->{-cases}->{$k}->{$dir}->[0]);
	      $dmn++;
	  }
      }
  }

    $diametre_marque/=$dmn if($dmn);

    my @epc=get_epc($p->{-id});
    my @ep=@epc[0,1];

    $layout->statement('NEWLayout')->execute(
	@epc,
	$p->{-p},
	$dpi,$dpi*$p->{-dim_x},$dpi*$p->{-dim_y},
	$diametre_marque,
	$layout->source_id($src,$timestamp));

    next PAGE if(!$dmn);

    for my $pos ('HG','HD','BD','BG') {
	die "Needs position$pos from page $p->{-id}" if(!$p->{-cases}->{'position'.$pos});
    }

    my $c=$p->{-cases};

    my $nc=0;
    for my $pos ('HG','HD','BD','BG') {
	$nc++;
	$layout->statement('NEWMark')->execute(
	    @ep,$nc,
	    center($c->{'position'.$pos},'bx'),
	    center($c->{'position'.$pos},'by')
	    );
    }
    if($c->{'nom'}) {
	$layout->statement('NEWNameField')->execute(
	    @ep,bbox($c->{'nom'}));
    }
    for my $k (sort { $a cmp $b } (keys %$c)) {
      if($k=~/chiffre:([0-9]+),([0-9]+)$/) {
	$layout->statement('NEWDigit')
	  ->execute(@ep,$1,$2,bbox($c->{$k}));
      }
      if($k=~/(case|casequestion|score|scorequestion):(.*):([0-9]+),(-?[0-9]+)$/) {
	my ($type,$name,$q,$a)=($1,$2,$3,$4);
        debug "- Box $k";
	$layout->question_name($q,$name) if($name ne '');
	$layout->statement('NEWBox')
	  ->execute(@ep,$role{$type},
		    $q,$a,bbox($c->{$k}),$c->{$k}->{'flags'},$c->{$k}->{char});
      }
    }

    $avance->progres($delta);
}

debug "Flagging questions...";

for my $f (@flags) {
  $layout->add_question_flag($f->{'student'},$f->{'question'},BOX_ROLE_ANSWER,$f->{'flags'});
}

debug "Ending transaction...";

$layout->end_transaction('MeTe');

$avance->fin();
