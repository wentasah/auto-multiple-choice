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
use AMC::Basic;
use AMC::ScoringEnv;

use Data::Dumper;

use_gettext;

my $t=AMC::Test->new('dir'=>__FILE__);

$t->begin("AMC::ScoringEnv type 0");

my $se=AMC::ScoringEnv->new_from_directives_string("a=1,b=HA,c=HO+1");

$se->set_variable("HA",5,1);
$se->set_variable("HO",10,1);

$t->test($se->n_errors,0);
$t->test($se->get_directive("a"),1);
$t->test($se->get_directive("b"),5);
$t->test($se->get_directive("c"),11);

$t->begin("AMC::ScoringEnv type 1");

$se->set_type(1);

$se->set_variable("HA",2,1);
$se->set_variable("HO",2,1);

$t->test($se->n_errors,0);
$t->test($se->get_directive("a"),1);
$t->test($se->get_directive("b"),2);
$t->test($se->get_directive("c"),3);

$t->begin("AMC::ScoringEnv string(default.x,set.x,requires.x)");

$se->set_type(2);

$se->variables_from_directives_string
  ("default.HA=10,default.HO=0,set.HO=HA*2,requires.HA=1,requires.HO=1",
   default=>1,set=>1);

$t->test($se->n_errors,0);
$t->test($se->get_directive("a"),1);
$t->test($se->get_directive("b"),10);
$t->test($se->get_directive("c"),21);

$se->variables_from_directives_string
  ("set.HO=5",set=>1);
$t->test($se->n_errors,1);

$se->variables_from_directives_string
  ("requires.HI=1",requires=>1);
$t->test($se->n_errors,2);

$t->begin("AMC::ScoringEnv directives(default.x,set.x,requires.x)");

$se->clear_errors;

$se->process_directives("x=-XX,y=YY*3,set.XX=2,set.YY=XX*5+HA");
$se->variables_from_directives(set=>1);

$t->test($se->n_errors,0);
$t->test($se->get_directive("x"),-2);
$t->test($se->get_directive("y"),60);

$t->ok;


