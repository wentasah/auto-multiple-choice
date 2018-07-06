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

use Data::Dumper;

require "./AMC/Test.pm";

my $t=AMC::Test->new('dir'=>__FILE__,
                    );

$t->prepare();

my $d=$t->get_defects();

$t->trace("[T] Defect test: different positions");

if(!$d->{DIFFERENT_POSITIONS}) {
  $t->trace("[E] Not detected!");
  $t->trace(Dumper($d));
  exit(1);
}

delete($d->{DIFFERENT_POSITIONS});

my @t=(keys %$d);
if(@t) {
  $self->trace("[E] Layout defects: ".join(', ',@t));
}

$t->ok;
