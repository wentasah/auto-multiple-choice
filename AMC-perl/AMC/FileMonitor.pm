# -*- perl -*-
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

package AMC::FileMonitor;

sub new {
    my ($class,%o)=(@_);

    my $self=
      {
       deltat=>1,
      };

    for my $k (keys %o) {
	$self->{$k}=$o{$k} if(defined($self->{$k}));
    }

    $self->{files}=[];
    $self->{timeout_id}=0;

    bless($self,$class);

    return($self);
}

sub add_file {
  my ($self,$path,$callout,%oo)=@_;
  push @{$self->{files}},
    {path=>$path,
     callout=>$callout,
     time=>$self->get_change_time($path),
     %oo} if($path);
  $self->start();
}

sub key_i {
  my ($self,$key,$value)=@_;
  if(@{$self->{files}}) {
    for my $i (0..$#{$self->{files}}) {
      return($i) if($self->{files}->[$i]->{$key} eq $value);
    }
    return(undef);
  } else {
    return(undef);
  }
}

sub remove_file {
  my ($self,$path)=@_;
  $self->remove_key('file',$path);
}

sub remove_key {
  my ($self,$key,$value)=@_;
  my $i=$self->key_i($key,$value);
  if(defined($i)) {
    splice(@{$self->{files}},$i,1);
    $self->stop
      if(!@{$self->{files}});
  }
}

sub update_file {
  my ($self,$path)=@_;
  my $i=$self->file_i($path);
  if(defined($i)) {
    $self->{files}->[$i]->{time}=$self->get_change_time($path);
  }
}

sub get_change_time {
  my ($self,$path)=@_;
  if(-e $path) {
    my @st=stat($path);
    return($st[10]);
  } else {
    return(0);
  }
}

sub start {
  my ($self)=@_;
  if(@{$self->{files}}) {
    if(!$self->{timeout_id}) {
      $self->{timeout_id}=Glib::Timeout
	->add_seconds($self->{deltat},\&monitor,$self);
    }
  }
}

sub stop {
  my ($self)=@_;
  Glib::Source->remove($self->{timeout_id});
  $self->{timeout_id}=0;
}

sub monitor {
  my ($self)=@_;
  for my $f (@{$self->{files}}) {
    my $t=$self->get_change_time($f->{path});
    if($t>$f->{time}) {
      $f->{time}=$t if(! $f->{repeat});
      &{$f->{callout}}() if($f->{callout});
    }
  }
  return(1);
}

1;
