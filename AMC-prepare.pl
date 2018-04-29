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

use encoding "utf-8";

use File::Copy;
use File::Spec::Functions qw/splitpath catpath splitdir catdir catfile rel2abs tmpdir/;
use File::Temp qw/ tempfile tempdir /;

use Module::Load;

use Getopt::Long;

use AMC::Basic;
use AMC::Gui::Avancement;
use AMC::Data;
use AMC::DataModule::scoring ':question';

use_gettext;
use_amc_plugins();

my $cmd_pid='';
my @output_files=();

sub catch_signal {
    my $signame = shift;
    debug "*** AMC-prepare : signal $signame, transfered to $cmd_pid...";
    kill 9,$cmd_pid if($cmd_pid);
    if(@output_files) {
      debug "Removing files that are beeing built: ".join(" ",@output_files);
      unlink(@output_files);
    }
    die "Killed";
}

$SIG{INT} = \&catch_signal;

# PARAMETERS

my $mode="mbs";
my $data_dir="";
my $calage='';

my $latex_engine='latex';
my @engine_args=();
my $engine_topdf='';
my $prefix='';
my $filter='';
my $filtered_source='';

my $debug='';
my $latex_stdout='';

my $n_procs=0;
my $number_of_copies=0;

my $progress=1;
my $progress_id='';

my $out_calage='';
my $out_sujet='';
my $out_corrige='';
my $out_corrige_indiv='';
my $out_catalog='';

my $jobname="amc-compiled";

my $f_tex;

@ARGV=unpack_args(@ARGV);

GetOptions("mode=s"=>\$mode,
	   "with=s"=>\$latex_engine,
	   "data=s"=>\$data_dir,
	   "calage=s"=>\$calage,
	   "out-calage=s"=>\$out_calage,
	   "out-sujet=s"=>\$out_sujet,
	   "out-corrige=s"=>\$out_corrige,
	   "out-corrige-indiv=s"=>\$out_corrige_indiv,
	   "out-catalog=s"=>\$out_catalog,
	   "convert-opts=s"=>\$convert_opts,
	   "debug=s"=>\$debug,
	   "latex-stdout!"=>\$latex_stdout,
	   "progression=s"=>\$progress,
	   "progression-id=s"=>\$progress_id,
	   "prefix=s"=>\$prefix,
	   "n-procs=s"=>\$n_procs,
	   "n-copies=s"=>\$number_of_copies,
	   "filter=s"=>\$filter,
	   "filtered-source=s"=>\$filtered_source,
	   );

set_debug($debug);

debug("AMC-prepare / DEBUG") if($debug);

# Split the LaTeX engine string, to get
#
# 1) the engine command $latex_engine (eg. pdflatex)
#
# 2) the engine arguments @engine_args to be passed to this command
#
# 3) the command used to make a PDF file from the engine output
# (eg. dvipdfmx)
#
# The LaTeX engine string is on the form
#   <latex_engine>[+<pdf_engine>] <engine_args>
#
# For exemple:
#
# pdflatex
# latex+dvipdfmx
# platex+dvipdfmx
# lualatex --shell-escape
# latex+dvipdfmx --shell-escape

sub split_latex_engine {
  my ($engine)=@_;

  $latex_engine=$engine if($engine);

  if($latex_engine =~ /([^ ]+)\s+(.*)/) {
    $latex_engine=$1;
    @engine_args=split(/ +/,$2);
  }

  if($latex_engine =~ /(.*)\+(.*)/) {
    $latex_engine=$1;
    $engine_topdf=$2;
  }
}

split_latex_engine();

sub set_filtered_source {
  my ($filtered_source)=@_;

  # change directory where the $filtered_source is, and set $f_base to
  # the $filtered_source without path and without extension

  ($v,$d,$f_tex)=splitpath($filtered_source);
  chdir(catpath($v,$d,""));
  $f_base=$f_tex;
  $f_base =~ s/\.tex$//i;

  # AMC usualy sets $prefix to "DOC-", but if $prefix is empty, uses
  # the base name

  $prefix=$f_base."-" if(!$prefix);
}

# Uses an AMC::Gui::Avancement object to tell regularly the calling
# program how much work we have done so far.

my $avance=AMC::Gui::Avancement::new($progress,'id'=>$progress_id);

# Get and test the source file

my $source=$ARGV[0];

die "Nonexistent source file: $source" if(! -f $source);

# $base is the source file base name (with the path but without
# extension).

my $base=$source;
$base =~ s/\.[a-zA-Z0-9]{1,4}$//gi;

# $filtered_source is the LaTeX fil made from the source file by the
# filter (for exemple, LaTeX or AMC-TXT).

$filtered_source=$base.'_filtered.tex' if(!$filtered_source);

# default $data_dir value (hardly ever used):

$data_dir="$base-data" if(!$data_dir);

# make these filenames global

for(\$data_dir,\$source,\$filtered_source) {
    $$_=rel2abs($$_);
}

set_filtered_source($filtered_source);

# These variables are used to track errors from LaTeX compiling

my $a_errors; # the number of errors
my @errors_msg=(); # errors messages (questions specifications problems)
my @latex_errors=(); # LaTeX compilation errors

sub flush_errors {
  debug(@errors_msg);
  print join('',@errors_msg);
  @errors_msg=();
}


# %info_vars collects the variables values that LaTeX wants to give us

my %info_vars=();

# check_question checks that, if the question question is a simple
# one, the number of correct answers is exactly one.

sub check_question {
    my ($q,$t)=@_;

    # if postcorrection is used, this check cannot be made as we will
    # only know which answers are correct after having captured the
    # teacher's copy.
    return() if($info_vars{'postcorrect'});

    if($q) {
      # For multiple questions, no problem. $q->{partial} means that
      # all the question answers have not yet been parsed (this can
      # happen when using AMCnumericChoices or AMCOpen, because the
      # answers are only given in the separate answer sheet).
	if(!($q->{'mult'} || $q->{'partial'})) {
	    my $n_correct=0;
	    my $n_total=0;
	    for my $i (grep { /^R/ } (keys %$q)) {
		$n_total++;
		$n_correct++ if($q->{$i});
	    }
	    if($n_correct!=1 && !$q->{'indicative'}) {
		$a_errors++;
		push @errors_msg,"ERR: "
		    .sprintf(__("%d/%d good answers not coherent for a simple question")." [%s]\n",$n_correct,$n_total,$t);
	    }
	}
    }
}

# analyse_amclog checks common errors in LaTeX about questions:
#
# * same question ID used multiple times for the same paper, or same
# answer ID used multiple times for the same question
#
# * simple questions with number of good answers != 1
#
# * answer given outside a question
#
# These errors can be detected parsing the *.amc log file produced by
# LaTeX compilation, through AUTOQCM[...] messages.

sub analyse_amclog {
  my ($amclog_file)=@_;

  my %analyse_data=();
  my %titres=();
  @errors_msg=();

  debug("Check AMC log : $amclog_file");

  open(AMCLOG,$amclog_file) or die "Unable to open $amclog_file: $!";
  while (<AMCLOG>) {

    # AUTOQCM[Q=N] tells that we begin with question number N

    if (/AUTOQCM\[Q=([0-9]+)\]/) {

      # first check that the previous question is ok:
      check_question($analyse_data{'q'},$analyse_data{'etu'}.":".$analyse_data{'titre'});

      # then clear current question data:
      $analyse_data{'q'}={};

      # if this question has already be seen for current student...
      if ($analyse_data{'qs'}->{$1}) {

	if ($analyse_data{'qs'}->{$1}->{'partial'}) {
	  # if the question was partial (answers was not given in the
	  # question, but are now given in the answer sheet), it's
	  # ok. Simply get back the data already processed, and clear
	  # 'partial' and 'closed' flags:

	  $analyse_data{'q'}=$analyse_data{'qs'}->{$1};
	  for my $flag (qw/partial closed/) {
	    delete($analyse_data{'q'}->{$flag});
	  }
	} else {
	  # if the question was NOT partial, this is an error!

	  $a_errors++;
	  push @errors_msg,"ERR: "
	    .sprintf(__("question ID used several times for the same paper: \"%s\"")." [%s]\n",$titres{$1},$analyse_data{'etu'});
	}
      }

      # register question data
      $analyse_data{'titre'}=$titres{$1};
      $analyse_data{'qs'}->{$1}=$analyse_data{'q'};
    }

    # AUTOQCM[QPART] tells that we end with a question without having
    # given all the answers

    if (/AUTOQCM\[QPART\]/) {
      $analyse_data{'q'}->{'partial'}=1;
    }

    # AUTOQCM[FQ] tells that we have finished with the current question

    if (/AUTOQCM\[FQ\]/) {
      $analyse_data{'q'}->{'closed'}=1;
    }

    # AUTOQCM[ETU=N] tells that we begin with student number N.

    if (/AUTOQCM\[ETU=([0-9]+)\]/) {
      # first check the last question from preceding student is ok:

      check_question($analyse_data{'q'},$analyse_data{'etu'}.":".$analyse_data{'titre'});

      # then clear all %analyse_data to begin with this student:

      %analyse_data=('etu'=>$1,'qs'=>{});
    }

    # AUTOACM[NUM=N=ID] tells that question number N (internal
    # question number, not the question number shown on the sheet)
    # refers to ID (question name, string given as an argument to
    # question environment)

    if (/AUTOQCM\[NUM=([0-9]+)=(.+)\]/) {
      # stores this association (two-way)

      $titres{$1}=$2;
      $analyse_data{'titres'}->{$2}=1;
    }

    # AUTOQCM[MULT] tells that current question is a multiple question

    if (/AUTOQCM\[MULT\]/) {
      $analyse_data{'q'}->{'mult'}=1;
    }

    # AUTOQCM[INDIC] tells that current question is an indicative
    # question

    if (/AUTOQCM\[INDIC\]/) {
      $analyse_data{'q'}->{'indicative'}=1;
    }

    # AUTOQCM[REP=N:S] tells that answer number N is S (S can be 'B'
    # for 'correct' or 'M' for wrong)

    if (/AUTOQCM\[REP=([0-9]+):([BM])\]/) {
      my $rep="R".$1;

      if ($analyse_data{'q'}->{'closed'}) {
	# If current question is already closed, this is an error!

	$a_errors++;
	push @errors_msg,"ERR: "
	  .sprintf(__("An answer appears to be given outside a question environment, after question \"%s\"")." [%s]\n",
		   $analyse_data{'titre'},$analyse_data{'etu'});
      }

      if (defined($analyse_data{'q'}->{$rep})) {
	# if we already saw an answer with the same N, this is an error!

	$a_errors++;
	push @errors_msg,"ERR: "
	  .sprintf(__("Answer number ID used several times for the same question: %s")." [%s]\n",$1,$analyse_data{'titre'});
      }

      # stores the answer's status
      $analyse_data{'q'}->{$rep}=($2 eq 'B' ? 1 : 0);
    }

    # AUTOQCM[VAR:N=V] tells that variable named N has value V

    if (/AUTOQCM\[VAR:([0-9a-zA-Z.-]+)=([^\]]+)\]/) {
      $info_vars{$1}=$2;
    }

  }
  close(AMCLOG);

  # check that the last question from the last student is ok:

  check_question($analyse_data{'q'},$analyse_data{'etu'}.":".$analyse_data{'titre'});

  # Send error messages to the calling program through STDOUT

  flush_errors();

  debug("AMC log $amclog_file : $a_errors errors.");
}

# execute(%oo) launches the LaTeX engine with the right arguments, call it
# again if needed (for exemple when a second run is necessary to get
# references right), and then produces a PDF file from LaTeX output.
#
# $oo{command_opts} should be the options to be passed to latex_cmd, to
# build the LaTeX command to run, with all necessary arguments

my $filter_engine;

sub execute {
    my %oo=(@_);
    my $errs=0;

    prepare_filter();

    # gives the processing command to the filter
    $oo{command}=[latex_cmd(@{$oo{command_opts}})];
    $ENV{AMC_CMD}=join(' ',@{$oo{command}});

    if($filter) {
      if(!$filter_engine->get_filter_result('done')
	 || $filter_engine->get_filter_result('jobspecific')) {
	$errs=do_filter();
	$filter_engine->set_filter_result('done',1) if(!$errs);
      }
    }

    # first removes previous run's outputs

    for my $ext (qw/pdf dvi ps/) {
	if(-f "$jobname.$ext") {
	    debug "Removing old $ext";
	    unlink("$jobname.$ext");
	}
    }

    exit 1 if($errs);

    # the filter could have changed the latex engine, so update it
    $oo{command}=[latex_cmd(@{$oo{command_opts}})];
    $ENV{AMC_CMD}=join(' ',@{$oo{command}});

    check_engine();

    my $min_runs=1; # minimum number of runs
    my $max_runs=2; # maximum number of runs
    my $n_run=0; # number of runs so far
    my $rerun=0; # has to re-run?
    my $format=''; # output format

    do {

	$n_run++;

	# clears errors from previous run

	$a_errors=0;
	@latex_errors=();

	debug "%%% Compiling: pass $n_run";

	# lauches the command

	$cmd_pid=open(EXEC,"-|",@{$oo{'command'}});
	die "Can't exec ".join(' ',@{$oo{'command'}}) if(!$cmd_pid);

	# parses the output

	while(<EXEC>) {
	    # LaTeX Warning: Label(s) may have changed. Rerun to get
	    # cross-references right. -> has to re-run

	    $rerun=1
	      if(/^LaTeX Warning:.*Rerun to get cross-references right/);
	    $min_runs=2
	      if(/Warning: .*run twice/);

	    # Output written on jobname.pdf (10 pages) -> output
	    # format is pdf

	    $format=$1 if(/^Output written on .*\.([a-z]+) \(/);

	    # Lines beginning with '!' are errors: collect them

	    if(/^\!\s*(.*)$/) {
	      my $e=$1;
	      $e .= "..." if($e !~ /\.$/);
	      push @latex_errors,$e;
	    }

	    # Relays LaTeX log to calling program

	    print STDERR $_ if(/^.+$/);
	    print $_ if($latex_stdout && /^.+$/);
	}
	close(EXEC);
	$cmd_pid='';

    } while( (($n_run<$min_runs) || ($rerun && $n_run<$max_runs)) && ! $oo{'once'});

    # For these engines, we already know what is the output format:
    # override detected one

    $format='dvi' if($latex_engine eq 'latex');
    $format='pdf' if($latex_engine eq 'pdflatex');
    $format='pdf' if($latex_engine eq 'xelatex');

    print "Output format: $format\n";
    debug "Output format: $format\n";

    # Now converts output to PDF. Output format can be DVI or PDF. If
    # PDF, nothing has to be done...

    if($format eq 'dvi') {
	if(-f "$jobname.dvi") {

	  # default DVI->PDF engine is dvipdfmx

	  $engine_topdf='dvipdfm'
	    if(!$engine_topdf);

	  # if the choosend DVI->PDF engine is not present, try to get
	  # another one

	  if(!commande_accessible($engine_topdf)) {
	    debug_and_stderr
	      "WARNING: command $engine_topdf not available";
	    $engine_topdf=choose_command('dvipdfmx','dvipdfm','xdvipdfmx',
					 'dvipdf');
	  }

	  if($engine_topdf) {
	    # Now, convert DVI to PDF

	    debug "Converting DVI to PDF with $engine_topdf ...";
	    if($engine_topdf eq 'dvipdf') {
	      system($engine_topdf,"$jobname.dvi","$jobname.pdf");
	    } else {
	      system($engine_topdf,"-o","$jobname.pdf","$jobname.dvi");
	    }
	    debug_and_stderr "ERROR $engine_topdf: $?" if($?);
	  } else {
	    # No available DVI->PDF engine!

	    debug_and_stderr
	      "ERROR: I can't find dvipdf/dvipdfm/xdvipdfmx command !";
	  }
	} else {
	    debug "No DVI";
	}
    }

}

# do_filter() converts the source file to LaTeX format, using the
# right AMC::Filter::* module

sub prepare_filter {
  if($filter) {
    if(!$filter_engine) {
      load("AMC::Filter::$filter");
      $filter_engine="AMC::Filter::$filter"->new(jobname=>$jobname);
      $filter_engine->pre_filter($source);

      # sometimes the filter says that the source file don't need to
      # be changed

      set_filtered_source($source)
	if($filter_engine->unchanged);
    }
  } else {
    # Empty filter: the source is already a LaTeX file
    set_filtered_source($source);
  }
}

sub do_filter {
  my $f_base;
  my $v;
  my $d;
  my $n_err=0;

  if($filter) {
    # Loads and call appropriate filter to convert $source to
    # $filtered_source

    prepare_filter();
    $filter_engine->filter($source,$filtered_source);

    # show conversion errors

    for($filter_engine->errors()) {
      print "ERR: $_\n";
      $n_err++;
    }

    # sometimes the filter asks to override the LaTeX engine

    split_latex_engine($filter_engine->{'project_options'}->{'moteur_latex_b'})
      if($filter_engine->{'project_options'}->{'moteur_latex_b'});

  }

  return($n_err);
}

# give_latex_errors($context) Relay suitably formatted LaTeX errors to
# calling program (usualy AMC GUI). $context is the name of the
# document we are building.

sub give_latex_errors {
    my ($context)=@_;
    if(@latex_errors) {
	print "ERR: <i>"
	    .sprintf(__("%d errors during LaTeX compiling")." (%s)</i>\n",(1+$#latex_errors),$context);
	for(@latex_errors) {
	    print "ERR>$_\n";
	}
	exit(1);
    }
}

# transfer($orig,$dest) moves $orig to $dest, removing $dest if $orig
# does not exist

sub transfer {
    my ($orig,$dest)=@_;
    if(-f $orig) {
	debug "Moving $orig --> $dest";
	move($orig,$dest);
    } else {
	debug "No source: removing $dest";
	unlink($dest);
    }
}

# latex_cmd(%o) builds the LaTeX command and arguments to be passed to
# the execute command, using the engine specifications and extra
# options %o to pass to LaTeX: for each name=>value from %o, a LaTeX
# command '\def\name{value}' is passed to LaTeX. This allows to relay
# some options to LaTeX (number of copies, document needed for
# exemple).

sub latex_cmd {
    my (%o)=@_;

    $o{'AMCNombreCopies'}=$number_of_copies if($number_of_copies>0);

    return($latex_engine,
	   "--jobname=".$jobname,
	   @engine_args,
	   "\\nonstopmode"
	   .join('',map { "\\def\\".$_."{".$o{$_}."}"; } (keys %o) )
	   ." \\input{\"$f_tex\"}");
}

# check_engine() checks that the requeted LaTeX engine is available on
# the system

sub check_engine {
    if(!commande_accessible($latex_engine)) {
	print "ERR: ".sprintf(__("LaTeX command configured is not present (%s). Install it or change configuration, and then rerun."),$latex_engine)."\n";
	exit(1);
    }
}

# the $mode option passed to AMC-prepare contains characters that
# explains what is to be prepared...

my %to_do=();
while($mode =~ s/^[^a-z]*([a-z])(\[[a-z]*\])?//i) {
  $to_do{$1}=(defined($2) ? $2 : 1);
}

############################################################################
# MODE f: filter source file to LaTeX format
############################################################################

if($to_do{f}) {
  # FILTER
  do_filter();
}

############################################################################
# MODE s: builds the subject and a solution (with all the answers for
# questions, but with a different layout)
############################################################################

if($to_do{s}) {
  $to_do{s}='[sc]' if($to_do{s} eq '1');

  @output_files=($out_sujet,$out_calage,$out_corrige,$out_catalog);

    my %opts=(qw/NoWatermarkExterne 1 NoHyperRef 1/);

    $out_calage=$prefix."calage.xy" if(!$out_calage);
    $out_corrige=$prefix."corrige.pdf" if(!$out_corrige);
    $out_catalog=$prefix."catalog.pdf" if(!$out_catalog);
    $out_sujet=$prefix."sujet.pdf" if(!$out_sujet);

    for my $f ($out_calage,$out_corrige,$out_corrige_indiv,$out_sujet,$out_catalog) {
	if(-f $f) {
	    debug "Removing already existing file: $f";
	    unlink($f);
	}
    }

    # 1) SUBJECT

    execute('command_opts'=>[%opts,'SujetExterne'=>1]);
    analyse_amclog("$jobname.amc");
    give_latex_errors(__"question sheet");

    exit(1) if($a_errors>0);

    transfer("$jobname.pdf",$out_sujet);
    transfer("$jobname.xy",$out_calage);

  # Looks for accents problems in question IDs...

  my %qids=();
  my $unknown_qid=0;
  if(open(XYFILE,$out_calage)) {
    binmode(XYFILE);
    while(<XYFILE>) {
      if(!utf8::decode($_) || /\\IeC/) {
	if(/\\tracepos\{[^:]*:[^:]*:(.+):[^:]*\}\{([+-]?[0-9.]+[a-z]*)\}\{([+-]?[0-9.]+[a-z]*)\}(?:\{([a-zA-Z]*)\})?$/) {
	  $qids{$1}=1;
	} else {
	  $unknown_qid=1;
	}
      }
    }
    close(XYFILE);
    if(%qids) {
      push @errors_msg,
	map { "WARN: ".sprintf(__("please remove accentuated or non-standard characters from the following question ID: \"%s\""),$_)."\n" } (sort { $a cmp $b } (keys %qids));
    } elsif($unknown_qid) {
      push @errors_msg,"WARN: ".__("some question IDs seems to have accentuated or non-standard characters. This may break future processings.")."\n";
    }
  }
  flush_errors();

    # Relays variables to calling process

    print "Variables :\n";
    for my $k (keys %info_vars) {
	print "VAR: $k=".$info_vars{$k}."\n";
    }

    # 2) SOLUTION

  if($to_do{s}=~/s/) {
    execute('command_opts'=>[%opts,'CorrigeExterne'=>1]);
    transfer("$jobname.pdf",$out_corrige);
    give_latex_errors(__"solution");
  } else {
    debug "Solution not requested: removing $out_corrige";
    unlink($out_corrige);
  }

    # 3) CATALOG

  if($to_do{s}=~/c/) {
    execute('command_opts'=>[%opts,'CatalogExterne'=>1]);
    transfer("$jobname.pdf",$out_catalog);
    give_latex_errors(__"catalog");
  } else {
    debug "Catalog not requested: removing $out_catalog";
    unlink($out_catalog);
  }
}

############################################################################
# MODE k: builds individual corrected answer sheets (exactly the same
# sheets as for the students, but with correct answers ticked).
############################################################################

if($to_do{k}) {

  my $of=$out_corrige_indiv;
  $of=$out_corrige if(!$of && !$to_do{s});
  $of=$prefix."corrige.pdf" if(!$of);

  if(-f $of) {
    debug "Removing already existing file: $of";
    unlink($of);
  }

  @output_files=($of);

  execute('command_opts'=>[qw/NoWatermarkExterne 1 NoHyperRef 1 CorrigeIndivExterne 1/]);
  transfer("$jobname.pdf",$of);
  give_latex_errors(__"individual solution");
}

############################################################################
# MODE b: extracts the scoring strategy to the scoring database,
# parsing the AUTOQCM[...] messages from the LaTeX output.
############################################################################

if($to_do{b}) {

    print "********** Making marks scale...\n";

    my %bs=();
    my %titres=();

    my $quest='';
    my $rep='';
    my $outside_quest='';
    my $etu=0;

    my $delta=0;

    # Launches the LaTeX engine

    execute('command_opts'=>[qw/ScoringExterne 1 NoHyperRef 1/],
	    'once'=>1);

    open(AMCLOG,"$jobname.amc") or die "Unable to open $jobname.amc : $!";

    # Opens a connection with the database

    my $data=AMC::Data->new($data_dir);
    my $scoring=$data->module('scoring');
    my $capture=$data->module('capture');

    my $qs={};
    my $current_q={};

    # and parse the log...

    $scoring->begin_transaction('ScEx');
    annotate_source_change($capture);
    $scoring->clear_strategy;

    while(<AMCLOG>) {
	debug($_) if($_);

	# AUTOQCM[TOTAL=N] tells that the total number of sheets is
	# N. This will allow us to relay the progression of the
	# process to the calling process.

	if(/AUTOQCM\[TOTAL=([\s0-9]+)\]/) {
	    my $t=$1;
	    $t =~ s/\s//g;
	    if($t>0) {
		$delta=1/$t;
	    } else {
		print "*** TOTAL=$t ***\n";
	    }
	}

	if(/AUTOQCM\[FQ\]/) {
	  # end of question: register it (or update it)
	  $scoring->new_question($etu,$quest,
				 ($current_q->{'multiple'}
				  ? QUESTION_MULT : QUESTION_SIMPLE),
				 $current_q->{'indicative'},
				 $current_q->{'strategy'});
	  $qs->{$quest}=$current_q;
	  $outside_quest=$quest;
	  $quest='';
	  $rep='';
	}

	if(/AUTOQCM\[Q=([0-9]+)\]/) {
	  # beginning of question
	  $quest=$1;
	  $rep='';
	  if($qs->{$quest}) {
	      $current_q=$qs->{$quest};
	  } else {
	      $current_q={'multiple'=>0,
			  'indicative'=>0,
			  'strategy'=>'',
	      };
	  }
	}

	if(/AUTOQCM\[ETU=([0-9]+)\]/) {
	  # beginning of student sheet
	  $avance->progres($delta) if($etu ne '');
	  $etu=$1;
	  print "Sheet $etu...\n";
	  debug "Sheet $etu...\n";
	  $qs={};
	}

	if(/AUTOQCM\[NUM=([0-9]+)=(.+)\]/) {
	  # association question-number<->question-title
	  $scoring->question_title($1,$2);
	}

	if(/AUTOQCM\[MULT\]/) {
	  # this question is a multiple-style one
	  $current_q->{'multiple'}=1;
	}

	if(/AUTOQCM\[INDIC\]/) {
	  # this question is an indicative one
	  $current_q->{'indicative'}=1;
	}

	if(/AUTOQCM\[REP=([0-9]+):([BM])\]/) {
	  # answer
	  $rep=$1;
	  my $qq=$quest;
	  if($outside_quest && !$qq) {
	    $qq=$outside_quest;
	    debug_and_stderr "WARNING: answer outside questions for student $etu (after question $qq)";
	  }
	  $scoring->new_answer
	    ($etu,$qq,$rep,($2 eq 'B' ? 1 : 0),'');
	}

	# AUTOQCM[BR=N] tells that this student is a replicate of student N

	if(/AUTOQCM\[BR=([0-9]+)\]/) {
	  my $alias=$1;
	  $scoring->replicate($alias,$etu);
	  $etu=$alias;
	}

	if(/AUTOQCM\[B=([^\]]+)\]/) {
	  # scoring strategy string
	  if($quest) {
	    if($rep) {
	      # associated to an answer
	      $scoring->add_answer_strategy($etu,$quest,$rep,$1);
	    } else {
	      # associated to a question
	      $current_q->{'strategy'}=
		  ($current_q->{'strategy'}
		   ? $current_q->{'strategy'}.',' : '').$1;
	    }
	  } else {
	    # global scoring strategy, associated to a student if
	    # $etu>0, or to all students if $etu==0
	    $scoring->add_main_strategy($etu,$1);
	  }
	}

	# AUTOQCM[BDS=string] gives us the default scoring stragety
	# for simple questions
	# AUTOQCM[BDM=string] gives us the default scoring stragety
	# for multiple questions

	if(/AUTOQCM\[BD(S|M)=([^\]]+)\]/) {
	  $scoring->default_strategy(($1 eq 'S' ? QUESTION_SIMPLE : QUESTION_MULT),
				  $2);
	}

	if(/AUTOQCM\[VAR:([0-9a-zA-Z.-]+)=([^\]]+)\]/) {
	  # variables
	  my $name=$1;
	  my $value=$2;
	  $name='postcorrect_flag' if ($name eq 'postcorrect');
	  $scoring->variable($name,$value);
	}
    }
    close(AMCLOG);

    $scoring->end_transaction('ScEx');
}

$avance->fin();
