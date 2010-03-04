#! /usr/bin/perl -w
#
# Copyright (C) 2008-2010 Alexis Bienvenue <paamc@passoire.fr>
#
# This file is part of Auto-Multiple-Choice
#
# Auto-Multiple-Choice is free software: you can redistribute it
# and/or modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation, either version 3 of
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

package AMC::Gui::Commande;

use Gtk2::Helper;

use AMC::Basic;
use AMC::Gui::Avancement;

sub new {
    my %o=(@_);
    my $self={
	'commande'=>'',
	'log'=>'',
	'avancement'=>'',
	'texte'=>'',
	'progres.id'=>'',
	'progres.pulse'=>'',
	'fin'=>'',
	'finw'=>'',
	'signal'=>9,
	'o'=>{},

	'erreurs'=>[],
	'variables'=>{},
	
	'pid'=>'',
	'avance'=>'',
	'fh'=>'',
	'tag'=>'',
	'pid'=>'',
    };

    for (keys %o) {
	$self->{$_}=$o{$_} if(defined($self->{$_}) || /^niveau/);
    }

    $self->{'commande'}=[$self->{'commande'}] if(!ref($self->{'commande'}));

    bless $self;
    
    return($self);
}

sub proc_pid {
    my ($self)=(@_);
    return($self->{'pid'});
}

sub erreurs {
    my ($self)=(@_);
    return(@{$self->{'erreurs'}});
}

sub variables {
    my ($self)=(@_);
    return(%{$self->{'variables'}});
}

sub variable {
    my ($self,$k)=(@_);
    return $self->{'variables'}->{$k};
}

sub quitte {
    my ($self)=(@_);
    my $pid=$self->proc_pid();
    debug "Canceling command [".$self->{'signal'}."->".$pid."].";
    
    kill $self->{'signal'},$pid if($pid =~ /^[0-9]+$/);
}

sub open {
    my ($self)=@_;

    $self->{'pid'}=open($self->{'fh'},"-|",@{$self->{'commande'}});
    if(defined($self->{'pid'})) {
	
	$self->{'tag'}=Gtk2::Helper->add_watch( fileno( $self->{'fh'} ),
						in => sub { $self->get_output() }
						);
	
	debug "Command [".$self->{'pid'}."] : ".join(' ',@{$self->{'commande'}});
	
	if($self->{'avancement'}) {
	    $self->{'avancement'}->set_text($self->{'texte'});
	    $self->{'avancement'}->set_fraction(0);
	    $self->{'avancement'}->set_pulse_step($self->{'progres.pulse'})
		if($self->{'progres.pulse'});
	}
	
	$self->{'avance'}=AMC::Gui::Avancement::new(0);
	
	$self->{'log'}->get_buffer()->set_text('');

    } else {
	print STDERR "ERROR execing command\n".join(' ',@{$self->{'commande'}})."\n"; 
    }
}


sub get_output {
    my ($self)=@_;

    if( eof($self->{'fh'}) ) {
        Gtk2::Helper->remove_watch( $self->{'tag'} );
	  close($self->{'fh'});
	  
	  debug "Command [".$self->{'pid'}."] : OK - ".(1+$#{$self->{'erreurs'}})." erreur(s)\n";
	  
	  $self->{'pid'}='';
	  $self->{'tag'}='';
	  $self->{'fh'}='';
	  
	  $self->{'avancement'}->set_text('');
	  
	  &{$self->{'finw'}}($self) if($self->{'finw'});
	  &{$self->{'fin'}}($self) if($self->{'fin'});

    } else {
	my $fh=$self->{'fh'};
	my $line = <$fh>;

	my $log=$self->{'log'};
	my $logbuff=$log->get_buffer();

	$logbuff->insert($logbuff->get_end_iter(),$line);
	$logbuff->place_cursor($logbuff->get_end_iter());
	$log->scroll_to_iter($logbuff->get_end_iter(),0,0,0,0);
	
	if($line =~ /^ERR/) {
	    chomp(my $lc=$line);
	    push @{$self->{'erreurs'}},$lc;
	}
	if($line =~ /^VAR:\s*([^=]+)=(.*)/) {
	    $self->{'variables'}->{$1}=$2;
	}

	if($self->{'avancement'}) {
	    if($self->{'progres.pulse'}) {
		$self->{'avancement'}->pulse;
	    } else {
		my $r=$self->{'avance'}->lit($line);
		$self->{'avancement'}->set_fraction($r) if($r);
	    }
	}
	
    }

    return 1;
}

1;

