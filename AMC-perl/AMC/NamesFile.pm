#
# Copyright (C) 2009-2016 Alexis Bienvenue <paamc@passoire.fr>
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

package AMC::NamesFile;

use AMC::Basic;
use Encode;
use Text::CSV;

sub new {
    my ($f,%o)=@_;
    my $self={'fichier'=>$f,
	      'encodage'=>'utf-8',
	      'separateur'=>'',
	      'identifiant'=>'',

	      'heads'=>[],
	      'problems'=>{},
	      'numeric.content'=>{},
	      'simple.content'=>{},
	      'err'=>[0,0],
	  };

    for (keys %o) {
	$self->{$_}=$o{$_} if(defined($self->{$_}));
    }

    $self->{'separateur'}=":,;\t" if(!$self->{'separateur'});
    $self->{'identifiant'}='(nom|surname) (prenom|name)'
	if(!$self->{'identifiant'});

    bless $self;

    @{$self->{'err'}}=($self->load());

    return($self);
}

sub errors {
    my ($self)=@_;
    return(@{$self->{'err'}});
}

sub load {
    my ($self)=@_;
    my @heads=();
    my %data=();
    my $err=0;
    my $errlig=0;
    my $line;
    my $sep=$self->{'separateur'};

    $self->{'noms'}=[];

    if($self->{'fichier'} &&
       -f $self->{'fichier'} && ! -z $self->{'fichier'}) {

      debug "Reading names file $self->{'fichier'}";

      # First pass: detect the number of comment lines, and the
      # separator

      my $comment_lines=0;

      if(open(LISTE,"<:encoding(".$self->{'encodage'}.")",
	      $self->{'fichier'})) {
      LINE: while(<LISTE>) {
	  if(/^\#/) {
	    $comment_lines++;
	    next LINE;
	  }
	  my $entetes=$_;
	  if(length($self->{'separateur'})>1) {
	    my $nn=-1;
	    for my $s (split(//,$self->{'separateur'})) {
	      my $k=0;
	      while($entetes =~ /$s/g) { $k++; }
	      if($k>$nn) {
		$nn=$k;
		$sep=$s;
	      }
	    }
	    debug "Detected separator: ".($sep eq "\t" ? "<TAB>" : "<".$sep.">");
	  }
	  last LINE;
	}
	close LISTE;
      }

      debug "NamesFile $self->{'fichier'}: $comment_lines comments lines";

      # Second pass: read the file with Text::CSV

      $self->{'numeric.content'}={};
      $self->{'simple.content'}={};
      $self->{duplicates}={};

      my $io;
      if(open($io,"<:encoding(".$self->{'encodage'}.")",
	      $self->{'fichier'})) {

	# skip comments lines

	if($comment_lines>0) {
	  for (1..$comment_lines) { $_=<$io> }
	}

	my $csv=Text::CSV->new({binary => 1,
				sep_char=>$sep,
				allow_whitespace=>1,
			       });

	# first line: header

	$self->{'heads'}=$csv->getline ($io);
	if($self->{'heads'}) {
	  for my $h (@{$self->{'heads'}}) {
	    $self->{'numeric.content'}->{$h}=0;
	    $self->{'simple.content'}->{$h}=0;
	  }
	} else {
	  debug("CSV [SEP=$sep]: Can't read headers");
	  return(1,$.);
	}
	$csv->column_names ($self->{'heads'});

	# following lines

	my $csv_line=0;

	while (my $row = $csv->getline_hr ($io)) {
	  if($row) {
	    # ignore blank lines
	    my $ok='';
	  KEY:for my $k (keys %$row) {
	      if(defined($row->{$k}) && $row->{$k} ne '') {
		$ok=1;
		last KEY;
	      }
	    }
	    if($ok) {
	      $csv_line++;
	      for my $k (keys %$row) {
		if(defined($data{$k}->{$row->{$k}})
		   && $data{$k}->{$row->{$k}}==1
		   && !$self->{duplicates}->{$k} ) {
		  $self->{duplicates}->{$k}=
		    {content=>$row->{$k},line=>$csv_line};
		}
		$data{$k}->{$row->{$k}}++;
		$self->{'numeric.content'}->{$k} ++
		  if($row->{$k} =~ /^[ 0-9.+-]*$/i);
		$self->{'simple.content'}->{$k} ++
		  if($row->{$k} =~ /^[ a-z0-9.+-]*$/i);
	      }
	      $row->{'_LINE_'}=$csv_line;
	      push @{$self->{'noms'}},$row;
	    } else {
	      debug "Blank line $. detected";
	    }
	  }
	}
	if(!$csv->eof) {
	  if($csv->error_diag()) {
	    debug "CSV: ".$csv->error_diag();
	    $errlig=$. if(!$errlig);
	    $err++;
	  }
	}

	close $io;

	# find unique identifiers

	for my $h (@{$self->{'heads'}}) {
	  my @lk=(keys %{$data{$h}});
	  $self->{duplicates}->{$h}->{n}=$#{$self->{'noms'}}-$#lk;
	}

	$self->{'keys'}=[grep { $self->{duplicates}->{$_}->{n} == 0 }
			 @{$self->{'heads'}}];

	# rajout identifiant
	$self->calc_identifiants();
	$self->tri('_ID_');

	return($err,$errlig);
      } else {
	return(-1,0);
      }
    } else {
	debug("Inexistant or empty names list file");
	debug("(file=".$self->{'fichier'}.")")
	  if(defined($self->{'fichier'}));
	$self->{'heads'}=[];
	$self->{'keys'}=[];
	$self->{'problems'}={'ID.dup'=>[],'ID.empty'=>0};
	return(0,0);
    }
}

sub head_first_duplicate {
  my ($self,$key)=@_;
  return($self->{'duplicates'}->{$key}->{content});
}

sub head_n_duplicates {
  my ($self,$key)=@_;
  return($self->{duplicates}->{$key}->{n});
}

sub get_value {
    my ($self,$key,$vals)=@_;
    my $r='';
  KEY: for my $k (split(/\|+/,$key)) {
      for my $h ($self->heads()) {
	  if($k =~ /^$h:([0-9]+)$/i) {
	      if(defined($vals->{$h})) {
		  $r=sprintf("%0".$1."d",$vals->{$h});
	      }
	  } elsif((lc($h) eq lc($k)) && defined($vals->{$h})) {
	      $r=$vals->{$h};
	  }
      }
      last KEY if($r ne '');
  }
    return($r);
}

sub calc_identifiants {
    my ($self)=@_;
    my %ids=();

    $self->{'problems'}={'ID.dup'=>[],'ID.empty'=>0};

    for my $n (@{$self->{'noms'}}) {
	my $i=$self->substitute($n,$self->{'identifiant'});
	$n->{'_ID_'}=$i;
	if($i) {
	    if($ids{$i}) {
		push @{$self->{'problems'}->{'ID.dup'}},$i;
	    } else {
		$ids{$i}=1;
	    }
	} else {
	    $self->{'problems'}->{'ID.empty'}++;
	}
    }
}

sub problem {
    my ($self,$k)=@_;
    return($self->{'problems'}->{$k});
}

sub tri {
    my ($self,$cle)=@_;
    $self->{'noms'}=[sort { $a->{$cle} cmp $b->{$cle} } @{$self->{'noms'}}];
}

sub tri_num {
    my ($self,$cle)=@_;
    $self->{'noms'}=[sort { $a->{$cle} <=> $b->{$cle} } @{$self->{'noms'}}];
}

sub taille {
    my ($self)=@_;
    return(1+$#{$self->{'noms'}});
}

sub heads { # entetes
    my ($self)=@_;
    return(@{$self->{'heads'}});
}

sub heads_count {
  my ($self,$check)=@_;
  my %h=map { $_=>0 } ($self->heads());
  for my $n (@{$self->{'noms'}}) {
    for my $k (keys %h) {
      $h{$k}++ if(&$check($n->{$k}));
    }
  }
  return(%h);
}

sub keys { # entetes qui peuvent servir de cle unique
    my ($self)=@_;
    return(sort { $self->{'simple.content'}->{$b} <=>
		      $self->{'simple.content'}->{$a}
		  || $self->{'numeric.content'}->{$b} <=>
		      $self->{'numeric.content'}->{$a}
		  || $a cmp $b }
		  @{$self->{'keys'}});
}

sub heads_for_keys { # entetes qui peuvent servir de cle unique
    my ($self)=@_;
    return(sort { $self->{duplicates}->{$a}->{n} <=>
		    $self->{duplicates}->{$b}->{n}
		  || $self->{'simple.content'}->{$b} <=>
		      $self->{'simple.content'}->{$a}
		  || $self->{'numeric.content'}->{$b} <=>
		      $self->{'numeric.content'}->{$a}
		  || $a cmp $b }
		  @{$self->{'heads'}});
}

sub liste {
    my ($self,$head)=@_;
    return(map { $_->{$head} } @{$self->{'noms'}} );
}

# use names fields from $n to subsitute (HEADER) substrings in $s
sub substitute {
    my ($self,$n,$s,%oo)=@_;

    my $prefix='';

    $prefix=$oo{'prefix'} if(defined($oo{'prefix'}));

    if(defined($n->{'_ID_'})) {
	my $nom=$n->{'_ID_'};
	$nom =~ s/^\s+//;
	$nom =~ s/\s+$//;
	$nom =~ s/\s+/ /g;

	$s =~ s/$prefix\(ID\)/$nom/g;
    } else {
	$s =~ s/$prefix\(ID\)/X/g;
    }

    $s =~ s/$prefix\(([^\)]+)\)/get_value($self,$1,$n)/gei;

    $s =~ s/^\s+//;
    $s =~ s/\s+$//;

    return($s);
}

sub simple_numeric {
  my ($a)=@_;
  $a =~ s/^0+// if($a =~ /^\d+$/);
  return($a);
}

sub same_values {
  my ($a,$b,$test_numeric)=@_;
  return(1) if($a eq $b);
  return(1) if($test_numeric && (simple_numeric($a) eq simple_numeric($b)));
  return(0);
}

sub data {
    my ($self,$head,$c,%oo)=@_;
    return() if(!defined($c));
    my @k=grep { defined($self->{'noms'}->[$_]->{$head})
		   && same_values($self->{'noms'}->[$_]->{$head},$c,$oo{test_numeric}) }
      (0..$#{$self->{'noms'}});
    if(!$oo{'all'}) {
	if($#k!=0) {
	    print STDERR "Error: non-unique name (".(1+$#k)." records)\n";
	    return();
	}
    }
    if($oo{'i'}) {
	return(@k);
    } else {
	return(map { $self->{'noms'}->[$_] } @k);
    }
}

sub data_n {
    my ($self,$n,$cle)=@_;
    return($self->{'noms'}->[$n]->{$cle});
}

1;

