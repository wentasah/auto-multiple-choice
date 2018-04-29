# -*- perl -*-
#
# Copyright (C) 2014 Alexis Bienvenue <paamc@passoire.fr>
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

package AMC::Path;

BEGIN {
    use Exporter   ();
    our ($VERSION, @ISA, @EXPORT);

    @ISA         = qw(Exporter);
    @EXPORT      = qw( &proj2abs &abs2proj );
}

sub abs2proj {
    my ($surnoms,$fich)=@_;
    if(defined($fich) && $fich) {

	$fich =~ s/\/{2,}/\//g;

      CLES:for my $s (sort { length($surnoms->{$b}) <=> length($surnoms->{$a}) } grep { $_ && $surnoms->{$_} } (keys %$surnoms)) {
	  my $rep=$surnoms->{$s};
	  $rep.="/" if($rep !~ /\/$/);
	  $rep =~ s/\/{2,}/\//g;
	  if($fich =~ s/^\Q$rep\E\/*//) {
	      $fich="$s/$fich";
	      last CLES;
	  }
      }

	return($fich);
    } else {
	return('');
    }
}

sub proj2abs {
    my ($surnoms,$fich)=@_;
    if(defined($fich)) {
	if($fich =~ /^\//) {
	    return($fich);
	} else {
	    $fich =~ s/^([^\/]*)//;
	    my $code=$1;
	    if(!$surnoms->{$code}) {
		$fich=$code.$fich;
		$code=$surnoms->{''};
	    }
	    my $rep=$surnoms->{$code};
	    $rep.="/" if($rep !~ /\/$/);
	    $rep.=$fich;
	    $rep =~ s/\/{2,}/\//g;
	    return($rep);
	}
    } else {
	return('');
    }
}

sub new {
  my (%o)=(@_);

  my $self={'projects_path'=>'',
	    'project_name'=>'',
	    'home_dir'=>'',
	   };

  for my $k (keys %o) {
    $self->{$k}=$o{$k} if(defined($self->{$k}));
  }

  bless $self;

  return($self);
}

sub set {
  my ($self,%p)=@_;
  for my $key (keys %p) {
    $self->{$key}=$p{$key};
  }
}

# builds a shorcuts list

sub shortcuts {
    my ($self,$proj)=@_;
    my %s=();

    $proj=$self->{project_name} if(!defined($proj));
    $proj='' if(!defined($proj));
    if($proj eq '<HOME>') {
      %s=('%HOME',$self->{home_dir});
    } else {
      %s=('%PROJETS'=>$self->{projects_path},
	  '%HOME',$self->{home_dir},
	  ''=>'%PROJETS',
	 );
      if($proj) {
	$s{'%PROJET'}=$self->{projects_path}."/".$proj;
	$s{''}='%PROJET';
      }
    }

    return(\%s);
}

# expands shortcuts like %PROJET, %HOME from a file path

sub absolu {
    my ($self,$f,$proj)=@_;
    return($f) if(!defined($f));
    return(proj2abs($self->shortcuts($proj),$f));
}

# replaces some paths with their shortcuts in a file path

sub relatif {
    my ($self,$f,$proj)=@_;
    return($f) if(!defined($f));
    return(abs2proj($self->shortcuts($proj),$f));
}

1;
