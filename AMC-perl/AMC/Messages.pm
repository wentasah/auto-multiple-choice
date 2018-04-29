#
# Copyright (C) 2012 Alexis Bienvenue <paamc@passoire.fr>
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

package AMC::Messages;

use AMC::Basic;

# possible types: INFO, WARN, ERR

my %message_type=('INFO'=>1,
		  'WARN'=>2,
		  'ERR'=>3,
		  );

sub add_message {
  my ($self,$type,$message)=@_;
  if(!$message_type{$type}) {
    debug "WARNING: inexistant message type - $type";
  }
  push @{$self->{'messages'}},{'type'=>$type,'message'=>$message};
}

sub get_messages {
  my ($self,$type)=@_;
  return(map { $_->{'message'} }
	 grep { $_->{'type'} eq $type } @{$self->{'messages'}});
}

sub n_messages {
  my ($self,$type)=@_;
  my @m=$self->get_messages($type);
  return(1+$#m);
}

sub messages_as_string {
  my ($self)=@_;
  my $s='';
  for(@{$self->{'messages'}}) {
    $s.= $_->{'type'} .": ".$_->{'message'} ."\n";
  }
  return($s);
}

sub higher_message_type {
  my ($self)=@_;
  my $h=0;
  my $type='';
  for(@{$self->{'messages'}}) {
    if($message_type{$_->{'type'}} > $h) {
      $type=$_->{'type'};
      $h=$message_type{$type};
    }
  }
  return($type);
}

