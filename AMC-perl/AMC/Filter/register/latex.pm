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

package AMC::Filter::register::latex;

use AMC::Filter::register;
use AMC::Basic;

@ISA=("AMC::Filter::register");

use_gettext;

sub new {
    my $class = shift;
    my $self  = $class->SUPER::new();
    bless ($self, $class);
    return $self;
}

sub name {
  return("LaTeX");
}

sub default_filename {
  return("source.tex");
}

sub default_content {
  my ($self,$file)=@_;
  open(EMPTY,">",$file);
  print EMPTY "\\documentclass{article}\n";
  print EMPTY "\\usepackage{automultiplechoice}\n";
  print EMPTY "\\begin{document}\n\n\\end{document}\n";
  close(EMPTY);
}

sub description {
  return(__"This is the native format for AMC. LaTeX is not so easy to use for unexperienced users, but the LaTeX power allows the user to build any multiple choice subject. As an example, the following is possible with LaTeX but not with other formats:\n* any kind of layout,\n* questions with random numerical values,\n* use of figures, mathematical formulas\n* and much more!");
}

sub weight {
  return(0.1);
}

sub file_patterns {
  return("*.tex","*.TEX");
}

sub filetype {
  return("tex");
}

sub claim {
  my ($self,$file)=@_;
  my $h=$self->file_head($file,256);
  return(.8) if($h && ($h =~ /\\usepackage.*\{automultiplechoice\}/
		       || $h =~ /\\documentclass\{/));
  return(.6) if($self->file_mimetype($file) eq 'text/x-tex');
  return(.5) if($file =~ /\.tex$/i);
  return(0.0);
}

1;
