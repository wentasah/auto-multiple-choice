#! /usr/bin/perl
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

use AMC::Test;

AMC::Test->new('dir'=>__FILE__,
	       'tex_engine'=>'pdflatex',
	       'perfect_copy'=>'','seuil'=>0.15,
	       'postcorrect_student'=>2,'postcorrect_copy'=>0,
	       'check_marks'=>{2=>20,3=>12.5},
	       'check_assoc'=>{2=>'01012012',3=>'01234567'},
	       'model'=>'(team)',
	       'annote'=>[3],'annote_files'=>['Tas_d_oeufs_casses.pdf'],'annote_ascii'=>1,
	      )
  ->default_process;

