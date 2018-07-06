#! /usr/bin/perl
#
# Copyright (C) 2018 Alexis Bienvenue <paamc@passoire.fr>
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

AMC::Test->new(dir=>__FILE__,'filter'=>'plain','tex_engine'=>'xelatex',
               perfect_copy=>[2],seuil=>0.25,
               export_full_csv=>[
                                 {-copy=>3,-question=>'Q001',-score=>1},
                                 {-copy=>3,-question=>'Q002',-score=>-1},
                                 {-copy=>3,-question=>'Q003',-score=>2},
                                 {-copy=>3,-question=>'Q004',-score=>-2},
                                 {-copy=>3,-question=>'Q005',-score=>0},
                                 {-copy=>3,-question=>'Q006',-score=>-10},
                                 {-copy=>3,-question=>'Q007',-score=>-10},
                                 {-copy=>3,-question=>'Q008',-score=>-10},
                                 {-copy=>3,-question=>'Q009',-score=>0},
                                 ],
              )
  ->default_process;
