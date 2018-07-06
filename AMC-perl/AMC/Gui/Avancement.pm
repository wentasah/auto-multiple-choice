#
# Copyright (C) 2008-2017 Alexis Bienvenue <paamc@passoire.fr>
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

package AMC::Gui::Avancement;

use AMC::Basic;

sub new {
    my ($entier,%o)=(@_);
    my $self={'entier'=>$entier,
	      'progres'=>0,
	      'debug'=>0,
	      'epsilon'=>0.02,
	      'lastshown'=>0,
	      'id'=>'',
	      'bar'=>'',
	  };

    for (keys %o) {
	$self->{$_}=$o{$_} if(defined($self->{$_}));
    }

    debug "Create progression pipe for <".$self->{id}."> up to $entier".
      ($self->{bar}?" (progress bar side)":"");

    bless $self;
    $|++ if($self->{'id'});
    return($self);
}

sub progres {
    my ($self,$suite)=(@_);
    $suite *=  $self->{'entier'};
    $self->{'progres'}+=$suite;
    if($self->{'progres'}>$self->{'entier'}) {
	$suite-=$self->{'progres'}-$self->{'entier'};
	$self->{'progres'}=$self->{'entier'};
    }
    print "===<".$self->{'id'}.">=+$suite\n" if($self->{'id'});
}

sub text {
  my ($self,$text)=(@_);
  print "===<".$self->{'id'}.">=T($text)\n" if($self->{'id'});
}

sub progres_abs {
    my ($self,$suite)=(@_);
    $self->progres($suite-$self->{'progres'});
}

sub fin {
    my ($self,$suite)=(@_);
    $self->progres_abs(1);
}

sub etat {
    my ($self)=@_;
    return($self->{'progres'});
}

sub lit {
    my ($self,$s)=(@_);
    my $r=-1;
    if($s =~ /===<(.*)>=\+([0-9,.]+(?:e[+-]?[0-9]+)?)/) {
	my $id=$1;
	my $suite=$2;
	$suite =~ s/,/./;
	$self->{'progres'}+=$suite;

	if($self->{'progres'}<0) {
	    debug("progres($id)=$self->{'progres'}");
	    $self->{'progres'}=0;
	}
	if($self->{'progres'}>1) {
	    debug("progres($id)=$self->{'progres'}");
	    $self->{'progres'}=1;
	}

	$r=$self->{'progres'};
    }
    if($s =~ /===<(.*)>=T\((.*)\)$/) {
      if($self->{'bar'}) {
	$self->{'bar'}->set_text($2);
      }
      $self->{'progres'}=0;
      $r=0;
    }
    if($r>=0 && $self->{'bar'}) {
      $self->{'bar'}->set_fraction($r);
      if($r==0 || $r>=$self->{'lastshown'}+$self->{'epsilon'}) {
	$self->{'lastshown'}=$r;
      }
    }
    return($r);
}

1;
