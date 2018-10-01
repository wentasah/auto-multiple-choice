#! /usr/bin/perl
#
# Copyright (C) 2008-2017 Alexis Bienvenue <paamc@passoire.fr>
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
use POSIX qw(ceil floor);
use AMC::Basic;
use AMC::Gui::Avancement;
use AMC::Scoring;
use AMC::Data;

use utf8;

my $darkness_threshold=0.1;
my $darkness_threshold_up=1.0;

my $floor_mark='';
my $null_mark=0;
my $perfect_mark=20;
my $ceiling=1;
my $granularity='0.5';
my $rounding='';
my $data_dir='';

my $postcorrect_student='';
my $postcorrect_copy='';
my $postcorrect_set_multiple='';

my $progres=1;
my $progres_id='';

my $debug='';

GetOptions("data=s"=>\$data_dir,
	   "seuil=s"=>\$darkness_threshold,
	   "seuil-up=s"=>\$darkness_threshold_up,
	   "debug=s"=>\$debug,
	   "grain=s"=>\$granularity,
	   "arrondi=s"=>\$rounding_scheme,
	   "notemax=s"=>\$perfect_mark,
	   "plafond!"=>\$ceiling,
	   "notemin=s"=>\$floor_mark,
	   "notenull=s"=>\$null_mark,
	   "postcorrect-student=s"=>\$postcorrect_student,
	   "postcorrect-copy=s"=>\$postcorrect_copy,
	   "postcorrect-set-multiple!"=>\$postcorrect_set_multiple,
	   "progression-id=s"=>\$progres_id,
	   "progression=s"=>\$progres,
	   );

set_debug($debug);

# fixes decimal separator ',' potential problem, replacing it with a
# dot.
for my $x (\$granularity,\$null_mark,\$floor_mark,\$perfect_mark) {
    $$x =~ s/,/./;
    $$x =~ s/\s+//;
}

# Implements the different possible rounding schemes.

sub rounding_inf {
    my $x=shift;
    return(floor($x));
}

sub rounding_central {
    my $x=shift;
    return(floor($x+0.5));
}

sub rounding_sup {
    my $x=shift;
    return(ceil($x));
}

my %rounding_function=('i'=>\&rounding_inf,'n'=>\&rounding_central,'s'=>\&rounding_sup);

# sets the rounding scheme to use to compute students marks, from
# parameter $rounding_scheme

if($rounding_scheme) {
    for my $k (keys %rounding_function) {
	if($rounding_scheme =~ /^$k/i) {
	    $rounding=$rounding_function{$k};
	}
    }
}

# Parameter $data_dir is needed!

if(! -d $data_dir) {
    attention("No DATA directory: $data_dir");
    die "No DATA directory: $data_dir";
}

# Parameter $granularity must be positive. If not, marks rounding is
# cancelled.

if($granularity<=0) {
    $granularity=1;
    $rounding='';
    $rounding_scheme='';
    debug("Nonpositive grain: rounding off");
}

# Uses an AMC::Gui::Avancement object to tell regularly the calling
# program how much work we have done so far.

my $avance=AMC::Gui::Avancement::new($progres,'id'=>$progres_id);

# Connects to the databases capture (to get the students sheets and to
# know which boxes have been ticked) and scoring (to write the
# computed scores!).

my $data=AMC::Data->new($data_dir);
my $capture=$data->module('capture');
my $scoring=$data->module('scoring');
my $layout=$data->module('layout');

# Uses an AMC::Scoring object to actually compute the questions
# scores.

my $score=AMC::Scoring::new('onerror'=>'die',
                            'data'=>$data,
                            'seuil'=>$darkness_threshold,
                            'seuil_up'=>$darkness_threshold_up,
                           );

$avance->progres(0.05);

# One only transaction for all the work:

$data->begin_transaction('MARK');

# get some useful build variables

my $code_digit_pattern=$layout->code_digit_pattern();

# Write the variables values in the database, so that they can be
# retrieved later, and clears all the scores that could have been
# already computed.

annotate_source_change($capture);
$scoring->clear_score;
$scoring->variable('darkness_threshold',$darkness_threshold);
$scoring->variable('darkness_threshold_up',$darkness_threshold_up);
$scoring->variable('mark_null',$null_mark);
$scoring->variable('mark_floor',$floor_mark);
$scoring->variable('mark_max',$perfect_mark);
$scoring->variable('ceiling',$ceiling);
$scoring->variable('rounding',$rounding_scheme);
$scoring->variable('granularity',$granularity);
$scoring->variable('postcorrect_student',$postcorrect_student);
$scoring->variable('postcorrect_copy',$postcorrect_copy);
$scoring->variable('postcorrect_set_multiple',$postcorrect_set_multiple);

# Gets the student/copy pairs that has been captured. Each element
# from the array @captured_studentcopy is an arrayref containing a different
# (student,copy) pair.

my @captured_studentcopy=$capture->student_copies();

# We already said that 0.05 of the work has been made, so the
# remaining ratio $delta per student/copy is:

my $delta=0.95;
$delta/=(1+$#captured_studentcopy) if($#captured_studentcopy>=0);

# If postcorrect mode is requested, sets the correct answers from the
# teacher's copy.

if($postcorrect_student) {
    $scoring->postcorrect($postcorrect_student,$postcorrect_copy,
			  $darkness_threshold,$darkness_threshold_up,
			  $postcorrect_set_multiple);
}

# Processes each student/copy in turn

for my $sc (@captured_studentcopy) {
  debug "MARK: --- SHEET ".studentids_string(@$sc);

  # The hash %codes collects the values of the AMCcodes.

  my %codes=();

  # Gets the scoring strategy for current student/copy, including
  # which answers are correct, from the scoring database.

  my $ssb=$scoring->student_scoring_base_sorted(@$sc,$darkness_threshold,$darkness_threshold_up);

  # transmits the main strategy (default strategy options values for
  # all questions) to the scoring engine.

  $score->set_default_strategy($ssb->{'main_strategy'});

  # The @question_scores collects scores for all questions

  my @question_scores=();

  # Process each question in turn

  for my $q (@{$ssb->{'questions'}}) {

    my $question=$q->{question};

    # $question is the question numerical ID, and
    # $q is the question scoring data (see AMC::DataModule::scoring)

    debug "MARK: QUESTION $question TITLE ".$q->{'title'};

    # Uses the scoring engine to score the question...
    #
    # $xx is the student score for this question,
    #
    # $why will give the reason for this score ("V" means no box
    # were ticked, for exemple).
    #
    # $max_score is the maximum score (score for perfect answers)

    $score->prepare_question($q);
    $score->set_type(0);
    ($xx,$why)=$score->score_question($sc->[0],$q,0);
    $score->set_type(1);
    ($max_score)=$score->score_max_question($sc->[0],$q);

    # If the title of the question is 'codename[N]' (with a numerical
    # N), then this question represents a digit from a AMCcode, so we
    # collect the value in the %codes hash.

    if ($q->{'title'} =~ /^(.*)$code_digit_pattern$/) {
      my $code_name=$1;
      my $code_digit=$2;
      my $chars=$capture->
        ticked_chars_pasted(@$sc,$question,$darkness_threshold,$darkness_threshold_up);
      $chars=$xx if(!defined($chars));
      debug "- code($code_name,$code_digit) = '$chars'";
      $codes{$code_name}->{$code_digit}=$chars;
    }

    if ($q->{'indicative'}) {
      # If the question is indicative, we don't collect the value in
      # the @question_scores array
      $max_score=1;
    } else {
      # Otherwise, we collect all scoring results to compute later the
      # overall aggregated score for the student.
      push @question_scores,{'score'=>$xx,
			     'raison'=>$why,
			     'notemax'=>$max_score,
			     'sc'=>[@$sc],
			     'question'=>$question,
			     };
    }

    # Write the scoring results in the scoring database.

    $scoring->new_score(@$sc,$question,$xx,$max_score,$why);
  }

  # Compute the final total score aggregating questions scores

  my ($total,$max_i)=$score->global_score($scoring,@question_scores);

  # Now apply rounding scheme

  my $x;

  if ($perfect_mark>0) {
    $x=($perfect_mark-$null_mark)/$granularity*$total/$max_i;
  } else {
    $x=$total/$granularity;
  }
  $x=&$rounding($x) if($rounding);
  $x*=$granularity;
  $x+=$null_mark;

  # Apply ceiling

  $x=$perfect_mark if($perfect_mark>0 && $ceiling && ($x-$perfect_mark)*($perfect_mark-$null_mark)>0);

  # Apply floor

  if ($floor_mark ne '' && $floor_mark !~ /[a-z]/i) {
    $x=$floor_mark
      if(($perfect_mark==0 && $x<$floor_mark) ||
	 ($x-$floor_mark)*($perfect_mark-$null_mark)<0);
  }

  # Writes the student's final mark in the scoring database

  $scoring->new_mark(@$sc,$total,$max_i,$x);

  # Build the AMCcodes values from their digits, and store them in the
  # scoring database

  for my $k (keys %codes) {
    my @i=(keys %{$codes{$k}});
    if ($#i >= 0) {
      my $v=join('',map { $codes{$k}->{$_} }
		 sort { $b <=> $a } (@i));
      $scoring->new_code(@$sc,$k,$v);
    }
  }

  # Tell the calling program that we have finished scoring a student

  $avance->progres($delta);
}

$data->end_transaction('MARK');

$avance->fin();
