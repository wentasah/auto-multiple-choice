#! /usr/bin/perl
#
# Copyright (C) 2016-2017 Alexis Bienvenue <paamc@passoire.fr>
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

AMC::Test->new(dir=>__FILE__,
               tex_engine=>'pdflatex',
               perfect_copy=>[2],seuil=>0.15,
               notemax=>'',rounding=>'',
               list=>'names.csv',list_key=>'id',code=>'id',
               check_assoc=>{4=>'3142'},
               export_full_csv=>[
                                 {-copy=>2,-question=>'h',-score=>2},
                                 {-copy=>2,-question=>'f',-score=>2},
                                 {-copy=>2,-question=>'m',-score=>2},
                                 {-copy=>2,-question=>'s',-score=>2},
                                 {-copy=>4,-question=>'h',-score=>1},
                                 {-copy=>4,-question=>'f',-score=>1},
                                 {-copy=>4,-question=>'m',-score=>1},
                                 {-copy=>4,-question=>'s',-score=>0},
                                 ],
              )
  ->default_process;
