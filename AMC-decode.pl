#! /usr/bin/perl
#
# Copyright (C) 2019-2021 Alexis Bienvenüe <paamc@passoire.fr>
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

use warnings;
use 5.012;

use Getopt::Long;

use AMC::Basic;
use AMC::Data;
use AMC::DataModule::capture qw/:zone/;
use AMC::DataModule::scoring qw/:direct/;
use AMC::Queue;
use AMC::Gui::Avancement;

use Module::Load;

my $zone_type    = ZONE_NAME;
my $tag          = 'names';
my $decoder_name = '';
my $all          = 0;
my $projects_dir = $ENV{HOME} . '/' . __("MC-Projects");
my $project_dir  = '';
my $cr_dir       = '';
my $data_dir     = '';
my $n_procs      = 0;
my $progress     = 0;
my $progress_id  = 0;

unpack_args();

GetOptions(
    "cr=s"      => \$cr_dir,
    "project=s" => \$project_dir,
    "projects-dir=s", \$projects_dir,
    "data=s"           => \$data_dir,
    "zone-type=s"      => \$zone_type,
    "tag=s"            => \$tag,
    "all!"             => \$all,
    "decoder=s"        => \$decoder_name,
    "n-procs=s"        => \$n_procs,
    "progression=s"    => \$progress,
    "progression-id=s" => \$progress_id,
);

$project_dir = $projects_dir . '/' . $project_dir if ( $project_dir !~ /\// );
$cr_dir      = $project_dir . "/cr"               if ( !$cr_dir );
$data_dir    = $project_dir . "/data"             if ( !$data_dir );

my $queue = '';

my $progress_h = AMC::Gui::Avancement::new( $progress, id => $progress_id );

sub catch_signal {
    my $signame = shift;
    $queue->killall() if ($queue);
    die "Killed";
}

$SIG{INT} = \&catch_signal;

my $data = AMC::Data->new($data_dir);

$data->require_module('capture');
$data->require_module('scoring');

$data->begin_transaction('Deco');
my @all_zones =
  @{ $data->module('capture')->zone_images_available($zone_type) };
my $last_decoded = $data->module('capture')->variable( 'last_decoded_' . $tag );
$last_decoded = 0 if ( !$last_decoded );

$data->module('scoring')->clear_code_direct(DIRECT_NAMEFIELD)
  if ($all);

if ( !$decoder_name ) {
    $data->end_transaction('Deco');
    debug("No decoder!");
    exit(0);
}

my $t = time();

load("AMC::Decoder::$decoder_name");
my $decoder = "AMC::Decoder::$decoder_name"->new();

$queue = AMC::Queue::new( 'max.procs', $n_procs );

my $delta;

sub decode_one {
    my ($z) = @_;
    my $path = $z->{image};
    $path = "$cr_dir/$path" if ($path);
    my $d = $decoder->decode_image( $path, $z->{imagedata} );
    debug("Zone $z->{zoneid}: $d->{ok} ($d->{status}) [$d->{value}]");
    print "Student $z->{student}/$z->{copy}: "
      . ( $d->{ok} ? "success" : "FAILED" )
      . " ($d->{status})"
      . ( $d->{ok} ? " -> $d->{value}" : "" ) . "\n";

    my $decode_data = AMC::Data->new($data_dir);
    my $scoring = $decode_data->module('scoring', version_checked=>1);
    $scoring->begin_transaction('DecS');
    $scoring->new_code(
        $z->{student}, $z->{copy}, "_namefield", $d->{value},
        DIRECT_NAMEFIELD
    );
    $scoring->end_transaction('DecS');
    $progress_h->progres($delta);
}

my $n_zones = 0;
for my $z (@all_zones) {
    debug( "$z->{zoneid} $z->{image} $z->{timestamp_auto}"
          . ( $z->{timestamp_auto} >= $last_decoded ? " [X]" : "" ) );

    if ( $all || $z->{timestamp_auto} >= $last_decoded ) {
        $n_zones += 1;
        $queue->add_process( \&decode_one, $z );
    }

}

$data->end_transaction('Deco');

$data->disconnect();

$delta = ( $n_zones > 1 ? 1 / $n_zones : 1 );

$queue->run();

$progress_h->fin();

debug("New last_decoded time for $tag: $t");

$data->connect;
my $capture = $data->module('capture');
$capture->variable_transaction( 'last_decoded_' . $tag, $t );

