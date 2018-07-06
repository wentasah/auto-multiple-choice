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

use Getopt::Long;
use AMC::Basic;

my $cr_dir='';
my $liste='';
my $data_dir='';
my $list='';
my $set='';
my $student='';
my $copy=0;
my $id=undef;
my $raw='';

GetOptions("cr=s"=>\$cr_dir,
	   "liste=s"=>\$liste,
	   "data=s"=>\$data_dir,
	   "list!"=>\$list,
	   "raw!"=>\$raw,
	   "set!"=>\$set,
	   "student=s"=>\$student,
	   "copy=s"=>\$copy,
	   "id=s"=>\$id,
	   );

if($list) {
  require AMC::Data;

  my $data=AMC::Data->new($data_dir);
  my $assoc=$data->module('association');
  my $capture=$data->module('capture');
  $data->begin_read_transaction('ALST');
  my @list;
  if($raw) {
    @list=map { [$_->{student},$_->{copy}] } (@{$assoc->list()});
  } else {
    @list=$capture->student_copies();
  }
  print "Student\tID\n";
  for my $c (@list) {
    print studentids_string(@$c)."\t";
    my $manual=$assoc->get_manual(@$c);
    my $auto=$assoc->get_auto(@$c);
    if(defined($manual)) {
      print $manual;
      print " (manual";
      if(defined($auto)) {
	print ", auto=".$auto;
      }
      print ")\n";
    } elsif(defined($auto)) {
      print $auto." (auto)\n";
    } else {
      print "(none)\n";
    }
  }
  $data->end_transaction('ALST');
} elsif($set) {
  require AMC::Data;

  my $data=AMC::Data->new($data_dir);
  my $assoc=$data->module('association');
  $data->begin_transaction('ASET');
  $assoc->set_manual($student,$copy,$id);
  $data->end_transaction('ASET');
} else {
  require AMC::Gui::Association;

  my $g=AMC::Gui::Association::new('cr'=>$cr_dir,
				   'liste'=>$liste,
				   'data_dir'=>$data_dir,
				   'global'=>1,
				  );

  Gtk3->main;
}


