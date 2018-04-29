#! /usr/bin/perl
#
# Copyright (C) 2012-2013 Alexis Bienvenue <paamc@passoire.fr>
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

AMC::Test->new('dir'=>__FILE__,'filter'=>'plain','tex_engine'=>'xelatex',
	       'src'=>'sujet.txt',
	       'list'=>'students.txt',
	       'code'=>'student.number','check_assoc'=>{4=>'00000973',
							5=>'00000974'},
	       'check_marks'=>{5=>10,4=>9},
	       'annote'=>[4,5],'annote_position'=>'case',
	      )->default_process;

