#! /usr/bin/perl
#
# Copyright (C) 2012-2018 Alexis Bienvenue <paamc@passoire.fr>
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

my $t=AMC::Test->new('dir'=>__FILE__);

if(!open(MV,"../Makefile.versions")) {
  $t->trace("[E] Can't open versions file: $!");
  exit 1;
}
while(<MV>) {
  $vsty=$1 if(/PACKAGE_V_STY=(.*)/);
}
close MV;

if(!$vsty) {
  $t->trace("[E] Can't find PACKAGE_V_STY");
  exit 1;
}

$t->check_textest;

if(!open(LOG,$t->{'temp_dir'}."/amc.log")) {
  $t->trace("[E] Can't open log file: $!");
  exit 1;
}
while(<LOG>) {
  if(/AMC version: (.*)/) { $va=$1; }
  if(/Package: automultiplechoice (.*)/) { $vb=$1; }
}
close LOG;

$t->begin("versions");

$t->test($va,$vsty,"AMC");
$t->test($vb,$vsty,"package");

$t->end();

$t->ok();
