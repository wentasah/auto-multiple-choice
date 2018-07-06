#! /usr/bin/perl
#
# Copyright (C) 2009-2017 Alexis Bienvenue <paamc@passoire.fr>
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
use AMC::NamesFile;
use AMC::Data;

my $notes_id='';
my $liste_file='';
my $liste_key='';
my $liste_enc='utf-8';
my $csv_build_name='';
my $data_dir='';
my $debug='';
my $preassoc='';

@ARGV=unpack_args(@ARGV);

GetOptions("notes-id=s"=>\$notes_id,
	   "pre-association!"=>\$preassoc,
	   "liste=s"=>\$liste_file,
	   "liste-key=s"=>\$liste_key,
	   "csv-build-name=s"=>\$csv_build_name,
	   "data=s"=>\$data_dir,
	   "encodage-liste=s"=>\$liste_enc,
	   "debug=s"=>\$debug,
	   );

set_debug($debug);

utf8::downgrade($liste_file);
utf8::downgrade($data_dir);

die "Needs notes-id" if(!$notes_id && !$preassoc);
die "Needs liste-key" if(!$liste_key);
die "Needs liste_file" if(! -s $liste_file);
die "Needs data_dir" if(!-d $data_dir);

my $data=AMC::Data->new($data_dir);
my $scoring=$data->module('scoring');
my $assoc=$data->module('association');
my $capture=$data->module('capture');
my $layout;

$layout=$data->module('layout')
  if($preassoc);

debug "Automatic association $liste_file [$liste_enc] / $liste_key";

# function that "cleans" IDs, removing leading zeros (so that 0001234
# will be the same as 1234)

sub clean_id {
  my ($i)=@_;
  $i =~ s/^0+//;
  return($i);
}

# First read from the students list the possible values for the
# primary key to be found there (from column named $liste_key).

my $liste_e=AMC::NamesFile::new($liste_file,
				'encodage'=>$liste_enc,
				"identifiant"=>$csv_build_name);

my %bon_code;
for my $ii (0..($liste_e->taille()-1)) {
  my $id=$liste_e->data_n($ii,$liste_key);
  $bon_code{clean_id($id)}=$id;
}

debug "Cleaned student list keys: ".join(',',keys %bon_code);

# Open association database and clear old automatic association

$assoc->begin_transaction('ASSA');
annotate_source_change($capture);

$assoc->check_keys($liste_key,$notes_id);
$assoc->clear_auto;

# Loop on all codes that can be read on the scans.

my $sth=$scoring->statement($preassoc ? 'preAssocCounts' : 'codesCounts');
if($preassoc) {
  $sth->execute();
} else {
  $sth->execute($notes_id);
}
while(my $v=$sth->fetchrow_hashref) {
  if($v->{'nb'}==1) {
    # nb is the number of scans on which the same code value has been
    # read. If nb=1, this is OK: we can process association...

    my $id_in_list=$bon_code{clean_id($v->{'value'})};
    if(defined($id_in_list)) {
      # Association OK
      debug "Association OK for code value $v->{'value'} ($id_in_list)";
      $assoc->set_auto((map { $v->{$_} } (qw/student copy/)),$id_in_list);
    } else {
      # ... unless this value is NOT in the students list!
      debug "Code value $v->{'value'} not found in students list: ignoring";
    }
  } else {
    # Code value found on several sheets: do nothing, wait for the
    # user to make a manual association for these sheets.
    debug "Incorrect association for code value \"".$v->{'value'}."\": $v->{'nb'} instances";
  }
}

$assoc->end_transaction('ASSA');
