#! /usr/bin/perl -w
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

package AMC::Test;

use AMC::Basic;
use AMC::Data;
use AMC::DataModule::capture qw(:zone);
use AMC::DataModule::scoring qw(:question);
use AMC::Scoring;
use AMC::NamesFile;

use Text::CSV;
use File::Spec::Functions qw(tmpdir);
use File::Temp qw(tempfile tempdir);
use File::Copy;
use Digest::MD5;

use Data::Dumper;

use DBI;

use IPC::Run qw(run);

use Getopt::Long;

use_gettext;

sub new {
  my ($class,%oo)=@_;

  my $self=
    {
     'dir'=>'',
     'filter'=>'',
     'tex_engine'=>'pdflatex',
     'multiple'=>'',
     'pre_allocate'=>0,
     'n_copies'=>5,
     'check_marks'=>'',
     'perfect_copy'=>[3],
     'src'=>'',
     'debug'=>0,
     'debug_pixels'=>0,
     'scans'=>'',
     'seuil'=>0.5,
     'seuil_up'=>1.0,
     'bw_threshold'=>0.6,
     'ignore_red'=>'',
     'tol_marque'=>0.4,
     'rounding'=>'i',
     'grain'=>0.01,
     'notemax'=>20,
     'postcorrect_student'=>'',
     'postcorrect_copy'=>'',
     'list'=>'',
     'list_key'=>'id',
     'code'=>'student',
     'check_assoc'=>'',
     'association_manual'=>'',
     'annote'=>'',
     'annote_files'=>[],
     'annote_ascii'=>0,
     'annote_position'=>'marge',
     'verdict'=>'%(id) %(ID)'."\n".'TOTAL : %S/%M => %s/%m',
     'verdict_question'=>"\"%"."s/%"."m\"",
     'model'=>'(N).pdf',
     'ok_checksums'=>{},
     'ok_checksums_file'=>'',
     'to_check'=>[],
     'export_full_csv'=>[],
     'export_csv_ticked'=>'AB',
     'export_ods'=>'',
     'blind'=>0,
     'check_zooms'=>{},
     'skip_prepare'=>0,
     'skip_scans'=>0,
     'tracedest'=>'STDERR',
     'debug_file'=>'',
     'pages'=>'',
     'extract_with'=>'qpdf',
     'force_convert'=>0,
     'documents'=>'sc',
    };

  for (keys %oo) {
    $self->{$_}=$oo{$_} if(exists($self->{$_}));
  }

  $self->{'dir'} =~ s:/[^/]*$::;

  bless($self,$class);

  if (!$self->{'src'}) {
    opendir(my $dh, $self->{'dir'})
      || die "can't opendir $self->{'dir'}: $!";
    my @tex = grep { /\.(tex|txt)$/ } sort { $a cmp $b } readdir($dh);
    closedir $dh;
    $self->{'src'}=$tex[0];
  }

  if (!$self->{'list'}) {
    opendir(my $dh, $self->{'dir'})
      || die "can't opendir $self->{'dir'}: $!";
    my @l = grep { /\.(csv|txt)$/ } readdir($dh);
    closedir $dh;
    $self->{'list'}=$l[0];
  }
  $self->{names}=AMC::NamesFile::new($self->{'dir'}.'/'.$self->{list},'utf8','id')
    if(-f $self->{'dir'}.'/'.$self->{list});

  my $to_stdout=0;

  GetOptions("debug!"=>\$self->{'debug'},
             "blind!"=>\$self->{'blind'},
             "log-to=s"=>\$self->{debug_file},
             "to-stdout!"=>\$to_stdout,
             "extract-with=s"=>\$self->{extract_with},
            );

  $self->{tracedest} = 'STDOUT' if($to_stdout);
  binmode $self->{tracedest}, ":utf8";

  $self->install;

  $self->{'check_dir'}=tmpdir()."/AMC-VISUAL-TEST";
  mkdir($self->{'check_dir'}) if(!-d $self->{'check_dir'});

  $self->read_checksums($self->{'ok_checksums_file'});
  $self->read_checksums($self->{'dir'}.'/ok-checksums');

  return $self;
}

sub set {
  my ($self,%oo)=@_;

  for (keys %oo) {
    $self->{$_}=$oo{$_} if(exists($self->{$_}));
  }
}

sub read_checksums {
  my ($self,$file)=@_;

  if (-f $file) {
    my $n=0;
    open CSF,$file or die "Error opening $file: $!";
    while (<CSF>) {
      if (/^\s*([a-f0-9]+)\s/) {
	$self->{'ok_checksums'}->{$1}=1;
	$n++;
      }
    }
    close CSF;
    $self->trace("[I] $n checksums read from $file");
  }

}

sub install {
  my ($self)=@_;

  my $temp_loc=tmpdir();
  $self->{'temp_dir'} = tempdir( DIR=>$temp_loc,
				 CLEANUP => (!$self->{'debug'}) );

  opendir(my $sh,$self->{'dir'})
    || die "can't opendir $self->{dir}: $!";
  for my $f (grep { ! /^\./ } (readdir($sh))) {
    system("cp","-r",$self->{'dir'}.'/'.$f,$self->{'temp_dir'});
  }
  closedir $sh;

  print { $self->{tracedest} } "[>] Installed in $self->{'temp_dir'}\n";

  if(-d ($self->{'temp_dir'}."/scans") && !$self->{'scans'}) {
    opendir(my $dh, $self->{'temp_dir'}."/scans")
      || die "can't opendir $self->{'temp_dir'}: $!";
    my @s = grep { ! /^\./ } readdir($dh);
    closedir $dh;

    if(@s) {
      $self->trace("[I] Provided scans: ".(1+$#s));
      $self->{'scans'}=[map { $self->{'temp_dir'}."/scans/$_" } sort { $a cmp $b } @s];
    }
  }

  for my $d (qw(data cr cr/corrections cr/corrections/jpg cr/corrections/pdf scans)) {
    mkdir($self->{'temp_dir'}."/$d") if(!-d $self->{'temp_dir'}."/$d");
  }

  $self->{'debug_file'}=$self->{'temp_dir'}."/debug.log"
    if(!$self->{'debug_file'});
  open(DB,">",$self->{'debug_file'});
  print DB "Test\n";
  close(DB);
}

sub see_blob {
  my ($self,$name,$blob)=@_;
  my $path=$self->{'temp_dir'}.'/'.$name;
  open FILE,">$path";
  binmode(FILE);
  print FILE $blob;
  close FILE;
  $self->see_file($path);
}

sub see_file {
  my ($self,$file)=@_;
  my $ext=$file;
  $ext =~ s/.*\.//;
  $ext=lc($ext);
  my $digest=Digest::MD5->new;
  open(FILE,$file) or die "Can't open '$file': $!";
  while(<FILE>) {
    if($ext eq 'pdf') {
      s:^/Producer \(.*\)::;
      s:^/CreationDate \(.*\)::;
      s:^/ModDate \(.*\)::;
    }
    $digest->add($_);
  }
  close FILE;
  my $dig=$digest->hexdigest;
  my $ff=$file;
  $ff =~ s:.*/::;
  if($self->{'ok_checksums'}->{$dig}) {
    $self->trace("[T] File ok (checksum): $ff");
  } else {
    # compares with already validated file
    my $validated=$self->{'temp_dir'}."/checked/$ff";
    if(-f $validated && $ff =~ /\.pdf$/i) {
      if(run('comparepdf','-ca','-v0',$validated,$file)) {
	$self->trace("[T] File ok (compare): $ff");
      } else {
	$self->trace("[E] File different (compare): $ff");
	exit(1) if(!$self->{blind});
      }
    } else {
      my $i=0;
      my $dest;
      do {
	$dest=sprintf("%s/%04d-%s",$self->{'check_dir'},$i,$ff);
	$i++;
      } while(-f $dest);
      copy($file,$dest);
      push @{$self->{'to_check'}},[$dig,$dest];
    }
  }
}

sub trace {
  my ($self,@m)=@_;
  print { $self->{tracedest} } join(' ',@m)."\n";
  open LOG,">>:utf8",$self->{'debug_file'};
  print LOG join(' ',@m)."\n";
  close LOG;
}

sub command {
  my ($self,@c)=@_;

  $self->trace("[*] ".join(' ',@c)) if($self->{'debug'});
  if(!run(\@c,'>>',$self->{'debug_file'},'2>>',$self->{'debug_file'})) {
    my $cc=$c[0];
    $cc.=" ".$c[1] if($#c>0);
    $cc.=" ..." if($#c>1);
    $self->trace("[E] Command `$cc' returned with $?");
    exit 1;
  }
}

sub amc_command {
  my ($self,$sub,@opts)=@_;

  push @opts,'--debug','%PROJ/debug.log' if($self->{'debug'});
  @opts=map { s:%DATA:$self->{'temp_dir'}/data:g;
	      s:%PROJ:$self->{'temp_dir'}:g;
	      $_;
	    } @opts;

  $self->command('auto-multiple-choice',$sub,@opts);
}

sub prepare {
  my ($self)=@_;

  $self->amc_command('prepare',
		     '--filter',$self->{'filter'},
		     '--with',$self->{'tex_engine'},
		     '--mode','s['.$self->{documents}.']',
                     '--epoch',946684800,
		     '--n-copies',$self->{'n_copies'},
		     '--prefix',$self->{'temp_dir'}.'/',
		     '%PROJ/'.$self->{'src'},
		     '--data','%DATA',
		    );
  $self->amc_command('meptex',
		     '--src','%PROJ/calage.xy',
		     '--data','%DATA',
		    );
  $self->amc_command('prepare',
		     '--filter',$self->{'filter'},
		     '--with',$self->{'tex_engine'},
		     '--mode','b',
		     '--n-copies',$self->{'n_copies'},
		     '--data','%DATA',
		     '%PROJ/'.$self->{'src'},
		    );
}

sub analyse {
  my ($self)=@_;

  if($self->{'perfect_copy'}) {
    $self->amc_command('prepare',
		       '--filter',$self->{'filter'},
		       '--with',$self->{'tex_engine'},
		       '--mode','k',
                       '--epoch',946684800,
		       '--n-copies',$self->{'n_copies'},
		       '--prefix','%PROJ/',
		       '%PROJ/'.$self->{'src'},
		      );

    my $nf=$self->{'temp_dir'}."/num";
    open(NUMS,">$nf");
    for (@{$self->{'perfect_copy'}}) { print NUMS "$_\n"; }
    close(NUMS);
    $self->amc_command('imprime',
		       '--sujet','%PROJ/corrige.pdf',
		       '--methode','file',
		       '--output','%PROJ/xx-copie-%e.pdf',
		       '--fich-numeros',$nf,
		       '--data','%DATA',
                       '--extract-with',$self->{'extract_with'},
		      );

    opendir(my $dh, $self->{'temp_dir'})
      || die "can't opendir $self->{'temp_dir'}: $!";
    my @s = grep { /^xx-copie-/ } readdir($dh);
    closedir $dh;
    push @{$self->{'scans'}},map { $self->{'temp_dir'}."/$_" } @s;
  }

  # prepares a file with the scans list

  my $scans_list=$self->{'temp_dir'}."/scans-list.txt";
  open(SL,">",$scans_list) or die "Open $scans_list: $!";
  for(@{$self->{'scans'}}) { print SL "$_\n"; }
  close(SL);

  #

  $self->amc_command('read-pdfform',
		     '--list',$scans_list,
		     '--data','%DATA',
		     ($self->{'multiple'} ? '--multiple' : '--no-multiple'),
                    );

  my @extract_opts=();
  if($self->{extract_with} =~ /^pdftk/) {
    push @extract_opts, '--no-use-qpdf';
  } elsif($self->{extract_with} eq 'qpdf') {
    push @extract_opts, '--no-use-pdftk';
  }
  $self->amc_command('getimages',
		     '--list',$scans_list,
		     '--copy-to',$self->{'temp_dir'}."/scans",
		     '--orientation',$self->get_orientation(),
                     ($self->{force_convert} ? "--force-convert" : "--no-force-convert"),
                     @extract_opts,
		     );

  $self->amc_command('analyse',
		     ($self->{'multiple'} ? '--multiple' : '--no-multiple'),
		     '--bw-threshold',$self->{'bw_threshold'},
		     '--pre-allocate',$self->{'pre_allocate'},
		     '--tol-marque',$self->{'tol_marque'},
                     ($self->{ignore_red} ? '--ignore-red' : '--no-ignore-red'),
		     '--projet','%PROJ',
		     '--data','%DATA',
		     '--debug-image-dir','%PROJ/cr',
		     '--liste-fichiers',$scans_list,
		     ) if($self->{'debug'});
  $self->amc_command('analyse',
		     ($self->{'multiple'} ? '--multiple' : '--no-multiple'),
		     '--bw-threshold',$self->{'bw_threshold'},
		     '--pre-allocate',$self->{'pre_allocate'},
		     '--tol-marque',$self->{'tol_marque'},
                     ($self->{ignore_red} ? '--ignore-red' : '--no-ignore-red'),
		     ($self->{'debug'} || $self->{debug_pixels}
		      ? '--debug-pixels' : '--no-debug-pixels'),
		     '--projet','%PROJ',
		     '--data','%DATA',
		     '--liste-fichiers',$scans_list,
		     );
}

sub note {
  my ($self)=@_;

  $self->amc_command('note',
		     '--data','%DATA',
		     '--seuil',$self->{'seuil'},
		     '--seuil-up',$self->{'seuil_up'},
		     '--grain',$self->{'grain'},
		     '--arrondi',$self->{'rounding'},
		     '--notemax',$self->{'notemax'},
		     '--postcorrect-student',$self->{'postcorrect_student'},
		     '--postcorrect-copy',$self->{'postcorrect_copy'},
		     );
}

sub assoc {
  my ($self)=@_;

  return if(!$self->{'list'});

  my @code=();
  if($self->{'code'} eq '<preassoc>') {
    push @code,'--pre-association';
  } else {
    push @code,'--notes-id',$self->{'code'};
  }

  $self->amc_command('association-auto',
		     '--liste','%PROJ/'.$self->{'list'},
		     '--liste-key',$self->{'list_key'},
		     @code,
		     '--data','%DATA',
                    );

  if($self->{association_manual}) {
    for my $a (@{$self->{association_manual}}) {
      $self->amc_command('association',
                         '--liste','%PROJ/'.$self->{'list'},
                         '--data','%DATA',
                         '--set',
                         '--student',$a->{student},
                         '--copy',$a->{copy},
                         '--id',$a->{id},
                         );
    }
  }
}

sub get_marks {
  my ($self)=@_;

  my $sf=$self->{'temp_dir'}."/data/scoring.sqlite";
  my $dbh = DBI->connect("dbi:SQLite:dbname=$sf","","");
  $self->{'marks'}=$dbh->selectall_arrayref("SELECT * FROM scoring_mark",
					    { Slice => {} });

  $self->trace("[I] Marks:");
  for my $m (@{$self->{'marks'}}) {
    $self->trace("    ".join(' ',map { $_."=".$m->{$_} } (qw/student copy total max mark/)));
  }
}

sub get_orientation {
  my ($self)=@_;

  my $l=AMC::Data->new($self->{'temp_dir'}."/data")->module('layout');
  $l->begin_read_transaction('tgor');
  my $o=$l->orientation();
  $l->end_transaction('tgor');
  return($o);
}

sub check_perfect {
  my ($self)=@_;
  return if(!$self->{'perfect_copy'});

  $self->trace("[T] Perfect copies test: "
	       .join(',',@{$self->{'perfect_copy'}}));

  my %p=map { $_=>1 } @{$self->{'perfect_copy'}};

  for my $m (@{$self->{'marks'}}) {
    $p{$m->{'student'}}=0
      if($m->{'total'} == $m->{'max'}
	&& $m->{'total'}>0 );
  }

  for my $i (keys %p) {
    if($p{$i}) {
      $self->trace("[E] Non-perfect copy: $i");
      exit(1);
    }
  }
}

sub check_marks {
  my ($self)=@_;
  return if(!$self->{'check_marks'});

  $self->trace("[T] Marks test: "
	       .join(',',keys %{$self->{'check_marks'}}));

  my %p=(%{$self->{'check_marks'}});

  for my $m (@{$self->{'marks'}}) {
    my $st=studentids_string($m->{'student'},$m->{'copy'});
    delete($p{$st})
      if($p{$st} == $m->{'mark'});
    $st='/'.$self->find_assoc($m->{'student'},$m->{'copy'});
    delete($p{$st})
      if($p{$st} == $m->{'mark'});
  }

  my @no=(keys %p);
  if(@no) {
    $self->trace("[E] Uncorrect marks: ".join(',',@no));
    exit(1);
  }

}

sub get_assoc {
  my ($self)=@_;

  my $sf=$self->{'temp_dir'}."/data/association.sqlite";

  if(-f $sf) {
    my $dbh = DBI->connect("dbi:SQLite:dbname=$sf","","");
    $self->{'association'}=$dbh->selectall_arrayref("SELECT * FROM association_association",
						    { Slice => {} });

    $self->trace("[I] Assoc:");
    for my $m (@{$self->{'association'}}) {
      for my $t (qw/auto manual/) {
        my ($n)=$self->{names}->data('id',$m->{$t},test_numeric=>1);
        if($n) {
          $m->{$t}=$n->{id};
          $m->{name}=$n->{_ID_};
        }
      }
      $self->trace("    ".join(' ',map { $_."=".$m->{$_} } (qw/student copy auto manual name/)));
    }
  }
}

sub find_assoc {
  my ($self,$student,$copy)=@_;
  my $r='';
  for my $a (@{$self->{'association'}}) {
    $r=(defined($a->{'manual'}) ? $a->{'manual'} : $a->{'auto'})
      if($a->{'student'} == $student && $a->{'copy'} == $copy);
  }
  return($r);
}

sub compare {
  my ($a,$b)=@_;
  return( (($a eq 'x') && (!defined($b)))
	  || ( $a eq $b ));
}

sub check_assoc {
  my ($self)=@_;
  return if(!$self->{'check_assoc'});

  $self->trace("[T] Association test: "
	       .join(',',keys %{$self->{'check_assoc'}}));

  my %p=(%{$self->{'check_assoc'}});

  for my $m (@{$self->{'association'}}) {
    my $st=studentids_string($m->{'student'},$m->{'copy'});
    delete($p{$st})
      if(compare($self->{'check_assoc'}->{$st},$m->{'auto'}));
    delete($p{'m:'.$st})
      if(compare($self->{'check_assoc'}->{'m:'.$st},$m->{'manual'}));
  }

  my @no=(keys %p);
  if(@no) {
    $self->trace("[E] Uncorrect association: ".join(',',@no));
    exit(1);
  }

}

sub annote {
  my ($self)=@_;
  return if($self->{blind} || !$self->{'annote'});

  my $nf=$self->{'temp_dir'}."/num-pdf";
  open(NUMS,">$nf");
  for (@{$self->{'annote'}}) { print NUMS "$_\n"; }
  close(NUMS);

  $self->amc_command('annotate',
		     '--names-file','%PROJ/'.$self->{'list'},
		     '--verdict',$self->{'verdict'},
		     '--verdict-question',$self->{'verdict_question'},
		     '--position',$self->{'annote_position'},
		     '--project','%PROJ',
		     '--data','%DATA',
		     ($self->{'annote_ascii'}
		      ? "--force-ascii" : "--no-force-ascii"),
		     '--n-copies',$self->{'n_copies'},
		     '--subject','%PROJ/sujet.pdf',
		     '--src','%PROJ/'.$self->{'src'},
		     '--with',$self->{'tex_engine'},
		     '--filename-model',$self->{'model'},
		     '--id-file','%PROJ/num-pdf',
		     '--darkness-threshold',$self->{'seuil'},
		     '--darkness-threshold-up',$self->{'seuil_up'},
		     );

  $pdf_dir=$self->{'temp_dir'}.'/cr/corrections/pdf';
  opendir(my $dh, $pdf_dir)
    || die "can't opendir $pdf_dir: $!";
  my @pdf = grep { /\.pdf$/i } readdir($dh);
  closedir $dh;
  for my $f (@pdf) { $self->see_file($pdf_dir.'/'.$f); }

  if(@{$self->{'annote_files'}}) {
    my %p=map { $_=>1 } @pdf;
    for my $f (@{$self->{'annote_files'}}) {
      if(!$p{$f}) {
	$self->trace("[E] Annotated file $f has not been generated.");
	exit(1);
      }
    }
    $self->trace("[T] Annotated file names: ".join(', ',@{$self->{'annote_files'}}));
  }
}

sub ok {
  my ($self)=@_;
  $self->end;
  if(@{$self->{'to_check'}}) {
    $self->trace("[?] ".(1+$#{$self->{'to_check'}})." files to check in $self->{'check_dir'}:");
    for(@{$self->{'to_check'}}) {
      $self->trace("    ".$_->[0]." ".$_->[1]);
    }
    exit(2) if(!$self->{'blind'});
  } else {
    $self->trace("[0] Test completed succesfully");
  }
}

sub get_defects {
  my ($self)=@_;

  my $l=AMC::Data->new($self->{'temp_dir'}."/data")->module('layout');
  $l->begin_read_transaction('test');
  my $d={$l->defects()};
  $l->end_transaction('test');
  return($d);
}

sub defects {
  my ($self)=@_;

  my $d=$self->get_defects();
  delete $d->{NO_NAME};
  my @t=(keys %$d);
  if(@t) {
    $self->trace("[E] Layout defects: ".join(', ',@t));
    exit 1;
  } else {
    $self->trace("[T] No layout defects");
  }
}

sub check_export {
  my ($self)=@_;
  my @csv=@{$self->{'export_full_csv'}};
  if(@csv) {
    $self->begin("CSV full export test (".(1+$#csv)." scores)");
    $self->amc_command('export',
		       '--data','%DATA',
		       '--module','CSV',
		       '--fich-noms','%PROJ/'.$self->{'list'},
		       '--option-out','columns=student.copy',
		       '--option-out','ticked='.$self->{export_csv_ticked},
		       '-o','%PROJ/export.csv',
		      );
    my $c=Text::CSV->new();
    open my $fh,"<:encoding(utf-8)",$self->{'temp_dir'}.'/export.csv';
    my $i=0;
    my %heads=map { $_ => $i++ } (@{$c->getline($fh)});
    my $copy=$heads{translate_column_title('copie')};
    if(!defined($copy)) {
      $self->trace("[E] CSV: ".translate_column_title('copie')
		   ." column not found");
      exit(1);
    }
    while(my $row=$c->getline($fh)) {
      for my $t (@csv) {
	if($t->{-copy} eq $row->[$copy]
	   && $t->{-question} && defined($heads{$t->{-question}})
	   && $t->{-abc} ) {
	  $self->test($row->[$heads{"TICKED:".$t->{-question}}],
		      $t->{-abc},"ABC for copy ".$t->{-copy}
		      ." Q=".$t->{-question});
	  $t->{'checked'}=1;
	}
	if($t->{-copy} eq $row->[$copy]
	   && $t->{-question} && defined($heads{$t->{-question}})
	   && defined($t->{-score}) ) {
	  $self->test($row->[$heads{$t->{-question}}],
		      $t->{-score},"score for copy ".$t->{-copy}
		      ." Q=".$t->{-question});
	  $t->{'checked'}=1;
	}
      }
    }
    close $fh;
    for my $t (@csv) {
      if(!$t->{'checked'}) {
	$self->trace("[E] CSV: line not found. ".join(', ',map { $_.'='.$t->{$_} } (keys %$t)));
	exit(1);
      }
    }
    $self->end;
  }

  if($self->{'export_ods'}) {
    require OpenOffice::OODoc;

    $self->begin("ODS full export test");
    $self->amc_command('export',
		       '--data','%DATA',
		       '--module','ods',
		       '--fich-noms','%PROJ/'.$self->{'list'},
		       '--option-out','columns=student.copy',
		       '--option-out','stats=h',
		       '-o','%PROJ/export.ods',
		      );
    my $doc = OpenOffice::OODoc::odfDocument(file=>$self->{'temp_dir'}.'/export.ods');
    my %iq=();
    my $i=0;
    while(my $id=$doc->getCellValue(1,0,$i)) {
      $iq{$id}=$i;
      $i+=5;
    }
  ONEQ: for my $q (@{$self->{'export_ods'}->{stats}}) {
      my $i=$iq{$q->{id}};
      if(defined($i)) {
        $self->test($doc->getCellValue(1,2,$i+1),$q->{total},'total');
        $self->test($doc->getCellValue(1,3,$i+1),$q->{empty},'empty');
        $self->test($doc->getCellValue(1,4,$i+1),$q->{invalid},'invalid');
        for my $a (@{$q->{answers}}) {
          $self->test($doc->getCellValue(1,4+$a->{i},$i+1),$a->{ticked},
                      'stats:'.$q->{id}.':'.$a->{i});
        }
      } else {
        $self->trace("[E] Stats: question not found in stats table: $q->{id}");
        exit 1;
      }
    }
    $self->end;
  }
}

sub check_zooms {
  my ($self)=@_;
  my $cz=$self->{'check_zooms'};
  my @zk=keys %$cz;
  return if(!@zk);

  my $capture=AMC::Data->new($self->{'temp_dir'}."/data")->module('capture');
  $capture->begin_read_transaction('cZOO');

  for my $p (keys %{$cz}) {
    $self->trace("[T] Zooms check : $p");

    my ($student,$page,$copy);
    if($p =~ /^([0-9]+)-([0-9]+):([0-9]+)$/) {
      $student=$1;$page=$2;$copy=$3;
    } elsif($p =~ /^([0-9]+)-([0-9]+)$/) {
      $student=$1;$page=$2;$copy=0;
    }

    my @zooms=grep { $_->{imagedata} }
      (@{$capture->dbh
	   ->selectall_arrayref($capture->statement('pageZonesDI'),
				{Slice=>{}},
				$student,$page,$copy,ZONE_BOX)
	 });

    if(1+$#zooms == $cz->{$p}) {
      for(@zooms) {
	$self->see_blob("zoom-".$student."-".$page.":".$copy."--"
			.$_->{id_a}."-".$_->{id_b}.".png",$_->{imagedata});
      }
    } else {
      $self->trace("[E] Zooms dir $p contains ".(1+$#zooms)." elements, but needs ".$cz->{$p});
      exit(1);
    }
  }

  $capture->end_transaction('cZOO');

}

sub check_textest {
  my ($self,$tex_file)=@_;
  if(!$tex_file) {
    opendir(my $dh, $self->{'dir'})
      || die "can't opendir $self->{'dir'}: $!";
    my @tex = grep { /\.tex$/ } readdir($dh);
    closedir $dh;
    $tex_file=$tex[0] if(@tex);
  }
  $tex_file=$self->{'temp_dir'}."/".$tex_file;
  if(-f $tex_file) {
    my @value_is,@value_shouldbe;
    chomp(my $cwd = `pwd`);
    chdir($self->{'temp_dir'});
    open(TEX,"-|",$self->{'tex_engine'},
	 $tex_file);
    while(<TEX>) {
      if(/^\!/) {
	$self->trace("[E] latex error: $_");
	exit(1);
      }
      if(/^SECTION\((.*)\)/) {
	$self->end();
	$self->begin($1);
      }
      if(/^TEST\(([^,]*),([^,]*)\)/) {
	$self->test($1,$2);
      }
      if(/^VALUEIS\((.*)\)/) {
        push @value_is,$1;
      }
      if(/^VALUESHOULDBE\((.*)\)/) {
        push @value_shouldbe,$1;
      }
    }
    close(TEX);
    chdir($cwd);
    if(@value_shouldbe) {
      for my $i (0..$#value_shouldbe) {
        $self->test($value_is[$i],$value_shouldbe[$i]);
      }
    }
    $self->end();
  } else {
    $self->trace("[X] TeX file not found: $tex_file");
    exit(1);
  }
}

sub data {
  my ($self)=@_;
  return(AMC::Data->new($self->{'temp_dir'}."/data"));
}

sub begin {
  my ($self,$title)=@_;
  $self->end if($self->{'test_title'});
  $self->{'test_title'}=$title;
  $self->{'n.subt'}=0;
}

sub end {
  my ($self)=@_;
  $self->trace("[T] ".
	       ($self->{'n.subt'} ? "(".$self->{'n.subt'}.") " : "")
	       .$self->{'test_title'}) if($self->{'test_title'});
  $self->{'test_title'}='';
}

sub datadump {
  my ($self)=@_;
  if($self->{'datamodule'} && $self->{'datatable'}) {
    print Dumper($self->{'datamodule'}->dbh
		 ->selectall_arrayref("SELECT * FROM $self->{'datatable'}",
				      { Slice=>{} }));
  }
  $self->{'datamodule'}->end_transaction
    if($self->{'datamodule'});
}

sub test {
  my ($self,$x,$v,$subtest)=@_;
  if(!defined($subtest)) {
    $subtest=++$self->{'n.subt'};
  }
  if(ref($x) eq 'ARRAY') {
    for my $i (0..$#$x) {
      $self->test($x->[$i],$v->[$i],1);
    }
  } else {
    if($x ne $v) {
      $self->trace("[E] ".$self->{'test_title'}." [$subtest] : \'$x\' should be \'$v\'");
      $self->datadump;
      exit(1);
    }
  }
}

sub test_undef {
  my ($self,$x)=@_;
  $self->{'n.subt'}++;
  if(defined($x)) {
    $self->trace("[E] ".$self->{'test_title'}." [$self->{'n.subt'}] : \'$x\' should be undef");
    $self->datadump;
    exit(1);
  }
}

sub test_scoring {
  my ($self,$question,$answers,$target_score)=@_;

  my $data=AMC::Data->new($self->{'temp_dir'}."/data");
  my $s=$data->module('scoring');
  my $c=$data->module('capture');

  $s->begin_transaction('tSCO');

  $s->clear_strategy;
  $s->clear_score;
  $s->new_question(1,1,
		   ($question->{multiple} ?
		    QUESTION_MULT : QUESTION_SIMPLE),
		   0,$question->{strategy});
  my $i=0;
  my $none=1;
  my $none_t=1;
  for my $a (@$answers) {
    $i++ if(!$a->{noneof});
    $none=0 if($a->{correct});
    $s->new_answer(1,1,$i,$a->{correct},$a->{strategy});
    $none_t=0 if($a->{ticked});
    $c->set_zone_manual(1,1,0,
			ZONE_BOX,1,$i,$a->{ticked});
  }
  if($question->{noneof_auto}) {
    $s->new_answer(1,1,0,$none,'');
    $c->set_zone_manual(1,1,0,
			ZONE_BOX,1,0,$none_t);
  }

  my $qdata=$s->student_scoring_base(1,0,0.5,1.0);

  $s->end_transaction('tSCO');

  my $scoring=AMC::Scoring->new(data=>$self->{'temp_dir'}."/data");
  $scoring->set_default_strategy($question->{default_strategy})
    if($question->{default_strategy});

  set_debug($self->{debug_file});

  $scoring->prepare_question($qdata->{questions}->{1});
  my ($score,$why)=$scoring->score_question(1,$qdata->{questions}->{1},0);

  set_debug('');

  $self->test($score,$target_score);
}

sub update_sqlite {
  my ($self)=@_;
  my $d=AMC::Data->new($self->{'temp_dir'}."/data");
  for my $m (qw/layout capture scoring association report/) {
    $d->module($m);
  }
  return($self);
}

sub check_pages {
  my ($self)=@_;
  if($self->{pages}) {
    $self->trace("[T] Pages check : ".join(",",@{$self->{pages}}));
    my $l=AMC::Data->new($self->{'temp_dir'}."/data")->module('layout');
    $l->begin_read_transaction('npag');
    for my $i (0..$#{$self->{pages}}) {
      my @p=$l->pages_for_student($i+1);
      my $mx=-1;
      for my $pp (@p) {
        $mx=$pp if $pp>$mx;
      }
      $self->test($mx,$self->{pages}->[$i]);
    }
    $l->end_transaction('npag');
  }
}

sub default_process {
  my ($self)=@_;

  $self->prepare if(!$self->{skip_prepare});
  $self->defects;
  $self->check_pages;
  $self->analyse if(!$self->{skip_scans});
  $self->check_zooms;
  $self->note;
  $self->assoc;
  $self->get_assoc;
  $self->get_marks;
  $self->check_marks;
  $self->check_perfect;
  $self->check_assoc;
  $self->annote;
  $self->check_export;

  $self->ok;
}

1;
