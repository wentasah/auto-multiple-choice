#! /usr/bin/perl
#
# Copyright (C) 2008-2017 Alexis Bienvenue <paamc@passoire.fr>
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

my $lic_head='';

open(THIS,__FILE__);
 LIG: while(<THIS>) {
     chomp;
     last LIG if(!/^#/);
     $lic_head.="$_\n";
}
close(THIS);
$lic_head.="\n";

my %k=(deb=>"XX",vc=>"",year=>"2016",month=>"01",day=>"01");

$s=`svnversion`;
if($s =~ /([0-9]+)[SM]*$/) {
    $k{vc}="svn:$1";
}

$s=`hg id`;
if($s =~ /^([0-9a-f]+\+?)/) {
  $k{vc}="r:$1";
}

$s=`git describe --tags`;
if ($s) {
  chomp $s;
  $k{vc}=$s;
}

open(CHL,"ChangeLog");
LINES: while(<CHL>) {
  if(/^([0-9:.a-z+-]+)\s+\((\d{4})-(\d{2})-(\d{2})\)/) {
    $k{deb}=$1;
    $k{year}=$2;
    $k{month}=$3;
    $k{day}=$4;
    last LINES;
  }
}

open(VMK,">Makefile.versions");
print VMK $lic_head;
print VMK "PACKAGE_V_DEB=$k{'deb'}\n";
print VMK "PACKAGE_V_VC=$k{'vc'}\n";
print VMK "PACKAGE_V_PDFDATE=$k{year}$k{month}$k{day}000000\n";
print VMK "PACKAGE_V_ISODATE=$k{year}-$k{month}-$k{day}\n";
close(VMK);

