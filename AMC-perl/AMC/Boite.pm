#
# Copyright (C) 2008-2012 Alexis Bienvenue <paamc@passoire.fr>
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

package AMC::Boite;

use AMC::Basic;

BEGIN {
    use Exporter   ();
    our ($VERSION, @ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);

    # set the version for version checking
    $VERSION     = 0.1.1;

    @ISA         = qw(Exporter);
    @EXPORT      = qw();
    %EXPORT_TAGS = ( );     # eg: TAG => [ qw!name1 name2! ],

    # your exported package globals go here,
    # as well as any optionally exported functions
    @EXPORT_OK   = qw(&max &min);
}

sub new {
    my (%o)=(@_);

    my $self={'coins'=>[[],[],[],[]],
	      'droite'=>1,
	  };

    for my $k (keys %o) {
	$self->{$k}=$o{$k} if(defined($self->{$k}));
    }

    $self->{'point.actuel'}=0;

    bless $self;

    return($self);
}

sub clone {
  my ($self)=@_;
  my $s={'coins'=>[map { [@$_] ; } (@{$self->{'coins'}})],
	 'droite'=>$self->{'droite'}};
  bless $s;
  return($s);
}

sub def_point_suivant {
    my ($self,$x,$y)=(@_);
    $self->{'coins'}->[$self->{'point.actuel'}++]=[$x,$y];
}

# definit la boite (droite) a l'aide de point haut-gauche et des
# tailles en x et y.

sub def_droite_MD {
    my ($self,$x,$y,$dx,$dy)=(@_);
    $self->{'coins'}->[0]=[$x,$y];
    $self->{'coins'}->[1]=[$x+$dx,$y];
    $self->{'coins'}->[2]=[$x+$dx,$y+$dy];
    $self->{'coins'}->[3]=[$x,$y+$dy];
    $self->{'droite'}=1;

    return($self);
}

# definit la boite (droite) a l'aide de point haut-gauche et du point
# bas-droit.

sub def_droite_MN {
    my ($self,$x,$y,$xp,$yp)=(@_);
    $self->{'coins'}->[0]=[$x,$y];
    $self->{'coins'}->[1]=[$xp,$y];
    $self->{'coins'}->[2]=[$xp,$yp];
    $self->{'coins'}->[3]=[$x,$yp];
    $self->{'droite'}=1;

    return($self);
}

# definit la boite (droite) a l'aide d'une element XML (obtenu grace a
# XML::Simple) qui comporte les elements xmin, xmax, ymin, ymax.

sub def_droite_xml {
    my ($self,$x)=(@_);
    $self->def_droite_MN(map { $x->{$_}; } qw/xmin ymin xmax ymax/);

    return($self);
}

sub def_complete {
    my ($self,$xa,$ya,$xb,$yb,$xc,$yc,$xd,$yd)=(@_);
    $self->{'coins'}->[0]=[$xa,$ya];
    $self->{'coins'}->[1]=[$xb,$yb];
    $self->{'coins'}->[2]=[$xc,$yc];
    $self->{'coins'}->[3]=[$xd,$yd];
    $self->{'droite'}=0;

    return($self);
}

sub un_seul {
    my $x=shift;
    my $t=ref($x);
    if($t eq '') {
	return($x);
    } elsif($t eq 'SCALAR') {
	return($$x);
    } elsif($t eq 'ARRAY') {
	return($x->[0]);
    } elsif($t eq 'HASH') {
	my @k=keys %$x;
	return($x->{$k[0]});
    }
}

# definit la boite a l'aide d'une element XML (obtenu grace a
# XML::Simple) fabrique par AMC::Boite::xml.

sub def_complete_xml {
    my ($self,$x)=(@_);
    $x=$x->{'coin'} if($x->{'coin'});
    $self->def_complete(map { (un_seul($x->{$_}->{'x'}),
			       un_seul($x->{$_}->{'y'})) }
			(1..4));

    return($self);
}

sub new_MD {
    my (@o)=(@_);
    my $self=new();
    $self->def_droite_MD(@o);
    return($self);
}

sub new_MN {
    my (@o)=(@_);
    my $self=new();
    $self->def_droite_MN(@o);
    return($self);
}

sub new_xml {
    my (@o)=(@_);
    my $self=new();
    $self->def_droite_xml(@o);
    return($self);
}

sub new_complete {
    my (@o)=(@_);
    my $self=new();
    $self->def_complete(@o);
    return($self);
}

sub new_complete_xml {
    my (@o)=(@_);
    my $self=new();
    $self->def_complete_xml(@o);
    return($self);
}

# renvoie une description textuelle de la boite.

sub txt {
    my $self=shift;
    if($self->{'droite'}) {
	return(sprintf("(%.2f,%.2f)-(%.2f,%.2f) %.2f x %.2f",
		       @{$self->{'coins'}->[0]},
		       @{$self->{'coins'}->[2]},
		       $self->{'coins'}->[2]->[0]-$self->{'coins'}->[0]->[0],
		       $self->{'coins'}->[2]->[1]-$self->{'coins'}->[0]->[1],
		       ));
    } else {
	return(sprintf("(%.2f,%.2f) (%.2f,%.2f) (%.2f,%.2f) (%.2f,%.2f)",
		       @{$self->{'coins'}->[0]},
		       @{$self->{'coins'}->[1]},
		       @{$self->{'coins'}->[2]},
		       @{$self->{'coins'}->[3]},
		       ));
    }
}


# renvoie une commande draw pour tracer la boite grace a ImageMagick
sub draw_list {
    my $self=shift;
    return("-draw","polygon ".$self->draw_points());
}

sub draw_points {
    my $self=shift;
    return(sprintf("%.2f,%.2f %.2f,%.2f %.2f,%.2f %.2f,%.2f",
		   @{$self->{'coins'}->[0]},
		   @{$self->{'coins'}->[1]},
		   @{$self->{'coins'}->[2]},
		   @{$self->{'coins'}->[3]},
		   )
	   );
}

# renvoie une commande draw pour tracer la boite grace a ImageMagick
sub draw {
    my $self=shift;
    return(' '.join(' ',map { '"'.$_.'"' } ($self->draw_list())).' ');
}

# renvoie une description XML des coins de la boite.

sub xml {
    my ($self,$n)=(@_);
    my $x='';
    my $pre=' ' x $n;
    for my $i (0..3) {
	$x.=sprintf($pre."<coin id=\"%d\"><x>%.4f</x><y>%.4f</y></coin>\n",
		    $i+1,@{$self->{'coins'}->[$i]});
    }
    return($x);
}

sub to_data {
  my ($self,$capture,$zoneid,$type)=@_;
  for my $i (0..3) {
    $capture->set_corner($zoneid,$i+1,$type,@{$self->{'coins'}->[$i]});
  }
}

# renvoie la commande a passer a AMC::Image pour mesurer le contenu de
# la boite dans une image.

sub commande_mesure {
    my ($self,$prop)=(@_);
    my $c="mesure $prop";
    for my $i (0..4) {
	$c.=" ".join(" ",@{$self->{'coins'}->[$i]});
    }
    return($c);
}

sub commande_mesure0 {
    my ($self,$prop,$shape)=(@_);
    my $c="mesure0 $prop $shape "
      .join(' ',$self->etendue_xy('xy'));
    return($c);
}

# renvoie les coordonnees du centre de la boite.

sub centre {
    my $self=shift;
    my $x=0;
    my $y=0;
    for my $i (0..4) {
	$x+=$self->{'coins'}->[$i]->[0];
	$y+=$self->{'coins'}->[$i]->[1];
    }
    return($x/4,$y/4);
}

# renvoie la projection du centre de la boite sur une direction donnee.

sub centre_projete {
    my ($self,$ux,$uy)=(@_);
    my ($x,$y)=$self->centre();
    return($x*$ux+$y*$uy);
}

sub tri_dir {
    my ($x,$y,$bx)=(@_);
    @$bx=sort { $a->centre_projete($x,$y) <=> $b->centre_projete($x,$y) } @$bx;
}

# a partir d'une liste de boites, renvoie les quatres boites extremes
# : HG, HD, BD, BG

sub extremes {
    my (@liste)=(@_);
    my @r=();

    if(@liste) {
	tri_dir(1,1,\@liste);
	push @r,$liste[0];
	tri_dir(-1,1,\@liste);
	push @r,$liste[0];
	tri_dir(-1,-1,\@liste);
	push @r,$liste[0];
	tri_dir(1,-1,\@liste);
	push @r,$liste[0];
    } else {
	debug "Warning: Empty list in [extremes] call";
    }

    return(@r);
}

sub centres_extremes {
    my (@ex)=extremes(@_);
    return(map { $_->centre() } (@ex));
}

# direction entre point i et point j

sub direction {
    my ($self,$i,$j)=(@_);
    return(atan2($self->{'coins'}->[$j]->[1]-$self->{'coins'}->[$i]->[1],
		 $self->{'coins'}->[$j]->[0]-$self->{'coins'}->[$i]->[0]));

}

# renvoie le rayon du cercle circonscrit, si la boite est un losange.

sub rayon {
    my $self=shift;
    my ($x,$y)=$self->centre();
    return(sqrt(($x-$self->{'coins'}->[0]->[0]) ** 2 +
		($y-$self->{'coins'}->[0]->[1]) ** 2));
}

sub max {
    my($max) = shift(@_);

    for my $temp (@_) {
        $max = $temp if($temp > $max);
    }
    return($max);
}

sub min {
    my($min) = shift(@_);

    for my $temp (@_) {
        $min = $temp if($temp < $min);
    }
    return($min);
}

sub pos_txt {
    my ($self,$ligne)=(@_);
    my ($xmin,$ymin,$xmax,$ymax)=$self->etendue_xy('4');
    return(int($xmin-($xmax-$xmin) * 1.1),
	   int($ymin+($ligne+1)*($ymax-$ymin)/3)
	   );
}

sub etendue_xy {
    my ($self,$mode,@o)=(@_);
    my ($xmin,$ymin,$xmax,$ymax)=(@{$self->{'coins'}->[0]},@{$self->{'coins'}->[0]});
    my @r;
    for my $i (1..3) {
	my $x=$self->{'coins'}->[$i]->[0];
	my $y=$self->{'coins'}->[$i]->[1];
	$xmax=$x if($x>$xmax);
	$xmin=$x if($x<$xmin);
	$ymax=$y if($y>$ymax);
	$ymin=$y if($y<$ymin);
    }
    if($mode eq 'xml') {
	@r=sprintf("xmin=\"%.2f\" xmax=\"%.2f\" ymin=\"%.2f\" ymax=\"%.2f\"",
		       $xmin,$xmax,$ymin,$ymax);
    } elsif($mode eq 'geometry') {
	my ($marge,$txt)=@o;
	($xmin,$ymin)=$self->pos_txt(-1) if($txt);
	@r=sprintf("%.2fx%.2f+%.2f+%.2f",
		   $xmax-$xmin+2*$marge,$ymax-$ymin+2*$marge,
		   $xmin-$marge,$ymin-$marge);
    } elsif($mode eq '4') {
	@r=($xmin,$ymin,$xmax,$ymax);
    } elsif($mode eq 'xy') {
	@r=($xmin,$xmax,$ymin,$ymax);
    } elsif($mode eq 'xmin') {
	@r=$xmin;
    } elsif($mode eq 'xmax') {
	@r=$xmax;
    } elsif($mode eq 'ymin') {
	@r=$ymin;
    } elsif($mode eq 'ymax') {
	@r=$ymax;
    } else {
	@r=($xmax-$xmin,$ymax-$ymin);
    }
    return(wantarray ? @r : $r[0]);
}

sub coordonnees {
    my ($self,$i,$c)=(@_);
    my @r=();
    push @r,$self->{'coins'}->[$i]->[0] if($c =~/x/i);
    push @r,$self->{'coins'}->[$i]->[1] if($c =~/y/i);
    return(wantarray ? @r : $r[0]);
}

sub diametre {
    my $self=shift;
    my ($dx,$dy)=$self->etendue_xy();
    return(($dx+$dy)/2);
}

sub bonne_etendue {
    my ($self,$dmin,$dmax)=(@_);
    my ($dx,$dy)=$self->etendue_xy();
    return( $dx >= $dmin && $dx <= $dmax
	    && $dy >= $dmin && $dy <= $dmax);
}

sub transforme { # avec AMC::Calage
    my ($self,$transf)=(@_);
    for my $i (0..3) {
	$self->{'coins'}->[$i]=[$transf->transforme(@{$self->{'coins'}->[$i]})];
    }
    $self->{'droite'}=0;
    return($self);
}

1;
