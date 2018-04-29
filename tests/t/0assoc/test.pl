#! /usr/bin/perl
#
# Copyright (C) 2016 Alexis Bienvenue <paamc@passoire.fr>
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
               association_manual=>
               [
                {id=>'01X',student=>4,copy=>0},
                {id=>'01Y',student=>5,copy=>0},
               ],
	       'check_marks'=>{map { $_=>$_ } (1..5)},
	       'check_assoc'=>{1=>'1',2=>'02',3=>'0003',
                               4=>'x',5=>'x',
                               'm:4'=>'01X','m:5'=>'01Y'},
	      )
  ->default_process;

