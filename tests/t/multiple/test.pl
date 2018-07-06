#! /usr/bin/perl
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

require "./AMC/Test.pm";

AMC::Test->new('dir'=>__FILE__,'tex_engine'=>'pdflatex',
	       'multiple'=>1,'perfect_copy'=>[2],
	       'grain'=>0.1,'rounding'=>'s','seuil'=>0.15,seuil_up=>0.7,
	       'check_marks'=>{'/000'=>20,'/007'=>10,'/132'=>16.7,'/101'=>13.4},
	       'verdict'=>'%(id) / %(ID)'."\n".'TOTAL : %S/%M => %s/%m',
	       'model'=>'(id)_(ID)',
	       'annote'=>['2:1','2:2','2:3'],'annote_ascii'=>1,
	       'annote_files'=>['007_Jojo.pdf','132_Globis.pdf','000_Perfect.pdf'],
	      )
  ->default_process;

