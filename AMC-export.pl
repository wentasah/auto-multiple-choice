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
use AMC::Gui::Avancement;

use Module::Load;

use_amc_plugins();

my $module='CSV';
my $output='';

my $data_dir='';
my $fich_notes='';
my $fich_assoc='';
my $fich_noms='';
my $noms_encodage='utf-8';
my $csv_build_name='';
my @o_out=();
my $debug='';
my $sort='n';
my $useall=1;
my $rtl='';

@ARGV=unpack_args(@ARGV);
@ARGV_ORIG=@ARGV;

GetOptions("module=s"=>\$module,
	   "sort=s"=>\$sort,
	   "useall=s"=>\$useall,
	   "data=s"=>\$data_dir,
	   "fich-noms=s"=>\$fich_noms,
	   "csv-build-name=s"=>\$csv_build_name,
	   "noms-encodage=s"=>\$noms_encodage,
	   "rtl!"=>\$rtl,
	   "option-out=s"=>\@o_out,
	   "output|o=s"=>\$output,
	   "debug=s"=>\$debug,
	   );

set_debug($debug);

debug "Parameters: ".join(" ",map { "<$_>" } @ARGV_ORIG);

load("AMC::Export::$module");
$ex = "AMC::Export::$module"->new();

$ex->set_options("sort",
		 "keys"=>$sort);

$ex->set_options("fich",
		 "datadir"=>$data_dir,
		 "noms"=>$fich_noms,
		 );

$ex->set_options("noms",
		 "encodage"=>$noms_encodage,
		 "useall"=>$useall,
		 "identifiant"=>$csv_build_name,
		 );

$ex->set_options("out","rtl"=>$rtl);

for my $oo (@o_out) {
    if($oo =~ /([^=]+)=(.*)/) {
	$ex->set_options("out",$1=>$2);
    }
}

debug "Exporting...";

utf8::downgrade($output);
$ex->export($output);

print $ex->messages_as_string();
