# -*- perl -*-
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

package AMC::DataModule::report;

# AMC reports data management.

# This module is used to store (in a SQLite database) and handle some
# data concerning reports.

# TABLES:
#
# student stores some student reports filenames.
#
# * type is the kind of report (see REPORT_* constants).
#
# * file is the filename of the report.
#
# * student
# * copy identify the student sheet.
#
# * timestamp is the time when the report were generated.
#
# * mail_status, mail_timestamp, mail_message reports mailing feadback

use Exporter qw(import);

use constant {
  REPORT_ANNOTATED_PDF=>1,
  REPORT_SINGLE_ANNOTATED_PDF=>2,

  REPORT_MAIL_NO=>0,
  REPORT_MAIL_OK=>1,
  REPORT_MAIL_FAILED=>100,
};

our @EXPORT_OK = qw(REPORT_ANNOTATED_PDF REPORT_SINGLE_ANNOTATED_PDF
                    REPORT_MAIL_OK REPORT_MAIL_FAILED);
our %EXPORT_TAGS = ( 'const' => [ qw/REPORT_ANNOTATED_PDF REPORT_SINGLE_ANNOTATED_PDF
                                     REPORT_MAIL_OK REPORT_MAIL_FAILED/ ],
		   );

use AMC::Basic;
use AMC::DataModule;

@ISA=("AMC::DataModule");

sub version_current {
  return(2);
}

sub version_upgrade {
    my ($self,$old_version)=@_;
    if($old_version==0) {

      # Upgrading from version 0 (empty database) to version 1 :
      # creates all the tables.

      debug "Creating capture tables...";
      $self->sql_do("CREATE TABLE IF NOT EXISTS ".$self->table("student")
                    ." (type INTEGER, file TEXT, student INTEGER, copy INTEGER DEFAULT 0, timestamp INTEGER, PRIMARY KEY (type,student,copy))");
      $self->sql_do("CREATE TABLE IF NOT EXISTS ".$self->table("directory")
                    ." (type INTEGER PRIMARY KEY, directory TEXT)");

      for(REPORT_ANNOTATED_PDF,REPORT_SINGLE_ANNOTATED_PDF) {
        $self->statement('addDirectory')->execute($_,'cr/corrections/pdf');
      }

      return(1);
    } elsif($old_version==1) {
      # version 2 includes mail_* columns

      debug "Adding mailing data...";
      $self->sql_do("ALTER TABLE ".$self->table("student")
                    ." ADD COLUMN mail_status INTEGER DEFAULT 0");
      $self->sql_do("ALTER TABLE ".$self->table("student")
                    ." ADD COLUMN mail_timestamp INTEGER DEFAULT 0");
      $self->sql_do("ALTER TABLE ".$self->table("student")
                    ." ADD COLUMN mail_message TEXT");

      return(2);
    }
    return('');
}

# defines all the SQL statements that will be used

sub define_statements {
  my ($self)=@_;
  my $t_student=$self->table("student");
  my $t_directory=$self->table("directory");
  my $t_assoc=$self->table("association","association");
  $self->{'statements'}=
    {
     'addDirectory'=>{'sql'=>"INSERT INTO $t_directory"
		      ." (type,directory)"
		      ." VALUES(?,?)"},
     'getDir'=>{'sql'=>"SELECT directory FROM $t_directory"
		." WHERE type=?"},
     'numType'=>{'sql'=>"SELECT COUNT(*) FROM $t_student"
		 ." WHERE type=?"},
     'allType'=>{'sql'=>"SELECT file FROM $t_student"
		 ." WHERE type=?"},
     'filesWithType'=>
     {'sql'=>"SELECT file FROM $t_student"
      ." WHERE type IN"
      ." ( SELECT a.type FROM $t_directory AS a,$t_directory AS b"
      ."   ON a.directory=b.directory AND b.type=? )"},
     'setStudent'=>{'sql'=>"INSERT OR REPLACE INTO $t_student"
		    ." (file,timestamp,type,student,copy,"
                    ."  mail_status,mail_message,mail_timestamp)"
		    ." VALUES (?,?,?,?,?,?,?,?)"},
     'setMailing'=>{'sql'=>"UPDATE $t_student SET "
		    ." mail_status=?, mail_message=?, mail_timestamp=?"
		    ." WHERE type=? AND student=? AND copy=?"},
     'getStudent'=>{'sql'=>"SELECT file FROM $t_student"
		    ." WHERE type=? AND student=? AND copy=?"},
     'getStudentTime'=>{'sql'=>"SELECT file,timestamp FROM $t_student"
			." WHERE type=? AND student=? AND copy=?"},
     'deleteType'=>{'sql'=>"DELETE FROM $t_student"
		    ." WHERE type=?"},
     'deleteReport'=>{'sql'=>"DELETE FROM $t_student"
		      ." WHERE type=? AND student=? AND copy=?"},
     'getAssociatedType'=>
     {'sql'=>"SELECT CASE"
      ."  WHEN a.manual IS NOT NULL THEN a.manual"
      ."  ELSE a.auto END AS id,r.file AS file,r.mail_status AS mail_status"
      ." FROM $t_assoc AS a,"
      ."   (SELECT * FROM $t_student WHERE type=?) AS r"
      ." ON a.student=r.student AND a.copy=r.copy"},
    };
}

# files_with_type($type) returns all registered files that are located
# in the same directory as files with type $type does (including files
# with type $type).

sub files_with_type {
  my ($self,$type)=@_;
  return($self->sql_list($self->statement('filesWithType'),
			 $type));
}

# delete_student_type($type) deletes all records for specified type.

sub delete_student_type {
  my ($self,$type)=@_;
  $self->statement('deleteType')->execute($type);
}

# delete_student_report() deletes a student report record.

sub delete_student_report {
  my ($self,$type,$student,$copy)=@_;
  $self->statement('deleteReport')->execute($type,$student,$copy);
}

# set_student_type($type,$student,$copy,$file,$timestamp) creates a
# new record for a student report file, or replace data if this report
# is already in the table.

sub set_student_report {
  my ($self,$type,$student,$copy,$file,$timestamp)=@_;
  $timestamp=time() if($timestamp eq 'now');
  $self->statement('setStudent')
    ->execute($file,$timestamp,$type,$student,$copy,0,"",0);
}

# report_mailing($student,$copy,$status,$message,$timestamp) records
# mailing status for the report

sub report_mailing {
  my ($self,$student,$copy,$status,$message,$timestamp)=@_;
  $timestamp=time() if($timestamp eq 'now');
  $self->statement('setMailing')
    ->execute($status,$message,$timestamp,REPORT_ANNOTATED_PDF,$student,$copy);
}

# free_student_report($type,$file) returns a filename based on $file
# that is not yet registered in the same directory as files with type
# $type.

sub free_student_report {
  my ($self,$type,$file,$basedir)=@_;

  my %registered=map { $_=>1 } ($self->files_with_type($type));
  if($registered{$file}) {
    my $template=$file;
    if(!($template =~ s/(\.[a-z0-9]+)$/_%04d$1/i)) {
      $template.='_%04d';
    }
    my $i=0;
    do {
      $i++;
      $file=sprintf($template,$i);
    } while($registered{$file});
  }

  return($file);
}

# get_dir($type) returns subdirectory (in project directory) where
# files for type $type are stored.

sub get_dir {
  my ($self,$type)=@_;
  return($self->sql_single($self->statement('getDir'),$type));
}

# get_student_report($type,$student,$copy) returns the filename of a
# given report.

sub get_student_report {
  my ($self,$type,$student,$copy)=@_;
  return($self->sql_single($self->statement('getStudent'),
			   $type,$student,$copy));
}

# get_student_report_time($type,$student,$copy) returns the filename of a
# given report, and the corresponding timestamp.

sub get_student_report_time {
  my ($self,$type,$student,$copy)=@_;
  return($self->sql_row($self->statement('getStudentTime'),
			$type,$student,$copy));
}

# get_associated_type($type) returns a list of reports of a particular
# type $type with the corresponding association IDs (primary key of
# the student in the students list file), like
#
# [{'file'=>'001.pdf','id'=>'001234','mail_status'=>0,
#  {'file'=>'002.pdf','id'=>'001538','mail_status'=>1,
# ]

sub get_associated_type {
  my ($self,$type)=@_;
  $self->{'data'}->require_module('association');
  return($self->dbh->selectall_arrayref($self->statement('getAssociatedType'),
					{Slice=>{}},$type));
}

# type_count($type) returns the number of recorded reports of type
# $type.

sub type_count {
  my ($self,$type)=@_;
  return($self->sql_single($self->statement('numType'),$type));
}

# all_type($type) returns all the report filenames for type $type

sub all_type {
  my ($self,$type)=@_;
  return($self->sql_list($self->statement('allType'),$type));
}

# all_there($type,$basedir) returns TRUE if all reports of type $type
# are distinct present files.

sub all_there {
  my ($self,$type,$basedir)=@_;
  my $dir=$basedir.'/'.$self->get_dir($type);
  my @f=$self->sql_list($self->statement('allType'),$type);
  my $n=$#f;
  my %f_here=();
  for(@f) {
    $f_here{$_}=1 if( -f $dir.'/'.$_ );
  }
  @f=(keys %f_here);
  return($#f==$n);
}

1;
