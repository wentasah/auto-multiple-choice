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
use AMC::Basic;

use Data::Dumper;

use_gettext;

my $t=AMC::Test->new('dir'=>__FILE__);

$t->begin("Scoring::simple");

$t->test_scoring({multiple=>0,strategy=>"b=2"},
		 [{correct=>1,strategy=>'',ticked=>1},
		  {correct=>0,strategy=>'',ticked=>0},
		  {correct=>0,strategy=>'',ticked=>0},
		 ],2);
$t->test_scoring({multiple=>0,strategy=>"b=2"},
		 [{correct=>1,strategy=>'3',ticked=>1},
		  {correct=>0,strategy=>'',ticked=>0},
		  {correct=>0,strategy=>'',ticked=>0},
		 ],3);
$t->test_scoring({multiple=>0,strategy=>"e=-1,b=2"},
		 [{correct=>1,strategy=>'',ticked=>1},
		  {correct=>0,strategy=>'',ticked=>1},
		  {correct=>0,strategy=>'',ticked=>0},
		 ],-1);
$t->test_scoring({multiple=>0,strategy=>"v=-2,e=-1,b=2"},
		 [{correct=>1,strategy=>'',ticked=>0},
		  {correct=>0,strategy=>'',ticked=>0},
		  {correct=>0,strategy=>'',ticked=>0},
		 ],-2);

$t->begin("Scoring::multiple");

$t->test_scoring({multiple=>1,strategy=>"b=2,m=-1",noneof_auto=>1},
		 [{correct=>1,strategy=>'',ticked=>1},
		  {correct=>1,strategy=>'',ticked=>0},
		  {correct=>0,strategy=>'',ticked=>0},
		 ],3);
$t->test_scoring({multiple=>1,strategy=>"b=3,m=-2,p=-2",noneof_auto=>1},
		 [{correct=>1,strategy=>'',ticked=>0},
		  {correct=>1,strategy=>'',ticked=>0},
		  {correct=>0,strategy=>'',ticked=>0},
		 ],-1);
$t->test_scoring({multiple=>1,strategy=>"e=-10,b=3,m=-2,p=-2"},
		 [{correct=>0,noneof=>1,ticked=>1},
		  {correct=>1,strategy=>'',ticked=>1},
		  {correct=>1,strategy=>'',ticked=>0},
		  {correct=>0,strategy=>'',ticked=>0},
		 ],-10);
$t->test_scoring({multiple=>1,strategy=>"e=-10,formula=NBC,set.INVALID=NMC>0 || NBC>4"},
		 [{correct=>1,strategy=>'',ticked=>1},
		  {correct=>1,strategy=>'',ticked=>1},
		  {correct=>1,strategy=>'',ticked=>1},
		  {correct=>1,strategy=>'',ticked=>1},
		  {correct=>1,strategy=>'',ticked=>1},
		  {correct=>0,strategy=>'',ticked=>0},
		 ],-10);
$t->test_scoring({multiple=>1,strategy=>"e=-10,formula=NBC,set.INVALID=NMC>0 || NBC>4"},
		 [{correct=>1,strategy=>'',ticked=>1},
		  {correct=>1,strategy=>'',ticked=>1},
		  {correct=>1,strategy=>'',ticked=>1},
		  {correct=>1,strategy=>'',ticked=>0},
		  {correct=>1,strategy=>'',ticked=>0},
		  {correct=>0,strategy=>'',ticked=>0},
		 ],3);
$t->test_scoring({multiple=>1,strategy=>"e=-10,formula=NBC,set.INVALID=NMC>0 || NBC>4"},
		 [{correct=>1,strategy=>'',ticked=>1},
		  {correct=>1,strategy=>'',ticked=>1},
		  {correct=>1,strategy=>'',ticked=>1},
		  {correct=>1,strategy=>'',ticked=>0},
		  {correct=>1,strategy=>'',ticked=>0},
		  {correct=>0,strategy=>'',ticked=>1},
		 ],-10);
$t->test_scoring({multiple=>1,default_strategy=>"formula=NBC-NMC",
		  strategy=>"b=1,m=0"},
		 [{correct=>1,strategy=>'',ticked=>1},
		  {correct=>1,strategy=>'',ticked=>1},
		  {correct=>1,strategy=>'',ticked=>0},
		  {correct=>0,strategy=>'',ticked=>1},
		  {correct=>0,strategy=>'',ticked=>0},
		 ],1);
$t->test_scoring({multiple=>1,default_strategy=>"formula=NBC-NMC",
		  strategy=>"formula=,b=1,m=0"},
		 [{correct=>1,strategy=>'',ticked=>1},
		  {correct=>1,strategy=>'',ticked=>1},
		  {correct=>1,strategy=>'',ticked=>0},
		  {correct=>0,strategy=>'',ticked=>1},
		  {correct=>0,strategy=>'',ticked=>0},
		 ],3);

$t->ok;


