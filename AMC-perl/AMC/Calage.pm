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

package AMC::Calage;

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
    @EXPORT_OK   = qw();
}

my $M_PI=atan2(1,1)*4;
my $HUGE=32000;

sub new {
    my (%o)=(@_);

    my $self={'type'=>'lineaire',
	      'log'=>1,
	      't_a'=>'',
	      't_b'=>'',
	      't_c'=>'',
	      't_d'=>'',
	      't_e'=>'',
	      't_f'=>'',
	      'MSE'=>'',
	  };

    for my $k (keys %o) {
	$self->{$k}=$o{$k} if(defined($self->{$k}));
    }

    bless $self;
    
    $self->identity();
    $self->clear_min_max();

    return($self);
}

sub mse {
    my ($self)=(@_);
    return($self->{'MSE'});
}

sub identity {
    my ($self)=(@_);
    $self->{'type'}='lineaire';
    $self->{'t_a'}=1;
    $self->{'t_b'}=0;
    $self->{'t_c'}=0;
    $self->{'t_d'}=1;
    $self->{'t_e'}=0;
    $self->{'t_f'}=0;
    $self->{'MSE'}=0;
}

##########################################################
# calcul vectoriel

sub moyenne {
    my @a=(@_);
    my $s=0;
    for (@a) { $s+=$_; }
    return($s/($#a+1));
}

sub crochet {
    my ($a,$b)=(@_);
    my $ma=moyenne(@$a);
    my $mb=moyenne(@$b);
    my $s=0;
    for(0..$#{$a}) {
	$s+=($a->[$_]-$ma)*($b->[$_]-$mb);
    }
    return($s/($#{$a}+1));
}

sub resoud_22 {
    # resoud systeme 2x2
    # ax+by=e
    # cx+dy=f
    my ($a,$b,$c,$d,$e,$f)=(@_);
    my $delta=$a*$d-$b*$c;
    return(($d*$e-$b*$f)/$delta,(-$c*$e+$a*$f)/$delta);
}

#############################################################

sub clear_min_max {
    my $self=shift;

    $self->{'t_x_min'}=$HUGE;
    $self->{'t_y_min'}=$HUGE;
    $self->{'t_x_max'}=0;
    $self->{'t_y_max'}=0;
}

sub transforme {
    my ($self,$x,$y,$nominmax)=(@_);
    
    my ($xp,$yp);

    if($self->{'type'} =~ /^[hl]/i) {
	$xp=$self->{'t_a'}*$x+$self->{'t_b'}*$y+$self->{'t_e'};
	$yp=$self->{'t_c'}*$x+$self->{'t_d'}*$y+$self->{'t_f'};
    }

    if(!$nominmax) {
	$self->{'t_x_min'}=$xp if($xp<$self->{'t_x_min'});
	$self->{'t_y_min'}=$yp if($yp<$self->{'t_y_min'});
	$self->{'t_x_max'}=$xp if($xp>$self->{'t_x_max'});
	$self->{'t_y_max'}=$yp if($yp>$self->{'t_y_max'});
    }

    return($xp,$yp);
}

sub calage {
    my ($self,$cx,$cy,$cxp,$cyp)=(@_);

    if($self->{'type'} =~ /^h/i) {
	###################### HELMERT

	my $theta,$alpha;

	$theta=atan2(crochet($cx,$cyp)-crochet($cxp,$cy),
		     crochet($cx,$cxp)+crochet($cy,$cyp));

	debug sprintf("theta = %.3f\n",$theta*180/$M_PI);

	my $den=crochet($cx,$cx)+crochet($cy,$cy);
	if(abs(cos($theta))>abs(sin($theta))) {
	    $alpha=(crochet($cx,$cxp)+crochet($cy,$cyp))/($den*cos($theta));
	} else {
	    $alpha=(crochet($cx,$cyp)-crochet($cxp,$cy))/($den*sin($theta));
	}

	if($alpha<0) {
	    $alpha=abs($alpha);
	    $theta+=($theta>0 ? -1 : 1)*$M_PI;
	}

	$self->{'t_e'}=moyenne(@$cxp)-$alpha*(moyenne(@$cx)*cos($theta)-moyenne(@$cy)*sin($theta));
	$self->{'t_f'}=moyenne(@$cyp)-$alpha*(moyenne(@$cx)*sin($theta)+moyenne(@$cy)*cos($theta));

	debug "alpha = $alpha\n";

	$self->{'t_a'}=$alpha*cos($theta);
	$self->{'t_b'}=-$alpha*sin($theta);
	$self->{'t_c'}=$alpha*sin($theta);
	$self->{'t_d'}=$alpha*cos($theta);

    } elsif($self->{'type'} =~ /^l/i) {
	########################## LINEAIRE

	my $sxx=crochet($cx,$cx);
	my $sxy=crochet($cx,$cy);
	my $syy=crochet($cy,$cy);

	my $sxxp=crochet($cx,$cxp);
	my $syxp=crochet($cy,$cxp);
	my $sxyp=crochet($cx,$cyp);
	my $syyp=crochet($cy,$cyp);

	($self->{'t_a'},$self->{'t_b'})
	    =resoud_22($sxx,$sxy,$sxy,$syy,$sxxp,$syxp);
	$self->{'t_e'}=moyenne(@$cxp)-($self->{'t_a'}*moyenne(@$cx)+$self->{'t_b'}*moyenne(@$cy));

	($self->{'t_c'},$self->{'t_d'})
	    =resoud_22($sxx,$sxy,$sxy,$syy,$sxyp,$syyp);
	$self->{'t_f'}=moyenne(@$cyp)-($self->{'t_c'}*moyenne(@$cx)+$self->{'t_d'}*moyenne(@$cy));
	
    } else {
	debug "ERR: invalid type: $self->{'type'}\n";
    }

    if($self->{'log'} && $self->{'type'} =~ /^[hl]/i) {
	debug "Linear transform:\n";
	debug sprintf(" %7.3f %7.3f     %10.3f\n %7.3f %7.3f     %10.3f\n",
		      $self->{'t_a'},$self->{'t_b'},$self->{'t_e'},
		      $self->{'t_c'},$self->{'t_d'},$self->{'t_f'});
    }

    ############ evaluation de la qualite de l'ajustement

    my $sd=0;
    for my $i (0..$#{$cx}) {
	my ($x,$y)=$self->transforme($cx->[$i],$cy->[$i],1);
	$sd+=($x-$cxp->[$i])**2+($y-$cyp->[$i])**2;
    }
    $self->{'MSE'}=sqrt($sd/($#{$cx}+1));

    debug(sprintf("MSE = %.3f\n",$self->{'MSE'}));
    printf("Adjust: MSE = %.3f\n",$self->{'MSE'}) if($self->{'log'});

    return($self->{'MSE'});
}

sub params {
  my ($self)=@_;
  return(map { $self->{$_} } (qw/t_a t_b t_c t_d t_e t_f MSE/));
}

sub xml {
    my ($self,$i)=(@_);
    my $pre=" " x $i;
    my $r=$pre.sprintf("<transformation type=\"%s\" mse=\"%f\">\n",
		       $self->{'type'},$self->{'MSE'});
    $r.=$pre."  <parametres>\n";
    if($self->{'type'} =~ /^[hl]/i) {
	$r.=$pre."      <a>".$self->{'t_a'}."</a>\n";
	$r.=$pre."      <b>".$self->{'t_b'}."</b>\n";
	$r.=$pre."      <c>".$self->{'t_c'}."</c>\n";
	$r.=$pre."      <d>".$self->{'t_d'}."</d>\n";
	$r.=$pre."      <e>".$self->{'t_e'}."</e>\n";
	$r.=$pre."      <f>".$self->{'t_f'}."</f>\n";
    }
    $r.=$pre."  </parametres>\n";
    $r.=$pre."</transformation>\n";
    return($r);
}
