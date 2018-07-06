# -*- perl -*-
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

package AMC::DataModule::scoring;

# AMC scoring management.

# This module is used to store (in a SQLite database) and handle all
# data concerning data scoring (scoring strategies, scores and marks).

# TERMINOLOGY NOTE:
#
# 'student' refers to the student number that is written at the top of
# each page, in the format +<student>/<page>/<check>+
#
# If the questions are printed from AMC, and not photocopied, each
# physical student has a different student number on his sheet.
#
# If some questions are photocopied before beeing distributed to the
# students, several students can have the same student number. To make
# a difference between their completed answer sheets, a 'copy' number
# is added. 'copy' is 1 for the first student using a given student
# number sheet, then 2, and so on.
#
# Hence, a completed answer sheet is identified by the (student,copy)
# couple, and a printed sheet (and correct answers, scoring
# strategies) is identified by the student number only.
#
# 'question' is a number associated by LaTeX with every different
# question (based on the small text given as XXX in the
# \begin{question}{XXX} or \begin{questionmult}{XXX} commands).
#
# 'answer' is the answer number, starting from 1 for each question,
# before beeing shuffled.

# TABLES:
#
# title contains the titles (argument of the \begin{question} and
# \begin{questionmult} commands) of all the questions
#
# * question is the question number, as created by LaTeX and used in
#   the databases <layout>, <capture>.
#
# * title id the title of the question.
#
# default holds the default scoring strategies, as specified with the
# \scoringDefaultM and \scoringDefaultS commands in the LaTeX source
# file. This table contains 2 rows.
#
# * type is the question type, either QUESTION_SIMPLE or QUESTION_MULT
#   (these constants are defined in this module).
#
# * strategy is the default strategy string for this question type.
#
# main holds scoring strategies defined outside question/questionmult
# environments, either outside the onecopy/examcopy data (with
# student=-1), or inside (student=current student number).
#
# * student is the student number.
#
# * strategy is the strategy string given in the LaTeX file as an
#   argument of the \scoring command.
#
# question holds scoring strategies for questions.
#
# * student is the student number.
#
# * question is the question number.
#
# * type is the question type, either QUESTION_SIMPLE or
#   QUESTION_MULT
#
# * indicative is 1 if the question is indicative (the score is not
#   taken into account when computing the student mark).
#
# * strategy is the question scoring strategy string, given in the
#   LaTeX file inside the question/questionmult environment (but
#   before \correctchoice and \wrongchoice commands).
#
# answer holds scoring strategies concerning answers.
#
# * student is the student number.
#
# * question is the question number.
#
# * answer is the answer number, starting from 1 for each question.
#
# * correct is 1 if this choice is correct (use of \correctchoice).
#
# * strategy is the answer scoring strategy string, given in the LaTeX
#   file after the corresponding correctchoice/wrongchoice commands.
#
# score holds the questions scores for each student.
#
# * student is the student number.
#
# * copy is the copy number.
#
# * question is the question number.
#
# * score is the score resulting from applying the scoring strategy to
#   the student's answers.
#
# * why is a small string that is used to know when special cases has
#   been encountered:
#
#     E means syntax error (several boxes ticked for a simple
#     question, or " none of the above" AND another box ticked for a
#     multiple question).
#
#     V means that no box are ticked.
#
#     P means that a floor has been applied.
#
# * max is the question score associated to a copy where all answers
#   are correct (or 1 for indicative questions).
#
# mark holds global marks of the students.
#
# * student is the student number.
#
# * copy is the copy number.
#
# * total is the total score (sum of the questions scores).
#
# * max is the total score associated to a perfect copy.
#
# * mark is the student mark.
#
# code holds the codes entered by the students (see \AMCcode).
#
# * student is the student number.
#
# * copy is the copy number.
#
# * code is the code name.
#
# * value is the code value.

# VARIABLES:
#
# postcorrect_flag is 1 if the postcorrect mode is supposed to be used
# (correct answers are not indicated in the LaTeX source, but will be
# set from a teacher completed answer sheet).
#
# postcorrect_student
# postcorrect_copy    identify the sheet completed by the teacher.
#
# postcorrect_set_multiple (see postcorrect function)
#
# --- the following values are supplied in the Preferences window
#
# darkness_threshold and darkness_threshold_up are the parameters used
# for determining wether a box is ticked or not.
#
# mark_floor is the minimum mark to be given to a student.
#
# mark_max is the mark to be given to a perfect completed answer
# sheet.
#
# ceiling is true if AMC should put a ceiling on the students marks
# (this can be useful if the SUF global scoring strategy is used).
#
# rounding is the rounding type to be used for the marks.
#
# granularity is the granularity for the marks rounding.

use Exporter qw(import);

use constant {
  QUESTION_SIMPLE => 1,
  QUESTION_MULT => 2,
};

our @EXPORT_OK = qw(QUESTION_SIMPLE QUESTION_MULT);
our %EXPORT_TAGS = ( 'question' => [ qw/QUESTION_SIMPLE QUESTION_MULT/ ],
		   );

use AMC::Basic;
use AMC::DataModule;
use AMC::DataModule::capture ':zone';
use AMC::DataModule::layout ':flags';

use XML::Simple;

@ISA=("AMC::DataModule");

sub version_current {
  return(1);
}

sub version_upgrade {
    my ($self,$old_version)=@_;
    if($old_version==0) {

	# Upgrading from version 0 (empty database) to version 1 :
	# creates all the tables.

	debug "Creating scoring tables...";
	$self->sql_do("CREATE TABLE IF NOT EXISTS ".$self->table("title")
		      ." (question INTEGER, title TEXT)");
	$self->sql_do("CREATE TABLE IF NOT EXISTS ".$self->table("default")
		      ." (type INTEGER, strategy TEXT)");
	$self->sql_do("CREATE TABLE IF NOT EXISTS ".$self->table("main")
		      ." (student INTEGER, strategy TEXT)");
	$self->sql_do("CREATE TABLE IF NOT EXISTS ".$self->table("question")
		      ." (student INTEGER, question INTEGER, type INTEGER, indicative INTEGER DEFAULT 0, strategy TEXT, PRIMARY KEY (student,question))");
	$self->sql_do("CREATE TABLE IF NOT EXISTS ".$self->table("answer")
		      ." (student INTEGER, question INTEGER, answer INTEGER, correct INTEGER, strategy INTEGER, PRIMARY KEY (student,question,answer))");
	$self->sql_do("CREATE TABLE IF NOT EXISTS ".$self->table("alias")
		      ." (student INTEGER,see INTEGER)");

	$self->sql_do("CREATE TABLE IF NOT EXISTS ".$self->table("score")
		      ." (student INTEGER, copy INTEGER, question INTEGER, score REAL, why TEXT, max REAL, PRIMARY KEY (student,copy,question))");
	$self->sql_do("CREATE TABLE IF NOT EXISTS ".$self->table("mark")
		      ." (student INTEGER, copy INTEGER, total REAL, max REAL, mark REAL, PRIMARY KEY (student,copy))");
	$self->sql_do("CREATE TABLE IF NOT EXISTS ".$self->table("code")
		      ." (student INTEGER, copy INTEGER, code TEXT, value TEXT, PRIMARY KEY (student,copy,code))");

	$self->statement('NEWdefault')->execute(QUESTION_SIMPLE,"");
	$self->statement('NEWdefault')->execute(QUESTION_MULT,"");

	$self->populate_from_xml;

	return(1);
    }
    return('');
}

# populate_from_xml read the old format XML files (if any) and inserts
# them in the new SQLite database

sub populate_from_xml {
  my ($self)=@_;
  my $scoring_file=$self->{'data'}->directory;
  $scoring_file =~ s:/[^/]+/?$:/bareme.xml:;
  return if(!-f $scoring_file);

  $self->progression('begin',__"Fetching scoring data from old format XML files...");

  my $xml=XMLin($scoring_file,ForceArray => 1,KeyAttr=> [ 'id' ]);

  $self->main_strategy(-1,$xml->{'main'});
  my @s=(keys %{$xml->{'etudiant'}});
  my $frac=0;

  for my $student (@s) {
    my $s=$xml->{'etudiant'}->{$student};
    if($student eq 'defaut') {
      $self->default_strategy(QUESTION_SIMPLE,
			      $s->{'question'}->{'S'}->{'bareme'});
      $self->default_strategy(QUESTION_MULT,
			      $s->{'question'}->{'M'}->{'bareme'});
    } elsif($student =~ /^[0-9]+$/) {
      $self->main_strategy($student,$s->{'main'});
      for my $question (keys %{$s->{'question'}}) {
	if($question =~ /^[0-9]+$/) {
	  my $q=$s->{'question'}->{$question};
	  $self->question_title($question,$q->{'titre'});
	  $self->new_question
	    ($student,$question,
	     ($q->{'multiple'} ? QUESTION_MULT : QUESTION_SIMPLE),
	     ($q->{'indicative'} ? 1 : 0),$q->{'bareme'});

	  if($q->{'reponse'}) {
	    if(ref($q->{'reponse'}) eq 'HASH') {
	      for my $answer (keys %{$q->{'reponse'}}) {
		my $a=$q->{'reponse'}->{$answer};
		$self->new_answer($student,$question,$answer,
				  $a->{'bonne'},$a->{'bareme'});
	      }
	    } else {
	      debug "WARNING: reponse is not a HASHREF for S=$student Q=$question";
	    }
	  }
	} else {
	  debug "Unknown question id: <$question>";
	}
      }
    } else {
      debug "Unknown student id: <$student>";
    }
    $frac++;
    $self->progression('fraction',0.5*$frac/($#s+1));
  }

  $scoring_file=$self->{'data'}->directory;
  $scoring_file =~ s:/[^/]+/?$:/notes.xml:;
  return if(!-f $scoring_file);

  $frac=0;

  $xml=XMLin($scoring_file,ForceArray => 1,KeyAttr=> [ 'id' ]);

  $self->variable('darkness_threshold',$xml->{'seuil'});
  $self->variable('darkness_threshold_up',1.0);
  $self->variable('mark_floor',$xml->{'notemin'});
  $self->variable('mark_max',$xml->{'notemax'});
  $self->variable('ceiling',$xml->{'plafond'});
  $self->variable('rounding',$xml->{'arrondi'});
  $self->variable('granularity',$xml->{'grain'});

  @s=(keys %{$xml->{'copie'}});
  for my $student (@s) {
    my $s=$xml->{'copie'}->{$student};

    if($student =~ /^(moyenne|max)$/) {
      debug "Skipping student <$student>";
    } elsif($student =~ /^[0-9]+$/) {
      $self->statement('NEWMark')
	->execute($student,0,
		  map { $s->{'total'}->[0]->{$_} } (qw/total max note/));

      for my $title (keys %{$s->{'question'}}) {
	my $q=$s->{'question'}->{$title};
	my $question=$self->question_number($title);
	$self->statement('NEWScore')
	  ->execute($student,0,$question,
		    $q->{'note'},$q->{'max'},$q->{'raison'});
      }

      for my $code (keys %{$s->{'code'}}) {
	$self->statement('NEWCode')->execute($student,0,$code,
					     $s->{'code'}->{$code}->{'content'});
      }
    } else {
      debug "WARNING: Unknown student <$student> importing XML marks";
    }
    $frac++;
    $self->progression('fraction',0.5*(1+$frac/($#s+1)));
  }

  $self->progression('end');
}

# defines all the SQL statements that will be used

sub define_statements {
  my ($self)=@_;
  my $t_answer=$self->table("answer");
  my $t_default=$self->table("default");
  my $t_zone=$self->table("zone","capture");
  $self->{'statements'}=
    {
     'NEWdefault'=>{'sql'=>"INSERT INTO $t_default"
		    ." (type,strategy) VALUES (?,?)"},
     'getDefault'=>{'sql'=>"SELECT strategy FROM $t_default"
		    ." WHERE type=?"},
     'setDefault'=>{'sql'=>"UPDATE $t_default"
		    ." SET strategy=? WHERE type=?"},
     'noDefault'=>{'sql'=>"UPDATE $t_default"
		    ." SET strategy=''"},
     'NEWMain'=>{'sql'=>"INSERT INTO ".$self->table("main")
		  ." (student,strategy) VALUES (?,?)"},
     'getMain'=>{'sql'=>"SELECT strategy FROM ".$self->table("main")
		  ." WHERE student=?"},
     'getAllMain'=>{'sql'=>"SELECT strategy FROM ".$self->table("main")
		    ." WHERE student=? OR student=-1 OR student=0 ORDER BY student"},
     'setMain'=>{'sql'=>"UPDATE ".$self->table("main")
		  ." SET strategy=? WHERE student=?"},
     'NEWTitle'=>{'sql'=>"INSERT INTO ".$self->table("title")
		  ." (question,title) VALUES (?,?)"},
     'getTitle'=>{'sql'=>"SELECT title FROM ".$self->table("title")
		  ." WHERE question=?"},
     'getQNumber'=>{'sql'=>"SELECT question FROM ".$self->table("title")
		    ." WHERE title=?"},
     'setTitle'=>{'sql'=>"UPDATE ".$self->table("title")
		  ." SET title=? WHERE question=?"},
     'NEWQuestion'=>{'sql'=>"INSERT OR REPLACE INTO ".$self->table("question")
		     ." (student,question,type,indicative,strategy)"
		     ." VALUES (?,?,?,?,?)"},
     'NEWAnswer'=>{'sql'=>"INSERT OR REPLACE INTO ".$self->table("answer")
		   ." (student,question,answer,correct,strategy)"
		   ." VALUES (?,?,?,?,?)"},
     'setAnswerStrat'=>{'sql'=>"UPDATE ".$self->table("answer")
		       ." SET strategy=? WHERE student=? AND question=? AND answer=?"},
     'addAnswerStrat'=>{'sql'=>"UPDATE ".$self->table("answer")
			    ." SET strategy=strategy||? WHERE student=? AND question=? AND answer=?"},
     'NEWAlias'=>{'sql'=>"INSERT INTO ".$self->table("alias")
		  ." (student,see) VALUES (?,?)"},
     'getAlias'=>{'sql'=>"SELECT see FROM ".$self->table("alias")
		  ." WHERE student=?"},
     'postCorrectNew'=>{'sql'=>"CREATE TEMPORARY TABLE IF NOT EXISTS"
		       ." pc_temp (q INTEGER, a INTEGER, c REAL, PRIMARY KEY(q,a))"},
     'postCorrectClr'=>{'sql'=>"DELETE FROM pc_temp"},
     'postCorrectPop'=>{'sql'=>"INSERT INTO pc_temp (q,a,c) "
			." SELECT id_a,id_b,CASE"
			."   WHEN manual >= 0 THEN manual"
			."   WHEN total<=0 THEN -1"
			."   WHEN black >= ? * total AND black <= ? * total THEN 1"
			."   ELSE 0"
			." END"
			." FROM ".$self->table("zone","capture")
			." WHERE capture_zone.student=? AND capture_zone.copy=? AND capture_zone.type=?"},
     'postCorrectMul'=>{'sql'=>"UPDATE ".$self->table("question")
			." SET type=CASE"
			."   WHEN (SELECT sum(c) FROM pc_temp"
			."          WHERE q=question)>1"
			."   THEN ?"
			."   ELSE ?"
			." END"
		       },
     'postCorrectSet'=>{'sql'=>"UPDATE ".$self->table("answer")
			." SET correct=(SELECT c FROM pc_temp"
			."     WHERE q=question AND a=answer)"},
     'NEWScore'=>{'sql'=>"INSERT INTO ".$self->table("score")
		  ." (student,copy,question,score,max,why)"
		  ." VALUES (?,?,?,?,?,?)"},
     'cancelScore'=>{'sql'=>"UPDATE ".$self->table("score")
		     ." SET why=? WHERE student=? AND copy=? AND question=?"},
     'NEWMark'=>{'sql'=>"INSERT INTO ".$self->table("mark")
		  ." (student,copy,total,max,mark)"
		  ." VALUES (?,?,?,?,?)"},
     'NEWCode'=>{'sql'=>"INSERT INTO ".$self->table("code")
		  ." (student,copy,code,value)"
		  ." VALUES (?,?,?,?)"},

     'studentMark'=>{'sql'=>"SELECT * FROM ".$self->table("mark")
		     ." WHERE student=? AND copy=?"},
     'marks'=>{'sql'=>"SELECT * FROM ".$self->table("mark")},
     'marksCount'=>{'sql'=>"SELECT COUNT(*) FROM ".$self->table("mark")},
     'codes'=>{'sql'=>"SELECT code FROM ".$self->table("code")
	       ." GROUP BY code ORDER BY code"},
     'qStrat'=>{'sql'=>"SELECT strategy FROM ".$self->table("question")
		." WHERE student=? AND question=?"},
     'aStrat'=>{'sql'=>"SELECT strategy FROM ".$self->table("answer")
		." WHERE student=? AND question=? AND answer=?"},
     'answers'=>{'sql'=>"SELECT answer FROM ".$self->table("answer")
		 ." WHERE student=? AND question=?"
		." ORDER BY answer"},
     'studentQuestions'=>{'sql'=>"SELECT question FROM ".$self->table("question")
			  ." WHERE student=?"},
     'questions'=>{'sql'=>"SELECT question,title FROM ".$self->table("title")
		   ." ORDER BY title"},
     'qMaxMax'=>{'sql'=>"SELECT MAX(max) FROM ".$self->table("score")
		 ." WHERE question=?"},
     'correct'=>{'sql'=>"SELECT correct FROM ".$self->table("answer")
		 ." WHERE student=? AND question=? AND answer=?"},
     'correctChars'=>
     {sql=>"SELECT char FROM "
      ." (SELECT answer FROM ".$self->table("answer")
      ."  WHERE student=? AND question=? AND correct>0) AS correct,"
      ." (SELECT answer,char FROM ".$self->table("box","layout")
      ."  WHERE student=? AND question=? AND role=?) AS char"
      ." ON correct.answer=char.answer ORDER BY correct.answer"},
     'correctForAll'=>{'sql'=>"SELECT question,answer,"
		       ." MIN(correct) AS correct_min,"
		       ." MAX(correct) AS correct_max "
		       ." FROM ".$self->table("answer")
		       ." GROUP BY question,answer"},
     'multiple'=>{'sql'=>"SELECT type FROM ".$self->table("question")
		 ." WHERE student=? AND question=?"},
     'indicative'=>{'sql'=>"SELECT indicative FROM ".$self->table("question")
		    ." WHERE student=? AND question=?"},
     'numQIndic'=>{'sql'=>"SELECT COUNT(*) FROM"
		   ." ( SELECT question FROM ".$self->table("question")
		   ." WHERE indicatve=? GROUP BY question)"},
     'oneIndic'=>{'sql'=>"SELECT COUNT(*) FROM ".$self->table("question")
		  ." WHERE question=? AND indicative=?"},
     'getScore'=>{'sql'=>"SELECT score FROM ".$self->table("score")
		  ." WHERE student=? AND copy=? AND question=?"},
     'getScoreC'=>{'sql'=>"SELECT score,max,why FROM ".$self->table("score")
		   ." WHERE student=? AND copy=? AND question=?"},
     'getCode'=>{'sql'=>"SELECT value FROM ".$self->table("code")
		  ." WHERE student=? AND copy=? AND code=?"},
     'codesCounts'=>{'sql'=>"SELECT student,copy,value,COUNT(*) as nb"
		     ." FROM ".$self->table("code")
		     ." WHERE code=? GROUP BY value"},
     'preAssocCounts'=>
     {'sql'=>"SELECT m.student,m.copy,l.id AS value,COUNT(*) AS nb"
      ." FROM ".$self->table("mark")." AS m"
      ."      , ".$self->table("association","layout")." AS l"
      ." ON m.student=l.student AND m.copy=0"
      ." GROUP BY l.id"},

     'avgMark'=>{'sql'=>"SELECT AVG(mark) FROM ".$self->table("mark")
		 ." WHERE NOT (student=? AND copy=?)"},
     'avgQuest'=>{'sql'=>"SELECT CASE"
		  ." WHEN SUM(max)>0 THEN 100*SUM(score)/SUM(max)"
		  ." ELSE '-' END"
		  ." FROM ".$self->table("score")
		  ." WHERE question=?"
		  ." AND NOT (student=? AND copy=?)"},
     'studentAnswersBase'=>
     {'sql'=>"SELECT question,answer"
      .",correct,strategy"
      .",(SELECT CASE"
      ."         WHEN manual >= 0 THEN manual"
      ."         WHEN total<=0 THEN -1"
      ."         WHEN black >= ? * total AND black <= ? * total THEN 1"
      ."         ELSE 0"
      ."  END FROM $t_zone"
      ."  WHERE $t_zone.student=? AND $t_zone.copy=? AND $t_zone.type=?"
      ."        AND $t_zone.id_a=$t_answer.question AND $t_zone.id_b=$t_answer.answer"
      ." ) AS ticked"
      ." FROM ".$self->table("answer")
      ." WHERE student=?"},
     'studentQuestionsBase'=>
     {'sql'=>"SELECT q.question,q.type,q.indicative,q.strategy,t.title"
      .",d.strategy AS default_strategy"
      ." FROM ".$self->table("question"). " q"
      ." LEFT OUTER JOIN ".$self->table("default")." d"
      ." ON q.type=d.type"
      ." LEFT OUTER JOIN ".$self->table("title")." t"
      ." ON q.question=t.question"
      ." WHERE student=?"},
     'deleteScores'=>{'sql'=>"DELETE FROM ".$self->table('score')
		     ." WHERE student=? AND copy=?"},
     'deleteMarks'=>{'sql'=>"DELETE FROM ".$self->table('mark')
		    ." WHERE student=? AND copy=?"},
     'deleteCodes'=>{'sql'=>"DELETE FROM ".$self->table('code')
		    ." WHERE student=? AND copy=?"},
     'pagesWhy'=>{'sql'=>"SELECT s.student,s.copy,GROUP_CONCAT(s.why) as why,b.page FROM "
                  .$self->table('score')." s"
                  ." JOIN "
                  ." ( SELECT student,page,question FROM ".$self->table("box","layout")
                  ."   WHERE role=?"
                  ."   GROUP BY student,page,question )"
                  . " b"
                  ." ON s.student=b.student AND s.question=b.question"
                  ." GROUP BY s.student,b.page,s.copy"},
    };
}

# page_why() returns a list of items like
# {student=>1,copy=>0,page=>1,why=>',V,E,,'}
# that collects all 'why' attributes for questions that are on each page.

sub pages_why {
  my ($self)=@_;
  return(@{$self->dbh->selectall_arrayref($self->statement('pagesWhy'),
                                          {Slice=>{}},
                                          BOX_ROLE_ANSWER
                                         )});
}


# default_strategy($type) returns the default scoring strategy string
# to be used for questions with type $type (QUESTION_SIMPLE or
# QUESTION_MULT).
#
# default_strategy($type,$strategy) sets the default strategy string
# for questions with type $type.

sub default_strategy {
  my ($self,$type,$strategy)=@_;
  if(defined($strategy)) {
    $self->statement('setDefault')->execute($strategy,$type);
  } else {
    return($self->sql_single($self->statement('getDefault'),$type));
  }
}

# main_strategy($student) returns the main scoring strategy string for
# student $student. If $student<=0 (-1 in the database), this refers
# to the argument of the \scoring command used outside the
# onecopy/examcopy loop. If $student>0, this refers to the argument of
# the \scoring command used inside the onecopy/examcopy loop, but
# outside question/questionmult environments.
#
# main_strategy($student,$strategy) sets the main scoring strategy
# string.

sub main_strategy {
  my ($self,$student,$strategy)=@_;
  $student=-1 if($student<=0);
  if(defined($strategy)) {
    if(defined($self->main_strategy($student))) {
      $self->statement('setMain')->execute($strategy,$student);
    } else {
      $self->statement('NEWMain')->execute($student,$strategy);
    }
  } else {
    return($self->sql_single($self->statement('getMain'),$student));
  }
}

#add_main_strategy($student,$strategy) adds the strategy string at the
#end of the student's main strategy string.

sub add_main_strategy {
  my ($self,$student,$strategy)=@_;
  $student=-1 if($student<=0);
  my $old=$self->main_strategy($student);
  if(defined($old)) {
      $self->statement('setMain')->execute($old.','.$strategy,$student);
  } else {
      $self->statement('NEWMain')->execute($student,$strategy);
  }
}

# main_strategy_all($student) returns a concatenation of the the main
# strategies for student=-1, student=0 and student=$student.

sub main_strategy_all {
  my ($self,$student)=@_;
  return(join(',',$self->sql_list($self->statement('getAllMain'),$student)));
}

# new_question($student,$question,$type,$indicative,$strategy) adds a
# question in the database, giving its characteristics. If the
# question already exists, it is updated with no error.

sub new_question {
  my ($self,$student,$question,$type,$indicative,$strategy)=@_;
  $self->statement('NEWQuestion')->execute
    ($student,$question,$type,$indicative,$strategy);
}

# question_strategy($student,$question) returns the scoring strategy
# string for a particlar question: argument of the \scoring command
# used inside a question/questionmult environment, before the
# \correctchoice and \wrongchoice commands.

sub question_strategy {
  my ($self,$student,$question)=@_;
  return($self->sql_single($self->statement('qStrat'),$student,$question));
}

# new_answer($student,$question,$answer,$correct,$strategy) adds an
# answer in the database, giving its characteristics. If the answer
# already exists, it is updated with no error.

sub new_answer {
  my ($self,$student,$question,$answer,$correct,$strategy)=@_;
  $self->statement('NEWAnswer')->execute
    ($student,$question,$answer,$correct,$strategy);
}

# answer_strategy($student,$question,$answer) returns the scoring
# strategy string for a particular answer: argument of the \scoring
# command used after \correctchoice and \wrongchoice commands.

sub answer_strategy {
  my ($self,$student,$question,$answer)=@_;
  return($self->sql_single($self->statement('aStrat'),$student,$question,$answer));
}

# answers($student,$question) returns an ordered list of answers
# numbers for a particular question. Answer number 0, placed at the
# end, corresponds to the answer "None of the above", when present.

sub answers {
  my ($self,$student,$question)=@_;
  my @a=$self->sql_list($self->statement('answers'),$student,$question);
  if($a[0]==0) {
    shift @a;
    push @a,0;
  }
  return(@a);
}

# correct_answer($student,$question,$answer) returns 1 if the
# corresponding box has to be ticked (the answer is a correct one),
# and 0 if not.

sub correct_answer {
  my ($self,$student,$question,$answer)=@_;
  return($self->sql_single($self->statement('correct'),
			   $student,$question,$answer));
}

# correct_chars($student,$question) returns the list of the chars
# written inside (or beside) the boxes corresponding to correct
# answers for a particular question

sub correct_chars {
  my ($self,$student,$question)=@_;
  $self->{'data'}->require_module('layout');
  return($self->sql_list($self->statement('correctChars'),
                         $student,$question,
                         $student,$question,BOX_ROLE_ANSWER));
}

# Same as correct_chars, but paste the chars if they all exist, and
# return undef otherwise

sub correct_chars_pasted {
  my ($self,@args)=@_;
  my @c=$self->correct_chars(@args);
  if(grep { !defined($_) } @c) {
    return(undef);
  } else {
    return(join("",@c));
  }
}

# correct_for_all() returns a reference to an array like
#
# [{question=>1,answer=>1,correct_min=>0,correct_max=>0},
#  {question=>1,answer=>2,correct_min=>1,correct_max=>1},
# ]
#
# This gives, for each question/answer, the minumum and maximum of the
# <correct> column for all students. Usualy, minimum and maximum are
# equal because the answer is either correct for all students either
# not correct for all students, but one can also encounter
# correct_min=0 and correct_max=1, in situations where the answers are
# not the same for all students (for example for questions with random
# numerical values).

sub correct_for_all {
  my ($self,$question,$answer)=@_;
  return($self->dbh->selectall_arrayref($self->statement('correctForAll'),
					{Slice=>{}}));
}

# multiple($student,$question) returns 1 if the corresponding
# question is multiple (type=QUESTION_MULT), and 0 if not.

sub multiple {
  my ($self,$student,$question)=@_;
  return($self->sql_single($self->statement('multiple'),
			   $student,$question) == QUESTION_MULT);
}

# correct_answer($student,$question) returns 1 if the corresponding
# question is indicative (use of \QuestionIndicative), and 0 if not.

sub indicative {
  my ($self,$student,$question)=@_;
  return($self->sql_single($self->statement('indicative'),
			   $student,$question));
}

# one_indicative($question,$indic) returns the number of students for
# which the question has indicative=$indic. In fact, a single question
# SHOULD be indicative for all students, or for none...

sub one_indicative {
  my ($self,$question,$indic)=@_;
  $indic=1 if(!defined($indic));
  return($self->sql_single($self->statement('oneIndic'),$question,$indic));
}

# num_questions_indic($i) returns the number of questions that have
# indicative=$i ($i is 0 or 1).

sub num_questions_indic {
  my ($self,$indicative)=@_;
  return($self->sql_single($self->statement('numQIndic'),$indicative));
}

# question_title($question) returns a question title.
#
# question_title($question,$title) sets a question title.

sub question_title {
  my ($self,$question,$title)=@_;
  if(defined($title)) {
    if(defined($self->question_title($question))) {
      $self->statement('setTitle')->execute($title,$question);
    } else {
      $self->statement('NEWTitle')->execute($question,$title);
    }
  } else {
    return($self->sql_single($self->statement('getTitle'),$question));
  }
}

# question_number($title) returns the question number corresponding to
# the given title.

sub question_number {
  my ($self,$title)=@_;
  return($self->sql_single($self->statement('getQNumber'),$title));
}

# question_maxmax($question) returns the maximum of the max value for
# question $question accross all students sheets

sub question_maxmax {
  my ($self,$question)=@_;
  return($self->sql_single($self->statement('qMaxMax'),$question));
}

# clear_strategy clears all data concerning the scoring strategy of
# the exam.

sub clear_strategy {
  my ($self)=@_;
  $self->clear_variables;
  $self->statement('noDefault')->execute;
  for my $t (qw/title main question answer alias/) {
    $self->sql_do("DELETE FROM ".$self->table($t));
  }
}

# clear_score clears all data concerning the scores/marks of the
# students.

sub clear_score {
  my ($self)=@_;
  for my $t (qw/score mark code/) {
    $self->sql_do("DELETE FROM ".$self->table($t));
  }
}

# set_answer_strategy($student,$question,$answer,$strategy) sets the
# scoring strategy string associated to a particular answer.

sub set_answer_strategy {
  my ($self,$student,$question,$answer,$strategy)=@_;
  $self->statement('setAnswerStrat')->execute($strategy,$student,$question,$answer);
}

# add_answer_strategy($student,$question,$answer,$strategy) adds the
# scoring strategy string to a particular answer's one.

sub add_answer_strategy {
  my ($self,$student,$question,$answer,$strategy)=@_;
  $self->statement('addAnswerStrat')->execute(",".$strategy,
					      $student,$question,$answer);
}

# replicate($see,$student) tells that the scoring strategy used for
# student $see has to be also used for student $student. This can be
# used only when the questions/answers are not different from a sheet
# to another (contrary to the use of random numerical values for
# exemple).

sub replicate {
  my ($self,$see,$student)=@_;
  $self->statement('NEWAlias')->execute($student,$see);
}

# unalias($student) gives the student number where to find scoring
# strategy for student $student (following a replicate path if
# present -- see previous method).

sub unalias {
  my ($self,$student)=@_;
  my $s=$student;
  do {
    $student=$s;
    $s=$self->sql_single($self->statement('getAlias'),$student);
  } while(defined($s));
  return($student);
}

# postcorrect($student,$copy,$darkness_threshold,$darkness_threshold_up,$set_multiple)
# uses the ticked values from the copy ($student,$copy) (filled by a
# teacher) to determine which answers are correct for all sheets. This
# can be used only when the questions/answers are not different from a
# sheet to another (contrary to the use of random numerical values for
# exemple).
#
# If $set_multiple is true, postcorrect also sets the type of all
# questions for which 2 or more answers are ticked on the
# ($student,$copy) answer sheet to be QUESTION_MULT, ans the type of
# all other questions to QUESTION_SIMPLE.

sub postcorrect {
  my ($self,$student,$copy,
      $darkness_threshold,$darkness_threshold_up,$set_multiple)=@_;
  die "Missing parameters in postcorrect call"
    if(!defined($darkness_threshold_up));
  $self->{'data'}->require_module('capture');
  $self->statement('postCorrectNew')->execute();
  $self->statement('postCorrectClr')->execute();
  $self->statement('postCorrectPop')
    ->execute($darkness_threshold,$darkness_threshold_up,$student,$copy,ZONE_BOX);
  $self->statement('postCorrectMul')->execute(QUESTION_MULT,QUESTION_SIMPLE)
    if($set_multiple);
  $self->statement('postCorrectSet')->execute();
}

# new_score($student,$copy,$question,$score,$score_max,$why) adds a
# question score row.

sub new_score {
  my ($self,$student,$copy,$question,$score,$score_max,$why)=@_;
  $self->statement('NEWScore')
    ->execute($student,$copy,$question,$score,$score_max,$why);
}

# cancel_score($student,$copy,$question) cancels scoring (sets the
# score and maximum score to zero) for this question.

sub cancel_score {
  my ($self,$student,$copy,$question)=@_;
  $self->statement('cancelScore')
    ->execute('C',$student,$copy,$question);
}

# new_mark($student,$copy,$total,$max,$mark) adds a mark row.

sub new_mark {
  my ($self,$student,$copy,$total,$max,$mark)=@_;
  $self->statement('NEWMark')
    ->execute($student,$copy,$total,$max,$mark);
}

# new_code($student,$copy,$code,$value) adds a code row.

sub new_code {
  my ($self,$student,$copy,$code,$value)=@_;
  $self->statement('NEWCode')
    ->execute($student,$copy,$code,$value);
}

# student_questions($student) returns a list of the question numbers
# used in the sheets for student number $student.

sub student_questions {
  my ($self,$student)=@_;
  return($self->sql_list($self->statement('studentQuestions'),
			 $student));
}

# questions returns an array of pointers (one for each question) to
# hashes ('question'=><question_number>,'title'=>'question_title').

sub questions {
  my ($self)=@_;
  return(@{$self->dbh->selectall_arrayref($self->statement('questions'),{Slice=>{}})});
}

# average_mark returns the average mark from all students marks.

sub average_mark {
  my ($self)=@_;
  my @pc=$self->postcorrect_sc;
  return($self->sql_single($self->statement('avgMark'),@pc));
}

# codes returns a list of codes names.

sub codes {
  my ($self)=@_;
  return($self->sql_list($self->statement('codes')));
}

# marks returns a pointer to an array of pointers (one for each
# student) to hashes giving all information from the mark table.

sub marks {
  my ($self)=@_;
  return(@{$self->dbh->selectall_arrayref($self->statement('marks'),{Slice=>{}})});
}

# marks_count returns the nmber of marks computed.

sub marks_count {
  my ($self)=@_;
  return($self->sql_single($self->statement('marksCount')));
}

# question_score($student,$copy,$question) returns the score of a
# particular student for a particular question.

sub question_score {
  my ($self,$student,$copy,$question)=@_;
  return($self->sql_single($self->statement('getScore'),
			   $student,$copy,$question));
}

# question_result($student,$copy,$question) returns a pointer to a
# hash ('score'=>XXX,'max'=>XXX,'why'=>XXX) extracted from the
# question table.

sub question_result {
  my ($self,$student,$copy,$question)=@_;
  my $sth=$self->statement('getScoreC');
  $sth->execute($student,$copy,$question);
  return($sth->fetchrow_hashref);
}

# student_code($student,$copy,$code) returns the value of the code
# named $code entered by a particular student.

sub student_code {
  my ($self,$student,$copy,$code)=@_;
  return($self->sql_single($self->statement('getCode'),
			   $student,$copy,$code));
}

# postcorrect_sc returns (postcorrect_student,postcorrect_copy), or
# (0,0) if not in postcorrect mode.

sub postcorrect_sc {
  my ($self)=@_;
  return($self->variable('postcorrect_student') || 0,
	 $self->variable('postcorrect_copy') || 0);
}

# question_average($question) returns the average (as a percentage of
# the maximum score, from 0 to 100) of the scores for a particular
# question.

sub question_average {
  my ($self,$question)=@_;
  my @pc=$self->postcorrect_sc;
  return($self->sql_single($self->statement('avgQuest'),$question,
			   @pc));
}

# student_global($student,$copy) returns a pointer to a hash
# ('student'=>XXX,'copy'=>XXX,'total'=>XXX,'max'=>XXX,'mark'=>XXX)
# extracted from the mark table.

sub student_global {
  my ($self,$student,$copy)=@_;
  my $sth=$self->statement('studentMark');
  $sth->execute($student,$copy);
  return($x=$sth->fetchrow_hashref);
}

# student_scoring_base($student,$copy,$darkness_threshold,$darkness_threshold_up)
# returns useful data to compute questions scores for a particular
# student (identified by $student and $copy), as a reference to a hash
# grouping questions and answers. For exemple :
#
# 'main_strategy'=>"",
# 'questions'=>
# { 1 =>{ 'question'=>1,
#         'title' => 'questionID',
#         'type'=>1,
#         'indicative'=>0,
#         'strategy'=>'',
#         'answers'=>[ { 'question'=>1, 'answer'=>1,
#                        'correct'=>1, 'ticked'=>0, 'strategy'=>"b=2" },
#                      {'question'=>1, 'answer'=>2,
#                        'correct'=>0, 'ticked'=>0, 'strategy'=>"" },
#                    ],
#       },
#  ...
# }

sub student_scoring_base {
  my ($self,$student,$copy,$darkness_threshold,$darkness_threshold_up)=@_;
  die "Missing parameters in student_scoring_base call"
    if(!defined($darkness_threshold_up));
  $self->{'data'}->require_module('capture');
  my $student_strategy=$self->unalias($student);
  my $r={'student_alias'=>$student_strategy,
	 'questions'=>{},
	 'main_strategy'=>$self->main_strategy_all($student_strategy)};
  my @sid=($student);
  push @sid,$student_strategy if($student != $student_strategy);
  for my $s (@sid) {
    my $sth;
    $sth=$self->statement('studentQuestionsBase');
    $sth->execute($s);
    while(my $qa=$sth->fetchrow_hashref) {
      $r->{'questions'}->{$qa->{'question'}}=$qa;
    }
    $sth=$self->statement('studentAnswersBase');
    $sth->execute($darkness_threshold,$darkness_threshold_up,
		  $student,$copy,ZONE_BOX,$s);
    while(my $qa=$sth->fetchrow_hashref) {
      push @{$r->{'questions'}->{$qa->{'question'}}->{'answers'}},$qa;
    }
  }
  return($r);
}

# student_scoring_base_sorted(...) organizes the data from
# student_scoring_base to get sorted questions, relative to their IDs
# (lexicographic order)
#
# 'main_strategy'=>"",
# 'questions'=>
# [ { 'question'=>1,
#     'title' => 'questionID',
#     'type'=>1,
#     'indicative'=>0,
#     'strategy'=>'',
#     'answers'=>[ { 'question'=>1, 'answer'=>1,
#                    'correct'=>1, 'ticked'=>0, 'strategy'=>"b=2" },
#                  {'question'=>1, 'answer'=>2,
#                    'correct'=>0, 'ticked'=>0, 'strategy'=>"" },
#                ],
#   },
#  ...
# ]

sub student_scoring_base_sorted {
  my ($self,@args)=@_;

  my $ssb=$self->student_scoring_base(@args);
  my @n=sort { $ssb->{questions}->{$a}->{title}
                 cmp $ssb->{questions}->{$b}->{title} }
    (keys %{$ssb->{questions}});
  my $sorted_q=[map { $ssb->{questions}->{$_} } (@n)];
  $ssb->{questions}=$sorted_q;

  return($ssb);
}

# delete_scoring_data($student,$copy) deletes all scoring data
# relative to a particular answer sheet.

sub delete_scoring_data {
  my ($self,$student,$copy)=@_;
  for my $part (qw/Scores Marks Codes/) {
    $self->statement('delete'.$part)->execute($student,$copy);
  }
}

1;
