#
# Copyright (C) 2009-2017 Alexis Bienvenue <paamc@passoire.fr>
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

package AMC::Exec;

use AMC::Basic;

sub new {
    my ($nom)=@_;
    my $self={'pid'=>'',
	      'nom'=>$nom || 'AMC',
	  };
    bless($self);
    return($self);
}

sub catch_signal {
    my ($self,$signame)=@_;
    if($self->{'pid'}) {
	debug "*** $self->{'nom'} : signal $signame, killing $self->{'pid'}...\n";
	kill 9,$self->{'pid'};
    }
    die "$self->{'nom'} killed";
}

sub signalise {
    my ($self)=@_;
    $SIG{INT} = sub { my $s=shift;$self->catch_signal($s); };
}

sub execute {
    my ($self,@c)=@_;

    my $prg=$c[0];

    if($prg) {

	if(!commande_accessible($prg)) {
	    debug "*** WARNING: program \"$prg\" not found in PATH!";
	}

	my $cmd_pid=fork();
	my @t=times();
	if($cmd_pid) {
	    $self->{'pid'}=$cmd_pid;
	    debug "Command [$cmd_pid] : ".join(' ',@c);
	    waitpid($cmd_pid,0);
	    my @tb=times();
	    debug "Cmd PID=$cmd_pid returns $?";
	    debug sprintf("Total parent exec times during $cmd_pid: [%7.02f,%7.02f]",$tb[0]+$tb[1]-$t[0]-$t[1],$tb[2]+$tb[3]-$t[2]-$t[3]);
	} else {
	    exec(@c);
	    die "Commande inexistante : $prg";
	}

    } else {
	debug "Command: no executable! ".join(' ',@c);
    }

}

1;

