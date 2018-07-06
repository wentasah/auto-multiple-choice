#
# Copyright (C) 2015-2017 Alexis Bienvenue <paamc@passoire.fr>
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

package AMC::Print::cupslp;

use AMC::Print;
use AMC::Basic;

@ISA=("AMC::Print");

sub nonnul {
    my $s=shift;
    $s =~ s/\000//g;
    return($s);
}

sub new {
  my $class = shift;
  my $self  = $class->SUPER::new(@_);

  $self->{method}='cupslp';
  return($self);
}

sub check_available {
  my @missing=();
  for my $command (qw/lp lpoptions lpstat/) {
    push @missing,$command if(!commande_accessible($command));
  }
  if(@missing) {
    return(sprintf(__("The following commands are missing: %s."),
		   join(' ',@missing)));
  } else {
    return();
  }
}

sub weight {
  return(2.0);
}

sub printers_list {
  my ($self)=@_;
  my @list=();
  open(PL,"-|","lpstat","-a")
    or die "Can't exec lpstat: $!";
  while(<PL>) {
    push @list,{name=>$1,description=>$1}
      if(/^([^\s]+)\s+accept/);
  }
  close PL;
  return(@list);
}

sub default_printer {
  my ($self)=@_;
  open(PL,"-|","lpstat","-d")
    or die "Can't exec lpstat: $!";
  while(<PL>) {
    return($1) if(/:\s*([^\s]+)/);
  }
  close PL;
  return('');
}

sub printer_options_list {
  my ($self,$printer)=@_;
  my @o=();
  open(OL,"-|","lpoptions","-p",$printer,"-l")
    or die "Can't exec lpoptions: $!";
  while(<OL>) {
    if(m!^([^\s]+)/([^:]+):\s*(.*)!) {
      my %option=(name=>$1,description=>$2,values=>[]);
      my $vals=$3;
      for my $k (split(/\s+/,$vals)) {
	if($k =~ s/^\*//) {
	  $option{default}=$k;
	}
	push @{$option{values}},
	  {name=>$k,description=>$k};
      }
      push @o,{%option};
    }
  }
  close OL;
  return(@o);
}

# PRINTING

sub select_printer {
  my ($self,$printer)=@_;
  $self->{printername}=$printer;
  $self->{printeroptions}={};
}

sub set_option {
  my ($self,$option,$value)=@_;
  $self->{printeroptions}->{$option}=$value;
}

sub print_file {
  my ($self,$filename,$label)=@_;
  my @command=("lp","-d",$self->{printername});
  for my $k (keys %{$self->{printeroptions}}) {
    push @command,"-o","$k=".$self->{printeroptions}->{$k};
  }
  push @command,$filename;
  debug "Printing command: ".join(" ",@command);
  system(@command);
}

1;
