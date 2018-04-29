#
# Copyright (C) 2015 Alexis Bienvenue <paamc@passoire.fr>
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

package AMC::Print;

use AMC::Basic;

sub new {
  my ($class,%o) = @_;
  my $self={method=>'none',
	    useful_options=>'',
	    error=>'',
	   };

  for my $k (keys %o) {
    $self->{$k}=$o{$k} if(defined($self->{$k}));
  }

  bless ($self, $class);
  return $self;
}

# printing-mode selection

sub check_available {
  return();
}

sub weight {
  return(0);
}

# PRINTING OPTIONS

# returns a list of hashrefs
# {name=>'printer short name',
#  description=>'printer description'}
sub printers_list {
  my ($self)=@_;
  return();
}

# returns the default printer name
sub default_printer {
  my ($self)=@_;
  my @p=$self->printers_list();
  return($p[0]->{name});
}

# returns a list of hashrefs
# {name=>'option name',
#  description=>'option description',
#  values=>[{name=>'value name',
#            description=>'value description'},
#            ...
#          ],
#  default=>'default value name',
# }
sub printer_options_list {
  my ($self,$printer)=@_;
  return();
}

sub printer_selected_options {
  my ($self,$printer)=@_;
  if($self->{useful_options} =~ /[^\s]/) {
    my $re="(".join("|",split(/\s+/,$self->{useful_options})).")";
    return(grep { $_->{name} =~ /^$re$/i }
	   ($self->printer_options_list($printer)));
  } else {
    return();
  }
}

# Builds a Gtk table for printer options
# $table = GtkTable to be modified
# $w = widgets hashref for use with transmet_pref/reprend_pref
# $prefs = AMC::Gui::Prefs object
# $printer = printer name
# $printer_options = current printer options hashref
sub printer_options_table {
  my ($self,$table,$w,$prefs,$printer,$printer_options)=@_;

  my @options=$self->printer_selected_options($printer);

  for($table->get_children) {
    $_->destroy();
  }

  $table->resize(@options ? 1+$#options : 1,2);

  my $y=0;
  my $widget;
  my $renderer;
  for my $o (@options) {
    $table->attach(Gtk2::Label->new($o->{description}),
		   0,1,$y,$y+1,["expand","fill"],[],0,0);
    $widget=Gtk2::ComboBox->new_with_model();
    $renderer = Gtk2::CellRendererText->new();
    $widget->pack_start($renderer, TRUE);
    $widget->add_attribute($renderer,'text',COMBO_TEXT);
    $w->{'printer_c_'.$o->{name}}=$widget;
    $table->attach($widget,1,2,$y,$y+1,["expand","fill"],[],0,0);
    $y++;

    my %opt_values=map {
      $_->{name}=>$_->{description}
    } @{$o->{values}};

    $prefs->store_register($o->{name} => cb_model(map {
      ($_->{name},$_->{description})
    } @{$o->{values}}));
    my $opt_value=$printer_options->{$o->{name}};
    if(!$opt_value || !$opt_values{$opt_value}) {
      debug "Setting option $o->{name} to default: $o->{default}";
      $printer_options->{$o->{name}}=$o->{default};
    }
  }
  $table->show_all();
}

# PRINTING

sub select_printer {
  my ($self,$printer)=@_;
}

sub set_option {
  my ($self,$option,$value)=@_;
}

sub print_file {
  my ($self,$filename)=@_;
}

1;
