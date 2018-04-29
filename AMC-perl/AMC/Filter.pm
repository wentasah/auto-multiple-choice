#
# Copyright (C) 2012-2013 Alexis Bienvenue <paamc@passoire.fr>
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

package AMC::Filter;

sub new {
    my ($class,%o) = @_;
    my $self={'errors'=>[],
	      'project_options'=>{},
	      'filter_results'=>{},
	      'jobname'=>'',
	      'jobspecific'=>'',
	     };

    for my $k (keys %o) {
	$self->{$k}=$o{$k} if(defined($self->{$k}));
    }

    bless ($self, $class);
    return $self;
}

sub clear {
  my ($self)=@_;
  $self->{'errors'}=[];
}

sub error {
  my ($self,$error_text)=@_;
  push @{$self->{'errors'}},$error_text;
}

sub errors {
  my ($self)=@_;
  return(@{$self->{'errors'}});
}

sub pre_filter {
  my ($self,$input_file)=@_;
}

sub filter {
  my ($self,$input_file,$output_file)=@_;
}

#####################################################################
# The following methods should NOT be overwritten
#####################################################################

sub set_project_option {
  my ($self,$name,$value)=@_;
  $self->{'project_options'}->{$name}=$value;
  print "VAR: project:$name=$value\n";
}

sub set_filter_result {
  my ($self,$name,$value)=@_;
  $self->{'filter_results'}->{$name}=$value;
}

sub get_filter_result {
  my ($self,$name)=@_;
  return($self->{'filter_results'}->{$name});
}

sub unchanged {
  my ($self)=@_;
  return($self->get_filter_result('unchanged'));
}

1;
