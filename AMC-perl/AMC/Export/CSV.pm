#
# Copyright (C) 2009-2016 Alexis Bienvenue <paamc@passoire.fr>
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

package AMC::Export::CSV;

use AMC::Basic;
use AMC::Export;

use Encode;

@ISA=("AMC::Export");

sub new {
    my $class = shift;
    my $self  = $class->SUPER::new();
    $self->{'out.encodage'}='utf-8';
    $self->{'out.separateur'}=",";
    $self->{'out.decimal'}=",";
    $self->{'out.entoure'}="\"";
    $self->{'out.ticked'}="";
    $self->{'out.columns'}='student.copy,student.key,student.name';
    bless ($self, $class);
    return $self;
}

sub load {
  my ($self)=@_;
  $self->SUPER::load();
  $self->{'_capture'}=$self->{'_data'}->module('capture');
}

sub parse_num {
    my ($self,$n)=@_;
    if($self->{'out.decimal'} ne '.') {
	$n =~ s/\./$self->{'out.decimal'}/;
    }
    return($self->parse_string($n));
}

sub parse_string {
    my ($self,$s)=@_;
    if($self->{'out.entoure'}) {
	$s =~ s/$self->{'out.entoure'}/$self->{'out.entoure'}$self->{'out.entoure'}/g;
	$s=$self->{'out.entoure'}.$s.$self->{'out.entoure'};
    }
    return($s);
}

sub export {
    my ($self,$fichier)=@_;
    my $sep=$self->{'out.separateur'};

    $sep="\t" if($sep =~ /^tab$/i);

    $self->{'noms.postcorrect'}=($self->{'out.ticked'} ne '');

    $self->pre_process();

    open(OUT,">:encoding(".$self->{'out.encodage'}.")",$fichier);

    $self->{'_scoring'}->begin_read_transaction('XCSV');

    my $dt=$self->{'_scoring'}->variable('darkness_threshold');
    my $dtu=$self->{'_scoring'}->variable('darkness_threshold_up');
    $dtu=1 if(!defined($dtu));
    my $lk=$self->{'_assoc'}->variable('key_in_list');

    my @student_columns=split(/,+/,$self->{'out.columns'});

    my @columns=();

    for my $c (@student_columns) {
      if($c eq 'student.key') {
	push @columns,"A:".encode('utf-8',$lk);
      } elsif($c eq 'student.name') {
	push @columns,translate_column_title('nom');
      } elsif($c eq 'student.copy') {
	push @columns,translate_column_title('copie');
      } else {
	push @columns,encode('utf-8',$c);
      }
    }

    push @columns,map { translate_column_title($_); } ("note");

    my @codes;
    my @questions;
    $self->codes_questions(\@codes,\@questions,!$self->{'out.ticked'});

    if($self->{'out.ticked'}) {
      push @columns,map { ($_->{'title'},"TICKED:".$_->{'title'}) } @questions;
      $self->{'out.entoure'}="\"" if(!$self->{'out.entoure'});
    } else {
      push @columns,map { $_->{'title'} } @questions;
    }

    push @columns,@codes;

    print OUT join($sep,map  { $self->parse_string($_) } @columns)."\n";

    for my $m (@{$self->{'marks'}}) {
      my @sc=($m->{'student'},$m->{'copy'});

      @columns=();

      for my $c (@student_columns) {
	push @columns,$self->parse_string($m->{$c} ?
					  $m->{$c} :
					  $m->{'student.all'}->{$c});
      }

      push @columns,$self->parse_num($m->{'mark'});

      for my $q (@questions) {
	push @columns,$self->parse_num($self->{'_scoring'}->question_score(@sc,$q->{'question'}));
	if($self->{'out.ticked'}) {
	  if($self->{'out.ticked'} eq '01') {
	    push @columns,join(';',$self->{'_capture'}
			       ->ticked_list_0(@sc,$q->{'question'},$dt,$dtu));
	  } elsif($self->{'out.ticked'} eq 'AB') {
	    my $t='';
	    my @tl=$self->{'_capture'}
	      ->ticked_list(@sc,$q->{'question'},$dt,$dtu);
	    if($self->{_capture}->has_answer_zero(@sc,$q->{'question'})) {
	      if(shift @tl) {
		$t.='0';
	      }
	    }
	    for my $i (0..$#tl) {
	      $t.=chr(ord('A')+$i) if($tl[$i]);
	    }
	    push @columns,"\"$t\"";
	  } else {
	    push @columns,'"S?"';
	  }
	}
      }

      for my $c (@codes) {
	push @columns,$self->{'_scoring'}->student_code(@sc,$c);
      }

      print OUT join($sep,@columns)."\n";
    }

    close(OUT);
}

1;
