# -*- perl -*-
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

package AMC::Gui::WindowSize;

sub size_monitor {
  my ($window,$options)=@_;
  if($options->{env}) {
    if($options->{env}->{$options->{key}} =~ /^([0-9]+)x([0-9]+)$/) {
      $window->resize($1,$2);
    }
    $window->signal_connect('configure-event'=>\&AMC::Gui::WindowSize::resize,
			    $options);
  }
}

sub resize {
  my ($window,$event,$options)=@_;
  if($options->{env} && $event->type eq 'configure') {
    my $dims=join('x',$event->width,$event->height);
    if($dims ne $options->{env}->{$options->{key}}) {
      $options->{env}->{$options->{key}}=$dims;
      $options->{env}->{'_modifie_ok'}=1;
    }
  }
  0;
}

1;
