#! /usr/bin/perl
#
# Copyright (C) 2013-2016 Alexis Bienvenue <paamc@passoire.fr>
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

use AMC::Basic;
use AMC::Annotate;
use AMC::Exec;

my $single_output='';
my $sort='';
my $filename_model='(N)-(ID)';
my $force_ascii=0;

my $pdf_subject='';
my $pdf_corrected='';
my $pdf_dir='';
my $cr_dir="";
my $project_dir='';
my $projects_dir='';

my $id_file='';

my $darkness_threshold='';
my $darkness_threshold_up='';

my $data_dir='';

my $debug='';

my $progress=1;
my $progress_id='';

my $text_color='red';
my $line_width=2;
my $font_name='Linux Libertine O 12';
my @o_symbols=();
my $annotate_indicatives='';
my $position='marges';
my $dist_to_box='1cm';
my $dist_margin='5mm';
my $dist_margin_globaltext='3mm';

my $significant_digits=4;

my $verdict='TOTAL : %S/%M => %s/%m';
my $verdict_question_cancelled='"X"';
my $verdict_question="\"%"."s/%"."m\"";

my $rtl='';

my $names_file='';
my $names_encoding='utf-8';
my $association_key='',
my $csv_build_name='';

my $embedded_max_size="";
my $embedded_jpeg_quality=80;
my $embedded_format="jpeg";

my $changes_only='';

my $compose='';
my $moteur_latex='pdflatex';
my $src_file='';
my $filter='';
my $filtered_source='';
my $n_copies=0;

# key is "to be ticked"-"ticked"
my %symboles=(
    '0-0'=>{qw/type none/},
    '0-1'=>{qw/type circle color red/},
    '1-0'=>{qw/type mark color red/},
    '1-1'=>{qw/type mark color blue/},
);

@ARGV=unpack_args(@ARGV);

GetOptions("cr=s"=>\$cr_dir,
	   "project=s",\$project_dir,
	   "projects-dir=s",\$projects_dir,
	   "data=s"=>\$data_dir,
	   "subject=s"=>\$pdf_subject,
	   "pdf-dir=s"=>\$pdf_dir,
	   "darkness-threshold=s"=>\$darkness_threshold,
	   "darkness-threshold-up=s"=>\$darkness_threshold_up,
	   "filename-model=s"=>\$filename_model,
	   "force-ascii!"=>\$force_ascii,
	   "single-output=s"=>\$single_output,
	   "sort=s"=>\$sort,
	   "id-file=s"=>\$id_file,
	   "debug=s"=>\$debug,
	   "progression=s"=>\$progress,
	   "progression-id=s"=>\$progress_id,
	   "line-width=s"=>\$line_width,
	   "font-name=s"=>\$font_name,
	   "text-color=s"=>\$text_color,
	   "symbols=s"=>\@o_symbols,
	   "indicatives!"=>\$annotate_indicatives,
	   "position=s"=>\$position,
	   "dist-to-box=s"=>\$dist_to_box,
	   "dist-margin=s"=>\$dist_margin,
	   "dist-margin-global=s"=>\$dist_margin_globaltext,
	   "n-digits=s"=>\$significant_digits,
	   "verdict=s"=>\$verdict,
	   "verdict-question=s"=>\$verdict_question,
	   "verdict-question-cancelled=s"=>\$verdict_question_cancelled,
	   "names-file=s"=>\$names_file,
	   "names-encoding=s"=>\$names_encoding,
	   "association-key=s"=>\$association_key,
	   "csv-build-name=s"=>\$csv_build_name,
	   "rtl!"=>\$rtl,
	   "changes-only!"=>\$changes_only,
	   "sort=s"=>\$sort,
	   "compose=s"=>\$compose,
	   "corrected=s"=>\$pdf_corrected,
	   "n-copies=s"=>\$n_copies,
	   "src=s"=>\$src_file,
	   "with=s"=>\$latex_engine,
	   "filter=s"=>\$filter,
	   "filtered-source=s"=>\$filtered_source,
	   "embedded-max-size=s"=>\$embedded_max_size,
	   "embedded-format=s"=>\$embedded_format,
	   "embedded-jpeg-quality=s"=>\$embedded_jpeg_quality,
	   );

set_debug($debug);

for(split(/,/,join(',',@o_symbols))) {
    if(/^([01]-[01]):(none|circle|mark|box)(?:[\/:]([\#a-z0-9]+))?$/) {
	$symboles{$1}={type=>$2,color=>$3};
    } else {
	die "Bad symbol syntax: $_";
    }
}

# try to set sensible values when these directories are not set by the
# user:

$projects_dir=$ENV{'HOME'}.'/'.__("MC-Projects") if(!$projects_dir);
$project_dir=$projects_dir.'/'.$project_dir if($project_dir !~ /\//);
$pdf_subject="DOC-sujet.pdf" if(!$pdf_subject);
$pdf_subject=$project_dir.'/'.$pdf_subject if($pdf_subject !~ /\//);
$pdf_corrected="DOC-indiv-solution.pdf" if(!$pdf_corrected);
$pdf_corrected=$project_dir.'/'.$pdf_corrected if($pdf_corrected !~ /\//);

$cr_dir=$project_dir."/cr" if(! $cr_dir);
$data_dir=$project_dir."/data" if(! $data_dir);
$pdf_dir=$cr_dir."/corrections/pdf" if(! $pdf_dir);

# single output should be a file name, not a path

$single_output =~ s:.*/::;

# We need a destination directory!

if(! -d $pdf_dir) {
    attention("No PDF directory: $pdf_dir");
    die "No PDF directory: $pdf_dir";
}

my $commandes=AMC::Exec::new('AMC-annotate');
$commandes->signalise();

# prepare the corrected answer sheet for all students. This file is
# used when option --compose is 2, to take sheets when there are no
# answer boxes on it. This can be very useful to produce a complete
# annotated answer sheet with subject *and* answers when separate
# answer sheet layout is used.

if($compose==2) {
  if(! -f $pdf_corrected) {

    debug "Building individual corrected sheet...";
    print "Building individual corrected sheet...\n";

    $commandes->execute("auto-multiple-choice","prepare",
			pack_args("--n-copies",$n_copies,
				  "--with",$latex_engine,
				  "--filter",$filter,
				  "--filtered-source",$filtered_source,
				  "--mode","k",
				  "--out-corrige-indiv",$pdf_corrected,
				  "--debug",debug_file(),
				  $src_file));
  }
}

my $annotate
  =AMC::Annotate::new(data_dir=>$data_dir,
		      project_dir=>$project_dir,
		      projects_dir=>$projects_dir,
		      pdf_dir=>$pdf_dir,
		      single_output=>$single_output,
		      filename_model=>$filename_model,
		      force_ascii=>$force_ascii,
		      pdf_subject=>$pdf_subject,
		      names_file=>$names_file,
		      names_encoding=>$names_encoding,
		      association_key=>$association_key,
		      csv_build_name=>$csv_buildname,
		      significant_digits=>$significant_digits,
		      darkness_threshold=>$darkness_threshold,
		      darkness_threshold_up=>$darkness_threshold_up,
		      id_file=>$id_file,
		      sort=>$sort,
		      annotate_indicatives=>$annotate_indicatives,
		      position=>$position,
		      text_color=>$text_color,
		      line_width=>$line_width,
		      font_name=>$font_name,
		      dist_to_box=>$dist_to_box,
		      dist_margin=>$dist_margin,
		      dist_margin_globaltext=>$dist_margin_globaltext,
		      symbols=>\%symboles,
		      verdict=>$verdict,
		      verdict_question=>$verdict_question,
		      verdict_question_cancelled=>$verdict_question_cancelled,
		      progress=>$progress,
		      progress_id=>$progress_id,
		      compose=>$compose,
		      pdf_corrected=>$pdf_corrected,
		      changes_only=>$changes_only,
		      embedded_max_size=>$embedded_max_size,
		      embedded_format=>$embedded_format,
		      embedded_jpeg_quality=>$embedded_jpeg_quality,
		     );

$annotate->go();
$annotate->quit();

