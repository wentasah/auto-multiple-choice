#! /usr/bin/perl

use Getopt::Long;
use File::Temp qw(tempfile);

my $debug=0;
my $do_fonts=0;
my $do_id=0;

GetOptions("debug!"=>\$debug,
           "fonts!"=>\$do_fonts,
           "id!"=>\$do_id,
           );

my ($pdf_source,$pdf_output)=@ARGV;

die "Needs PDF source file" if(!$pdf_source);
$pdf_output=$pdf_source if(!$pdf_output);

my ($fh_us,$uncompressed_source)=tempfile( 'US-XXXXXX', TMPDIR => 1 );
my ($fh_uo,$uncompressed_output)=tempfile( 'UO-XXXXXX', TMPDIR => 1 );

if($debug) {
  print "US = $uncompressed_source\n";
  print "UO = $uncompressed_output\n";
}

system("pdftk",$pdf_source,"output",$uncompressed_source,"uncompress")==0
  || die "pdftk uncompress error: $!";

my $i=-1;

sub new_font_prefix {
  $i++;
  return('ZWHS'.chr(ord('A')+int($i/26)).chr(ord('A')+($i%26)));
}

my %dict=();

open($fh_us,$uncompressed_source) || die "US open error: $!";
open($fh_uo,">",$uncompressed_output) || die "UO open error: $!";
while(<$fh_us>) {
  my $l=$_;
  if($do_fonts) {
    if($l =~ m=^/(?:BaseFont|FontName) /([A-Z]+\+.*)=) {
      my $fontname=$1;
      if(!$dict{$fontname}) {
        my $new_fontname=$fontname;
        my $prefix=new_font_prefix();
        $new_fontname =~ s/^[A-Z]+/$prefix/;
        $dict{$fontname}=$new_fontname;
        print "$fontname --> $new_fontname\n" if($debug);
      }
    }
    for my $k (keys %dict) {
      if($l =~ s/\Q$k\E/$dict{$k}/g) {
        print "Found $k line $.\n" if($debug);
      }
    }
  }
  if($do_id) {
    $l =~ s:/ID \[<[A-F0-9]+> <[A-F0-9]+>\]:/ID [<00> <00>]:i;
  }
  print $fh_uo $l;
}
close(US);
close($fh_uo);

system("pdftk",$uncompressed_output,"output",$pdf_output,"compress")==0
  || die "pdftk compress error: $!";
