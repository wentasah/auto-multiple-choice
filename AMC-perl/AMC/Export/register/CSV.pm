#
# Copyright (C) 2012,2014 Alexis Bienvenue <paamc@passoire.fr>
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

package AMC::Export::register::CSV;

use AMC::Export::register;
use AMC::Basic;
use AMC::Gui::Prefs;

@ISA=("AMC::Export::register");

sub new {
    my $class = shift;
    my $self  = $class->SUPER::new();
    bless ($self, $class);
    return $self;
}

sub name {
  return('CSV');
}

sub extension {
  return('.csv');
}

sub options_from_config {
  my ($self,$options_project,$options_main,$options_default)=@_;
  my $enc=$options_project->{"encodage_csv"}
    || $options_main->{"defaut_encodage_csv"}
      || $options_main->{"encodage_csv"}
	|| $options_main->{"defaut_encodage_csv"}
	  || $options_default->{"encodage_csv"}
	    || "UTF-8";
  return("encodage"=>$enc,
	 "columns"=>$options_project->{'export_csv_columns'},
	 "decimal"=>$options_main->{'delimiteur_decimal'},
	 "separateur"=>$options_project->{'export_csv_separateur'},
	 "ticked"=>$options_project->{'export_csv_ticked'},
	);
}

sub options_default {
  return('export_csv_separateur'=>";",
	 'export_csv_ticked'=>'',
	 'export_csv_columns'=>'student.copy,student.key,student.name',
	);
}

sub build_config_gui {
  my ($self,$w,$prefs)=@_;
  my $t=Gtk2::Table->new(3,2);
  my $widget;
  my $y=0;
  my $renderer;

  $t->attach(Gtk2::Label->new(__"Separator"),
	     0,1,$y,$y+1,["expand","fill"],[],0,0);
  $widget=Gtk2::ComboBox->new_with_model();
  $renderer = Gtk2::CellRendererText->new();
  $widget->pack_start($renderer, TRUE);
  $widget->add_attribute($renderer,'text',COMBO_TEXT);
  $prefs->store_register('export_csv_separateur'=>cb_model("TAB"=>'<TAB>',
							   ";"=>";",
							   ","=>","));
  $w->{'export_c_export_csv_separateur'}=$widget;
  $t->attach($widget,1,2,$y,$y+1,["expand","fill"],[],0,0);
  $y++;

  $t->attach(Gtk2::Label->new(__"Ticked boxes"),0,1,$y,$y+1,["expand","fill"],[],0,0);
  $widget=Gtk2::ComboBox->new_with_model();
  $renderer = Gtk2::CellRendererText->new();
  $widget->pack_start($renderer, TRUE);
  $widget->add_attribute($renderer,'text',COMBO_TEXT);
  $prefs->store_register('export_csv_ticked'=>cb_model(""=>__"No",
						       "01"=>(__"Yes:")." 0;0;1;0",
						       "AB"=>(__"Yes:")." AB",
						      ));
  $w->{'export_c_export_csv_ticked'}=$widget;
  $t->attach($widget,1,2,$y,$y+1,["expand","fill"],[],0,0);
  $y++;

  $widget=Gtk2::Button->new_with_label(__"Choose columns");
  $widget->signal_connect(clicked => \&main::choose_columns_current);
  $t->attach($widget,0,2,$y,$y+1,["expand","fill"],[],0,0);
  $y++;

  $t->show_all;
  return($t);
}

sub weight {
  return(.9);
}

1;
