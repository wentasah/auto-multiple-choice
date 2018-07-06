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

my $t=AMC::Test->new('dir'=>__FILE__,'filter'=>'plain','tex_engine'=>'xelatex',
                     perfect_copy=>[],notemax=>0,multiple=>1,
                     'check_marks'=>{'1:1'=>2,'1:2'=>6},
                    );

$t->prepare;

$t->set(ignore_red=>1);
$t->analyse;

$t->set(ignore_red=>0);
$t->analyse;

$t->note;
$t->get_marks;
$t->check_marks;

$t->ok;

