#
# Copyright (C) 2012-2014 Alexis Bienvenue <paamc@passoire.fr>
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

package AMC::Export::register;

sub new {
    my $class = shift;
    my $self={};
    bless ($self, $class);
    return $self;
}

sub name {
  return("empty");
}

sub extension {
  return('.xxx');
}

sub type {
  my ($self)=@_;
  my $ext=$self->extension();
  $ext =~ s/^.*\.//;
  return($ext);
}

sub options_from_config {
  my ($self,$options_project,$options_main,$options_default)=@_;
  return();
}

sub options_default {
  return();
}

sub needs_module {
  return();
}

sub build_config_gui {
  my ($self,$w,$prefs)=@_;
}

sub hide {
  return('standard_export_options'=>0);
}

sub weight {
  return(1);
}

1;
