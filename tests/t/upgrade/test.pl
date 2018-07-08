#! /usr/bin/perl
#
# Copyright (C) 2013-2017 Alexis Bienvenue <paamc@passoire.fr>
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

my $t=AMC::Test->new('dir'=>__FILE__,'tex_engine'=>'pdflatex',
		     notemax=>0,seuil=>0.15,grain=>0.5,rounding=>'n',
		     scans=>[],
		     check_marks=>{1=>121,2=>330,3=>421,4=>432},
		     check_assoc=>{1=>121,3=>421,2=>'x','m:2'=>330,4=>432},
		     perfect_copy=>[2])->update_sqlite();
$t->get_marks();
$t->check_marks();

$t->get_assoc();
$t->check_assoc();

$t->note();

$t->get_marks();
$t->check_marks();

$t->assoc();

$t->get_assoc();
$t->check_assoc();

$t->analyse();
$t->note();
$t->get_marks();
$t->check_perfect();

$t->ok();
