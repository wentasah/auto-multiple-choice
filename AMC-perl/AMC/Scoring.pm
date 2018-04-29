# -*- perl -*-
#
# Copyright (C) 2012-2015 Alexis Bienvenue <paamc@passoire.fr>
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

package AMC::Scoring;

use AMC::Basic;
use AMC::DataModule::scoring qw/:question/;
use AMC::ScoringEnv;

sub new {
    my (%o)=(@_);

    my $self={'onerror'=>'stderr',
	      'seuil'=>0,
	      'seuil_up'=>1.0,
	      'data'=>'',
	      'default_strategy'=>'',
	      'default_strategy_plain'=>'',
	      '_capture'=>'',
	      '_scoring'=>'',
	  };

    for my $k (keys %o) {
	$self->{$k}=$o{$k} if(defined($self->{$k}));
    }

    bless $self;

    if($self->{'data'}) {
      $self->{'_capture'}=$self->{'data'}->module('capture');
      $self->{'_scoring'}=$self->{'data'}->module('scoring');
    }

    $self->set_default_strategy();

    return($self);
}

sub error {
  my ($self,$t)=@_;
  debug $t;
  if($self->{'onerror'} =~ /\bstderr\b/i) {
    print STDERR "$t\n";
  }
  if($self->{'onerror'} =~ /\bdie\b/i) {
    die $t;
  }
}

###########################
# get data from databases #
###########################

sub ticked {
  my ($self,$student,$copy,$question,$answer)=@_;
  return($self->{'_capture'}
	 ->ticked($student,$copy,$question,$answer,
		  $self->{'seuil'},$self->{'seuil_up'}));
}

# tells if the answer given by the student is the correct one (ticked
# if it has to be, or not ticked if it has not to be).
sub answer_is_correct {
    my ($self,$student,$copy,$question,$answer)=@_;
    return($self->ticked($student,$copy,$question,$answer)
	   == $self->{'_scoring'}->correct_answer($student,$question,$answer));
}

#################
# score methods #
#################

# make a ScoringEnv object to hold questionnary-wide default strategy

sub set_default_strategy {
  my ($self,$strategy_string)=@_;
  $self->{'default_strategy_plain'}=
    AMC::ScoringEnv->new_from_directives_string($strategy_string);
  $self->{'default_strategy'}=AMC::ScoringEnv
    ->new_from_directives_string("e=0,b=1,m=0,v=0,d=0,auto=-1,"
				 .$strategy_string);
}

# prepares the ScoringEnv object that will be used for the current
# question, processing question-wide directives

sub prepare_question {
  my ($self,$question_data)=@_;

  $self->{env}=$self->{default_strategy}->clone;
  $self->{env}->process_directives($question_data->{default_strategy});
  $self->{env}->process_directives($question_data->{strategy});
}

# set variables values that depend on the data capture: number of
# ticked answers, ...

sub set_number_variables {
  my ($self,$question_data,$correct)=@_;

  my $vars={'NB'=>0,'NM'=>0,'NBC'=>0,'NMC'=>0};

  $self->{env}->set_type($correct);

  my $n_ok=0;
  my $n_ticked=0;
  my $ticked_adata='';
  my $n_all=0;
  my $n_plain=0;
  my $ticked_noneof='';

  for my $a (@{$question_data->{'answers'}}) {
    my $c=$a->{'correct'};
    my $t=($correct ? $c : $a->{'ticked'});

    debug("[ Q ".$a->{'question'}." A ".$a->{'answer'}." ] ticked $t (correct $c) TYPE=$correct\n");

    $n_ok+=($c == $t ? 1 : 0);
    $n_ticked+=$t;
    $ticked_adata=$a if($t);
    $n_all++;

    if($a->{'answer'}==0) {
      $ticked_noneof=$a->{'ticked'};
    } else {
      my $bn=($c ? 'B' : 'M');
      my $co=($t ? 'C' : '');
      $vars->{'N'.$bn}++;
      $vars->{'N'.$bn.$co}++ if($co);

      $n_plain++;
    }
  }

  $self->{env}->set_variables_from_hashref($vars,0);
  $self->{env}->set_variable("N",$n_plain,0);
  $self->{env}->set_variable("N_ALL",$n_all,0);
  $self->{env}->set_variable("N_RIGHT",$n_ok,0);
  $self->{env}->set_variable("N_TICKED",$n_ticked,0);
  $self->{env}->set_variable("NONEOF_TICKED",$ticked_noneof,0);
  $self->{env}->set_variable("IMULT",
			     $question_data->{'type'}==QUESTION_MULT ? 1 : 0);
  $self->{env}->set_variable("IS",
			     $question_data->{'type'}==QUESTION_SIMPLE ? 1 : 0);

  $self->{ticked_answer_data}=$ticked_adata;
}

# processes set.X directives from ticked answers

sub process_ticked_answers_setx {
  my ($self,$question_data,$correct)=@_;

  for my $a (@{$question_data->{'answers'}}) {
    my $c=$a->{'correct'};
    my $t=($correct ? $c : $a->{'ticked'});

    $self->{env}->variables_from_directives_string($a->{strategy},set=>1)
      if($t);
  }
}

#######################################################
# small methods to relay to embedded ScoringEnv object

sub variable {
  my ($self,$key)=@_;
  return($self->{env}->get_variable($key));
}

sub directive {
  my ($self,$key)=@_;
  return($self->{env}->get_directive($key));
}

sub set_directive {
  my ($self,$key,$value)=@_;
  return($self->{env}->set_directive($key,$value));
}

sub defined_directive {
  my ($self,$key)=@_;
  return($self->{env}->defined_directive($key));
}

#######################################################

# process some complex strategies for multiple questions (haut, mz)
# and rewrite them in terms of core scoring strategy directives.
sub expand_multiple_strategies {
  my ($self)=@_;

  if($self->directive("haut")) {
    $self->set_directive("d",$self->directive("haut").'-N');
    $self->set_directive("p",0) if(!$self->defined_directive("p"));
  } elsif($self->directive("mz")) {
    $self->set_directive("d",$self->directive("mz"));
    $self->set_directive("p",0) if(!$self->defined_directive("p"));
    $self->set_directive("b",0);
    $self->set_directive("m",-( abs($self->directive("mz"))
				+abs($self->directive("p"))+1 ));
  }
}

# the same for simple strategies
sub expand_simple_strategies {
  my ($self)=@_;
  if($self->defined_directive("mz")) {
    $self->set_directive("b",$self->directive("mz"));
    #cancels d directive value
    $self->set_directive("d",0);
  }
}

# detect syntax error for current question
sub syntax_error {
  my ($self,$correct)=@_;
  return('') if($correct);

  if($self->variable("IMULT")) {
    if($self->variable("N_TICKED") != 1
       && $self->variable("NONEOF_TICKED")) {
      # incompatible answers: the student has ticked one
      # plain answer AND the answer "none of the
      # above"...
      return("NONEOF & others");
    }
  } else {
    if($self->variable("N_TICKED")>1) {
      # incompatible answers: there are more than one
      # ticked boxes
      return("more than one ticked box");
    }
  }
  return('');
}

# tests if a formula has been given. If so, set the score to the value
# computed from this formula
sub use_formula {
  my ($self,$score,$why)=@_;
  if($self->defined_directive("formula")
    && $self->directive("formula") =~ /[^\s]/) {
    # a formula is given to compute the score directly
    debug "Using formula";
    $$score=$self->directive("formula");
    return(1);
  } else {
    return(0);
  }
}

# post-process for the score : forced value(force), shift(d), floor(p)
sub post_process {
  my ($self,$score,$why)=@_;
  if($$why !~ /^[VE]/i) {
    if($self->defined_directive("force")) {
      $$score=$self->directive("force");
      debug "FORCE: $$score";
      $$why = 'F';
    } else {

      # adds the 'd' shift value
      if($self->defined_directive("d")) {
	my $d=$self->directive("d");
	debug "Shift: $d";
	$$score+=$d;
      }

      # applies the 'p' floor value
      if($self->defined_directive("p")) {
	my $p=$self->directive("p");
	if($$score<$p) {
	  debug "Floor: $p";
	  $$score=$p;
	  $$why='P';
	}
      }
    }
  }
}

# adds answers scores for a multiple question
sub multiple_standard_score {
  my ($self,$answers,$correct,$score,$why)=@_;

  for my $a (@$answers) {
    # process only plain answers, not the "none of the above" answer
    if($a->{'answer'} != 0) {
      my $code=($correct || ($a->{'ticked'}==$a->{'correct'})
		? "b" : "m");
      my $answer_env=$self->{env}->clone;
      $answer_env->process_directives($a->{'strategy'});
      my $code_val=$answer_env->get_directive($code);
      debug("Delta(".$a->{'answer'}."|$code)=$code_val");
      $$score+=$code_val;

      # bforce|mforce directive for this answer: pass it to
      # the question force directive, so that the question score
      # will be set to this value.
      $self->set_directive("force",$answer_env->get_directive
			   ($code."force"))
	if($answer_env->defined_directive($code."force"));
    }
  }
}

sub simple_standard_score {
  my ($self,$score,$why)=@_;

  my $sb=$self->{ticked_answer_data}->{'strategy'};
  $sb =~ s/^\s*,+//;
  $sb =~ s/,+\s*$//;
  if($sb ne '') {
    # some value is given as a score for the
    # ticked answer
    $$score=$sb;
  } else {
    # take into account the scoring strategy for
    # the question: 'auto', or 'b'/'m'

    if($self->directive("auto")>-1) {
      debug "Scoring: auto";
      $$score=$self->{ticked_answer_data}->{'answer'}
	+$self->directive("auto")-1;
    } else {
      my $code=($self->variable("N_RIGHT")==$self->variable("N_ALL") ? "b" : "m");
      debug "Scoring: code $code";
      $$score=$self->directive($code);
    }
  }
}

# returns the score for a particular student-sheet/question, applying
# the given scoring strategy.
sub score_question {
  my ($self,$etu,$copy,$question_data,$correct)=@_;
  my $answers=$question_data->{'answers'};

  my $xx='';
  my $why='';

  $self->{env}->clear_errors;

  $self->set_number_variables($question_data,$correct);
  $self->process_ticked_answers_setx($question_data,$correct);
  $self->{env}->variables_from_directives(default=>1,set=>1,setx=>1,requires=>1);

  if($self->{env}->n_errors()) {
    $why="E";
    $xx=$self->directive("e");
    debug "Scoring errors: ".join(', ',$self->{env}->errors);
  } elsif($self->variable("N_TICKED")==0) {
    # no ticked boxes at all
    $xx=$self->directive("v");
    $why='V';
  } elsif(my $err=$self->syntax_error($correct)) {
    debug "Scoring syntax error: $err";
    $xx=$self->directive("e");
    $why='E';
  } elsif($self->variable("INVALID")) {
    debug "INVALID variable is set";
    $xx=$self->directive("e");
    $why='E';
  }

  if(!$why) {
    if($self->variable("IMULT")) {
      # MULTIPLE QUESTION

      $xx=0;

      $self->expand_multiple_strategies();

      if(!$self->use_formula(\$xx,\$why)) {
	$self->multiple_standard_score($answers,$correct,\$xx,\$why);
      }

      $self->post_process(\$xx,\$why);

    } else {
      # SIMPLE QUESTION

      $self->expand_simple_strategies();

      if(!$self->use_formula(\$xx,\$why)) {
	$self->simple_standard_score(\$xx,\$why);
      }
    }
  }

  debug "MARK: score=$xx ($why)";

  return($xx,$why);
}

# returns the score associated with correct answers for a question.
sub score_correct_question {
    my ($self,$etu,$question_data)=@_;
    debug "MARK: scoring correct answers";
    return($self->score_question($etu,0,$question_data,1));
}

# returns the maximum score for a question: MAX parameter value, or,
# if not present, the score_correct_question value.
sub score_max_question {
   my ($self,$etu,$question_data)=@_;
   debug "MARK: scoring correct answers for MAX";
   my ($x,$why)=($self->score_question($etu,0,$question_data,1));
   if($self->defined_directive("MAX")) {
     return($self->directive("MAX"),'M');
   } else {
     return($x,$why);
   }
}

# sums up the questions scores and return the global score and max
# score, handling global scoring parameters like SUF and allowempty.
#
# $scoring is the AMC::DataModule::scoring object to write to the
# database.
#
# @questions is an array of elements like
# {'score'=>xx,'raison'=>rr,'notemax'=>xxmax} for each question.

sub global_score {
  my ($self,$scoring,@questions)=@_;
  my $total=0;
  my $max=0;

  my $skip=$self->{'default_strategy_plain'}->get_directive("allowempty");
  if($skip>0) {
    @questions=sort { ($a->{'raison'} eq 'V' ? 0 : 1) <=>
			($b->{'raison'} eq 'V' ? 0 : 1)
		      || $b->{'notemax'} <=> $a->{'notemax'} } @questions;
    while($skip>0 && @questions
	  && $questions[0]->{'raison'} eq 'V') {
      $skip--;
      $scoring->cancel_score(@{$questions[0]->{'sc'}},
			     $questions[0]->{'question'})
	if($scoring);
      shift @questions;
    }
  }

  for my $q (@questions) {
    $total+=$q->{'score'};
    $max+=$q->{'notemax'};
  }

  $max=$self->{'default_strategy_plain'}->get_directive("SUF")
    if($self->{'default_strategy_plain'}->defined_directive("SUF"));

  if ($max<=0) {
    debug "Warning: Nonpositive value for MAX.";
    $max=1;
  }

  return($total,$max);
}

1;
