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

package AMC::Export::register::ods;

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
  return('OpenOffice');
}

sub extension {
  return('.ods');
}

sub options_from_config {
  my ($self,$config)=@_;
  return("columns"=>$config->get('export_ods_columns'),
	 "nom"=>$config->get('nom_examen'),
	 "code"=>$config->get('code_examen'),
	 "stats"=>$config->get('export_ods_stats'),
	 "statsindic"=>$config->get('export_ods_statsindic'),
	 "groupsums"=>$config->get('export_ods_group'),
	 "groupsep"=>$config->get('export_ods_groupsep'),
	 );
}

sub needs_catalog {
  my ($self,$config)=@_;
  return($config->get('export_ods_stats')
        || $config->get('export_ods_statsindic'));
}

sub options_default {
  return('export_ods_columns'=>'student.copy,student.key,student.name',
	 'export_ods_stats'=>'',
	 'export_ods_statsindic'=>'',
	 'export_ods_group'=>'0',
	 'export_ods_groupsep'=>':',
	 );
}

sub needs_module {
  return('OpenOffice::OODoc');
}

sub build_config_gui {
  my ($self,$w,$prefs)=@_;
  my $t=Gtk3::Grid->new();
  my $widget;
  my $renderer;
  my $y=0;

# TRANSLATORS: Check button label in the exports tab. If checked, a table with questions basic statistics will be added to the ODS exported spreadsheet.
  $t->attach(Gtk3::Label->new(__"Stats table"),
	     0,$y,1,1);
  $widget=Gtk3::ComboBox->new();
  $renderer = Gtk3::CellRendererText->new();
  $widget->pack_start($renderer, TRUE);
  $widget->add_attribute($renderer,'text',COMBO_TEXT);
# TRANSLATORS: Menu to export statistics table in the exports tab. The first menu entry means 'do not build a stats table' in the exported ODS file. You can omit the [...] part, that is here only to state the context.
  $prefs->store_register('export_ods_stats'=>cb_model(""=>__p("None [no stats table to export]"),
# TRANSLATORS: Menu to export statistics table in the exports tab. The second menu entry means 'build a stats table, with a horizontal flow' in the exported ODS file.
					      "h"=>__("Horizontal flow"),
# TRANSLATORS: Menu to export statistics table in the exports tab. The second menu entry means 'build a stats table, with a vertical flow' in the exported ODS file.
					      "v"=>__("Vertical flow")));
  $w->{'export_c_export_ods_stats'}=$widget;
  $t->attach($widget,1,$y,1,1);
  $y++;

# TRANSLATORS: Check button label in the exports tab. If checked, a table with indicative questions basic statistics will be added to the ODS exported spreadsheet.
  $t->attach(Gtk3::Label->new(__"Indicative stats table"),
	     0,$y,1,1);
  $widget=Gtk3::ComboBox->new();
  $renderer = Gtk3::CellRendererText->new();
  $widget->pack_start($renderer, TRUE);
  $widget->add_attribute($renderer,'text',COMBO_TEXT);
  $prefs->store_register('export_ods_statsindic'=>cb_model(""=>__"None",
						   "h"=>__"Horizontal flow",
						   "v"=>__"Vertical flow"));
  $w->{'export_c_export_ods_statsindic'}=$widget;
  $t->attach($widget,1,$y,1,1);
  $widget->set_tooltip_text(__"Create a table with basic statistics about answers for each indicative question?");
  $y++;

# TRANSLATORS: Check button label in the exports tab. If checked, sums of the scores for groups of questions will be added to the exported table.
  $t->attach(Gtk3::Label->new(__"Score groups"),
	     0,$y,1,1);

  my $w_groups=Gtk3::Grid->new();

  $widget=Gtk3::ComboBox->new();
  $renderer = Gtk3::CellRendererText->new();
  $widget->pack_start($renderer, TRUE);
  $widget->add_attribute($renderer,'text',COMBO_TEXT);
# TRANSLATORS: Option for ODS export: group questions by scope? This is the menu entry for 'No, don't group questions by scope in the exported ODS file'
  $prefs->store_register('export_ods_group'=>cb_model("0"=>__"No",
# TRANSLATORS: Option for ODS export: group questions by scope? This is the menu entry for 'Yes, group questions by scope in the exported ODS file, and report total scores'
                                                      "1"=>__"Yes (values)",
# TRANSLATORS: Option for ODS export: group questions by scope? This is the menu entry for 'Yes, group questions by scope in the exported ODS file, and report total scores as percentages.'
                                                      "2"=>__"Yes (percentages)"));
  $w->{'export_c_export_ods_group'}=$widget;

  $widget->set_tooltip_text(__"Add sums of the scores for each question group?");
  $w_groups->attach($widget,0,0,1,1);

  $w_groups->attach(Gtk3::Label->new(" ".(__"with scope separator")." "),1,0,1,1);

  $widget=Gtk3::ComboBox->new();
  $renderer = Gtk3::CellRendererText->new();
  $widget->pack_start($renderer, TRUE);
  $widget->add_attribute($renderer,'text',COMBO_TEXT);
# TRANSLATORS: Option for ODS export: group questions by scope? This is the menu entry for 'No, don't group questions by scope in the exported ODS file'
  $prefs->store_register('export_ods_groupsep'=>cb_model(":"=>__"':'",
# TRANSLATORS: Option for ODS export: group questions by scope? This is the menu entry for 'Yes, group questions by scope in the exported ODS file, and you can detect the scope from a question ID using the text before the separator .'
							 "."=>__"'.'"));
  $w->{'export_c_export_ods_groupsep'}=$widget;

  $widget->set_tooltip_text(__"To define groups, use question ids in the form \"group:question\" or \"group.question\", depending on the scope separator.");
  $w_groups->attach($widget,2,0,1,1);

  $t->attach($w_groups,1,$y,1,1);
  $y++;

  my $b=Gtk3::Button->new_with_label(__"Choose columns");
  $b->signal_connect(clicked => \&main::choose_columns_current);
  $t->attach($b,0,$y,2,1);
  $y++;

  $t->show_all;
  return($t);
}

sub weight {
  return(.2);
}

1;
