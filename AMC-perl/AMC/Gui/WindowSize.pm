# -*- perl -*-
#
# Copyright (C) 2012-2017 Alexis Bienvenue <paamc@passoire.fr>
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

sub constraints {
  my ($x0, $dx, $dxmax)=@_;
  my $over = $$x0 + $$dx - $dxmax;
  if($over > 0) {
    if($over > $$x0) {
      $$x0 = 0;
      $$dx = $dxmax;
    } else {
      $$x0 -= $over;
    }
  }
}

sub size_monitor {
  my ($window, $options)=@_;
  if($options->{config}) {
    if($options->{config}->get($options->{key})
       =~ /^([0-9]+)x([0-9]+)(?:\+([0-9]+)\+([0-9]+))?$/) {
      my $target_w = $1;
      my $target_h = $2;
      my $x = $3; $x = 0 if(!defined($x));
      my $y = $4; $y = 0 if(!defined($y));
      my $screen = $window->get_screen();
      my $max_w = $screen->get_width;
      my $max_h = $screen->get_height;

      constraints(\$x, \$target_w, $max_w);
      constraints(\$y, \$target_h, $max_h);

      $window->move($x, $y);
      $window->resize($target_w, $target_h);
    }
    $window->signal_connect('configure-event' => \&AMC::Gui::WindowSize::resize,
			    $options);
  }
}

sub resize {
  my ($window, $event, $options)=@_;
  if($options->{config} && $event->type eq 'configure') {
    my $dims=join('x', $event->width, $event->height);
    my $pos=join('+', $event->window->get_root_origin);
    $options->{config}->set($options->{key}, $dims . "+" . $pos);
  }
  0;
}

1;
