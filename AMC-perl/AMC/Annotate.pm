#! /usr/bin/perl
#
# Copyright (C) 2013-2017 Alexis Bienvenue <paamc@passoire.fr>
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

package AMC::Annotate;

use Gtk3;
use List::Util qw(min max sum);
use File::Copy;
use Unicode::Normalize;

use AMC::Path;
use AMC::Basic;
use AMC::Export;
use AMC::Subprocess;
use AMC::NamesFile;
use AMC::Substitute;
use AMC::DataModule::report ':const';
use AMC::DataModule::capture qw/:zone :position/;
use AMC::DataModule::layout qw/:flags/;
use AMC::Gui::Avancement;

use utf8;

sub new {
    my (%o)=(@_);

    my $self={
	      data_dir=>'',
	      project_dir=>'',
	      projects_dir=>'',
	      pdf_dir=>'',
	      single_output=>'',
	      filename_model=>'(N)-(ID)',
	      force_ascii=>'',
	      pdf_subject=>'',
	      names_file=>'',
	      names_encoding=>'utf8',
	      association_key=>'',
	      csv_build_name=>'',
	      significant_digits=>1,
	      darkness_threshold=>'',
	      darkness_threshold_up=>'',
	      id_file=>'',
	      sort=>'',
	      annotate_indicatives=>'',
	      position=>'marges',
	      text_color=>'red',
	      line_width=>1,
	      font_name=>'Linux Libertine O 12',
	      dist_to_box=>'1cm',
	      dist_margin=>'5mm',
	      dist_margin_globaltext=>'3mm',
	      symbols=>{'0-0'=>{qw/type none/},
			'0-1'=>{qw/type circle color red/},
			'1-0'=>{qw/type mark color red/},
			'1-1'=>{qw/type mark color blue/},
		       },
	      verdict=>'',
	      verdict_question=>'',
	      verdict_question_cancelled=>'',
	      progress=>'',
	      progress_id=>'',
	      compose=>0,
	      pdf_corrected=>'',
	      changes_only=>'',
	      embedded_max_size=>'',
	      embedded_format=>'jpeg',
	      embedded_jpeg_quality=>80,
              rtl=>'',
	      debug=>(get_debug() ? 1 : 0),
	  };

    for my $k (keys %o) {
	$self->{$k}=$o{$k} if(defined($self->{$k}));
    }

    for my $k (grep { /_(dir|file)$/ || /^pdf_/ } (keys %$self)) {
      utf8::downgrade($self->{$k});
    }

    $self->{type}=($self->{single_output} ? REPORT_SINGLE_ANNOTATED_PDF
		   : REPORT_ANNOTATED_PDF );

    # checks that the position option is available
    $self->{position}=lc($self->{position});
    if($self->{position} !~ /^(marges?|case|zones|none)$/i) {
      debug "ERROR: invalid \<position>: $self->{position}";
      $self->{position}='none';
    }

    # chacks that the embedded_format is ok
    $self->{embedded_format}=lc($self->{embedded_format});
    if($self->{embedded_format} !~ /^(jpeg|png)$/i) {
      debug "ERROR: invalid <embedded_format>: $self->{embedded_format}";
      $self->{embedded_format}='jpeg';
    }

    # checks that the pdf files exist
    for my $k (qw/subject corrected/) {
      if($self->{'pdf_'.$k} && ! -f $self->{'pdf_'.$k}) {
	debug "WARNING: PDF $k file not found: ".$self->{'pdf_'.$k};
	$self->{'pdf_'.$k}='';
      }
    }

    # force to default value when filename model is empty
    $self->{filename_model}='(N)-(ID)'
      if($self->{filename_model} eq '');

    # adds pdf extension if not already there
    if($self->{filename_model} !~ /\.pdf$/i) {
      debug "Adding pdf extension to $self->{filename_model}";
      $self->{filename_model}.='.pdf';
    }

    # if the corrected answer sheet is not given, use the subject
    # instead.
    if($self->{compose}==2 && ! -f $self->{pdf_corrected}) {
      $self->{compose}=1;
    }

    # which pdf file will be used as a background when scans are not
    # available?
    if($self->{compose}==1) {
      $self->{pdf_background}=$self->{pdf_subject};
    } elsif($self->{compose}==2) {
      $self->{pdf_background}=$self->{pdf_corrected};
    }

    # set up the object to send progress to calling program
    $self->{avance}=AMC::Gui::Avancement::new($self->{progress},
					      'id'=>$self->{progress_id})
      if($self->{progress});

    bless $self;
    return($self);
}

# units conversion

my %units=(
	   in=>1,
	   ft=>12,
	   yd=>36,
	   pt=>1/72,
	   cm=>1/2.54,
	   mm=>1/25.4,
	   m=>1000/25.4,
	  );

sub dim2in {
  my ($d)=@_;
 UNITS: for my $u (keys %units) {
    if($d =~ /^(.*)(?<![a-zA-Z])$u$/) {
      $d=$1*$units{$u};
    }
  }
  return($d);
}

# get absolute path from a path that can contain %PROJECT or %PROJECTS
# strings, that refer to the project directory and the projetcs
# directory.

sub absolute_path {
  my ($self,$path)=@_;
  if($self->{project_dir}) {
    $path=proj2abs({'%PROJET',$self->{project_dir},
		    '%PROJETS',$self->{projects_dir},
		    '%HOME'=>$ENV{'HOME'},
		   },
		   $path);
  }
  utf8::downgrade($path);
  return($path);
}

# Tests if the report that has already been made is still present and
# up to date. If up-to-date, returns the filename. Otherwise, returns
# the empty string.

sub student_uptodate {
  my ($self,$student)=@_;

  my ($filename,$timestamp)
    =$self->{report}->get_student_report_time(REPORT_ANNOTATED_PDF,@$student);

  if($filename) {
    debug "Registered filename ".show_utf8($filename);
    utf8::encode($filename);
    my $source_change=$self->{capture}->variable('annotate_source_change');
    debug "Registered answer sheet: updated at $timestamp, source change at $source_change";

    # we say there is an up-to-date annotated answer sheet if the file
    # exists and has been built after the last time some result or
    # configuration variable were changed.
    debug "Directory ".show_utf8($self->{pdf_dir});
    debug "Looking for filename ".show_utf8($filename);
    my $path="$self->{pdf_dir}/$filename";
    if(-f $path && $timestamp>$source_change) {
      debug "Exists!";
      return($filename);
    } else {
      debug "NOT up-to-date.";
    }
  } else {
    debug "No registered annotated answer sheet.";
  }
  return('');
}

# Computes the filename to be used for the student annotated answer
# sheet. Returns this filename, and, if there is already a up-to-date
# annotated answer sheet, also returns the name of this one.

sub pdf_output_filename {
  my ($self,$student)=@_;

  $self->needs_data;
  $self->needs_names;

  my $f=$self->{filename_model};

  debug "F[0]=$f";

  # computes student/copy four digits ID and substitutes (N) with it
  my $ex;
  if($student->[1]) {
    $ex=sprintf("%04d:%04d",@$student);
  } else {
    $ex=sprintf("%04d",$student->[0]);
  }
  $f =~ s/\(N\)/$ex/gi;

  debug "F[N]=".show_utf8($f);

  # get student data from the students list file, and substitutes
  # into filename
  if($self->{names}) {
    $self->{data}->begin_read_transaction('rAGN');
    my $i=$self->{association}->get_real(@$student);
    $self->{data}->end_transaction('rAGN');

    my $name='XXX';
    my $n;

    debug "Association -> ID=$i";

    if(defined($i)) {
      debug "Name found";
      ($n)=$self->{names}->data($self->{association_key},$i,test_numeric=>1);
      if($n) {
	$f=$self->{names}->substitute($n,$f);
      }
    }

    debug "F[n]=".show_utf8($f);

  } else {
    $f =~ s/-?\(ID\)//gi;
  }

  # Substitute all spaces and non-ascii characters from the file name
  # if the user asked so.

  if($self->{force_ascii}) {
    $f=string_to_filename($f,'copy');
    debug "F[a]=".show_utf8($f);
  }

  # The filename we would like to use id $f, but now we have to check
  # it is not already used for another annotated file... and register
  # it.

  $self->{data}->begin_transaction('rSST');

  # check if there is already an up-to-date annotated answer sheet for
  # this student BEFORE removing the entry from the database (and
  # recall this filename).

  my $uptodate_filename='';
  if($self->{changes_only}) {
    $uptodate_filename=$self->student_uptodate($student);
  }

  # delete the entry from the database, and build a filename that is
  # not already registered for another student (the same or similar to
  # $f).

  $self->{report}->delete_student_report($self->{type},@$student);
  $f=$self->{report}->free_student_report($self->{type},$f);
  $self->{report}->set_student_report($self->{type},@$student,$f,'now');

  $self->{data}->end_transaction('rSST');

  utf8::encode($f);

  debug "F[R]=".show_utf8($f);

  return($f,$uptodate_filename);
}

sub connects_to_database {
  my ($self)=@_;

  # Open connections to the SQLite databases that we will use.

  $self->{data}=AMC::Data->new($self->{data_dir});
  for my $m (qw/layout capture association scoring report/) {
    $self->{$m}=$self->{data}->module($m);
  }

  # If they are not already given by the user, read association_key
  # and darkness_threshold from the variables in the database.

  $self->{association_key}=$self->{association}->variable_transaction('key_in_list');
  $self->{darkness_threshold}=$self->{scoring}
    ->variable_transaction('darkness_threshold') if(!$self->{darkness_threshold});
  $self->{darkness_threshold_up}=$self->{scoring}
    ->variable_transaction('darkness_threshold_up') if(!$self->{darkness_threshold_up});

  # But darkness_threshold_up is not defined for old projects… set it
  # to an inactive value in this case

  $self->{darkness_threshold_up}=1.0 if(!$self->{darkness_threshold_up});
}

sub error {
  my ($self,$message)=@_;

  debug_and_stderr("**ERROR** $message");
}

sub needs_data {
  my ($self)=@_;

  if(!$self->{data}) {
    $self->connects_to_database;
  }
}

sub connects_students_list {
  my ($self)=@_;

  $self->needs_data();

  # If given, opens the students list and read it.

  if(-f $self->{names_file}) {
    $self->{names}=AMC::NamesFile::new($self->{names_file},
				       "encodage"=>$self->{names_encoding},
				       "identifiant"=>$self->{csv_build_name});

    debug "Keys in names file: ".join(", ",$self->{names}->heads());
  } else {
    debug "Names file not found: $self->{names_file}";
  }

  # Set up a AMC::Substitute object that will be used to substitute
  # marks, student name, and so on in the verdict strings for question
  # scores and global header.

  $self->{subst}=AMC::Substitute::new('names'=>$self->{names},
				      'scoring'=>$self->{scoring},
				      'assoc'=>$self->{association},
				      'name'=>'',
				      'chsign'=>$self->{significant_digits},
				     );
}

sub needs_names {
  my ($self)=@_;

  if(!$self->{subst}) {
    $self->connects_students_list;
  }
}

# get a sorted list of all students, using AMC::Export

sub compute_sorted_students_list {
  my ($self)=@_;

  if(!$self->{sorted_students}) {
    # Use AMC::Export that can do the work for us...

    my $sorted_students=AMC::Export->new();
    $sorted_students->set_options('fich',
				  'datadir'=>$self->{data_dir},
				  'noms'=>$self->{names_file});
    $sorted_students->set_options('noms',
				  'encodage'=>$self->{names_encoding},
				  'useall'=>0);
    $sorted_students->set_options('sort',
				  'keys'=>$self->{sort});
    $sorted_students->pre_process();

    $self->{sorted_students}=$sorted_students;
  }
}

# sort the students so that they are ordered as in the sorted_students
# list

sub sort_students {
  my ($self)=@_;

  $self->compute_sorted_students_list();
  my %include=map { studentids_string(@$_)=>1 } (@{$self->{students}});
  $self->{students}=[
		     map { [ $_->{'student'},$_->{'copy'} ] }
		     grep { $include{studentids_string($_->{'student'},$_->{'copy'})} }
		     (@{$self->{sorted_students}->{'marks'}})
		    ];

}

# get the students to process from a file and return the number of
# students

sub get_students_from_file {
  my ($self)=@_;
  my @students;

  # loads a list of students from a plain text file (one per line)
  if(-f $self->{id_file}) {
    my @students;
    open(NUMS,$self->{id_file});
    while(<NUMS>) {
      if(/^([0-9]+):([0-9]+)$/) {
	push @students,[$1,$2];
      } elsif(/^([0-9]+)$/) {
	push @students,[$1,0];
      }
    }
    close(NUMS);

    $self->{students}=\@students;
    return(1+$#students);
  } else {
    return(0);
  }
}

# get the students to process from capture data (all students that
# have some data capture -- scan or manual -- on at least one page)

sub get_students_from_data {
  my ($self)=@_;

  $self->needs_data;

  $self->{capture}->begin_read_transaction('gast');
  $self->{students}=$self->{capture}->dbh
    ->selectall_arrayref($self->{capture}->statement('studentCopies'));
  $self->{capture}->end_transaction('gast');

  return(1+$#{$self->{students}});
}

# get the students to process

sub get_students {
  my ($self)=@_;

  my $n=$self->get_students_from_file ||
    $self->get_students_from_data;

  # sort this list if we are going to make an unique annotated
  # file with all the students' copies (and if a sort key is given)
  if($n>1 && $self->{single_output} && $self->{sort}) {
    $self->sort_students();
  }

  debug "Number of students to process: $n";

  return($n);
}

# get dimensions of a subject page

sub get_dimensions {
  my ($self)=@_;

  $self->needs_data;

  # get width, height and DPI from a subject page (these values should
  # be the same for all pages).

  $self->{data}->begin_read_transaction("aDIM");

  ($self->{width},$self->{height},undef,$self->{dpi})
    =$self->{layout}->dims($self->{layout}->random_studentPage);

  $self->{data}->end_transaction("aDIM");

  # Now, convert all dist_* lenghts to a number of points.

  if(!$self->{unit_pixels}) {
    for my $dd (map { \$self->{'dist_'.$_} }
		(qw/to_box margin margin_globaltext/)) {
      $$dd=dim2in($$dd);
    }
    $self->{unit_pixels}=1;
  }
}

sub needs_dims {
  my ($self)=@_;

  if(!$self->{dpi}) {
    $self->get_dimensions;
  }
}

# subprocess (call to AMC-buildpdf) initialisation

sub process_start {
  my ($self)=@_;

  $self->needs_dims;

  $self->{process}=AMC::Subprocess::new(mode=>'buildpdf');
  $self->{process}->set('args',
			['-d',$self->{dpi},
			 '-w',$self->{width},
			 '-h',$self->{height}]);
  $self->command("embedded ".$self->{embedded_format});
  if($self->{embedded_max_size} =~ /([0-9]*)x([0-9]*)/i) {
    my $width=$1;
    my $height=$2;
    $self->command("max width ".($width ? $width : 0));
    $self->command("max height ".($height ? $height : 0));
  }
  $self->command("jpeg quality ".$self->{embedded_jpeg_quality});
  $self->command("margin ".$self->{dist_margin});
  $self->command("debug") if($self->{debug});
}

# send a command to the subprocess

sub command {
  my ($self,@command)=@_;
  $self->{process}->commande(@command);
}

# Sends a (maybe multi-line) text to AMC-buildpdf to be used in the
# following command.

sub stext {
  my ($self,$text)=@_;
  utf8::encode($text);
  $self->command("stext begin\n$text\n__END__");
}

# gets RGB values (from 0.0 to 1.0) from color text description

sub color_rgb {
  my ($s)=@_;
  my $col=Gtk3::Gdk::Color::parse($s);
  if($col) {
    return($col->red/65535,$col->green/65535,$col->blue/65535);
  } else {
    debug "Color parse error: $col";
    return(.5,.5,.5);
  }
}

# set color for drawing

sub set_color {
  my ($self,$color_string)=@_;
  $self->command(join(' ',
		      "color",
		      color_rgb($color_string)));
}

# inserts a page from a pdf file

sub insert_pdf_page {
  my ($self,$pdf_path,$page)=@_;

  if($pdf_path ne $self->{loaded_pdf}) {
    # If this PDF file is not already loaded by AMC-buildpdf, load it.
    $self->command("load pdf $pdf_path");
    $self->{loaded_pdf}=$pdf_path;
  }
  $self->command("page pdf $page");
}

# get a list of pages for a particular student

sub student_pages {
  my ($self,$student)=@_;
  return($self->{layout}->pages_info_for_student($student->[0],enter_tag=>1));
}

# Inserts the background for an annotated page. Returns:
#
# -1 if no page were inserted (without compose option, or when the
# page from the subject is not available)
#
# 0 if a scan is used
#
# 1 if a subject page with no answer boxes is used
#
# 2 if a subject page with answer boxes is used

sub page_background {
  my ($self,$student,$page)=@_;

  # First get the scan, if available...

  my $page_capture=$self->{capture}->get_page($student->[0],$page->{page},$student->[1])
    || {};
  my $scan='';

  $scan=$self->absolute_path($page_capture->{src})
    if($page_capture->{src});

  if(-f $scan) {
    # If the scan is available, use it (with AMC-buildpdf "page png"
    # or "page img" command, depending on the file type). The matrix
    # that transforms coordinates from subject to scan has been
    # computed when automatic data capture was made. It is sent to
    # AMC-buildpdf.

    my $img_type='img';
    if(AMC::Basic::file_mimetype($scan) eq 'image/png') {
      $img_type='png';
    }
    $self->command("page $img_type $scan");
    $self->command(join(' ',
			"matrix",map { $page_capture->{$_} } (qw/a b c d e f/)));

    return(0);
  } else {
    if($scan) {
      debug "WARNING: Registered scan \"$scan\" was not found.";
    }
    # If there is no scan,
    if($page->{enter} && -f $self->{pdf_subject}) {

      # If the page contains something to be filled by the student
      # (either name field or boxes), inserts the page from the PDF
      # subject.

      debug "Using subject page.";
      $self->insert_pdf_page($self->{pdf_subject},$page->{subjectpage});
      $self->command("matrix identity");

      return(2);
    } else {
      if(!$page->{enter}) {
	debug "Page without fields.";
      }

      # With <compose> option, pages without anything to be filled
      # (only subject) are added, from the corrected PDF if available
      # (then the student will see the correct answers easily on the
      # annotated answer sheet).

      if(-f $self->{pdf_background}) {
	$self->insert_pdf_page($self->{pdf_background},$page->{subjectpage});
	return(1);
      }
    }
    return(-1);
  }
}

# draws one symbol. $b is one row from the capture:pageZones SQL query
# (from which we use only the id_a=question, id_b=answer and role
# attributes). When $tick is true, boxes are tickedas the student did
# (this can be usefull for manual data capture for example, when the
# background is not the scan but the PDF subject, and we want to
# illustrate which boxes has been ticked by the student).

sub draw_symbol {
  my ($self,$student,$b,$tick)=@_;

  my $p_strategy=$self->{scoring}->unalias($student->[0]);
  my $q=$b->{'id_a'}; # question number
  my $r=$b->{'id_b'}; # answer number
  my $indic=$self->{scoring}->indicative($p_strategy,$q); # is it an indicative question?

  # ticked on this scan?
  my $cochee=$self->{capture}->ticked(@$student,
				      $q,$r,
				      $self->{darkness_threshold},
				      $self->{darkness_threshold_up});

  # get box position on subject
  my $box=$self->{layout}->get_box_info($student->[0],$q,$r,$b->{role});

  # when the subject background is used instead of the scan, darken
  # boxes that have been ticked by the student
  if($tick && $cochee) {
    debug "Tick.";
    $self->set_color('black');
    $self->command(join(' ',($self->{darkness_threshold_up}<1 ? 'mark' : 'fill'),
			map { $box->{$_} } (qw/xmin xmax ymin ymax/)
		       ));
  }

  return if($indic && !$self->{annotate_indicatives});

  # to be ticked?
  my $bonne=$self->{scoring}->correct_answer($p_strategy,$q,$r);

  debug "Q=$q R=$r $bonne-$cochee";

  # get symbol to draw
  my $sy=$self->{symbols}->{"$bonne-$cochee"};

  if ($box->{flags}
      & BOX_FLAGS_DONTANNOTATE) {
    debug "This box is flagged \"don't annotate\": skipping";
  } else {
    if ($sy->{type} =~ /^(circle|mark|box)$/) {
      # tells AMC-buildpdf to draw the symbol with the right color
      $self->set_color($sy->{color});
      $self->command(join(' ',$sy->{type},
			  map { $box->{$_} } (qw/xmin xmax ymin ymax/)
			 ));
    } elsif ($sy->{type} eq 'none') {
    } else {
      debug "Unknown symbol type ($bonne-$cochee): $sy->{type}";
    }
  }

  # records box position so that question scores can be
  # well-positioned

  $self->{question}->{$q}={} if(!$self->{question}->{$q});
  push @{$self->{question}->{$q}->{'x'}},($box->{xmin}+$box->{xmax})/2;
  push @{$self->{question}->{$q}->{'y'}},($box->{ymin}+$box->{ymax})/2;
}

# draws symbols on one page

sub page_symbols {
  my ($self,$student,$page,$tick)=@_;

  # clears boxes positions data for the page

  $self->{question}={};

  # goes through all the boxes on the page

  # the question boxes (in separate answer sheet mode)
  if($self->{compose}==1) {
    my $sth=$self->{layout}->statement('pageQuestionBoxes');
    $sth->execute($student->[0],$page);
    while(my $box=$sth->fetchrow_hashref) {
      $self->draw_symbol($student,$box,1);
    }
  }

  # the answer boxes that were captured
  my $sth=$self->{capture}->statement('pageZones');
  $sth->execute($student->[0],$page,$student->[1],ZONE_BOX);
  while(my $box=$sth->fetchrow_hashref) {
    $self->draw_symbol($student,$box,$tick);
  }
}

# computes the score text for a particular question

sub qtext {
  my ($self,$student,$question)=@_;

  my $result=$self->{scoring}->question_result(@$student,$question);

  my $text;

  # begins with the right verdict version depending on if the question
  # result was cancelled or not.

  if ($result->{'why'} =~ /c/i) {
    $text=$self->{verdict_question_cancelled};
  } else {
    $text=$self->{verdict_question};
  }

  # substitute scores values

  $text =~ s/\%[S]/$result->{'score'}/g;
  $text =~ s/\%[M]/$result->{'max'}/g;
  $text =~ s/\%[W]/$result->{'why'}/g;
  $text =~ s/\%[s]/$self->{subst}->format_note($result->{'score'})/ge;
  $text =~ s/\%[m]/$self->{subst}->format_note($result->{'max'})/ge;

  # evaluates the result

  my $te=eval($text);
  if ($@) {
    debug "Annotation: $text";
    debug "Evaluation error $@";
  } else {
    $text=$te;
  }

  return($text);
}

# mean of the y positions of the boxes for one question

sub q_ymean {
  my ($self,$q)=@_;

  return(sum(@{$self->{question}->{$q}->{'y'}})/(1+$#{$self->{question}->{$q}->{'y'}}));
}


# where to write question status?

# 1) scores written in the left margin
sub qtext_position_marge {
  my ($self,$student,$page,$question)=@_;

  my $y=$self->q_ymean($question);

  if ($self->{rtl}) {
    return("stext margin 1 $y 1 0.5");
  } else {
    return("stext margin 0 $y 0 0.5");
  }
}

# 2) scores written in one of the margins (left or right), depending
# on the position of the boxes. This mode is often used when the
# subject is in a 2-column layout.
sub qtext_position_marges {
  my ($self,$student,$page,$q)=@_;

  # fist extract the y coordinates of the boxes in the left column
  my $left=1;
  my @y=map { $self->{question}->{$q}->{'y'}->[$_] }
    grep { $self->{rtl} xor ( $self->{question}->{$q}->{'x'}->[$_] <= $self->{width}/2 ) }
      (0..$#{$self->{question}->{$q}->{'x'}} );
  if (!@y) {
    # if empty, use the right column
    $left=0;
    @y=map { $self->{question}->{$q}->{'y'}->[$_] } 
      grep { $self->{rtl} xor ( $self->{question}->{$q}->{'x'}->[$_] > $self->{width}/2 ) }
	(0..$#{$self->{question}->{$q}->{'x'}} );
  }

  # set the x-position to the left or right margin
  my $jx=1;
  $jx=0 if($left xor $self->{rtl});

  # set the y-position to the mean of y coordinates of the
  # boxes in the corresponding column
  my $y=sum(@y)/(1+$#y);

  return("stext margin $jx $y $jx 0.5");
}

# 3) scores written at the side of all the boxes
sub qtext_position_case {
  my ($self,$student,$page,$q)=@_;

  my $x=max(@{$self->{question}->{$q}->{'x'}})
    + ($self->{rtl} ? 1: -1)*$self->{dist_to_box}*$self->{dpi};
  my $y=$self->q_ymean($q);
  return("stext $x $y 0 0.5");
}

# 4) scores written in the zone defined by the source file
sub qtext_position_zones {
  my ($self,$student,$page,$q)=@_;
  my @c=();
  for my $b ($self->{layout}->score_zones($student->[0],$page,$q)) {
    push @c,"stext rectangle ".
      join(" ",map { $b->{$_} } (qw/xmin xmax ymin ymax/));
  }
  return(\@c);
}

# writes one question score

sub write_qscore {
  my ($self,$student,$page,$question)=@_;

  return if($self->{position} eq 'none');

  # no score to write for indicative questions
  if($self->{scoring}->indicative($p_strategy,$q)) {
    debug "Indicative question: no score to write";
    return;
  }

  my $text=$self->qtext($student,$question);
  my $xy="qtext_position_".$self->{position};
  my $command=$self->$xy($student,$page,$question);
  if(ref($command) eq 'ARRAY') {
    if($#$command>=0) {
      $self->stext($text);
      for my $c (@$command) {
	$self->command($c) if($c);
      }
    }
  } elsif($command) {
    $self->stext($text);
    $self->command($command);
  }
}

# writes question scores on one page

sub page_qscores {
  my ($self,$student,$page)=@_;

  if ($self->{position} ne 'none') {

    $self->needs_names;

    $self->set_color($self->{text_color});

    # go through all questions present on the page (recorded while
    # drawing symbols)
    for my $q (sort { $a cmp $b } (keys %{$self->{question}})) {
      $self->write_qscore($student,$page,$q);
    }

  }
}

# draws the page header (only on the first page)

sub page_header {
  my ($self,$student)=@_;

  if(!$self->{header_drawn}) {

    $self->needs_names;

    $self->set_color($self->{text_color});
    $self->command("matrix identity");
    $self->stext($self->{subst}->substitute($self->{verdict},@$student));
    $self->command("stext "
		   .($self->{rtl} ?
		     $self->{width}-$self->{dist_margin_globaltext}*$self->{dpi}
		     :$self->{dist_margin_globaltext}*$self->{dpi})
		   ." ".($self->{dist_margin_globaltext}*$self->{dpi})." "
		   .($self->{rtl}?"1.0":"0.0")." 0.0");

    $self->{header_drawn}=1;

  }
}

# annotate a single page

sub student_draw_page {
  my ($self,$student,$page)=@_;

  debug "Processing page $student->[0]:$student->[1] page $page->{page} ...";

  my $draw=$self->page_background($student,$page);
  if($draw >= 0) {
    $self->command("line width $self->{line_width}");
    $self->command("font name $self->{font_name}");
    $self->page_symbols($student,$page->{page},$draw>0);
    $self->page_qscores($student,$page->{page});
    $self->command("matrix identity");
    $self->page_header($student);
  } else {
    debug "Nothing to draw for this page";
  }
}

# process a student copy

sub process_student {
  my ($self,$student)=@_;

  debug "Processing student $student->[0]:$student->[1]";

  # Computes the filename to use, and check that there is no
  # up-to-date version of the annotated answer sheet (if so, simply
  # keep or rename the file).

  if(!$self->{single_output}) {
    my ($f,$f_ok)=$self->pdf_output_filename($student);
    debug "Directory ".show_utf8($self->{pdf_dir});
    debug "Dest file ".show_utf8($f);
    debug "Existing  ".show_utf8($f_ok);
    my $path=$self->{pdf_dir}."/$f";
    if($f_ok ne '') {
      # we only need to move the file!
      debug "The file is up-to-date";
      if($f ne $f_ok) {
        debug "... but has to be moved: $f_ok --> $f";
        my $path_ok=$self->{pdf_dir}."/$f_ok";
	move($path_ok,$path)
	  || debug "ERROR: moving the annotated file in directory $self->{pdf_dir} from $f_ok to $f";
      }
      return();
    }
    $self->command("output $path");
  }

  # Go through all the pages for the student.

  $self->{data}->begin_read_transaction('aOST');

  $self->{header_drawn}=0;
  for my $page ($self->student_pages($student)) {
    $self->student_draw_page($student,$page);
  }

  $self->{data}->end_transaction('aOST');
}

# All processing

sub go {
  my ($self)=@_;

  my $n=$self->get_students();

  debug "STUDENTS TO PROCESS: $n\n";

  if($n>0) {
    $self->process_start;

    # With option <single_output>, all annotated answer sheets are
    # made in a single PDF file. We open this file.

    $self->command("output ".$self->{pdf_dir}."/".$self->{single_output})
      if($self->{single_output});

    # Loop over students...

    for my $student (@{$self->{students}}) {
      $self->process_student($student);
      $self->{avance}->progres(1/$n) if($self->{avance});
    }
  }
}

# quit!

sub quit {
  my ($self)=@_;

  $self->{process}->ferme_commande if($self->{process});
  $self->{avance}->fin() if($self->{avance});
}

1;
