#! /usr/bin/perl
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

use Getopt::Long;
use AMC::Basic;
use AMC::Gui::Manuel;

my $mep_dir='points-mep';
my $cr_dir='points-cr';
my $liste='noms.txt';
my $sujet='';
my $etud='';
my $dpi=75;
my $debug='';

my $seuil=0.1;

GetOptions("sujet=s"=>\$sujet,
	   "liste=s"=>\$liste,
	   "copie=s"=>\$etud,
	   "dpi=s"=>\$dpi,
	   "debug=s"=>\$debug,
	   );

set_debug($debug);

my $g=AMC::Gui::Manuel::new('liste'=>$liste,
			    'sujet'=>$sujet,
			    'etud'=>$etud,
			    'dpi'=>$dpi,
			    'seuil'=>$seuil,
			    'global'=>1,
			    );

Gtk2->main;

