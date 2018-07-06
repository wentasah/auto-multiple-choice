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

package AMC::Export::register::List;

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
# TRANSLATORS: List of students with their scores: one of the export formats.
  return(__("PDF list"));
}

sub extension {
  return('.pdf');
}

sub options_from_config {
  my ($self,$config)=@_;
  return("nom"=>$config->get('nom_examen'),
	 "code"=>$config->get('code_examen'),
	 "decimal"=>$config->get('delimiteur_decimal'),
	 "pagesize"=>$config->get('export_pagesize'),
	 "ncols"=>$config->get('export_ncols'),
	);
}

sub options_default {
  return('export_ncols'=>2,
	 'export_pagesize'=>'a4');
}

sub build_config_gui {
  my ($self,$w,$prefs)=@_;
  my $t=Gtk3::Grid->new();
  my $widget;
  my $y=0;
  $t->attach(Gtk3::Label->new(__"Number of columns"),
	     0,$y,1,1);
  $widget=Gtk3::SpinButton->new(Gtk3::Adjustment->new(1,1,5,1,1,0),0,0);
  $widget->set_tooltip_text(__"Long list is divided into this number of columns on each page.");
  $w->{'export_s_export_ncols'}=$widget;
  $t->attach($widget,1,$y,1,1);
  $y++;
  $t->attach(Gtk3::Label->new(__"Paper size"),
             0,$y,1,1);
  $widget=Gtk3::ComboBox->new();
  my $renderer = Gtk3::CellRendererText->new();
  $widget->pack_start($renderer, TRUE);
  $widget->add_attribute($renderer,'text',COMBO_TEXT);
  $prefs->store_register('export_pagesize'=>cb_model("a3"=>"A3",
						     "a4"=>"A4",
						     "letter"=>"Letter",
						     "legal"=>"Legal"));
  $w->{'export_c_export_pagesize'}=$widget;
  $t->attach($widget,1,$y,1,1);
  $y++;

  $t->show_all;
  return($t);
}

sub weight {
  return(.5);
}

1;
