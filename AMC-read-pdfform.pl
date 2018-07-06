#! /usr/bin/perl -w
#
# Copyright (C) 2017 Alexis Bienvenue <paamc@passoire.fr>
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

use AMC::Basic;
use AMC::Gui::Avancement;
use AMC::Data;
use AMC::DataModule::capture qw/ :zone /;

use Encode;

use Getopt::Long;

use Data::Dumper;

use_gettext;
binmode(STDOUT, ":utf8");

my $list_file='';
my $progress_id='';
my $debug='';
my $data_dir='';
my $multiple='';

GetOptions("list=s"=>\$list_file,
           "progression-id=s"=>\$progress_id,
           "debug=s"=>\$debug,
           "multiple!"=>\$multiple,
           "data=s"=>\$data_dir,
	  );

die "data directory not found: $data_dir" if(!-d $data_dir);

set_debug($debug);

my $p=AMC::Gui::Avancement::new(1,'id'=>$progress_id)
  if($progress_id);

my @forms=(@ARGV);

if(-f $list_file) {
  open(LIST,$list_file);
  while(<LIST>) {
    chomp;
    push @forms,$_;
  }
  close(LIST);
}

my $data=AMC::Data->new($data_dir);
my $layout=$data->module('layout');
my $capture=$data->module('capture');

sub value_is_true {
  my ($s)=@_;
  return($s =~ /yes/i || $s =~ /^on/i);
}

my $copy_id={};
my @pages=();

sub clear_copy_id {
  $copy_id={};
  @pages=();
}

sub get_copy_id {
  my ($student_id,$page)=@_;
  my $key="$student_id/$page";
  if(!exists($copy_id->{$key})) {
    if($multiple) {
      $copy_id->{$key}=$capture->new_page_copy($student_id,$page);
    } else {
      $copy_id->{$key}=0;
    }
    push @pages,{student=>$student_id,page=>$page,copy=>$copy_id->{$key}};
    if($capture->set_page_auto(undef,$student_id,$page,$copy_id->{$key},time(),
                               undef,undef,undef,undef,undef,undef,
                               0)) {
      debug "Overwritten page data for [FORM] "
        .pageids_string($student_id,$page,$copy_id->{$key});
      $capture->tag_overwritten($student_id,$page,$copy_id->{$key});
      print "VAR+: overwritten\n";
    }
  }
  return($copy_id->{$key});
}

sub handle_field {
  my ($field)=@_;

  return(0) if(!$field->{Name});
  if($field->{Name} =~ /^([0-9]+):case:(.*):([0-9]+),([0-9]+)$/) {
    my ($student_id,$q_name,$q_id,$a_id)=($1,$2,$3,$4);
    my $page=$layout->box_page($student_id,$q_id,$a_id);
    my $copy=get_copy_id($student_id,$page);
    debug("Field ".$field->{Name}." got PAGE=$page and COPY=$copy");
    $capture->set_zone_auto($student_id,$page,$copy,
                            ZONE_BOX,$q_id,$a_id,
                            100,(value_is_true($field->{Value}) ? 100 : 0),
                            undef,undef);
    return(1);
  }
  if($field->{Name} =~ /^([0-9]+):namefield$/) {
    my $student_id=$1;
    my $page=$layout->namefield_page($student_id);
    my $copy=get_copy_id($student_id,$page);
    debug("Field ".$field->{Name}." got PAGE=$page and COPY=$copy");
    my $zoneid=$capture->get_zoneid($student_id,$page,$copy,ZONE_NAME,0,0,1);
    my $value=decode_utf8($field->{Value});
    $capture->set_zone_auto_id($zoneid,-1,-1,"text:".$value,undef);
    return(1);
  }
  return(0);
}

my @not_considered;

if(@forms) {
  $p->text(__("Reading PDF forms...")) if($p);

  my $dp=1/(1+$#forms);
  for my $f (@forms) {
    my $n_fields=0;
    if($f =~ /\.pdf$/i) {
      if(-f $f) {
        # Extract form data with pdfformfields (before, we were using pdftk):
        open(FORM,"-|","auto-multiple-choice","pdfformfields",$f)
          or die "Error with pdfformfields: $!";
        my $field={};
        clear_copy_id();
        $data->begin_transaction('PDFF');

        while(<FORM>) {
          chomp;
          if(/^---/) {
            $n_fields += handle_field($field);
            $field={};
          }
          if(/^Field([^\s]*):\s(.*)/) {
            $field->{$1}=$2;
          }
        }
        close FORM;

        $n_fields += handle_field($field);
        $data->end_transaction('PDFF');

        debug "Read $n_fields fields from $f";
      } else {
        debug "Skip file not found: $f";
      }
    } else {
      debug "Skip file without PDF extension: $f";
    }

    $p->progres($dp) if($p);

    push @not_considered,$f if($n_fields==0);
  }
}

# write back PDF files not used to files list

if($list_file) {
  open(LIST,">",$list_file);
  for(@not_considered) {
    print LIST "$_\n";
  }
  close(LIST);
} else {
  debug "WARNING: no output list file requested";
}

$p->text('') if($p);

