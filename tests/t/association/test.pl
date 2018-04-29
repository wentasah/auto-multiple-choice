#! /usr/bin/perl
#
# Copyright (C) 2012-2016 Alexis Bienvenue <paamc@passoire.fr>
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

use_gettext;

my $t=AMC::Test->new('dir'=>__FILE__);
my $d=$t->data;
my $a=$d->module('association');
my $c=$d->module('capture');

$d->begin_transaction;

$t->{'datamodule'}=$a;
$t->{'datatable'}='association_association';

$t->begin('AMC::DataModule::association::get/set');

$a->set_manual(1,2,"001");
$t->test($a->get_manual(1,2),1);
$a->set_manual(1,2,"001A");
$t->test($a->get_manual(1,2),"001A");

$a->set_auto(1,2,"001");
$t->test($a->get_auto(1,2),1);
$a->set_auto(1,2,"001A");
$t->test($a->get_auto(1,2),"001A");

##

$a->clear();

$a->statement('NEWAssoc')->execute(10,0,100,"a100");
$a->statement('NEWAssoc')->execute(11,0,"m110",110);
$a->statement('NEWAssoc')->execute(11,1,111,"a111");
$a->statement('NEWAssoc')->execute(1,1,undef,undef);

$t->begin('AMC::DataModule::association::get_manual');

$t->test($a->get_manual(10,0),"100");
$t->test($a->get_manual(11,0),"m110");
$t->test_undef($a->get_manual(1,1));

$t->begin('AMC::DataModule::association::get_auto');

$t->test($a->get_auto(11,0),"110");
$t->test($a->get_auto(11,1),"a111");
$t->test_undef($a->get_auto(1,1));

$t->begin('AMC::DataModule::association::get_real');

$a->set_manual(11,1,undef);
$a->set_auto(11,0,undef);

$t->test($a->get_real(10,0),"100");
$t->test($a->get_real(11,0),"m110");
$t->test($a->get_real(11,1),"a111");
$t->test_undef($a->get_real(1,1));

$t->begin('AMC::DataModule::association::counts');

@c=$a->counts;
$t->test(\@c,[2,2,3]);

$t->begin('AMC::DataModule::association::state');

$a->statement('NEWAssoc')->execute(2,10,undef,"a100");

$a->set_auto(2,3,"a100");
$t->test($a->state(5,5),0);
$t->test($a->state(10,0),1);
$t->test($a->state(2,10),2);

$t->begin('AMC::DataModule::association::clear_auto');

$a->clear_auto;
my @c=$a->counts;
$t->test(\@c,[0,2,2]);

$t->begin('AMC::DataModule::association::real_back');

$a->set_auto(2,4,"001");
$a->set_auto(2,5,"001");
$a->set_manual(2,5,"023");
$a->set_manual(2,6,"024");

@c=$a->real_back("m110");
$t->test(\@c,[11,0]);
@c=$a->real_back("001");
$t->test(\@c,[2,4]);
@c=$a->real_back(1);
$t->test(\@c,[2,4]);
@c=$a->real_back("023");
$t->test(\@c,[2,5]);
@c=$a->real_back("024");
$t->test(\@c,[2,6]);

$t->begin('AMC::DataModule::association::real_count');

$a->clear;
$a->statement('NEWAssoc')->execute(10,0,undef,100);
$a->statement('NEWAssoc')->execute(11,0,100,undef);
$a->statement('NEWAssoc')->execute(11,1,100,100);
$a->statement('NEWAssoc')->execute(11,2,100,"a100");
$a->statement('NEWAssoc')->execute(1,1,undef,undef);

$t->test($a->sql_single($a->statement('realCount'),100),4);

$t->begin('AMC::DataModule::association::delete_target');

$a->delete_target(100);
$t->test($a->sql_single($a->statement('realCount'),100),0);
$t->test_undef($a->real_back(100));

$t->begin('AMC::DataModule::association::missing_count');

$a->clear;
$a->statement('NEWAssoc')->execute(10,0,undef,1001);
$a->statement('NEWAssoc')->execute(11,0,1002,undef);
$a->statement('NEWAssoc')->execute(11,1,1003,1004);
$a->statement('NEWAssoc')->execute(11,2,1005,1006);
$a->statement('NEWAssoc')->execute(1,1,undef,undef);

$c->set_page_auto("haha1.tif",10,1,0,time(),1,0,0,1,0,0,0);
$c->set_page_auto("haha2.tif",10,2,0,time(),1,0,0,1,0,0,0);
$c->set_page_auto("haha3.tif",11,1,0,time(),1,0,0,1,0,0,0);
$c->set_page_auto("haha4.tif",11,1,1,time(),1,0,0,1,0,0,0);
$c->set_page_auto("haha5.tif",11,1,2,time(),1,0,0,1,0,0,0);
$c->set_page_auto("haha6.tif",11,1,3,time(),1,0,0,1,0,0,0);
$c->set_page_auto("haha7.tif",1,1,1,time(),1,0,0,1,0,0,0);

$t->test($a->missing_count,2);

$d->end_transaction;

$t->ok;


