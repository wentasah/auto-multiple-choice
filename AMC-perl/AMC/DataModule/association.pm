# -*- perl -*-
#
# Copyright (C) 2011-2017 Alexis Bienvenue <paamc@passoire.fr>
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

package AMC::DataModule::association;

# AMC associations management.

# This module is used to store (in a SQLite database) and handle all
# data concerning associations between completed answer sheets and
# students (from the students list).

# TABLES:
#
# association holds data concerning association between a student
# completed answer sheet (identified by its student number and its
# copy number) and the student name (in fact the student identifier
# found in the students list file).
#
# * student is the student number of the completed answer sheet.
#
# * copy is the copy number (0 if the question sheet has not been
#   photocopied, and 1,2,... otherwise).
#
# * auto is the student ID (a primary key found in the students list
#   file) associated with the answer sheet by automatic association,
#   or NULL if no automatic association were made for this sheet.
#
# * manual is the student ID (a primary key found in the students list
#   file) associated with the answer sheet by manual association,
#   or NULL if no automatic association were made for this sheet.

# VARIABLES:
#
# key_in_list is the column name from students list file where to find
#   the primary key that will be used in the association data to
#   identify a student.
#
# code is the code name in the LaTeX source file (first argument given
#   to the \AMCcode command) that is used for automatic association.

use AMC::Basic;
use AMC::DataModule;

use IO::File;
use XML::Simple;

@ISA=("AMC::DataModule");

sub version_current {
  return(1);
}

sub immutable_variables {
  return("code_storage");
}

sub version_upgrade {
    my ($self,$old_version)=@_;
    if($old_version==0) {

      $self->variable("code_storage","full");

	# Upgrading from version 0 (empty database) to version 1 :
	# creates all the tables.

	debug "Creating scoring tables...";
	$self->sql_do("CREATE TABLE IF NOT EXISTS ".$self->table("association")
		      ." (student INTEGER, copy INTEGER, manual TEXT, auto TEXT, PRIMARY KEY (student,copy))");

	$self->populate_from_xml;

	return(1);
    }
    return('');
}

# populate_from_xml read the old format XML file (if any) and insert
# it in the new SQLite database

sub populate_from_xml {
  my ($self)=@_;
  my $assoc_file=$self->{'data'}->directory;
  $assoc_file =~ s:/[^/]+/?$:/association.xml:;
  return if(!-f $assoc_file);

  $self->progression('begin',__"Fetching association results from old format XML files...");

  my $i=IO::File->new($assoc_file,"<:encoding(utf-8)");
  my $a=XMLin($i,'ForceArray'=>1,'KeyAttr'=>['id']);
  $i->close();

  $self->variable('key_in_list',$a->{'liste_key'});
  $self->variable('code',$a->{'notes_id'});

  my @s=(keys %{$a->{'copie'}});
  my $frac=0;

  for my $student (@s) {
    my $s=$a->{'copie'}->{$student};
    $self->statement('NEWAssoc')
      ->execute($student,0,$s->{'manuel'},$s->{'auto'});
    $frac++;
    $self->progression('fraction',$frac/(1+$#s));
  }

  $self->progression('end');
}

# defines all the SQL statements that will be used

sub define_statements {
  my ($self)=@_;
  my $at=$self->table("association");
  my $t_page=$self->table("page","capture");
  $self->{'statements'}=
    {
     'NEWAssoc'=>{'sql'=>"INSERT INTO $at"
		  ." (student,copy,manual,auto) VALUES (?,?,?,?)"},
     'insert'=>{'sql'=>"INSERT OR IGNORE INTO $at"
		." (student,copy,manual,auto) VALUES (?,?,?,?)"},
     'getManual'=>{'sql'=>"SELECT manual FROM $at"
		   ." WHERE student=? AND copy=?"},
     'getAuto'=>{'sql'=>"SELECT auto FROM $at"
		 ." WHERE student=? AND copy=?"},
     'setManual'=>{'sql'=>"UPDATE $at"
		   ." SET manual=? WHERE student=? AND copy=?"},
     'setAuto'=>{'sql'=>"UPDATE $at"
		 ." SET auto=? WHERE student=? AND copy=?"},
     'getReal'=>{'sql'=>"SELECT CASE"
		 ." WHEN manual IS NOT NULL THEN manual"
		 ." ELSE auto END"
		 ." FROM $at"
		 ." WHERE student=? AND copy=?"},
     'realCount'=>{'sql'=>"SELECT COUNT(*) FROM ( SELECT CASE"
		   ." WHEN manual IS NOT NULL THEN manual"
		   ." ELSE auto END AS real"
		   ." FROM $at"
		   ." ) WHERE real=?||''"},
     'realCounts'=>{'sql'=>
                    " SELECT t.student AS student,t.copy AS copy,t.real AS real,t.manual AS manual,t.auto AS auto,c.n AS n"
                    ." FROM"
                    ." ( SELECT CASE"
                    ."   WHEN manual IS NOT NULL THEN manual"
                    ."   ELSE auto END AS real,student,copy,manual,auto FROM $at"
                    ." ) AS t,"
                    ." ( SELECT CASE"
                    ."   WHEN manual IS NOT NULL THEN manual"
                    ."   ELSE auto END AS real,"
                    ."   COUNT(*) AS n FROM $at GROUP by real"
                    ." ) AS c"
                    ." ON t.real=c.real"
                   },
     'realBack'=>{'sql'=>"SELECT student,copy FROM ( SELECT CASE"
		  ." WHEN manual IS NOT NULL THEN manual"
		  ." ELSE auto END AS real, student, copy"
		  ." FROM $at"
		  ." ) WHERE real=?||''"},
     'realBackInt'=>{'sql'=>"SELECT student,copy FROM ( SELECT CASE"
                     ." WHEN manual IS NOT NULL THEN manual"
                     ." ELSE auto END AS real, student, copy"
                     ." FROM $at"
                     ." ) WHERE CAST(real AS INTEGER)=?"},
     'counts'=>{'sql'=>"SELECT COUNT(auto),COUNT(manual),"
		." SUM(CASE WHEN auto IS NOT NULL OR manual IS NOT NULL"
		."          THEN 1 ELSE 0 END)"
		." FROM $at"},
     'clearAuto'=>{'sql'=>"UPDATE $at SET auto=NULL"},
     'findManual'=>{'sql'=>"SELECT student,copy FROM $at WHERE manual=?||''"},
     'unlink'=>{'sql'=>"UPDATE $at SET manual="
		." ( CASE WHEN manual IS NULL OR auto=?||'' THEN 'NONE' ELSE NULL END )"
		." WHERE manual=? OR ( auto=?||'' AND manual IS NULL )"},
     'assocMissingCount'=>{'sql'=>"SELECT COUNT(*) FROM"
			   ."(SELECT student,copy FROM $t_page"
			   ." EXCEPT SELECT student,copy FROM $at"
			   ." WHERE manual IS NOT NULL OR auto IS NOT NULL)"},
     'deleteAssociations'=>{'sql'=>"DELETE FROM $at"
			    ." WHERE student=? AND copy=?"},
     'list'=>{'sql'=>"SELECT * FROM $at ORDER BY student,copy"},
    };
}

# get_manual($student,$copy) returns the manual association ID for the
# given answer sheet.

sub get_manual {
  my ($self,$student,$copy)=@_;
  return($self->sql_single($self->statement('getManual'),
			   $student,$copy));
}

# get_auto($student,$copy) returns the automatic association ID for the
# given answer sheet.

sub get_auto {
  my ($self,$student,$copy)=@_;
  return($self->sql_single($self->statement('getAuto'),
			   $student,$copy));
}

# get_real($student,$copy) returns the resulting association ID for the
# given answer sheet (manual one if present, or automatic one).

sub get_real {
  my ($self,$student,$copy)=@_;
  return($self->sql_single($self->statement('getReal'),
                           $student,$copy));
}

# with_association($student,$copy) returns TRUE if the copy is associated

sub with_association {
  my ($self,$student,$copy)=@_;
  my $r=$self->get_real($student,$copy);
  return(defined($r) && $r ne '');
}

# set_manual($student,$copy,$manual) sets the manual association ID for the
# given answer sheet.

sub set_manual {
  my ($self,$student,$copy,$manual)=@_;
  my $n=$self->statement('insert')->execute($student,$copy,$manual,undef);
  if($n<=0) {
    $self->statement('setManual')->execute($manual,$student,$copy);
  }
}

# set_auto($student,$copy,$manual) sets the automatic association ID for the
# given answer sheet.

sub set_auto {
  my ($self,$student,$copy,$auto)=@_;
  my $n=$self->statement('insert')->execute($student,$copy,undef,$auto);
  if($n<=0) {
    $self->statement('setAuto')->execute($auto,$student,$copy);
  }
}

# counts returns a list containing the number A of automatic
# associations, the number M of manual associations, and the total
# number T of answer sheets that are associated. T is not always equal
# to A+M, as a particular answer sheet may have automatic AND manual
# associations, for exemple when automatic association did not work
# well and has been corrected by manual association.

sub counts {
  my ($self)=@_;
  my $sth=$self->statement('counts');
  $sth->execute;
  return(@{$sth->fetchrow_arrayref});
}

# clear clears all association data.

sub clear {
  my ($self)=@_;
  $self->sql_do("DELETE FROM ".$self->table('association'));
}

# clear_auto clears all automatic association data

sub clear_auto {
  my ($self)=@_;
  $self->statement('clearAuto')->execute;
}

# check_keys($key_in_list,$code) checks that the value of the
# variables 'key_in_list' and 'code' corresponds to the given
# values. If not, association data is cleared.

sub check_keys {
  my ($self,$key_in_list,$code)=@_;
  if($self->variable('key_in_list') ne $key_in_list) {
    debug "Association variable mismatch: clearing database";
    $self->clear;
    $self->variable('key_in_list',$key_in_list);
    $self->variable('code',$code);
  } elsif($code ne '---' && $self->variable('code') ne $code) {
    debug "Association <code> variable mismatch: clearing automatic association";
    $self->clear_auto;
    $self->variable('code',$code);
  }
}

# real_back($code) returns the (student,copy) list corresponding to
# the answer sheet that is currently associated with the student ID
# $code.

sub real_back {
  my ($self,$code)=@_;
  my @r=$self->sql_row($self->statement('realBack'),$code);
  # for backward compatibility, makes real_back work even if the
  # leading zeroes are givenn or not in the database or in
  # $code... but only for databases created with older versions or
  # with code_storage variable different from "full"
  if($self->{immutable}->{code_storage} ne "full" &&
     $#r<1 && $code=~/^[0-9]*[1-9][0-9]*$/) {
    $code =~ s/^0+//;
    @r=$self->sql_row($self->statement('realBackInt'),$code);
  }
  return(@r);
}

# state($student,$copy) returns:
#
# 0 if this answer sheet has not been associated with a student name ;
#
# 1 if this answer sheet has been associated with a student name, and
#   no other sheet has been associated with the same student name ;
#
# 2 if this answer sheet has been associated with a student name, but
#   some other sheets has been associated with the same student name.

sub state {
  my ($self,$student,$copy)=@_;
  my $r=$self->get_real($student,$copy);
  if(!defined($r) || !$r || $r eq 'NONE') {
    return(0);
  } else {
    my $nb=$self->sql_single($self->statement('realCount'),$r);
    return($nb==1 ? 1 : 2);
  }
}

# counts_hash() returns a hashref $r that can be used to get the
# number of copies that has the same associated student as some copy.
#
# if $student,$copy is associated with a student,
# $r->{studentids_string($student,$copy)} is a hashref with
# manual -> student ID of manual association
# auto   -> student ID of auto association
# real   -> associated student ID
# n      -> number of copies with the sams associated student
# state  -> the same as state($student,$copy)
# color  -> color used in copies list

sub counts_hash {
  my ($self)=@_;
  my $r={};
  for my $l (@{$self->dbh->selectall_arrayref($self->statement('realCounts'),
                                              { Slice => {} })}) {
    my $etat=(!defined($l->{real}) || !$l->{real} || $l->{real} eq 'NONE' ? 0
              : $l->{n}==1 ? 1 : 2);
    $r->{studentids_string($l->{student},$l->{copy})}=
      {%$l,
       etat=>$etat,
       color=>($etat==0 ?
               (defined($l->{manual}) && $l->{manual} eq 'NONE' ? 'salmon' : undef)
               :
               $etat==1 ?
               ($l->{manual} ? 'lightgreen' : 'lightblue')
               :
               'salmon'),
      };
  }
  return($r);
}

# delete_target($code) removes associations made with student ID $code
# (manual associations with this ID are removed, and automatic
# associations with this ID are overwritten with a manual association
# with 'NONE'). This method also returns a reference to an array of
# array references [<student>,<copy>] with all the sheets
# that were associated with this student name.

sub delete_target {
  my ($self,$code)=@_;
  my $r=$self->dbh->selectall_arrayref($self->statement('realBack'),{},$code);
  $self->statement('unlink')->execute($code,$code,$code);
  return($r);
}

# missing_count returns the number of entered sheets without association

sub missing_count {
  my ($self)=@_;
  $self->{'data'}->require_module('capture');
  return($self->sql_single($self->statement('assocMissingCount')));
}

# delete_association_data($student,$copy) deletes all association data
# for this answer sheet.

sub delete_association_data {
  my ($self,$student,$copy)=@_;
  for my $part (qw/Associations/) {
    $self->statement('delete'.$part)->execute($student,$copy);
  }
}

# list() returns all association data

sub list {
  my ($self)=@_;
  return($self->dbh->selectall_arrayref($self->statement('list'),{Slice=>{}}));
}

1;
