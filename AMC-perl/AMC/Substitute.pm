#! /usr/bin/perl
#
# Copyright (C) 2012-2016 Alexis Bienvenue <paamc@passoire.fr>
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

package AMC::Substitute;

use AMC::Basic;

sub new {
    my (%o)=@_;
    my $self={'names'=>'',
	      'scoring'=>'',
	      'assoc'=>'',
	      'name'=>'','chsign'=>4,
	      'lk'=>'',
	  };

    for (keys %o) {
	$self->{$_}=$o{$_} if(defined($self->{$_}));
    }

    bless $self;
    return($self);
}

sub format_note {
  my ($self,$mark)=@_;

  if($self->{'chsign'}) {
    $mark=sprintf("%.*g",$self->{'chsign'},$mark);
  }
  return($mark);
}

sub substitute {
  my ($self,$text,$student,$copy)=@_;

  if($self->{'scoring'}) {
    my $student_mark=$self->{'scoring'}->student_global($student,$copy);

    if($student_mark) {
      $text =~ s/\%[S]/$self->format_note($student_mark->{'total'})/ge;
      $text =~ s/\%[M]/$self->format_note($student_mark->{'max'})/ge;
      $text =~ s/\%[s]/$self->format_note($student_mark->{'mark'})/ge;
      $text =~ s/\%[m]/$self->format_note($self->{'scoring'}->variable('mark_max'))/ge;
    } else {
      debug "No marks found ! Copy=".studentids_string($student,$copy);
    }
  }

  $text =~ s/\%[n]/$self->{'name'}/ge;

  if($self->{'assoc'} && $self->{'names'}) {
    $self->{'lk'}=$self->{'assoc'}->variable('key_in_list')
      if(!$self->{'lk'});

    my $i=$self->{'assoc'}->get_real($student,$copy);
    my $n;

    debug "Association -> ID=$i";

    if(defined($i)) {
      ($n)=$self->{'names'}->data($self->{'lk'},$i,test_numeric=>1);
      if($n) {
	$text=$self->{'names'}->substitute($n,$text,'prefix'=>'%');
      }
    }
  }

  return($text);
}

1;
