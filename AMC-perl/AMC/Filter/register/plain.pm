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

package AMC::Filter::register::plain;

use AMC::Filter::register;
use AMC::Basic;

@ISA=("AMC::Filter::register");

sub new {
    my $class = shift;
    my $self  = $class->SUPER::new();
    bless ($self, $class);
    return $self;
}

sub name {
  return("AMC-TXT");
}

sub default_filename {
  return("source.txt");
}

sub default_content {
  my ($self,$file)=@_;
  open(EMPTY,">",$file);
  print EMPTY "# AMC-TXT file\n";
  print EMPTY "Title:\nPresentation:\n";
  close(EMPTY);
}

sub description {
  return(__"This is a plain text format for easy question writting. See the following minimal example:\n\nTitle: Paper title\n\n* Which is the capital city of Cameroon?\n+ Yaounde\n- Douala\n- Kribi");
}

sub weight {
  return(0.2);
}

sub forced_options {
  return('moteur_latex_b');
}

sub file_patterns {
  return("*.txt","*.TXT");
}

sub needs_latex_package {
  return("xltxtra","multicol");
}

sub filetype {
  return("txt");
}

sub claim {
  my ($self,$file)=@_;
  my $h=$self->file_head($file,256);
  return(.9) if($h && $h =~ /^\s*\#\s*AMC-TXT/);
  return(.3) if($file =~ /\.txt$/i);
  return(0.0);
}

1;
