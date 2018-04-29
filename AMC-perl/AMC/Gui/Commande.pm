#! /usr/bin/perl -w
#
# Copyright (C) 2008-2014 Alexis Bienvenue <paamc@passoire.fr>
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

package AMC::Gui::Commande;

use Gtk2::Helper;
use Encode;

use AMC::Basic;
use AMC::Gui::Avancement;

use AMC::Messages;

@ISA=("AMC::Messages");

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
	'clear'=>1,

	'messages'=>[],
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
    return($self->get_messages('ERR'));
}

sub warnings {
    my ($self)=(@_);
    return($self->get_messages('WARN'));
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

    $self->{closing}=1;
    $self->stop_watch();

    my $pid=$self->proc_pid();
    debug "Canceling command [".$self->{'signal'}."->".$pid."].";

    kill $self->{'signal'},$pid if($pid =~ /^[0-9]+$/);

    $self->close(cancelled=>1);
}

sub open {
    my ($self)=@_;

    $self->{'times'}=[times()];
    $self->{'pid'}=open($self->{'fh'},"-|",@{$self->{'commande'}});
    if(defined($self->{'pid'})) {

	$self->{'tag'}=Gtk2::Helper->add_watch( fileno( $self->{'fh'} ),
						in => sub { $self->get_output() }
						);

	debug "Command [".$self->{'pid'}."] : "
	  .join(' ',map { /\s/ || ! $_ ? "\"$_\"" : $_ }
		@{$self->{'commande'}});

	if($self->{'avancement'}) {
	    $self->{'avancement'}->set_text($self->{'texte'});
	    $self->{'avancement'}->set_fraction(0);
	    $self->{'avancement'}->set_pulse_step($self->{'progres.pulse'})
		if($self->{'progres.pulse'});
	}

	$self->{'avance'}=AMC::Gui::Avancement::new
	  (0,'bar'=>$self->{'avancement'});

	$self->{'log'}->get_buffer()->set_text('') if($self->{'clear'});

    } else {
	print STDERR "ERROR execing command\n".join(' ',@{$self->{'commande'}})."\n";
    }
}

sub stop_watch {
  my ($self)=@_;

  if($self->{tag}) {
    Gtk2::Helper->remove_watch( $self->{tag} );
    $self->{tag}='';
  }
}

sub close {
  my ($self,%data)=@_;

  $self->stop_watch();

  close($self->{'fh'});

  debug "Command [".$self->{'pid'}."] : OK - ".($self->n_messages('ERR'))." erreur(s)\n";

  my @tb=times();
  debug sprintf("Total parent exec times during ".$self->{pid}.": [%7.02f,%7.02f]",$tb[0]+$tb[1]-$self->{'times'}->[0]-$self->{'times'}->[1],$tb[2]+$tb[3]-$self->{'times'}->[2]-$self->{'times'}->[3]);

  $self->{'pid'}='';
  $self->{'tag'}='';
  $self->{'fh'}='';

  $self->{'avancement'}->set_text('');

  &{$self->{'finw'}}($self,%data) if($self->{'finw'});
  &{$self->{'fin'}}($self,%data) if($self->{'fin'});
}

sub get_output {
    my ($self)=@_;

    return if($self->{closing});

    if( eof($self->{'fh'}) ) {
      $self->close();
    } else {
	my $fh=$self->{'fh'};
	my $line = decode("utf8",<$fh>);
	my $r='';

	if($self->{'avancement'}) {
	    if($self->{'progres.pulse'}) {
		$self->{'avancement'}->pulse;
	    } else {
	      $self->{'avance'}->lit($line,
				     {'bar'=>$self->{'avancement'}});
	    }
	}

	if($r eq '') {
	  my $log=$self->{'log'};
	  my $logbuff=$log->get_buffer();

	  $logbuff->insert($logbuff->get_end_iter(),$line);
	  $logbuff->place_cursor($logbuff->get_end_iter());
	  $log->scroll_to_iter($logbuff->get_end_iter(),0,0,0,0);

	  if($line =~ /^(ERR|INFO|WARN)/) {
	    chomp(my $lc=$line);
	    $lc =~ s/^(ERR|INFO|WARN)[:>]\s*//;
	    $self->add_message($1,$lc);
	  }
	  if($line =~ /^VAR:\s*([^=]+)=(.*)/) {
	    $self->{'variables'}->{$1}=$2;
	  }
	  for my $k (qw/OK FAILED/) {
	    if($line =~ /^$k/) {
	      $self->{'variables'}->{$k}++;
	    }
	  }
	}


    }

    return 1;
}

1;

