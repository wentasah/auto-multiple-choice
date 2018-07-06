#! /usr/bin/perl
#
# Copyright (C) 2016-2017 Alexis Bienvenue <paamc@passoire.fr>
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

AMC::Test->new('dir'=>__FILE__,'tex_engine'=>'pdflatex',
               'perfect_copy'=>[1],
               'grain'=>0.1,'rounding'=>'s',
               'export_ods'=>
               {
                stats=>[
                        {id=>'A',invalid=>1,empty=>1,total=>5,
                         answers=>[
                                   {i=>1,ticked=>2},
                                   {i=>2,ticked=>1},
                                   {i=>3,ticked=>0},
                                   {i=>4,ticked=>0},
                                  ]},
                        {id=>'B',invalid=>0,empty=>1,total=>5,
                         answers=>[
                                   {i=>1,ticked=>2},
                                   {i=>2,ticked=>2},
                                   {i=>3,ticked=>1},
                                   {i=>4,ticked=>0},
                                   {i=>5,ticked=>1},
                                  ]},
                         {id=>'C',invalid=>1,empty=>1,total=>5,
                          answers=>[
                                    {i=>1,ticked=>1},
                                    {i=>2,ticked=>3},
                                    {i=>3,ticked=>1},
                                    {i=>4,ticked=>1},
                                    {i=>5,ticked=>0},
                                   ]},
                      ],
               },
              )
  ->default_process;
