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
use File::Spec::Functions qw/tmpdir/;
use File::Temp qw/ tempfile tempdir /;
use File::Copy;

use Module::Load;
use Module::Load::Conditional qw/check_install/;

use AMC::Basic;
use AMC::Exec;
use AMC::Data;
use AMC::Gui::Avancement;

my $data_dir="";
my $sujet='';
my $print_cmd='cupsdoprint %f';
my $progress='';
my $progress_id='';
my $debug='';
my $fich_nums='';
my $methode='CUPS';
my $imprimante='';
my $options='number-up=1';
my $output_file='';
my $output_answers_file='';
my $split='';
my $answer_first='';
my $extract_with='pdftk';

GetOptions(
	   "data=s"=>\$data_dir,
	   "sujet=s"=>\$sujet,
	   "fich-numeros=s"=>\$fich_nums,
	   "progression=s"=>\$progress,
	   "progression-id=s"=>\$progress_id,
	   "print-command=s"=>\$print_cmd,
	   "methode=s"=>\$methode,
	   "imprimante=s"=>\$imprimante,
	   "output=s"=>\$output_file,
	   "split!"=>\$split,
	   "answer-first!"=>\$answer_first,
	   "options=s"=>\$options,
	   "debug=s"=>\$debug,
	   "extract-with=s"=>\$extract_with,
	   );

set_debug($debug);

my $commandes=AMC::Exec::new('AMC-imprime');
$commandes->signalise();

die "Needs data directory" if(!$data_dir);
die "Needs subject file" if(!$sujet);

die "Needs print command" if($methode =~ /^command/i && !$print_cmd);
die "Needs output file" if($methode =~ /^file/i && !$output_file);

my @available_extracts=(qw/pdftk gs/);

die "Invalid value for extract_with"
  if(!grep(/^$extract_with$/,@available_extracts));

@available_extracts=grep { commande_accessible($_) }
  @available_extracts;

die "No available extract engine" if(!@available_extracts);

if(!grep(/^$extract_with$/,@available_extracts)) {
  $extract_with=$available_extracts[0];
  debug("Switching to extract engine $extract_with");
}

my $avance=AMC::Gui::Avancement::new($progress,'id'=>$progress_id);

my $data=AMC::Data->new($data_dir);
my $layout=$data->module('layout');

my @es;

if($fich_nums) {
    open(NUMS,$fich_nums);
    while(<NUMS>) {
	push @es,$1 if(/^([0-9]+)$/);
    }
    close(NUMS);
} else {
  $layout->begin_read_transaction('prST');
  @es=$layout->query_list('students');
  $layout->end_transaction('prST');
}

my $cups;

if($methode =~ /^cups/i) {
  my $mod="AMC::Print::".lc($methode);
  load($mod);
  my $error=$mod->check_available();
  if($error) {
    die $error;
  }

  $cups=$mod->new();
  $cups->select_printer($imprimante);

  # record options (so that if given multiple times, the last value
  # is considered)
  my %opts=();
  for my $o (split(/\s*,+\s*/,$options)) {
    my $on=$o;
    my $ov=1;
    if($o =~ /([^=]+)=(.*)/) {
      $on=$1;
      $ov=$2;
    }
    $opts{$on}=$ov;
  }

  for my $o (keys %opts) {
    debug "Option : $o=$opts{$o}";
    $cups->set_option($o,$opts{$o});
  }
}

sub process_pages {
  my ($slices,$f_dest,$elong)=@_;

  my $tmp = File::Temp->new( DIR=>tmpdir(),UNLINK => 1, SUFFIX => '.pdf' );
  $fn=$tmp->filename();
  my $n_slices=1+$#{$slices};

  print "Student $elong : $n_slices slices to file $fn...\n";
  return() if($n_slices==0);

  if($extract_with eq 'gs') {
    die "Can't use <gs> to build multiple-slices PDF file. Please switch to <pdftk>."
      if($n_slices>1);
    $commandes->execute("gs","-dBATCH","-dNOPAUSE","-q","-sDEVICE=pdfwrite",
			"-sOutputFile=$fn",
			"-dFirstPage=".$slices->[0]->{first},
			"-dLastPage=".$slices->[0]->{last},
			$sujet);
  } elsif($extract_with eq 'pdftk') {
    $commandes->execute("pdftk",$sujet,"cat",
			(map { $_->{first}."-".$_->{last} } @$slices),
			"output",$fn);
  }

  if($methode =~ /^cups/i) {
    $cups->print_file($fn,"QCM : sheet $elong");
  } elsif($methode =~ /^file/i) {
    $f_dest.="-%e.pdf" if($f_dest !~ /[%]e/);
    $f_dest =~ s/[%]e/$elong/g;

    debug "Moving to $f_dest";
    move($fn,$f_dest);
  } elsif($methode =~ /^command/i) {
    my @c=map { s/[%]f/$fn/g; s/[%]e/$elong/g; $_; } split(/\s+/,$print_cmd);

    #print STDERR join(' ',@c)."\n";
    $commandes->execute(@c);
  } else {
    die "Unknown method: $methode";
  }

  close($tmp);
}

for my $e (@es) {
  my $elong=sprintf("%04d",$e);
  my ($debut,$fin,$debutA,$finA);
  $layout->begin_read_transaction('prSP');
  ($debut,$fin)=$layout->query_row('subjectpageForStudent',$e);
  ($debutA,$finA)=$layout->query_row('subjectpageForStudentA',$e)
    if($split||$answer_first);
  $layout->end_transaction('prSP');

  my @sl_all=();
  if($debut && $fin) {
    push @sl_all,{first=>$debut,last=>$fin};
  }

  my @sl_answer=();
  if($debutA && $finA) {
    push @sl_answer,{first=>$debutA,last=>$finA};
  }
  my @sl_preanswer=();
  if($debut && $debutA && $debut<$debutA) {
    push @sl_preanswer,{first=>$debut,last=>$debutA-1};
  }
  my @sl_postanswer=();
  if($fin && $finA && $fin>$finA) {
    push @sl_postanswer,{first=>$finA+1,last=>$fin};
  }

  if($split) {
    process_pages(\@sl_preanswer,$output_file,$elong."-0S");
    process_pages(\@sl_answer,$output_file,$elong."-1A");
    process_pages(\@sl_postanswer,$output_file,$elong."-2S");
  } else {
    if($answer_first) {
      process_pages([@sl_answer,@sl_postanswer,@sl_preanswer],
		    $output_file,$elong);
    } else {
      process_pages(\@sl_all,
		    $output_file,$elong);
    }
  }

  $avance->progres(1/(1+$#es));
}

$avance->fin();


