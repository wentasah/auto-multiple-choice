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

package AMC::Filter::register;

use Module::Load;
use Module::Load::Conditional qw/check_install/;

use AMC::Basic qw(!file_mimetype);

use_gettext;

#####################################################################
# These methods should be overwritten for derivated classes (that
# describe file formats that AMC can handle)
#####################################################################

sub new {
    my $class = shift;
    my $self={'project_options'=>''};
    bless ($self, $class);
    return $self;
}

# short name of the file format
sub name {
  return("empty");
}

# default filename when creating a new one inside project directory
sub default_filename {
  return("source");
}

# create new empty file
sub default_content {
  my ($self,$file)=@_;
}

# weight in the list of all available formats. 0 is at the top, 1 is
# at the bottom line
sub weight {
  return(1);
}

# function to set some project parameters for this format to work properly.
# use <set_project_option> method
sub configure {
  my ($self,$options_project);
}

# this function returns a list of project options that are set
# automatically by the filter. These options will be greyed out in the
# Edit/Preferences window so that the user can not modify them.
sub forced_options {
  return();
}

# description of the format, that will be display in the window
# showing details about file formats
sub description {
  return(__"No description available.");
}

# list of file patterns (like "*.txt") that corresponds to source
# files for this format
sub file_patterns {
  return();
}

# filetype to choose right editor. Currently, only "tex" and "txt" are
# available.
sub filetype {
  return("");
}

# returns an URL where to find documentation about the syntax to be
# used
sub doc_url {
  return("");
}

# list of required LaTeX packages
sub needs_latex_package {
  return();
}

# list of required commands
sub needs_command {
  return();
}

# list of required fonts
sub needs_font {
  return([{'type'=>'fontconfig',
	   'family'=>[]}, # <--  needs one of the fonts in the list
	 ]);
}

# returns a number that tells how likely the file is written for this
# format. 1.0 means "yes, I'm sure this file is written for this
# format", -1.0 means "I'm sure it is NOT written for this format",
# and 0.0 means "I don't know".
sub claim {
  my ($self,$file)=@_;
  return(0);
}

#####################################################################
# The following methods should NOT be overwritten
#####################################################################

sub set_oo {
  my ($self,$config)=@_;
  $self->{'project_options'}=$config;
}

sub set_project_option {
  my ($self,$name,$value)=@_;
  $self->{'project_options'}->set("project:$name",$value);
}

sub missing_latex_packages {
  my ($self)=@_;
  return() if(!commande_accessible("kpsewhich"));
  my @mp=();
  for my $p ($self->needs_latex_package()) {
    my $ok=0;
    open KW,"-|","kpsewhich","-all","$p.sty";
    while(<KW>) { chomp();$ok=1 if(/./); }
    close(KW);
    push @mp,$p if(!$ok);
  }
  return(@mp);
}

sub missing_commands {
  my ($self)=@_;
  my @mc=();
  for my $c ($self->needs_command()) {
    push @mc,$c if(!commande_accessible($c));
  }
  return(@mc);
}

sub missing_fonts {
  my ($self)=@_;
  my @mf=();
  my $fonts=$self->needs_font;
  for my $spec (@$fonts) {
    push @mf,$spec if(!check_fonts($spec));
  }
  return(@mf);
}

sub check_dependencies {
  my ($self)=@_;
  my %miss=('latex_packages'=>[$self->missing_latex_packages()],
	    'commands'=>[$self->missing_commands()],
	    'fonts'=>[$self->missing_fonts()],
	   );
  my $ok=1;
  for my $k (keys %miss) {
    $ok=0 if(@{$miss{$k}});
  }
  $miss{'ok'}=$ok;
  return(\%miss);
}

sub file_head {
  my ($self,$file,$size)=@_;
  return('') if(!$file);
  my $h;
  my $n;
  my $fh;
  return if(!-f $file);
  if(open($fh,"<",$file)) {
    $n=read $fh,$h,$size;
    close($fh);
  }
  if(!defined($n)) {
    debug_and_stderr("Error reading from $file: $!");
  }
  return($h);
}

sub file_mimetype {
  my ($self,$file)=@_;
  return(AMC::Basic::file_mimetype($file));
}

1;
