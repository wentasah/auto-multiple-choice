#
# Copyright (C) 2008-2013 Alexis Bienvenue <paamc@passoire.fr>
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

package AMC::Subprocess;

use AMC::Basic;
use IPC::Open2;

sub new {
    my (%o)=(@_);
    my $self={'file'=>'',
	      'ipc_in'=>'',
	      'ipc_out'=>'',
	      'ipc'=>'',
	      'args'=>['%f'],
	      'mode'=>'detect',
	      'exec_file'=>'',
	  };

    for my $k (keys %o) {
	$self->{$k}=$o{$k} if(defined($self->{$k}));
    }

    if(! $self->{'exec_file'}) {
      if($self->{'mode'}) {
	$self->{'exec_file'}=amc_specdir('libexec').'/AMC-'.$self->{'mode'};
      }
    }

    if(! -f $self->{'exec_file'}) {
      die "AMC::Subprocess: No program to execute";
    }

    bless $self;

    return($self);
}

sub set {
    my ($self,%oo)=(@_);
    for my $k (keys %oo) {
	$self->{$k}=$oo{$k} if(defined($self->{$k}));
    }
}

sub commande {
    my ($self,@cmd)=(@_);
    my @r=();

    if(!$self->{'ipc'}) {
	debug "Exec subprocess..."; 
	my @a=map { ( $_ eq '%f' ? $self->{'file'} : $_ ) }
	(@{$self->{'args'}});
	debug join(' ',$self->{'exec_file'},@a);
	$self->{'times'}=[times()];
	$self->{'ipc'}=open2($self->{'ipc_out'},$self->{'ipc_in'},
			     $self->{'exec_file'},@a);

	binmode $self->{'ipc_out'},':utf8';
	binmode $self->{'ipc_in'},':utf8';
	debug "PID=".$self->{'ipc'}." : ".$self->{'ipc_in'}." --> ".$self->{'ipc_out'};
    }

    debug "CMD : ".join(' ',@cmd);

    print { $self->{'ipc_in'} } join(' ',@cmd)."\n";

    my $o;
  GETREPONSE: while($o=readline($self->{'ipc_out'})) {
      chomp($o);
      debug "|> $o";
      last GETREPONSE if($o =~ /_{2}END_{2}/);
      push @r,$o;
  }

    return(@r);
}

sub ferme_commande {
    my ($self)=(@_);
    if($self->{'ipc'}) {
	debug "Image sending QUIT";
	print { $self->{'ipc_in'} } "quit\n";
	waitpid $self->{'ipc'},0;
	$self->{'ipc'}='';
	$self->{'ipc_in'}='';
	$self->{'ipc_out'}='';
	my @tb=times();
	debug sprintf("Image finished: parent times [%7.02f,%7.02f]",
		      $tb[0]+$tb[1]-$self->{'times'}->[0]-$self->{'times'}->[1],$tb[2]+$tb[3]-$self->{'times'}->[2]-$self->{'times'}->[3]);
    }
}

sub DESTROY {
    my ($self)=(@_);
    $self->ferme_commande();
}

1;
