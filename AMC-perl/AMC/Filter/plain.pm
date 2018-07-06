#
# Copyright (C) 2012-2017 Alexis Bienvenue <paamc@passoire.fr>
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

package AMC::Filter::plain;

use AMC::Filter;
use AMC::Basic;

use File::Spec;
use Data::Dumper;

use utf8;

@ISA=("AMC::Filter");

use_gettext;

sub new {
    my $class = shift;
    my $self  = $class->SUPER::new();

    # list of available global options:

    $self->{'options_names'}=[qw/Title Presentation Code Lang Font
				 BoxColor PaperSize
				 AnswerSheetTitle AnswerSheetPresentation
				 AnswerSheetColumns
				 CompleteMulti SeparateAnswerSheet AutoMarks
				 DefaultScoringM DefaultScoringS
				 L-Question L-None L-Name L-Student
				 LaTeX LaTeX-Preambule LaTeX-BeginDocument
				 LaTeXEngine xltxtra
				 ShuffleQuestions Columns QuestionBlocks
				 Arabic ArabicFont
				 Disable
				 ManualDuplex SingleSided
				 L-OpenText L-OpenReserved
				 CodeDigitsDirection
				 PackageOptions
				 NameFieldWidth NameFieldLines NameFieldLinespace
				 TitleWidth
                                 Pages
                                 RandomSeed
				/];

    # from these options, which ones are boolean valued?

    $self->{'options_boolean'}=[qw/LaTeX xltxtra
				   ShuffleQuestions QuestionBlocks
				   CompleteMulti SeparateAnswerSheet AutoMarks
				   Arabic
				   ManualDuplex SingleSided
				  /];

    # current groups list
    $self->{'groups'}=[];
    # global LaTeX definitions
    $self->{latex_defs}=[];
    # packages needed
    $self->{packages}={};
    # maximum of digits that a hrizontal code can handle
    $self->{'maxhorizcode'}=6;
    # options values
    $self->{'options'}={};

    # default values for options:

    $self->{'default_options'}=
      {'latexengine'=>'xelatex','xltxtra'=>1,
       'questionblocks'=>1,'shufflequestions'=>1,
       'completemulti'=>1,
       'font'=>'Linux Libertine O',
       'arabicfont'=>'Rasheeq',
       'implicitdefaultscoringm'=>'haut=2',
       'l-name'=>'',
       'l-student'=>__("Please code your student number opposite, and write your name in the box below."),
       'disable'=>'',
       'manualduplex'=>'',
       'singlesided'=>'',
       'codedigitsdirection'=>'',
       'namefieldwidth'=>'',
       'namefieldlines'=>'',
       'namefieldlinespace'=>'.5em',
       'titlewidth'=>".47\\linewidth",
       'randomseed'=>"1527384",
      };

    # List of modules to be used when parsing (see parse_*
    # corresponding methods for implementation). Modules in the
    # Disable global option won't be used.

    $self->{'parse_modules'}=['verbatim','local_latex','images','embf','title','text'];

    # current question number among questions for which no ID is given
    # in the source
    $self->{'qid'}=0;

    bless ($self, $class);
    return $self;
}

# arabic default localisation texts
my %l_arabic=('l-question'=>'السؤال',
	      'l-none'=>'لا توجد اجابة صحيحة',
	      );

# arabic alphabet to replace letters ABCDEF... in the boxes
my @alphabet_arabic=('أ','ب','ج','د','ه','و','ز','ح','ط','ي','ك','ل',
		     'م','ن','س','ع','ف','ص','ق','ر','ش','ت','ث','خ',
		     'ذ','ض','ظ','غ',
                    );

# add a global LaTeX definition
sub add_global_latex_def {
  my ($self,$tex)=@_;
  push @{$self->{latex_defs}},$tex;
}

# require a specific LaTeX package, with options in the form
# needs_package("geometry","margins"=>'1cm',"noheadfoot"=>'')
sub needs_package {
  my ($self,$package,%options)=@_;
  $self->{packages}->{$package}={} if(!defined($self->{packages}->{$package}));
  for my $o (keys %options) {
    $self->{packages}->{$package}->{$o}=$options{$o};
  }
}

# parse boolean options to get 0 (from empty value, "NO" or " FALSE")
# or 1 (from other values).
sub parse_bool {
  my ($b)=@_;
  if($b =~ /^\s*(no|false|0)\s*$/i) {
    return(0);
  } else {
    return($b);
  }
}

sub first_defined {
  for(@_) { return($_) if(defined($_)); }
}

# transforms the list of current options values to make it coherent
sub parse_options {
  my ($self)=@_;

  # boolean options are parsed to get 0 or 1
  for my $n (@{$self->{'options_boolean'}}) {
    $self->{'options'}->{lc($n)}=parse_bool($self->{'options'}->{lc($n)});
  }

  # if AR language is selected, apply default arabic localisation
  # options and set 'arabic' option to 1
  if($self->{'options'}->{'lang'} eq 'AR') {
    for (keys %l_arabic) {
      $self->{'options'}->{$_}=$l_arabic{$_}
	if(!$self->{'options'}->{$_});
    }
    $self->{'options'}->{'arabic'}=1;
  }

  # if JA language is selected, switch to 'platex+dvipdf' LaTeX
  # engine, remove default font and don't use xltxtra LaTeX package
  if($self->{'options'}->{'lang'} eq 'JA') {
    $self->{'default_options'}->{'latexengine'}='platex+dvipdf';
    $self->{'default_options'}->{'font'}='';
    $self->{'default_options'}->{'xltxtra'}='';
  }

  # set options values to default if not defined in the source
  for my $k (keys %{$self->{'default_options'}}) {
    $self->{'options'}->{$k}=$self->{'default_options'}->{$k}
      if(!defined($self->{'options'}->{$k}));
  }

  # relay LaTeX engine option to the project itself
  $self->set_project_option('moteur_latex_b',
			    $self->{'options'}->{'latexengine'});

  # split Pages option to pages_question and/or pages_total
  if($self->{options}->{pages}) {
    if($self->{options}->{separateanswersheet} &&
       $self->{options}->{pages} =~ /^\s*([0-9]*)\s*\+\s*([0-9]*)\s*$/) {
      my $a=$1 || 0;
      my $b=$2 || 0;
      $self->{options}->{pages_question}=$a;
      $self->{options}->{pages_total}=$a+$b;
    } elsif($self->{options}->{pages} =~ /^\s*([0-9]+)\s*$/) {
      $self->{options}->{pages_total}=$1;
    } else {
# TRANSLATORS: Message when the Pages option used in AMC-TXT can't be parsed. %s will be replaced with the option value
      $self->error(sprintf(__"Pages option value can't be understood: %s",$self->{options}->{pages}));
    }
  }
}

# adds an object (hash) to a container (list) and returns the
# corresponding new hashref
sub add_object {
  my ($container,%object)=@_;
  push @$container,{%object};
  return($container->[$#$container]);
}

# adds a group to current state
sub add_group {
  my ($self,%g)=@_;
  add_object($self->{'groups'},%g);
}

# cleanup for text: removes leading and trailing spaces
sub value_cleanup {
  my ($self,$v)=@_;
  $$v =~ s/^\s+//;
  $$v =~ s/\s+$//;
}

# issue an AMC-TXT (syntax) error to be shown by the GUI
sub parse_error {
  my ($self,$text)=@_;
  $self->error("<i>AMC-TXT(".sprintf(__('Line %d'),$.).")</i> ".$text);
}

# check that a set of answers for a given question is coherent: one
# need more than one answer, and a simple question needs one and only
# one correct answer.
sub check_answers {
  my ($self,$question)=@_;
  if($question) {
    if($#{$question->{'answers'}}<1) {
# TRANSLATORS: Error text for AMC-TXT parsing, when opening a new question whereas the previous question has less than two choices
      $self->parse_error(__"Previous question has less than two choices");
    } else {
      my $n_correct=0;
      for my $a (@{$question->{'answers'}}) {
	$n_correct++ if($a->{'correct'});
      }
      if(!($question->{'multiple'} || $question->{'indicative'})) {
	if($n_correct!=1) {
# TRANSLATORS: Error text for AMC-TXT parsing
	  $self->parse_error(sprintf(__("Previous question is a simple question but has %d correct choice(s)"),$n_correct));
	}
      }
    }
  }
}

sub group_by_id {
  my ($self,$id,%oo)=@_;
  my $group='';

  if($id) {

  GROUPS: for(@{$self->{groups}}) {
      if($_->{id} eq $id) { $group=$_ ; last GROUPS; }
    }

  } else {
    $id='unnamed'.$self->unused_letter();
  }

  if(!$group) {
    $group=$self->add_group('id'=>$id,'questions'=>[],%oo);

    if($id ne '_main_') {
      # calls newly created group from the 'main' one

      my $main=$self->group_by_id('_main_');

      add_object($main->{'questions'},
		 textonly=>1,
		 text=>{type=>'latex',
			string=>$self->group_insert_command_name($group)},
		 %oo,
		);
    }
  }

  return($group);
}

sub read_options {
  my ($self,$options_string)=@_;
  my %oo=();
  my @opts=split(/,+/,$options_string);
  for (@opts) {
    if(/^([^=]+)=(.*)/) {
      $oo{$1}=$2;
    } else {
      $oo{$_}=1;
    }
  }
  return(%oo);
}

# parse the whole source file to a data tree ($self->{'groups'})
sub read_source {
  my ($self,$input_file)=@_;

  $self->{reader_state}=
    {
     follow=>'', # variable where to add content comming from
                 # following lines
     group=>$self->group_by_id('_main_'),  # current group
     question=>'', # current question
    };

  $self->read_file($input_file);
  $self->check_answers($self->{reader_state}->{question});
}

sub read_file {
  my ($self,$input_file)=@_;

  # regexp that matches an option name:
  my $opt_re='('.join('|',@{$self->{'options_names'}}).')';

  debug "Parsing $input_file";

  open(my $infile,"<",$input_file);
  binmode($infile);

 LINE: while(<$infile>) {
    if(!utf8::decode($_)) {
      $self->parse_error(__"Invalid encoding: you must use UTF-8, but your source file was saved using another encoding");
      last LINE;
    }

    chomp;

    debug ":> $_";

    # removes comments
    if(/^\s*\#/) {
      debug "Comment";
      next LINE;
    }

    # Insert other file...
    if(/^\s*IncludeFile:\s*(.*)/i) {
      my $filename=$1;
      $filename =~ s/\s+$//;
      my ($volume,$directories,$file) =
	File::Spec->splitpath( $input_file );
      my $dir=File::Spec->catpath($volume,$directories,'');
      my $f=File::Spec->rel2abs($filename,$dir);
      debug "Include $f";
      if(-f $f) {
	$self->read_file($f);
      } else {
	$self->parse_error(sprintf(__("File not found: %s"),$f));
      }
    }

    # options
    if(/^\s*$opt_re:\s*(.*)/i) {
      debug "Option line ($1)";
      $self->{options}->{lc($1)}=$2;
      $self->value_cleanup($self->{reader_state}->{follow});
      $self->{reader_state}->{follow}=\$self->{'options'}->{lc($1)};
      $self->check_answers($self->{reader_state}->{question});
      $self->{reader_state}->{question}='';
      next LINE;
    }

    if(/^([a-z0-9-]+):/i) {
      debug "Unknown option";
# TRANSLATORS: Error text for AMC-TXT parsing, when an unknown option is given a value
      $self->parse_error(sprintf(__("Unknown option: %s"),$1));
    }

    # groups
    if(/^\s*\*([\(\)])(?:\[([^]]*)\])?\s*(.*)/) {
      my $action=$1;
      my $options=$2;
      my $text=$3;
      debug "Group A=$action O=$options";
      my %oo=$self->read_options($options);
      if($action eq '(') {
        $self->needs_package('needspace') if($oo{needspace});
	$self->{reader_state}->{group}=
	  $self->group_by_id($oo{group},
			     parent=>$self->{reader_state}->{group},
			     header=>$text,
			     %oo);
	$self->{reader_state}->{follow}=\$self->{reader_state}->{group}->{header};
      } else {
	$self->{reader_state}->{group}->{footer}=$text;
	$self->{reader_state}->{follow}=\$self->{reader_state}->{group}->{footer};
	$self->{reader_state}->{group}=$self->{reader_state}->{group}->{parent};
      }
      next LINE;
    }

    # questions
    if(/^\s*(\*{1,2})(?:<([^>]*)>)?(?:\[([^]]*)\])?(?:\{([^\}]*)\})?\s*(.*)/) {
      $self->check_answers($self->{reader_state}->{question});
      my $star=$1;
      my $angles=$2;
      my $options=$3;
      my $scoring=$4;
      my $text=$5;
      debug "Question S=$star A=$angles O=$options S=$scoring";
      my %oo=$self->read_options($options);
      my $q_group=$self->{reader_state}->{group};

      if($oo{group}) {
	$q_group=$self->group_by_id($oo{group});
      }

      $self->{reader_state}->{question}=
	add_object($q_group->{'questions'},
		   'multiple'=>length($star)==2,
		   'open'=>$angles,
		   'scoring'=>$scoring,
		   'text'=>$text,'answers'=>[],%oo);
      $self->value_cleanup($self->{reader_state}->{follow});
      $self->{reader_state}->{follow}=\$self->{reader_state}->{question}->{'text'};
      next LINE;
    }

    # answers
    if(/^\s*(\+|-)(?:\[([^]]*)\])?(?:\{([^\}]*)\})?\s*(.*)/) {
      if($self->{reader_state}->{question}) {
	my $sign=$1;
	my $letter=$2;
	my $scoring=$3;
	my $text=$4;
	debug "Choice G=$sign L=$letter S=$scoring";
	my $a=add_object($self->{reader_state}->{question}->{answers},
			 'text'=>$text,'correct'=>($sign eq '+'),
			 'letter'=>$letter,
			 'scoring'=>$scoring);
	$self->value_cleanup($self->{reader_state}->{follow});
	$self->{reader_state}->{follow}=\$a->{'text'};
      } else {
	debug "Choice outside question";
# TRANSLATORS: Error text for AMC-TXT parsing when a choice is given but no question were opened
	$self->parse_error(__"Choice outside question");
      }
      next LINE;
    }

    # text following last line
    if($self->{reader_state}->{follow}) {
      debug "Follow...";
      ${$self->{reader_state}->{follow}}.="\n".$_;
    }
  }
  debug "Cleanup...";
  $self->value_cleanup($self->{reader_state}->{follow});
  close($infile);
}

# bold font LaTeX command, not used in arabic language because there
# is often no bold font arabic font.
sub bf_or {
  my($self,$replace,$bf)=@_;
  return($self->{'options'}->{'arabic'}
	 ? $replace : ($bf ? $bf : "\\bf"));
}

####################################################################
# PARSING METHODS
#
# ARGUMENT: list of components
# RETURN VALUE: list of parsed components
#
# A component is a {type=>TYPE,string=>STRING} hashref, where
# * TYPE is the component type: 'txt' for AMC-TXT text, 'latex' for
#   LaTeX code.
# * STRING is the component string
#
# When all parsing methods has been applied, the result must be a list
# of 'latex' components, that will be concatenated to get the LaTeX
# code corresponding to the source file.

# parse_images extracts an image specification (like '!image.jpg!')
# from 'txt' components, and replaces the component with 3 components:
# the preceding text, the LaTeX code that inserts the image, and the
# following text
sub parse_images {
  my ($self,@components)=@_;
  my @o=();
  for my $c (@components) {
    if($c->{'type'} eq 'txt') {
      my $s=$c->{'string'};
      while($s =~ /!(?:\{([^!\s]+)\})?(?:\[([^!\s]+)\])?([^!\s]+)!/p) {
	my $options=$1;
	my $ig_options=$2;
	my $path=$3;
	my $before=${^PREMATCH};
	my $after=${^POSTMATCH};
	push @o,{'type'=>'txt','string'=>$before};
	my $l="\\includegraphics".($ig_options ? '['.$ig_options.']' : '')
	  .'{'.$path.'}';
	if($options =~ /\bcenter\b/) {
	  $l="\\begin{center}$l\\end{center}";
	}
	push @o,{'type'=>'latex','string'=>$l};
	$s=$after;
      }
      push @o,{'type'=>'txt','string'=>$s};
    } else {
      push @o,$c;
    }
  }
  return(@o);
}

# parse_local_latex extracts a local LaTeX specification (like
# '[[$f(x)$]]') from 'txt' components
sub parse_local_latex {
  my ($self,@components)=@_;
  my @o=();
  for my $c (@components) {
    if($c->{'type'} eq 'txt') {
      my $s=$c->{'string'};
      while($s =~ /\[\[(((?!\]\]).)+)\]\]/p) {
	my $latex=$1;
	my $before=${^PREMATCH};
	my $after=${^POSTMATCH};
	push @o,{'type'=>'txt','string'=>$before};
	push @o,{'type'=>'latex','string'=>$latex};
	$s=$after;
      }
      push @o,{'type'=>'txt','string'=>$s};
    } else {
      push @o,$c;
    }
  }
  return(@o);
}

# generic code to parse '[xxx] ... [/xxx]' constructs
sub parse_tags {
  my ($self,$name,$parse_content,@components)=@_;
  my @o=();
  for my $c (@components) {
    if($c->{'type'} eq 'txt') {
      my $s=$c->{'string'};
      while($s =~ /\[\Q$name\E\](.*?)\[\/\Q$name\E\]/sp) {
	my $content=$1;
	my $before=${^PREMATCH};
	my $after=${^POSTMATCH};
	push @o,{'type'=>'txt','string'=>$before};
	push @o,&$parse_content($self,$content);
	$s=$after;
      }
      push @o,{'type'=>'txt','string'=>$s};
    } else {
      push @o,$c;
    }
  }
  return(@o);
}

# insert LaTeX code to write verbatim texts
sub verbatim_content {
  my ($self,$verb)=@_;
  my $letter=$self->unused_letter();

  # adds linebreaks at the beginning and end of $verb, if they none already
  $verb = "\n".$verb if($verb !~ /^\n/);
  $verb = $verb."\n" if($verb !~ /\n$/);

  $self->add_global_latex_def("\\begin{SaveVerbatim}{AMCverb$letter}$verb\\end{SaveVerbatim}");
  $self->needs_package('fancyvrb');
  return({type=>'latex',
          string=>"\\UseVerbatim{AMCverb$letter}"});
}

# parse [verbatim] ... [/verbatim] constructs
sub parse_verbatim {
  my ($self,@components)=@_;
  return($self->parse_tags("verbatim",\&verbatim_content,@components));
}

# generic code to parse '[xxx ... xxx]' constructs
sub parse_brackets {
  my ($self,$modifier,$tex_open,$tex_close,@components)=@_;
  my @o=();
  my $levels=0;
  my $tex;
  for my $c (@components) {
    if($c->{'type'} eq 'txt') {
      my $s=$c->{'string'};
      while($s =~ /(\[\Q$modifier\E|\Q$modifier\E\])/p) {
	my $sep=$1;
	my $before=${^PREMATCH};
	my $after=${^POSTMATCH};
	if($sep=~/^\[/) {
	  $tex=$tex_open;
	  $levels++;
	} else {
	  $tex=$tex_close;
	  $levels--;
	}
	push @o,{'type'=>'txt','string'=>$before};
	push @o,{'type'=>'latex','string'=>$tex};
	$s=$after;
      }
      push @o,{'type'=>'txt','string'=>$s};
    } else {
      push @o,$c;
    }
  }
  return(@o);
}

# parse_embf inserts LaTeX commands to switch to italic, bold or
# typewriter font or underlined text when '[_ ... _]', '[* ... *]',
# '[| ... |]' or '[/ ... /]' constructs are used in AMC-TXT, respectively.
sub parse_embf {
  my ($self,@components)=@_;
  my @c=$self->parse_brackets('_',"\\textit{","}",@components);
  @c=$self->parse_brackets('*',"\\textbf{","}",@c);
  @c=$self->parse_brackets('/',"\\underline{","}",@c);
  @c=$self->parse_brackets('|',"\\texttt{","}",@c);
  return(@c);
}

# parse_title inserts LaTeX commands to build a title line from '[==
# ... ==]' constructs.
sub parse_title {
  my ($self,@components)=@_;
  return($self->parse_brackets('==',"\\AMCmakeTitle{","}",@components));
}

# parse_text transforms plain text (with no special constructs) to
# LaTeX code, escaping some characters that have special meaning for
# LaTeX.
sub parse_text {
  my ($self,@components)=@_;
  my @o=();
  for my $c (@components) {
    if($c->{'type'} eq 'txt') {
      my $s=$c->{'string'};
      if(! $self->{'options'}->{'latex'}) {
	$s =~ s/\\/\\(\\backslash\\)/g;
	$s =~ s/~/\\(\\sim\\)/g;
	$s =~ s/\*/\\(\\ast\\)/g;
	$s =~ s/([&{}\#_%])/\\\1/g;
	$s =~ s/-/-{}/g;
	$s =~ s/\$/\\textdollar{}/g;
	$s =~ s/\^/\\textasciicircum{}/g;
      }
      push @o,{'type'=>'latex','string'=>$s};
    } else {
      push @o,$c;
    }
  }
  return(@o);
}

# parse_all calls all requested parse_* methods in turn (when they are
# not disabled by the Disable global option).
sub parse_all {
  my ($self,@components)=@_;
  for my $m (@{$self->{'parse_modules'}}) {
    my $mm='parse_'.$m;
    @components=$self->$mm(@components)
      if($self->{'options'}->{'disable'} !~ /\b$m\b/);
  }
  return(@components);
}

# Checks that the resulting components list has only 'latex' components
sub check_latex {
  my ($self,@components)=@_;
  my @s=();
  for my $c (@components) {
    if($c->{'type'} ne 'latex') {
      debug_and_stderr "ERR(FILTER): non-latex resulting component (".
	$c->{'type'}."): ".$c->{'string'};
    }
    push @s,$c->{'string'};
  }
  return(@s);
}

# converts AMC-TXT string to a LaTeX string: make a single 'txt'
# component, apply parse_all and check_latex, and then concatenates
# the components
sub format_text {
  my ($self,$t)=@_;
  my $src;
  if(ref($t) eq 'HASH') {
    $src=$t;
  } else {
    $t =~ s/^\s+//;
    $t =~ s/\s+$//;
    $src={'type'=>'txt','string'=>$t};
  }

  return(join('',$self->check_latex($self->parse_all($src))));
}

# builds the LaTeX scoring command from the question's scoring
# strategy (or the default scoring strategy)
sub scoring_string {
  my ($self,$obj,$type)=@_;
  # manual scoring if some scoring was used, either for the question
  # or for one of the answers
  my $manual_scoring=(length $obj->{'scoring'} ? 1 : 0);
  if($obj->{answers}) {
    for my $a (@{$obj->{answers}}) {
      $manual_scoring=1 if(length $a->{scoring});
    }
  }
  my $s=$obj->{'scoring'};
  # set to explicit default (defined by DefaultScoringS or
  # DefaultScoringM):
  if(! length($s)) {
    $s=$self->{'options'}->{'defaultscoring'.$type};
  }
  # if no manual scoring and no explicit default scoring, use the
  # implicit default scoring:
  if(!length($s) && !$manual_scoring) {
    $s=$self->{'options'}->{'implicitdefaultscoring'.$type};
  }
  return(length($s) ? "\\scoring{$s}" : "");
}

# builds the LaTeX code for an answer: \correctchoice or \wrongchoice,
# followed by the scoring command
sub format_answer {
  my ($self,$a)=@_;
  my $t='\\'.($a->{'correct'} ? 'correct' : 'wrong').'choice';
  $t.='['.$a->{letter}.']' if($a->{letter} ne '');
  $t.='{'
    .$self->format_text($a->{'text'})."}";
  $t.=$self->scoring_string($a,'a');
  $t.="\n";
  return($t);
}

sub arabic_env {
  my ($self,$action)=@_;
  if($self->{'options'}->{'arabic'} && $self->bidi_year()<2011) {
    return("\\".$action."{arab}");
  } else {
    return("");
  }
}

# builds the LaTeX code for the question (including answers)
sub format_question {
  my ($self,$q)=@_;
  my $t='';

  if($q->{textonly}) {

    $t.=$self->arabic_env('begin');
    $t.=$self->format_text($q->{'text'})."\n";
    $t.=$self->arabic_env('end');

  } else {

    my $qid=$q->{'id'};
    $qid=$q->{'name'} if(!$qid);
    $qid=sprintf("Q%03d",++$self->{'qid'}) if(!$qid);
    my $mult=($q->{'multiple'} ? 'mult' : '');
    my $ct=($q->{'horiz'} ? 'horiz' : '');

    $t.=$self->arabic_env('begin');
    $t.='\\begin{question'.$mult.'}{'.$qid."}";
    $t.=$self->scoring_string($q,($q->{'multiple'} ? 'm' : 's'));
    $t.="\n";
    $t.=$self->format_text($q->{'text'})."\n";
    $t.="\\QuestionIndicative\n" if($q->{'indicative'});
    if ($q->{open} ne '') {
      $t.="\\AMCOpen{".$q->{open}."}{";
    } else {
      $t.="\\begin{multicols}{".$q->{'columns'}."}\n"
	if ($q->{'columns'}>1);
      $t.="\\begin{choices$ct}".($q->{'ordered'} ? "[o]" : "")."\n";
    }
    for my $a (@{$q->{'answers'}}) {
      $t.=$self->format_answer($a);
    }
    if ($q->{open} ne '') {
      $t.="}\n";
    } else {
      $t.="\\end{choices$ct}\n";
      $t.="\\end{multicols}\n"
	if ($q->{'columns'}>1);
    }
    $t.="\\end{question".$mult."}";
    $t.=$self->arabic_env('end');
    $t.="\n";
  }

  return($t);
}

sub int_to_letters {
  my ($self,$i)=@_;
  my $l='';
  while($i>0) {
    $l=chr(ord("A")+($i % 26)).$l;
    $i=int($i/26);
  }
  return($l);
}

sub unused_letter {
  my ($self)=@_;
  $self->{'letter_i'}++;
  return($self->int_to_letters($self->{'letter_i'}));
}

# returns a new group name 'groupX' (where X is a letter beginnig at
# A)
sub create_group_name {
  my ($self)=@_;
  return( "gr".$self->unused_letter() );
}

# returns the group name (creating one if necessary)
sub group_name {
  my ($self,$group)=@_;
  if(!$group->{name}) {
    if($group->{id} =~ /^[a-z]+$/i) {
      $group->{name}=$group->{id};
    } else {
      $group->{name}=$self->create_group_name();
    }
  }
  return($group->{name});
}

# gets the Year for the version of installed bidi.sty. This will be
# used to adapt the LaTeX code to version before or after 2011
sub bidi_year {
  my ($self)=@_;
  if(!$self->{'bidiyear'}) {
    my $f=find_latex_file("bidi.sty");
    if(-f $f) {
      open(BIDI,$f);
    BIDLIG: while(<BIDI>) {
	if(/\\bididate\{([0-9]+)\//) {
	  $self->{'bidiyear'}=$1;
	  last BIDLIG;
	}
      }
      close(BIDI);
    }
  }
  return($self->{'bidiyear'});
}

# builds and returns the LaTeX header
sub file_header {
  my ($self)=@_;
  my $t='';

  my @package_options=();

  my $o=$self->{'options'}->{packageoptions};
  $o =~ s/^\s+//;
  $o =~ s/\s+$//;
  if($o) {
    for my $oo (split(/,+/,$o)) {
      push @package_options,$oo;
    }
  }

  push @package_options,"bloc" if($self->{'options'}->{'questionblocks'});
  for my $on (qw/completemulti separateanswersheet automarks/) {
    push @package_options,$on if($self->{'options'}->{$on});
  }

  push @package_options,"lang=".uc($self->{'options'}->{'lang'})
    if($self->{'options'}->{'lang'});

  my $po='';
  $po='['.join(',',@package_options).']' if(@package_options);

  if($self->{'options'}->{'arabic'}) {
    $t.="% bidi YEAR ".$self->bidi_year()."\n";
  }

  $t .= "\\documentclass{article}\n";
  $t .= "\\usepackage{bidi}\n"
    if($self->{'options'}->{'arabic'} && $self->bidi_year()<2011);
  $t .= "\\usepackage{xltxtra}\n" if($self->{'options'}->{'xltxtra'});
  $t .= "\\usepackage{arabxetex}\n"
    if($self->{'options'}->{'arabic'} && $self->bidi_year()<2011);
  $t .= "\\usepackage".$po."{automultiplechoice}\n";
  $t .= "\\usepackage{"
    .($self->{'options'}->{'arabic'} && $self->bidi_year()<2011
      ? "fmultico" : "multicol")."}\n";

  # packages
  for my $p (keys %{$self->{packages}}) {
    my @opts=();
    for my $o (keys %{$self->{packages}->{$p}}) {
      push @opts,($o . ($self->{packages}->{$p}->{$o} eq '' ? '' :
                        "=".$self->{packages}->{$p}->{$o}));
    }
    $t .= "\\usepackage".(@opts ? "[".join(",",@opts)."]" : "")
      ."{".$p."}\n";
  }

  $t .= "\\setmainfont{".$self->{'options'}->{'font'}."}\n"
    if($self->{'options'}->{'font'});
  $t .= "\\newfontfamily{\\arabicfont}[Script=Arabic,Scale=1]{".$self->{'options'}->{'arabicfont'}."}\n"
    if($self->{'options'}->{'arabicfont'} && $self->{'options'}->{'arabic'});
  $t .= "\\geometry{paper=".lc($self->{'options'}->{'papersize'})."paper}\n"
    if($self->{'options'}->{'papersize'});
  $t .= $self->{'options'}->{'latex-preambule'};
  $t .= "\\usepackage{arabxetex}\n"
    if($self->{'options'}->{'arabic'} && $self->bidi_year()>=2011);
  $t .= "\\begin{document}\n";
  $t .= "\\def\\AMCmakeTitle#1{\\par\\noindent\\hrule\\vspace{1ex}{\\hspace*{\\fill}\\Large\\bf #1\\hspace*{\\fill}}\\vspace{1ex}\\par\\noindent\\hrule\\par\\vspace{1ex}}\n";
  $t .= "\\AMCrandomseed{".$self->{'options'}->{'randomseed'}."}\n";
  if($self->{'options'}->{'boxcolor'}) {
    if($self->{'options'}->{'boxcolor'}
       =~ /^\\definecolor\{amcboxcolor\}/) {
      $t .= $self->{'options'}->{'boxcolor'};
    } elsif($self->{'options'}->{'boxcolor'}
       =~ /^\#([a-f0-9]{2})([a-f0-9]{2})([a-f0-9]{2})$/i) {
      $t .= "\\definecolor{amcboxcolor}{rgb}{"
	.sprintf("%0.2f,%0.2f,%0.2f",map { hex($_)/256.0 } ($1,$2,$3))."}\n";
    } else {
      $t .= "\\definecolor{amcboxcolor}{named}{"
	.$self->{'options'}->{'boxcolor'}."}\n";
    }
    $t .= "\\AMCboxColor{amcboxcolor}\n";
  }
  $t .= "\\AMCtext{none}{"
    .$self->format_text($self->{'options'}->{'l-none'})."}\n"
    if($self->{'options'}->{'l-none'});
  $t .= "\\def\\AMCotextGoto{\\par ".$self->format_text($self->{'options'}->{'l-opentext'})."}\n"
    if($self->{'options'}->{'l-opentext'});
  $t .= "\\def\\AMCotextReserved{".$self->format_text($self->{'options'}->{'l-openreserved'})."}\n"
    if($self->{'options'}->{'l-openreserved'});

  $t.="\\def\\AMCbeginQuestion#1#2{\\noindent{"
    .$self->bf_or("\\Large")." "
      .$self->{'options'}->{'l-question'}." #1} #2\\hspace{1em}}\n"
	."\\def\\AMCformQuestion#1{{"
	  .$self->bf_or("\\Large")." "
	    .$self->{'options'}->{'l-question'}." #1 :}}\n"
	      if($self->{'options'}->{'l-question'});
  if($self->{'options'}->{'arabic'}) {
    $t.="\\def\\AMCchoiceLabel#1{\\csname ArabicAlphabet\\Alph{#1}\\endcsname}\n";
    my $letter="A";
    for my $c (@alphabet_arabic) {
      $t.="\\def\\ArabicAlphabet$letter"."{$c}\n";
      $letter++;
    }
  }
  $t .= $self->{'options'}->{'latex-begindocument'};

  return($t);
}

# Builds and returns the question sheet head (or the answer sheet head
# if $answersheet is true)
sub page_header {
  my ($self,$answersheet)=@_;
  my $t="";

  my $titlekey='';

  if($self->{'options'}->{'separateanswersheet'}) {
    if($answersheet) {
      if($self->{'options'}->{'code'}>0) {
	$titlekey='answersheettitle';
      }
    } else {
      $titlekey='title';
    }
  } else {
    if($self->{'options'}->{'code'}>0) {
      $titlekey='title';
    }
  }
  if($titlekey && $self->{'options'}->{$titlekey}) {
    $t.="\\begin{center}".$self->bf_or("\\Large","\\bf\\large")." "
      .$self->format_text($self->{'options'}->{$titlekey})
	."\\end{center}";
    $t.="\n\n";
  }
  return($t);
}

# Builds and returns the name field LaTeX code
sub full_namefield {
  my ($self,$with_code)=@_;
  my $n_ligs;
  if($self->{'options'}->{'namefieldlines'}) {
    $n_ligs=$self->{'options'}->{'namefieldlines'};
  } else {
    $n_ligs=($with_code ? 2 : 1);
  }
  my $t='';
  $t.="\\namefield{\\fbox{";
  $t.="\\begin{minipage}{.9\\linewidth}"
    .($self->{'options'}->{'l-name'}
      ? $self->{'options'}->{'l-name'}
      : '\\AMClocalized{namesurname}')
      .(("\n\n\\vspace*{".$self->{'options'}->{'namefieldlinespace'}."}\\dotfill") x $n_ligs)
	."\n\\vspace*{1mm}"
	  ."\n\\end{minipage}";
  $t.="\n}}";
  return($t);
}

# Builds and returns the student identification block LaTeX code (with
# name field and AMCcode if requested)
sub student_block {
  my ($self)=@_;
  my $t='';

  if($self->{'options'}->{'code'}>0) {
    # Header layout with a code (student number)

    my $vertical=($self->{'options'}->{'code'}>$self->{'maxhorizcode'});
    $vertical=1 if($self->{options}->{codedigitsdirection} =~ /^v/i);
    $vertical=0 if($self->{options}->{codedigitsdirection} =~ /^h/i);

    $t.="{\\setlength{\\parindent}{0pt}\\hspace*{\\fill}";
    $t.=($vertical?"":"\\hbox{\\vtop{");
    $t.= "\\LR{" if($self->{'options'}->{'arabic'} && $vertical);
    $t.="\\AMCcode".($vertical ? "" : "H")."{student.number}{".
	$self->{'options'}->{'code'}."}";
    $t.= "}" if($self->{'options'}->{'arabic'} && $vertical);
    $t.=($vertical?"":"}}")."\\hspace*{\\fill}"
      ."\\begin{minipage}".($vertical?"[b]":"[t]")."{"
      .($self->{'options'}->{'namefieldwidth'} ?
	$self->{'options'}->{'namefieldwidth'} : '5.8cm')
	."}"
	."\$\\long".($self->{'options'}->{'arabic'} ? "right" : "left")
	  ."arrow{}\$\\hspace{0pt plus 1cm}"
	    .$self->{'options'}->{'l-student'}
	      ."\\vspace{3ex}\n\n\\hfill"
		.$self->full_namefield(1)
		  ."\\hfill\\vspace{5ex}\\end{minipage}\\hspace*{\\fill}"
		    ."\n\n}";
    $t.="\\vspace{4mm}\n";
  } else {
    # header layout without code
    $t.= "\\begin{minipage}{"
      .$self->{'options'}->{'titlewidth'}
      ."}\n";
    my $titlekey=($self->{'options'}->{'separateanswersheet'}
		  ? 'answersheettitle' : 'title');
    if($self->{'options'}->{$titlekey}) {
      $t.= "\\begin{center}".$self->bf_or("\\Large","\\bf\\large")." "
	.$self->format_text($self->{'options'}->{$titlekey})
	  ."\\end{center}\n\n";
    }
    $t.= "\\end{minipage}\\hfill\n";
    $t.= "\\begin{minipage}{".
      ($self->{'options'}->{'namefieldwidth'} ?
	$self->{'options'}->{'namefieldwidth'} : ".47\\linewidth")
      ."}\n";
    $t.= $self->full_namefield(0);
    $t.= "\\end{minipage}\\vspace{4mm}\n\n";
  }
  return($t);
}

sub group_insert_command_name {
  my ($self,$group)=@_;
  return("\\insertPlainGroup".$self->group_name($group));
}

sub group_insert_command_def {
  my ($self,$group)=@_;
  my $t="\\def".$self->group_insert_command_name($group)."{";
  $t.="\\needspace{".$group->{needspace}."}\n"
    if($group->{needspace});
  if($group->{header}) {
    $t.="\\noindent ".$self->format_text($group->{header});
    $t.="\\vspace{1.5ex}\\par\n" if(!$group->{custom}
			   && $group->{columns}<=1);
  }
  $t.="\\begin{multicols}{".$group->{columns}."}"
    if($group->{columns}>1);
  for my $q (grep { $_->{first} } (@{$group->{questions}})) {
    $t.=$self->format_question($q)."\n";
  }
  $t.="\\insertgroup";
  $t.="[".$group->{numquestions}."]" if($group->{numquestions});
  $t.="{".$self->group_name($group)."}";
  for my $q (grep { $_->{last} } (@{$group->{questions}})) {
    $t.="\n".$self->format_question($q);
  }
  $t.="\\end{multicols}"
    if($group->{columns}>1);
  if($group->{footer}) {
    $t.=$self->format_text($group->{footer});
    $t.="\\vspace{1.5ex}\\par\n" if(!$group->{custom} && !$group->{cut});
  }
  $t.="}\n";
  return($t);
}

# writes the LaTeX output file
sub write_latex {
  my ($self,$output_file)=@_;

  my $tex='';

  for my $group (@{$self->{'groups'}}) {

    # create group elements from the questions

    my @questions=grep { !($_->{first} || $_->{last}) }
      @{$group->{'questions'}};

    my $q;
    while($q=shift @questions) {
      $tex .= "\\element{".$self->group_name($group)."}{\n";
      $tex .= $self->format_question($q);
      while(@questions && $questions[0]->{'next'}) {
	$tex .= "\n";
	$tex .= $self->format_question(shift @questions);
      }
      $tex .= "}\n";
    }

    # command to print the group

    $tex .= $self->group_insert_command_def($group);
  }

  $tex .= "\\onecopy{5}{\n";

  $tex .= "\\begin{arab}" if($self->{'options'}->{'arabic'});
  $tex .= $self->page_header(0);
  $tex .= $self->student_block
    if(!$self->{'options'}->{'separateanswersheet'});

  if($self->{'options'}->{'presentation'}) {
    $tex .= $self->format_text($self->{'options'}->{'presentation'})."\n\n";
  }
  $tex .= "\\vspace{4mm}\\noindent\\hrule\n";
  $tex .= "\\end{arab}" if($self->{'options'}->{'arabic'});
  $tex .= "\n\n";

  # shuffle groups...
  for my $g (@{$self->{groups}}) {
    $tex .= "\\shufflegroup{".$self->group_name($g)."}\n"
      if(parse_bool(first_defined($g->{shuffle},$self->{'options'}->{'shufflequestions'})));
  }

  # print groups
  $tex .= "\\begin{arab}"
    if($self->{'options'}->{'arabic'} && $self->bidi_year()>=2011);
  if($self->{'options'}->{'columns'}>1) {
    $tex .= "\\begin{multicols}{".$self->{'options'}->{'columns'}."}\n";
  } else {
    $tex .= "\\vspace{2ex}\n\n";
  }

  $tex .= $self->group_insert_command_name($self->group_by_id('_main_'))."\n";

  if($self->{'options'}->{'columns'}>1) {
    $tex .= "\\end{multicols}\n";
  }
  $tex .= "\\end{arab}"
    if($self->{'options'}->{'arabic'} && $self->bidi_year()>=2011);

  # separate answer sheet
  if($self->{'options'}->{'separateanswersheet'}) {
    $tex .= "\n\\AMCaddpagesto{".$self->{options}->{pages_question}."}"
      if($self->{options}->{pages_question});
    if($self->{'options'}->{'singlesided'}) {
      $tex .= "\n\\clearpage\n\n";
    } else {
      $tex .= "\n\\AMCcleardoublepage\n\n";
    }
    $tex .= "\\AMCformBegin\n";

    $tex .= "\\begin{arab}" if($self->{'options'}->{'arabic'});
    $tex .= $self->page_header(1);
    $tex .= $self->student_block;
    if($self->{'options'}->{'answersheetpresentation'}) {
      $tex .= $self->format_text($self->{'options'}->{'answersheetpresentation'})."\n\n";
    }
    $tex .= "\\vspace{4mm}\\noindent\\hrule\n";
    $tex .= "\\end{arab}" if($self->{'options'}->{'arabic'});
    $tex .= "\n\n";

    $tex .= "\\begin{arab}" if($self->{'options'}->{'arabic'});
    $tex .= "\\begin{multicols}{".$self->{'options'}->{'answersheetcolumns'}."}\n"
      if($self->{'options'}->{'answersheetcolumns'}>1);
    $tex .= "\\AMCform\n";
    $tex .= "\\end{multicols}\n"
      if($self->{'options'}->{'answersheetcolumns'}>1);
    $tex .= "\\end{arab}" if($self->{'options'}->{'arabic'});
  }

  $tex .= "\n\n";
  $tex .= "\\AMCaddpagesto{".$self->{options}->{pages_total}."}\n"
      if($self->{options}->{pages_total});
  $tex .= "\\AMCcleardoublepage\n" if($self->{'options'}->{'manualduplex'});

  $tex .= "}\n";
  $tex .= "\\end{document}\n";

  open(OUT,">:utf8",$output_file);

  print OUT $self->file_header();
  print OUT join("\n",@{$self->{latex_defs}})."\n";
  print OUT $tex;

  close(OUT);
}

# Checks that the requested prerequisites (in fact, fonts) are
# installed on the system
sub check {
  my ($self)=@_;
  my @cf=('font');
  my @mf=();
  push @cf,'arabicfont' if($self->{'options'}->{'arabic'});
  for my $k (@cf) {
    if($self->{'options'}->{'font'}) {
      if(!check_fonts({'type'=>'fontconfig',
		       'family'=>[$self->{'options'}->{$k}]})) {
	push @mf,$self->{'options'}->{$k}
      }
    }
  }
  $self->error(sprintf(__("The following fonts does not seem to be installed on the system: <b>%s</b>."),join(', ',@mf))) if(@mf);
}

# Whole filter processing
sub filter {
  my ($self,$input_file,$output_file)=@_;
  $self->read_source($input_file);
  $self->parse_options();
  $self->check();
  $self->write_latex($output_file);
}

1;
