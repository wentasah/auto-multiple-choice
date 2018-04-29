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

AMC::Test->new('dir'=>__FILE__,'tex_engine'=>'pdflatex',
	       'bw_threshold'=>0.4,
	       'seuil'=>0.5,
	       'grain'=>0.6,
	       'perfect_copy'=>'',
	       'export_full_csv'=>
	       [{-copy=>1,-question=>'inf-expo-indep',-score=>1},
		{-copy=>1,-question=>'sum',-score=>2},
		{-copy=>1,-question=>'product',-score=>2},
		{-copy=>1,-question=>'sqrt',-score=>2},
		{-copy=>1,-question=>'cities',-score=>0},
		{-copy=>1,-question=>'capital',-score=>2},
		{-copy=>2,-question=>'inf-expo-indep',-score=>0},
		{-copy=>2,-question=>'sum',-score=>0},
		{-copy=>2,-question=>'product',-score=>0},
		{-copy=>2,-question=>'sqrt',-score=>0},
		{-copy=>2,-question=>'cities',-score=>0},
		{-copy=>2,-question=>'capital',-score=>0},
		{-copy=>3,-question=>'inf-expo-indep',-score=>1},
		{-copy=>3,-question=>'sum',-score=>0},
		{-copy=>3,-question=>'product',-score=>2},
		{-copy=>3,-question=>'sqrt',-score=>2},
		{-copy=>3,-question=>'cities',-score=>0},
		{-copy=>3,-question=>'capital',-score=>0},
		{-copy=>4,-question=>'inf-expo-indep',-score=>0},
		{-copy=>4,-question=>'sum',-score=>0},
		{-copy=>4,-question=>'product',-score=>1},
		{-copy=>4,-question=>'sqrt',-score=>1},
		{-copy=>4,-question=>'cities',-score=>0},
		{-copy=>4,-question=>'capital',-score=>1},
		],
	      )
  ->default_process;

