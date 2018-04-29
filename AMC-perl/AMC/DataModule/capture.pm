# -*- perl -*-
#
# Copyright (C) 2011-2016 Alexis Bienvenue <paamc@passoire.fr>
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

package AMC::DataModule::capture;

# AMC capture data management.

# This module is used to store (in a SQLite database) and handle all
# data concerning data capture (automatic and manual).

# TABLES:
#
# page describes how a page scan fits with a question document page.
#
# * src is the scan file name (this is a raster image file, like
#   tiff. Usualy a each scan file contains only one page). This
#   filename is absolute, with some shortcuts for portability: %PROJET
#   is the project directory, %PROJETS is the directory where all
#   projects are stored, and %HOME is the user home directory.
#
# * student is the student number of the question page corresponding
#   to the scan
#
# * page is the page number of the question page corresponding
#   to the scan (the page number starts from 1 for eevery student)
#
# * copy is the copy number of this page. When each student has his
#   own student number (question paper is printed from AMC and not
#   photocopied), copy is null. When all the question papers are
#   photocopied from, say, the three first versions of the subject,
#   student is the number from 1 to 3 identifying the original
#   question paper student number, and copy is an integer used to
#   differentiate the completed answer sheets coming from the
#   photocopied answer sheets from the same question paper.
#
# * timestamp_auto is the time when the scan processing was done
#   (using time function: seconds from Jan 1 1970), or -1 if there is
#   no automatic data capture for this page.
#
# * timestamp_manual is the time when the last manual data capture was
#   done (set to -1 if none).
#
# * a,b,c,d,e,f are the 6 parameters describing the linear transform
#   that taked the positions from the question paper to the positions
#   from the scan. Thus, if (x,y) are coordinates of a point on the
#   question paper, the corresponding pixel on the scan file should be
#   near coordinates (x',y'), with
#
#     x' = a*x + b*y + e
#     y' = c*x + d*y + f
#
# * mse is the mean square error for the four corner marks on the page
#   to be perfectly transported from the question paper to the scan by
#   the linear transform defined by (a,b,c,d,e,f).
#
# * layout_image is the filename of the scan image with added drawings
#   showing where boxes are detected. This is a relative filename; the
#   file should be in the %PROJET/cr directory (cr subdirectory of the
#   project directory).
#
# * annotated is the filename of the annotated jpeg of the page, when
#   available. This is a relative filename; the file should be in the
#   %PROJET/cr/corrections/jpg directory.
#
# * timestamp_annotate is the time the annotated page was produced.

# zone describes the different objects that can be found on the scans
# (corner marks, boxes, name field)
#
# * zoneid is an object identifier, also used for the position table.
#
# * student
# * page
# * copy    are the same as for the page table
#
# * type is the object type: ZONE_FRAME for the zone made from the 4
#   corner centers, ZONE_NAME for the name field zone, ZONE_DIGIT for
#   binary boxes at the top of the page identifying the page, ZONE_BOX
#   for the answers boxes to be filled (or not) by the students. The
#   constants ZONE_* are defined later.
#
# * id_a is the question number for ZONE_BOX, or the number id for
#   ZONE_DIGIT. It does not have any meaning for other objects.
#
# * id_b is the answer number for ZONE_BOX, and the digit number for
#   ZONE_DIGIT.
#
# * total is the total number of pixels from the scan inside the zone,
#   or -1 if not measured.
#
# * black is the number of black pixels from the scan inside the zone,
#   or -1 if not measured.
#
# * manual is 1 if the box is declared to be filled by a manual data
#   capture action, 0 if declared not to be filled, and -1 if no
#   manual data capture occured for this zone.
#
# * image is the name of the zone image file, extracted from the
#   scan. This filename is relative to the %PROJET/cr/zooms directory
#   (%PROJET is here the project directory).

# position retains the position of the zones corners on the scan
#
# * zoneid is the zone identifier, as used in the zone table.
#
# * corner is the corner number (1=TL, 2=TR, 3=BR, 4=BL)
#
# * x
# * y  are the coordinates of the zone corner on the scan.
#
# * type is the type of the considered corner: POSITION_BOX if one
#   considers the corner of the box/zone, and POSITION_MEASURE if one
#   considers the corner of the measuring zone (a zone slightly
#   reduced from the box zone, so as not to consider box contours when
#   measuring the number of black pixels).

# failed lists all the scans that could not be processed, as the page
# numbers (student number, page number and check code, as binary
# boxes) could not be read on the top of the page.
#
# * filename is the scan filename.
#
# * timestamp is the time when processing was done.


use Exporter qw(import);

use constant {
  ZONE_FRAME=>1,
  ZONE_NAME=>2,
  ZONE_DIGIT=>3,
  ZONE_BOX=>4,

  POSITION_BOX=>1,
  POSITION_MEASURE=>2,
};

our @EXPORT_OK = qw(ZONE_FRAME ZONE_NAME ZONE_DIGIT ZONE_BOX
		  POSITION_BOX POSITION_MEASURE);
our %EXPORT_TAGS = ( 'zone' => [ qw/ZONE_FRAME ZONE_NAME ZONE_DIGIT ZONE_BOX/ ],
		     'position'=> [ qw/POSITION_BOX POSITION_MEASURE/ ],
		   );

use DBI qw(:sql_types);

use AMC::Basic;
use AMC::DataModule;
use XML::Simple;

@ISA=("AMC::DataModule");

use_gettext();

sub version_current {
  return(4);
}

sub version_upgrade {
    my ($self,$old_version)=@_;
    if($old_version==0) {

      # Upgrading from version 0 (empty database) to version 1 :
      # creates all the tables.

      debug "Creating capture tables...";
      $self->sql_do("CREATE TABLE IF NOT EXISTS ".$self->table("page")
		    ." (src TEXT, student INTEGER, page INTEGER, copy INTEGER DEFAULT 0, timestamp_auto INTEGER DEFAULT 0, timestamp_manual INTEGER DEFAULT 0, a REAL, b REAL, c REAL, d REAL, e REAL, f REAL, mse REAL, layout_image TEXT, annotated TEXT, timestamp_annotate INTEGER, PRIMARY KEY (student,page,copy))");
      $self->sql_do("CREATE TABLE IF NOT EXISTS ".$self->table("zone")
		    ." (zoneid INTEGER PRIMARY KEY, student INTEGER, page INTEGER, copy INTEGER, type INTEGER, id_a INTEGER, id_b INTEGER, total INTEGER DEFAULT -1, black INTEGER DEFAULT -1, manual REAL DEFAULT -1, image TEXT)");
      $self->sql_do("CREATE TABLE IF NOT EXISTS ".$self->table("position")
		    ." (zoneid INTEGER, corner INTEGER, x REAL, y REAL, type INTEGER, PRIMARY KEY (zoneid,corner,type))");
      $self->sql_do("CREATE TABLE IF NOT EXISTS ".$self->table("failed")
		    ." (filename TEXT UNIQUE, timestamp INTEGER)");
      $self->populate_from_xml;

      return(1);
    } elsif($old_version==1) {

      # Includes zoom files in the database

      debug "Including zoom files in the database...";
      $self->sql_do("ALTER TABLE ".$self->table("zone")
		    ." ADD COLUMN imagedata BLOB");

      my $list=$self->get_image_paths(ZONE_BOX);
      my $nn=1+$#{$list};

      if($nn>0) {
	$self->progression('begin',__"Including zooms in the database...");

	my $ii=0;
	for my $i (@{$list}) {
	  if($i->{image}) {
	    my $f=$self->{'data'}->{'directory'}."/../cr/zooms/".$i->{image};
	    if(defined($f) && -f $f) {
	      $self->set_image($i->{zoneid},file_content($f));
	    }
	  }
	  $ii++;
	  $self->progression('fraction',$ii/$nn);
	}

	$self->progression('end');
      }

      return(2)
    } elsif($old_version==2) {
      $self->progression('begin',__("Building capture database indexes..."));
      $self->sql_do("CREATE UNIQUE INDEX IF NOT EXISTS "
		    .$self->index("index_zone")." ON "
		    .$self->table("zone","self")." (student,page,copy,type,id_a,id_b)");

      $self->progression('end');
      return(3);
    } elsif($old_version==3) {
      $self->progression('begin',__("Building capture database indexes..."));
      $self->sql_do("CREATE INDEX IF NOT EXISTS "
		    .$self->index("index_zone_nopage")." ON "
		    .$self->table("zone","self")." (student,copy,type,id_a,id_b)");

      $self->progression('end');
      return(4);
    }
    return('');
}

# Internal function used by populate_from_xml to put all corners
# coordinates of a particular box

sub populate_position {
  my ($self,$xml,$zoneid,$type)=@_;

  return if(!$xml);

  for my $corner (keys %$xml) {
    $self->statement('NEWPosition')
      ->execute($zoneid,
		$corner,
		$xml->{$corner}->{'x'},
		$xml->{$corner}->{'y'},
		$type);
  }
}

# populate_from_xml read the old format XML files (if any) and inserts
# them in the new SQLite database

sub populate_from_xml {
  my ($self)=@_;
  my $cr=$self->{'data'}->directory;
  $cr =~ s/\/[^\/]+\/?$/\/cr/;
  return if(!-d $cr);

  $self->progression('begin',__"Fetching data capture results from old format XML files...");

  my $cordir="$cr/corrections/jpg/";

  opendir(DIR, $cr) || die "can't opendir $cr: $!";
  @xmls = grep { /\.xml$/ && -s "$cr/".$_ } readdir(DIR);
  closedir DIR;

  my $frac=0;

 XML: for my $f (@xmls) {
    my $anx=XMLin("$cr/".$f,
		  ForceArray => ["analyse","chiffre","case","id"],
		  KeepRoot=>1,
		  KeyAttr=> [ 'id' ]);
    next XML if(!$anx->{'analyse'});
  ID: for my $id (keys %{$anx->{'analyse'}}) {
      my $an=$anx->{'analyse'}->{$id};
      my @ep=get_ep($id);
      my %oo;

      my @st=stat("$cr/".$f);
      $oo{'timestamp'}=$st[9];

      if ($an->{'manuel'}) {
	# This is a XML description of a manual data capture: no
	# position information, only ticked-or-not for all
	# boxes
	$self->set_page_manual(@ep,0,$oo{'timestamp'});

	for my $c (keys %{$an->{'case'}}) {
	  my $case=$an->{'case'}->{$c};
	  $self->set_zone_manual(@ep,0,ZONE_BOX,
				 $case->{'question'},$case->{'reponse'},
				 $case->{'r'});
	}
      } else {
	# This is a XML description of an automatic data
	# capture: contains full information about darkness and
	# positions of the boxes
	$oo{'mse'}=$an->{'transformation'}->{'mse'};
	for my $k (qw/a b c d e f/) {
	  $oo{$k}=$an->{'transformation'}->{'parametres'}->{$k};
	}

	$self->set_page_auto($an->{'src'},@ep,0,
			     map { $oo{$_} } (qw/timestamp a b c d e f mse/));

	if($an->{'cadre'}) {
	  my $zoneid=$self->get_zoneid(@ep,0,ZONE_FRAME,0,0,1);
	  $self->populate_position($an->{'cadre'}->{'coin'},
				   $zoneid,POSITION_BOX);
	}
	if($an->{'nom'}) {
	  my $zoneid=$self->get_zoneid(@ep,0,ZONE_NAME,0,0,1);
	  $self->populate_position($an->{'nom'}->{'coin'},
				   $zoneid,POSITION_BOX);
	  # Look if the namefield image is present...
	  my $nf="nom-".id2idf($id).".jpg";
	  if(-f "$cr/$nf") {
	    $self->set_zone_auto_id_without_imagedata($zoneid,-1,-1,$nf);
	  }
	}

	for my $c (keys %{$an->{'case'}}) {
	  my $case=$an->{'case'}->{$c};
	  my $zoneid=$self->get_zoneid(@ep,0,ZONE_BOX,
				       $case->{'question'},$case->{'reponse'},1);

	  my $zf=sprintf("%d-%d/%d-%d.png",
			 @ep,
			 $case->{'question'},$case->{'reponse'});
	  $zf='' if(!-f "$cr/zooms/$zf");

	  $self->set_zone_auto_id_without_imagedata
	    ($zoneid,
	     $case->{'pixels'},$case->{'pixelsnoirs'},
	     $zf);

	  $self->populate_position($case->{'coin'},$zoneid,POSITION_BOX);
	  $self->populate_position($an->{'casetest'}->{$c}->{'coin'},
				   $zoneid,POSITION_MEASURE);
	}

	# Look if annotated scan is present...
	my $af="page-".id2idf($id).".jpg";
	if(-f $cordir.$af) {
	  my @sta=stat($cordir.$af);
	  $self->set_annotated(@ep,0,$af,$sta[9]);
	}
	# Look if layout scan is present...
	if(-f $cr.'/'.$af) {
	  my @sta=stat($cr.'/'.$af);
	  $self->set_layout_image(@ep,0,$af,$sta[9]);
	}
      }
    }

    $frac++;
    $self->progression('fraction',$frac/($#xmls+1));
  }

  $self->progression('end');
}

# defines all the SQL statements that will be used

sub define_statements {
  my ($self)=@_;
  my $t_page=$self->table("page");
  my $t_zone=$self->table("zone");
  my $t_position=$self->table("position");
  my $t_failed=$self->table("failed");
  my $t_box=$self->table("box","layout");
  my $t_namefield=$self->table("namefield","layout");
  my $t_layoutpage=$self->table("page","layout");
  my $t_lnf=$self->table("namefield","layout");
  $self->{'statements'}=
    {
     'NEWPageAuto'=>{'sql'=>"INSERT INTO $t_page"
		     ." (src,student,page,copy,timestamp_auto,a,b,c,d,e,f,mse)"
		     ." VALUES (?,?,?,?,?,?,?,?,?,?,?,?)"},
     'NEWPageManual'=>{'sql'=>"INSERT INTO $t_page"
		       ." (student,page,copy,timestamp_manual)"
		       ." VALUES (?,?,?,?)"},
     'SetPageAuto'=>{'sql'=>"UPDATE $t_page"
		     ." SET src=?, timestamp_auto=?, a=?, b=?, c=?, d=?, e=?, f=?, mse=?"
		     ." WHERE student=? AND page=? AND copy=?"},
     'SetPageManual'=>{'sql'=>"UPDATE $t_page"
		       ." SET timestamp_manual=?"
		       ." WHERE student=? AND page=? AND copy=?"},
     'NEWZone'=>{'sql'=>"INSERT INTO $t_zone"
		 ." (student,page,copy,type,id_a,id_b)"
		 ." VALUES (?,?,?,?,?,?)"},
     'getZoneID'=>{'sql'=>"SELECT zoneid FROM $t_zone"
		   ." WHERE student=? AND page=? AND copy=? AND type=? AND id_a=? AND id_b=?"},
     'zonesCount'=>{'sql'=>"SELECT COUNT(*) FROM $t_zone"
		    ." WHERE student=? AND page=? AND copy=? AND type=?"},
     'zone'=>{'sql'=>"SELECT COUNT(*) FROM $t_zone"
	      ." WHERE student=? AND page=? AND copy=? AND type=?"
	      ." AND id_a=? AND id_b=?"},
     'NEWPosition'=>{'sql'=>"INSERT OR REPLACE INTO $t_position"
		     ." (zoneid,corner,x,y,type)"
		     ." VALUES (?,?,?,?,?)"},
     'setPosition'=>{'sql'=>"UPDATE $t_position"
		     ." SET x=?, y=? WHERE zoneid=? AND corner=? AND type=?"},
     'getPage'=>{'sql'=>"SELECT * FROM $t_page"
		 ." WHERE student=? AND page=? AND copy=?"},
     'setZoneManual'=>{'sql'=>"UPDATE $t_zone"
		       ." SET manual=? WHERE zoneid=?"},
     'setZoneAuto'=>{'sql'=>"UPDATE $t_zone"
		     ." SET total=?, black=?, image=?, imagedata=? WHERE zoneid=?"},
     'setZoneAutoPrim'=>{'sql'=>"UPDATE $t_zone"
			 ." SET total=?, black=?, image=? WHERE zoneid=?"},
     'nPages'=>{'sql'=>"SELECT COUNT(*) FROM $t_page"
		." WHERE timestamp_auto>0 OR timestamp_manual>0"},
     'nPagesAuto'=>{'sql'=>"SELECT COUNT(*) FROM $t_page"
		   ." WHERE timestamp_auto>0"},
     'students'=>{'sql'=>"SELECT student FROM $t_page"
		 ." WHERE timestamp_auto>0 OR timestamp_manual>0"
		  ." GROUP BY student ORDER BY student"},
     'nCopies'=>{'sql'=>"SELECT COUNT(*) FROM (SELECT student,copy FROM $t_page"
		 ." WHERE timestamp_auto>0 OR timestamp_manual>0"
		 ." GROUP BY student,copy)"},
     'studentCopies'=>{'sql'=>"SELECT student,copy FROM $t_page"
		       ." WHERE timestamp_auto>0 OR timestamp_manual>0"
		       ." GROUP BY student,copy ORDER BY student,copy"},
     'maxCopy'=>{'sql'=>"SELECT MAX(copy) FROM $t_page"},
     'maxAnswer'=>{'sql'=>"SELECT MAX(id_b) FROM $t_zone WHERE type=?"},
     'pageCopies'=>{'sql'=>"SELECT copy FROM $t_page"
		    ." WHERE student=? AND page=? AND copy>=?"
		    ." ORDER BY copy"},
     'pageLastCopy'=>{'sql'=>"SELECT MAX(copy) FROM $t_page"
		      ." WHERE student=? AND page=?"},
     'pagesChanged'=>{'sql'=>"SELECT student,page,copy FROM $t_page"
		      ." WHERE timestamp_auto>? OR timestamp_manual>?"},
     'pagesSummary'=>
     {'sql'=>"SELECT student,page,copy,mse,timestamp_auto,timestamp_manual"
      .",CASE WHEN timestamp_auto>0 AND mse>? THEN ?"
      ."      ELSE ?"
      ."  END AS mse_color"
      .",CASE WHEN timestamp_manual>0 THEN ?"
      ."      WHEN timestamp_auto>0 THEN ?"
      ."      ELSE ?"
      ."  END AS color"
      .",CASE WHEN timestamp_manual>0 THEN timestamp_manual"
      ."      ELSE timestamp_auto"
      ."  END AS timestamp"
      .",(SELECT MIN(ABS(1.0*black/total-?))"
      ."   FROM $t_zone"
      ."   WHERE $t_zone.student=$t_page.student"
      ."     AND $t_zone.page=$t_page.page AND $t_zone.copy=$t_page.copy"
      ."     AND $t_zone.type=? AND total>0) AS delta"
      .",(SELECT MIN(ABS(1.0*black/total-?))"
      ."   FROM $t_zone"
      ."   WHERE $t_zone.student=$t_page.student"
      ."     AND $t_zone.page=$t_page.page AND $t_zone.copy=$t_page.copy"
      ."     AND $t_zone.type=? AND total>0) AS delta_up"
      ." FROM $t_page"},
     'pages'=>{'sql'=>"SELECT * FROM $t_page"
	       ." WHERE timestamp_auto>0 OR timestamp_manual>0"},
     'missingPages'=>
     {'sql'=>"SELECT enter.student AS student,enter.page AS page ,$t_page.copy AS copy"
      ." FROM (SELECT student,page FROM $t_box WHERE role=1"
      ."       UNION SELECT student,page FROM $t_namefield) AS enter,"
      ."      $t_page"
      ." ON enter.student=$t_page.student"
      ." EXCEPT SELECT student,page,copy FROM $t_page"
      ." ORDER BY student,copy,page"},
     'questionOnlyPages'=>
     {'sql'=>"SELECT student,page,0 AS copy FROM $t_box WHERE role=2"
      ." EXCEPT SELECT student,page,0 AS copy FROM $t_box WHERE role=1"},
     'noCapturePages'=>
     {'sql'=>"SELECT student,page,0 AS copy FROM $t_box WHERE role=1"
      ." UNION SELECT student,page,0 AS copy FROM $t_namefield"
      ." EXCEPT SELECT student,page,copy FROM $t_page"
      ." WHERE timestamp_auto>0 OR timestamp_manual>0"},
     'pageNearRatio'=>{'sql'=>"SELECT MIN(ABS(1.0*black/total-?))"
		       ." FROM $t_zone"
		       ." WHERE student=? AND page=? AND copy=? AND total>0"},
     'pageZones'=>{'sql'=>"SELECT zoneid,id_a,id_b,total,black,manual,1 AS role FROM $t_zone"
		   ." WHERE student=? AND page=? AND copy=? AND type=?"},
     'zonesImages'=>{'sql'=>"SELECT image FROM $t_zone"
		     ." WHERE student=? AND page=? AND copy=? AND type=?"},
     'imagePaths'=>{'sql'=>"SELECT zoneid,image FROM $t_zone WHERE type=?"},
     'setImage'=>{'sql'=>"UPDATE $t_zone SET image='',imagedata=? WHERE zoneid=?"},
     'zoomsTotalSize'=>{'sql'=>"SELECT SUM(LENGTH(imagedata)) FROM $t_zone"
			." WHERE type=?"},
     'zoomsCleanup'=>{'sql'=>"UPDATE $t_zone SET imagedata=NULL WHERE type=?"},
     'pageZonesAll'=>{'sql'=>"SELECT * FROM $t_zone"
		      ." WHERE type=?"},
     'pageZonesD'=>{'sql'=>"SELECT zoneid,id_a,id_b,total,black,manual"
		    ." FROM $t_zone"
		    ." WHERE student=? AND page=? AND copy=? AND type=?"
		    ." AND total>0"
		    ." ORDER BY 1.0*black/total"},
     'pageZonesDI'=>{'sql'=>"SELECT *"
		    ." FROM $t_zone"
		    ." WHERE student=? AND page=? AND copy=? AND type=?"
		    ." AND total>0"
		    ." ORDER BY 1.0*black/total"},
     'zoneDarkness'=>{'sql'=>"SELECT 1.0*black/total FROM $t_zone"
		      ." WHERE zoneid=? AND total>0"},
     'zoneImage'=>{'sql'=>"SELECT image FROM $t_zone"
		      ." WHERE student=? AND copy=? AND type=?"},
     'setManualPage'=>{'sql'=>"UPDATE $t_page"
		       ." SET timestamp_manual=?"
		       ." WHERE student=? AND page=? AND copy=?"},
     'setManual'=>{'sql'=>"UPDATE $t_zone"
		   ." SET manual=?"
		   ." WHERE student=? AND page=? AND copy=?"
		   ." AND type=? AND id_a=? AND id_b=?"},
     'setManualPageZones'=>{'sql'=>"UPDATE $t_zone"
			    ." SET manual=?"
			    ." WHERE student=? AND page=? AND copy=?"},
     'ticked'=>{'sql'=>"SELECT CASE"
		." WHEN manual >= 0 THEN manual"
		." WHEN total<=0 THEN -1"
		." WHEN black >= ? * total AND black <= ? * total THEN 1"
		." ELSE 0"
		." END FROM $t_zone"
		." WHERE student=? AND copy=? AND type=? AND id_a=? AND id_b=?"},
     'tickedSums'=>{'sql'=>
		    "SELECT * FROM (SELECT zone.id_a AS question,zone.id_b AS answer,SUM(CASE"
		    ." WHEN why=\"V\" THEN 0"
		    ." WHEN why=\"E\" THEN 0"
		    ." WHEN zone.manual >= 0 THEN zone.manual"
		    ." WHEN zone.total<=0 THEN -1"
		    ." WHEN zone.black >= ? * zone.total AND zone.black <= ? * zone.total THEN 1"
		    ." ELSE 0"
		    ." END) AS nb"
		    ." FROM $t_zone AS zone, scoring.scoring_score AS score"
		    ." ON zone.student=score.student AND zone.copy=score.copy AND zone.id_a=score.question"
		    ." WHERE zone.type=? GROUP BY zone.id_a,zone.id_b)"
		    ." UNION"
		    ." SELECT * FROM (SELECT question,\"invalid\" AS answer,"
		    ." COUNT(*)-COUNT(NULLIF(why,\"E\")) AS nb"
		    ." FROM scoring.scoring_score"
		    ." GROUP BY question)"
		    ." UNION"
		    ." SELECT * FROM (SELECT question,\"empty\" AS answer,"
		    ." COUNT(*)-COUNT(NULLIF(why,\"V\")) AS nb"
		    ." FROM scoring.scoring_score"
		    ." GROUP BY question)"
		    ." UNION"
		    ." SELECT * FROM (SELECT question,\"all\" AS answer,COUNT(*) AS nb"
		    ." FROM scoring.scoring_score"
		    ." GROUP BY question)"
		   },
     'tickedList'=>{'sql'=>"SELECT CASE"
		    ." WHEN manual >= 0 THEN manual"
		    ." WHEN total<=0 THEN -1"
		    ." WHEN black >= ? * total AND black <= ? * total THEN 1"
		    ." ELSE 0"
		    ." END FROM $t_zone"
		    ." WHERE student=? AND copy=? AND type=? AND id_a=?"
		    ." ORDER BY id_b"},
     'tickedPage'=>{'sql'=>"SELECT CASE"
		    ." WHEN manual >= 0 THEN manual"
		    ." WHEN total<=0 THEN -1"
		    ." WHEN black >= ? * total AND black <= ? * total THEN 1"
		    ." ELSE 0"
		    ." END,id_a,id_b FROM $t_zone"
		    ." WHERE student=? AND page=? AND copy=? AND type=?"},
     'zoneCorner'=>{'sql'=>"SELECT x,y FROM $t_position"
		    ." WHERE zoneid=? AND type=? AND corner=?"},
     'zoneCenter'=>{'sql'=>"SELECT AVG(x),AVG(y) FROM $t_position"
		    ." WHERE zoneid=? AND type=?"},
     'zoneDist'=>{'sql'=>"SELECT AVG((x-?)*(x-?)+(y-?)*(y-?))"
		  ." FROM $t_position"
		  ." WHERE zoneid=? AND type=?"},
     'getAnnotated'=>{'sql'=>"SELECT annotated,timestamp_annotate,student,page,copy"
		      ." FROM $t_page"
		      ." WHERE timestamp_annotate>0"
		      ." ORDER BY student,copy,page"},
     'getAnnotatedFiles'=>{'sql'=>"SELECT annotated"
			   ." FROM $t_page"
			   ." WHERE timestamp_auto>0"
			   ." ORDER BY student,copy,page"},
     'getAnnotatedPage'=>{'sql'=>"SELECT annotated"
			  ." FROM $t_page"
			  ." WHERE timestamp_annotate>0"
			  ." AND student=? AND page=? AND copy=?"},
     'annotatedCount'=>{'sql'=>"SELECT COUNT(*) FROM $t_page"
			." WHERE timestamp_annotate>0 AND annotated NOT NULL"},
     'getScanPage'=>{'sql'=>"SELECT src"
			  ." FROM $t_page"
			  ." WHERE student=? AND page=? AND copy=?"},
     'setAnnotated'=>{'sql'=>"UPDATE $t_page"
		      ." SET annotated=?, timestamp_annotate=?"
		      ." WHERE student=? AND page=? AND copy=?"},
     'setAnnotatedPageOutdated'=>{'sql'=>"UPDATE $t_page"
				  ." SET timestamp_annotate=0"
				  ." WHERE student=? AND page=? AND copy=?"},
     'setAnnotatedCopyOutdated'=>{'sql'=>"UPDATE $t_page"
				  ." SET timestamp_annotate=0"
				  ." WHERE student=? AND copy=?"},
     'setLayout'=>{'sql'=>"UPDATE $t_page"
		   ." SET layout_image=?"
		   ." WHERE student=? AND page=? AND copy=?"},
     'getLayout'=>{'sql'=>"SELECT layout_image FROM $t_page"
		   ." WHERE student=? AND page=? AND copy=?"},
     'questionHasZero'=>{'sql'=>"SELECT COUNT(*) FROM $t_zone"
			 ." WHERE student=? AND copy=? AND type=? AND id_a=?"
			 ." AND id_b=0"},
     'Failed'=>{'sql'=>"INSERT OR REPLACE INTO $t_failed"
		." (filename,timestamp)"
		." VALUES (?,?)"},
     'failedList'=>{'sql'=>"SELECT * FROM $t_failed"},
     'failedNb'=>{'sql'=>"SELECT COUNT(*) FROM $t_failed"},
     'deleteFailed'=>{'sql'=>"DELETE FROM $t_failed WHERE filename=?"},
     'deletePagePositions'=>
     {'sql'=>"DELETE FROM $t_position"
      ." WHERE zoneid IN"
      ." (SELECT zoneid FROM $t_zone WHERE student=? AND page=? AND copy=?)"},
     'deletePageZones'=>{'sql'=>"DELETE FROM $t_zone"
			 ." WHERE student=? AND page=? AND copy=?"},
     'deletePage'=>{'sql'=>"DELETE FROM $t_page"
			 ." WHERE student=? AND page=? AND copy=?"},
     'pagesStudent'=>
     {'sql'=>"SELECT a.page AS page,a.subjectpage AS subjectpage,"
      ."             b.annotated AS annotated"
      ." FROM (SELECT * FROM $t_layoutpage WHERE student=?) AS a"
      ." LEFT JOIN"
      ."      (SELECT * FROM $t_page"
      ."        WHERE student=? AND copy=? AND timestamp_annotate>0) AS b"
      ." ON a.page=b.page ORDER BY a.page"
     },
     'nameFields'=>
     {'sql'=>"SELECT a.student AS student,a.page AS page,a.copy AS copy,"
      ."             b.image  AS image FROM"
      ." ( SELECT c.student,c.page,c.copy FROM"
      ."     (SELECT * FROM $t_page WHERE timestamp_auto>0 OR timestamp_manual>0 )"
      ."      AS c, $t_lnf AS l"
      ."     ON c.student=l.student AND c.page=l.page ) AS a"
      ." LEFT OUTER JOIN"
      ." ( SELECT student,page,copy,image FROM $t_zone WHERE type=? ) AS b"
      ." ON a.student=b.student AND a.page=b.page AND a.copy=b.copy"
     },
     'photocopy'=>{'sql'=>"SELECT COUNT(*) FROM $t_page WHERE copy>0"},
     'zonesBBox'=>{'sql'=>"SELECT z.id_a AS question,z.id_b AS answer,"
		   ."   min(p.x) AS xmin,max(p.x) AS xmax,"
		   ."   min(p.y) AS ymin,max(p.y) AS ymax"
		   ." FROM $t_zone AS z,$t_position as p"
		   ." ON z.zoneid=p.zoneid"
		   ." WHERE z.student=? AND z.page=? AND z.copy=?"
		   ."   AND z.type=? AND p.type=?"
		   ." GROUP BY z.zoneid"},
     'zonesCorners'=>{'sql'=>"SELECT z.id_a AS question,z.id_b AS answer,"
		      ."   p.x AS x,p.y AS y,p.corner AS corner"
		      ." FROM $t_zone AS z,$t_position as p"
		      ." ON z.zoneid=p.zoneid"
		      ." WHERE z.student=? AND z.page=? AND z.copy=?"
		      ."   AND z.type=? AND p.type=?"
		      ." ORDER BY z.zoneid,p.corner"},
    };
  $self->{'statements'}->{'pageSummary'}=
    {'sql'=>$self->{'statements'}->{'pagesSummary'}->{'sql'}
     ." WHERE student=? AND page=? AND copy=?"};
  $self->{'statements'}->{'pagesSummary'}->{'sql'}.=" ORDER BY student,page,copy";
}

# get_page($student,$page,$copy) returns all columns from the row with
# given ($student,$page,$copy) in table capture_page. If such a row
# exists, a hashref is returned. If not, undef is returned.

sub get_page {
  my ($self,$student,$page,$copy)=@_;
  return($self->dbh->selectrow_hashref($self->statement('getPage'),{},
				       $student,$page,$copy));
}

# set_page_auto(...) fills one row of the page table.

sub set_page_auto {
  my ($self,$src,$student,$page,$copy,
      $timestamp,$a,$b,$c,$d,$e,$f,$mse)=@_;
  if($self->get_page($student,$page,$copy)) {
    $self->statement('SetPageAuto')->execute($src,
					     $timestamp,$a,$b,$c,$d,$e,$f,
					     $mse,
					     $student,$page,$copy);
  } else {
    $self->statement('NEWPageAuto')->execute($src,$student,$page,$copy,
					     $timestamp,$a,$b,$c,$d,$e,$f,
					     $mse);
  }
}

# sep_page_manual($student,$page,$copy,$timestamp) sets the timestamp
# for a manual data capture for a particular page. With no $timestamp
# argument, present time is used.

sub set_page_manual {
  my ($self,$student,$page,$copy,
      $timestamp)=@_;
  $timestamp=time() if(!defined($timestamp));
  if($self->get_page($student,$page,$copy)) {
    $self->statement('SetPageManual')->execute($timestamp,
					       $student,$page,$copy);
  } else {
    $self->statement('NEWPageManual')->execute($student,$page,$copy,
					       $timestamp);
  }
}

# get_zoneid($student,$page,$copy,$type,$id_a,$id_b,$create) gets the
# zone identifier corresponding to a particular zone. If $create is
# true, the identifier is created if not yet present in the database.

sub get_zoneid {
  my ($self,$student,$page,$copy,$type,$id_a,$id_b,$create)=@_;
  my $r=$self->dbh->selectrow_arrayref($self->statement('getZoneID'),{},
				       $student,$page,$copy,$type,$id_a,$id_b);
  if($r) {
    return($r->[0]);
  } else {
    if($create) {
      $self->statement('NEWZone')->execute($student,$page,$copy,$type,$id_a,$id_b);
      return($self->dbh->sqlite_last_insert_rowid());
    } else {
      return(undef);
    }
  }
}

# set_zone_manual($student,$page,$copy,$type,$id_a,$id_b,$manual) sets
# the manual value (ticked or not) for a particular zone

sub set_zone_manual {
  my ($self,$student,$page,$copy,$type,$id_a,$id_b,$manual)=@_;
  my $zoneid=$self->get_zoneid($student,$page,$copy,$type,$id_a,$id_b,1);
  $self->statement('setZoneManual')->execute($manual,$zoneid);
}

# set_zone_auto(...,$total,$black,$image,$image_data) sets automated
# data capture results for a particular zone.

sub set_zone_auto {
  my ($self,$student,$page,$copy,$type,$id_a,$id_b,$total,$black,$image,$image_data)=@_;
  $self->set_zone_auto_id($self->get_zoneid($student,$page,$copy,$type,$id_a,$id_b,1),
			  $total,$black,$image,$image_data);
}

sub set_zone_auto_id {
  my ($self,$zoneid,$total,$black,$image,$image_data)=@_;
  my $sth=$self->statement('setZoneAuto');
  $sth->bind_param(1,$total);
  $sth->bind_param(2,$black);
  $sth->bind_param(3,$image);
  $sth->bind_param(4,$image_data,SQL_BLOB);
  $sth->bind_param(5,$zoneid);
  $sth->execute();
}

sub set_zone_auto_id_without_imagedata {
  my ($self,$zoneid,$total,$black,$image)=@_;
  my $sth=$self->statement('setZoneAutoPrim');
  $sth->bind_param(1,$total);
  $sth->bind_param(2,$black);
  $sth->bind_param(3,$image);
  $sth->bind_param(4,$zoneid);
  $sth->execute();
}

# n_pages returns the number of copies for which a data capture (manual
# or auto) is declared.

sub n_copies {
  my ($self)=@_;
  return($self->sql_single($self->statement('nCopies')));
}

# n_pages returns the number of pages for which a data capture (manual
# or auto) is declared.

sub n_pages {
  my ($self)=@_;
  return($self->sql_single($self->statement('nPages')));
}

# n_pages_transaction calls n_pages inside a SQLite transaction.

sub n_pages_transaction {
  my ($self)=@_;
  $self->begin_read_transaction;
  my $n=$self->n_pages;
  $self->end_transaction;
  return($n);
}

# students returns the list of students numbers for which a data
# capture is declared.

sub students {
  my ($self)=@_;
  return($self->sql_list($self->statement('students')));
}

# student_copies returns a list of [student,copy] for which a data
# capture is declared.

sub student_copies {
  my ($self)=@_;
  return(@{$self->dbh->selectall_arrayref($self->statement('studentCopies'))});
}

# students_transaction calls students inside a SQLite transaction.

sub students_transaction {
  my ($self)=@_;
  $self->begin_read_transaction;
  my @r=$self->students;
  $self->end_transaction;
  return(@r);
}

# n_pages_auto returns the number of pages for which a automated data
# capture occured.

sub n_pages_auto {
  my ($self)=@_;
  return($self->sql_list($self->statement('nPagesAuto')));
}

# page_sensitivity($student,$page,$copy,$darkness_threshold,$darkness_threshold_up)
# returns a sensitivity value for the page automated data
# capture. When this value is low (near 0), black and white boxes have
# darkness values far away from the threshold, and thus one can think
# that it is well recognized if the boxes are ticked or not. With high
# values of the sensitivity (the maximal value is 10), ticked boxes
# are not robustly detected: if one changes a little the darkness
# threshold, boxes can pass from the ticked to not-ticked state or
# vice versa.

sub sensitivity_down {
  my ($delta,$threshold)=@_;
  return(defined($delta) && $threshold>0 ? 10*($threshold-$delta)/$threshold : undef);
}

sub sensitivity_up {
  my ($delta,$threshold)=@_;
  return(defined($delta) && $threshold<1 ? sensitivity($delta,1-$threshold) : undef);
}

sub sensitivity {
  my ($delta,$threshold,$delta_up,$threshold_up)=@_;
  my $s=sensitivity_down($delta,$threshold);
  my $s_up=sensitivity_up($delta_up,$threshold_up);
  return(defined($s_up) && (!defined($s) || $s_up>$s) ?
	 $s_up : $s);
}

sub page_sensitivity {
  my ($self,$student,$page,$copy,$darkness_threshold,$darkness_threshold_up)=@_;
  die "Missing parameters in pqge_sensitivity call"
    if(!defined($darkness_threshold_up));
  my $delta=$self->sql_single($self->statement('pageNearRatio'),
			      $darkness_threshold,
			      $student,$page,$copy);
  my $delta_up=$self->sql_single($self->statement('pageNearRatio'),
				 $darkness_threshold_up,
				 $student,$page,$copy);
  return(sensitivity($delta,$darkness-threshold,
		     $delta_up,$darkness_threshold_up));
}

# page_summary($student,$page,$copy,%options) returns a hash %s giving
# some summarized information about the page automated data capture
# process:
#
# $s{'mse'} is the mean square error of the transform from question
# paper coordinates to scan coordinates
#
# $s{'mse_color'} is 'red' if the MSE exceeds
# $options{'mse_threshold'}, and undef otherwise
#
# $s{'color'} is blue if some automated data capture occured for this
# page, green if some manual data capture occured, and undef
# otherwise.
#
# $s{'update'} is a textual reprsentation of the date when the last
# data capture occured.
#
# $s{'sensitivity'} is the sensitivity (see function page_sensitivity).
#
# $s{'sensitivity'} is 'red' is the sensitivity exceeds
# $options{'sensitivity_threshold'}, undef otherwise.
#
# $s{'why'} (only available if $options{'why'} is true) collects all
# 'why' attributes from all qeustions on the page (from the scoring table)

# summaries returns a reference to an array containing the summaries
# of all pages.

sub compute_summaries {
  my ($self,$r,%oo)=@_;
  # compute some more variables from the SQL result
  for my $p (@$r) {
    $p->{'mse_string'}=($p->{'timestamp_auto'}>0 ?
			sprintf($p->{'timestamp_manual'}>0 ? "(%.01f)" : "%.01f",
				$p->{'mse'})
			: "---");
    $p->{'sensitivity'}=sensitivity($p->{'delta'},$oo{'darkness_threshold'},
				    $p->{'delta_up'},$oo{'darkness_threshold_up'});
    $p->{'sensitivity_string'}=(defined($p->{'sensitivity'}) 
				? sprintf("%.1f",$p->{'sensitivity'}) : "---");
    $p->{'sensitivity_color'}=(defined($p->{'sensitivity'}) ?
			       ($p->{'sensitivity'} > $oo{'sensitivity_threshold'}
				? 'red' : undef) : undef);
  }
  if($oo{why}) {
    $self->require_module("layout");
    my %why=();
    for my $w ($self->module("scoring")->pages_why()) {
      $why{pageids_string($w->{student},$w->{page},$w->{copy})}=$w->{why};
    }
    for my $p (@$r) {
      $p->{why}=$why{pageids_string($p->{student},$p->{page},$p->{copy})};
    }
  }
  return($r);
}

sub page_summary {
  my ($self,$student,$page,$copy,%oo)=@_;
  my $r=$self->dbh->selectall_arrayref($self->statement('pageSummary'),
				       {Slice=>{}},
				       $oo{'mse_threshold'},'red',undef,
				       'lightblue','lightgreen',undef,
				       $oo{'darkness_threshold'},ZONE_BOX,
				       $oo{'darkness_threshold_up'},ZONE_BOX,
				       $student,$page,$copy,
				      );
  if($r && $r->[0]) {
    $r=$self->compute_summaries($r,%oo);
    return(%{$r->[0]});
  } else {
    return();
  }
}

sub summaries {
  my ($self,%oo)=@_;
  my $r=$self->dbh->selectall_arrayref($self->statement('pagesSummary'),
				       {Slice=>{}},
				       $oo{'mse_threshold'},'red',undef,
				       'lightblue','lightgreen',undef,
				       $oo{'darkness_threshold'},ZONE_BOX,
				       $oo{'darkness_threshold_up'},ZONE_BOX,
				      );
  return($self->compute_summaries($r,%oo));
}

# zone_drakness($zoneid) return the darkness (from 0 to 1) for a
# particular zone.

sub zone_darkness {
  my ($self,$zoneid)=@_;

  return($self->sql_single($self->statement('zoneDarkness'),
			   $zoneid));
}

# ticked($student,$copy,$question,$answer,$darkness_threshold,$darkness_threshold_up)
# returns 1 if the darkness of a particular zone exceeds
# $darkness_threshold and is less than $darkness_threshold_up, and 0
# otherwise. If a manual data capture occured for this zone, the
# darkness is not considered and the manual result is given instead.

sub ticked {
  my ($self,$student,$copy,$question,$answer,
      $darkness_threshold,$darkness_threshold_up)=@_;
  die "Missing parameters in ticked call"
    if(!defined($darkness_threshold_up));
  return($self->sql_single($self->statement('ticked'),
			   $darkness_threshold,$darkness_threshold_up,
			   $student,$copy,ZONE_BOX,$question,$answer));
}

# ticked_sums($darkness_threshold,$darkness_threshold_up) returns a
# ref to a list of hashrefs like
#
# [{'question=>1,'answer'=>1,nb=>4},
#  {'question=>1,'answer'=>'invalid',nb=>1},
#  {'question=>1,'answer'=>'empty',nb=>2},
# ]
#
# that gives, for each question, the number of times each answer was
# ticked, and the number of sheets where this question was not
# replied, and where this question got invalid answers.

sub ticked_sums {
  my ($self,$darkness_threshold,$darkness_threshold_up)=@_;
  die "Missing parameters in ticked_sums call"
    if(!defined($darkness_threshold_up));
  return($self->dbh->selectall_arrayref($self->statement('tickedSums'),
					{ Slice=>{} },
					$darkness_threshold,$darkness_threshold_up,ZONE_BOX)
	 );
}

# has_answer_zero($student,$copy,$question) returns true if the
# requested question has an answer "none of the above are correct".

sub has_answer_zero {
  my ($self,$student,$copy,$question)=@_;
  return($self->sql_single($self->statement('questionHasZero'),
			   $student,$copy,ZONE_BOX,$question));
}

# ticked_list($student,$copy,$question,$darkness_threshold,$darkness_threshold_up)
# returns a list with the ticked results for all the answers boxes
# from a particular question. Answers are ordered with the answer
# number, so that the answer "None of the above" (if present), with
# answer number 0, is placed at the beginning.

sub ticked_list {
  my ($self,$student,$copy,$question,$darkness_threshold,$darkness_threshold_up)=@_;
  die "Missing parameters in ticked_list call"
    if(!defined($darkness_threshold_up));
  return($self->sql_list($self->statement('tickedList'),
			 $darkness_threshold,$darkness_threshold_up,
			 $student,$copy,ZONE_BOX,$question));
}

# ticked_list_0 id the same as ticked_list, but answer 0
# (corresponding to "None of the above") is placed at the end of the
# list.

sub ticked_list_0 {
  my ($self,$student,$copy,$question,$darkness_threshold,$darkness_threshold_up)=@_;
  die "Missing parameters in ticked_list_0 call"
    if(!defined($darkness_threshold_up));
  my @tl=$self->ticked_list($student,$copy,$question,$darkness_threshold,$darkness_threshold_up);
  if($self->has_answer_zero($student,$copy,$question)) {
    my $zero=shift @tl;
    push @tl,$zero;
  }
  return(@tl);
}

# zones_count($student,$page,$copy,$type) returns the number of zones
# of type $type from a particular page.

sub zones_count {
  my ($self,$student,$page,$copy,$type)=@_;
  $type=POSITION_BOX if(!$type);
  return($self->sql_single($self->statement('zonesCount'),
			   $student,$page,$copy,$type));
}

# zone_dist2($zoneid,$x,$y,$type) returns the mean of the square
# distance from the point ($x,$y) to the corners of a particular zone.

sub zone_dist2 {
  my ($self,$zoneid,$x,$y,$type)=@_;
  $type=POSITION_BOX if(!$type);
  return($self->sql_single($self->statement('zoneDist'),
			   $x,$x,$y,$y,$zoneid,$type));
}

# zone_corner($zoneid,$corner,$type) returns the coordinates of a zone
# corner as a list (with two values).

sub zone_corner {
  my ($self,$zoneid,$corner,$type)=@_;
  $type=POSITION_BOX if(!$type);
  return($self->sql_row($self->statement('zoneCorner'),
			$zoneid,$type,$corner));
}

# set_corner($zoneid,$corner,$type,$x,$y) sets the coordinates of a
# corner of a zone (or the corner measuring zone, reduced from the
# original zone, depending on the $type parameter).

sub set_corner {
  my ($self,$zoneid,$corner,$type,$x,$y)=@_;
  $self->statement('NEWPosition')
    ->execute($zoneid,$corner,$x,$y,$type);
}

# zone_images($student,$copy,$type) returns a list of the image values
# of zones corresponding to $student,$value,$type.

sub zone_images {
  my ($self,$student,$copy,$type)=@_;
  return($self->sql_list($self->statement('zoneImage'),
			 $student,$copy,$type));
}

# set_layout_image($student,$page,$copy,$file) sets the name of the
# scan with drawings of the boxes image file.

sub set_layout_image {
  my ($self,$student,$page,$copy,$file)=@_;
  $self->statement('setLayout')
    ->execute($file,$student,$page,$copy);
}

# get_layout_image($student,$page,$copy) gets the name of the
# scan with drawings of the boxes image file.

sub get_layout_image {
  my ($self,$student,$page,$copy)=@_;
  return($self->sql_single($self->statement('getLayout'),
			   $student,$page,$copy));
}

# get_zones_images($student,$page,$copy,$type) returns a list of the image
# filenames extracted from the scan corresponding to the given page,
# with the given zone type.

sub get_zones_images {
  my ($self,$student,$page,$copy,$type)=@_;
  return($self->sql_list($self->statement('zonesImages'),
			 $student,$page,$copy,$type));
}

# set_annotated($student,$page,$copy,$file,$timestamp) sets the name
# of the annotated image file, and the time when it wad made.

sub set_annotated {
  my ($self,$student,$page,$copy,$file,$timestamp)=@_;
  $timestamp=time() if(!$timestamp);
  $self->statement('setAnnotated')
    ->execute($file,$timestamp,$student,$page,$copy);
}

# outdate_annotated_page($student,$page,$copy) sets the corresponding
# annotated page as outdated (can be used for example if ticked data
# has changed for this page).

sub outdate_annotated_page {
  my ($self,$student,$page,$copy)=@_;
  $self->statement('setAnnotatedPageOutdated')
    ->execute($student,$page,$copy);
}

# outdate_annotated_copy($student,$copy) sets the corresponding
# annotated copy as outdated (can be used for example if ticked data
# has changed for this page).

sub outdate_annotated_copy {
  my ($self,$student,$copy)=@_;
  $self->statement('setAnnotatedCopyOutdated')
    ->execute($student,$copy);
}

# annotated_all_there($directory) returns TRUE if all pages with a
# automatic data capture have a JPEG annotated scan present in
# $directory.

sub annotated_all_there {
  my ($self,$directory)=@_;
  my @f=$self->sql_list($self->statement('getAnnotatedFiles'));
  my $ok=1;
  for(@f) {
    if($_) {
      $ok=0 if(!-f "$directory/$_");
    } else {
      $ok=0;
    }
  }
  return($ok);
}

# get_annotated_page($student,$page,$copy) returns the annotated image
# filename of a particular page.

sub get_annotated_page {
  my ($self,$student,$page,$copy)=@_;
  my $f=$self->sql_single($self->statement('getAnnotatedPage'),
			  $student,$page,$copy);
  return($f);
}

# annotated_count() returns the number of annotated sheets.

sub annotated_count {
  my ($self)=@_;
  return($self->sql_single($self->statement('annotatedCount')));
}

# get_scan_page($student,$page,$copy) returns the scan image
# filename of a particular page.

sub get_scan_page {
  my ($self,$student,$page,$copy)=@_;
  my $f=$self->sql_single($self->statement('getScanPage'),
			  $student,$page,$copy);
  return($f);
}

# max_copy_number returns the maximum copy number for all pages

sub max_copy_number {
  my ($self)=@_;
  return($self->sql_single($self->statement('maxCopy')) || 0);
}

# max_answer_number returns the maximum answer number for all questions

sub max_answer_number {
  my ($self)=@_;
  return($self->sql_single($self->statement('maxAnswer'),ZONE_BOX) || 0);
}

# new_page_copy($student,$page,$allocate) creates a new (unused) copy
# number for a given question page. If $allocate is positive, returns
# $allocate if it is unused for this page, or the next unused number.

sub new_page_copy {
  my ($self,$student,$page,$allocate)=@_;
  if($allocate) {
    my $a=$allocate;
    my @used=$self->sql_list($self->statement('pageCopies'),
			     $student,$page,$allocate);
    while(@used && $a==$used[0]) {
      $a++;
      shift @used;
    }
    return($a);
  } else {
    my $c=$self->sql_single($self->statement('pageLastCopy'),
			    $student,$page);
    if($c) {
      return($c+1);
    } else {
      return(1);
    }
  }
}

# set_manual(...,$type,$id_a,$id_b,$manual) sets the manual value for
# a particular zone.

sub set_manual {
  my ($self,$student,$page,$copy,$type,$id_a,$id_b,$manual)=@_;
  if(!$self->sql_single($self->statement('zone'),
			$student,$page,$copy,$type,$id_a,$id_b)) {
    $self->statement('NEWZone')->execute($student,$page,$copy,$type,$id_a,$id_b);
  }
  $self->statement('setManual')->execute($manual,$student,$page,$copy,$type,$id_a,$id_b);
}

# remove_manual($student,$page,$copy) deletes all manual data capture
# information for a particular page.

sub remove_manual {
  my ($self,$student,$page,$copy)=@_;
  $self->statement('setManualPage')->execute(-1,$student,$page,$copy);
  $self->statement('setManualPageZones')->execute(-1,$student,$page,$copy);
}

# counts returns a hash %r giving the %r{'complete'} number of
# complete sheets captured, and the %r{'incomplete'} number of student
# sheets for which one part has been captured (with manual or
# automated data capture), and one other part needs capturing.
# Moreover, $r{'missing'} is a reference to an array containing
# {'student'=>XXX,'page'=>XXX,'copy'=>XXX} for all missing pages.

sub counts {
  my ($self)=@_;
  my %r=('incomplete'=>0,'complete'=>0);
  my %dup=();
  $self->{'data'}->require_module('layout');
  $r{'missing'}=$self->dbh
    ->selectall_arrayref($self->statement('missingPages'),{Slice=>{}});
  for my $p (@{$r{'missing'}}) {
    my $k=$p->{'student'}."/".$p->{'copy'};
    if(!$dup{$k}) {
      $r{'incomplete'}++;
      $dup{$k}=1;
    }
  }
  $r{'complete'}=$self->n_copies()-$r{'incomplete'};
  return(%r);
}

# failed($filename,$timestamp) creates or updates a failed row for
# file $filename.

sub failed {
  my ($self,$filename,$timestamp)=@_;
  $timestamp=time if(! $timestamp);
  $self->statement('Failed')->execute($filename,$timestamp);
}

# no_capture_pages returns a reference to an array of elements
# [student,page,copy] for pages from the question paper that have not
# been captured (all with copy=0).

sub no_capture_pages {
  my ($self)=@_;
  return($self->dbh->selectall_arrayref($self->statement('noCapturePages')));
}

# no_capture_pages returns a reference to an array of elements
# [student,page,copy] for pages from the question paper that has boxes
# from the question but no boxes from the answer sheet (all with
# copy=0). The result is empty if not in separate answer sheet mode.

sub question_only_pages {
  my ($self)=@_;
  return($self->dbh->selectall_arrayref($self->statement('questionOnlyPages')));
}

# delete_page_data($student,$page,$copy) deletes all data concerning
# the given page (automatic and manual data capture) from the database.

sub delete_page_data {
  my ($self,$student,$page,$copy)=@_;
  $self->statement('deletePagePositions')->execute($student,$page,$copy);
  $self->statement('deletePageZones')->execute($student,$page,$copy);
  $self->statement('deletePage')->execute($student,$page,$copy);
}

# get_student_pages($student,$copy) returns an arrayref giving some
# information for all pages from sheet ($student,$copy). For example:
#
# [{'page'=>1,'annotated'=>'page-37-1.jpg','subjectpage'=>181},
#  {'page'=>2,'annotated'=>undef,'subjectpage'=>182},
# ]
#
# For each page, a hashref contains:
# * page for the page number,
# * annotated for the filename of the annotated jpg, if present,
# * subjectpage for the page number from complete subject PDF file

sub get_student_pages {
  my ($self,$student,$copy)=@_;
  $self->{'data'}->require_module('layout');
  return($self->dbh->selectall_arrayref($self->statement('pagesStudent'),
					{ Slice => {} },
					$student,$student,$copy));
}

# get_namefields() returns an arrayref giving, for each page with a
# namefield for which a capture has been made, the name of the
# namefield image if it exists.
#
# For example:
#
# [{student=>1,page=>3,copy=>1,image=>'name-1.jpg'},
#  {student=>1,page=>3,copy=>2,image=>undef},
# ]

sub get_namefields {
  my ($self)=@_;
  $self->{'data'}->require_module('layout');
  return($self->dbh->selectall_arrayref($self->statement('nameFields'),
					{ Slice => {} },ZONE_NAME));
}

# get_zones_bbox($student,$page,$copy,$zone_type) returns an arrayref
# giving, for each zone with type $zone_type (defaulting to ZONE_BOX)
# on scanned page ($student,$page,$copy), the bounding box on the scan.
#
# For example:
#
# [{question=>1,answer=>1,
#   xmin=>1646.92,xmax=>1684.57,ymin=>1608.12,ymax=>1645.38},
#  {question=>1,answer=>2,
#   xmin=>1591.68,xmax=>1629.33,ymin=>1517.17,ymax=>1554.43},
# ]

sub get_zones_bbox {
  my ($self,$student,$page,$copy,$zone_type)=@_;
  $zone_type=ZONE_BOX if(!defined($zone_type));
  return($self->dbh->selectall_arrayref($self->statement('zonesBBox'),
					{ Slice => {} },
					$student,$page,$copy,
					$zone_type,POSITION_BOX));
}

# get_zones_corners($student,$page,$copy,$zone_type) returns an
# arrayref giving, for each zone with type $zone_type (defaulting to
# ZONE_BOX) on scanned page ($student,$page,$copy), the corners on the
# scan. In the resulting array, corners are ordered.
#
# For example:
#
# [{zoneid=>156,question=>1,answer=>1,x=>1646.92,y=>1608.12,corner=>1},
#  {zoneid=>156,question=>1,answer=>1,x=>1667.12,y=>1610.43,corner=>2},
#  ...
# ]

sub get_zones_corners {
  my ($self,$student,$page,$copy,$zone_type)=@_;
  $zone_type=ZONE_BOX if(!defined($zone_type));
  return($self->dbh->selectall_arrayref($self->statement('zonesCorners'),
					{ Slice => {} },
					$student,$page,$copy,
					$zone_type,POSITION_BOX));
}

# n_photocopy() returns the number of captures made on a photocopy of
# the subject, that is made with mode 'Some sheets were photocopied'
# (these captures are identified by a positive 'copy' value).

sub n_photocopy {
  my ($self)=@_;
  return($self->sql_single($self->statement('photocopy')));
}

# clear_all() clears all the layout data tables.

sub clear_all {
    my ($self)=@_;
    for my $t (qw/page zone position failed/) {
	$self->sql_do("DELETE FROM ".$self->table($t));
    }
}

# get_image_paths($type) returns an arrayref with image paths of all
# zones of type $type, like
#
# [{zoneid=>153,image=>"zone-image-001.png"},
#  ...
# ]

sub get_image_paths {
  my ($self,$type)=@_;
  return($self->dbh->selectall_arrayref($self->statement('imagePaths'),
					{ Slice => {} },$type));
}

# set_image($zoneid,$imagedata) sets the imagedata (the image content
# as a blob) for zone $zoneid.

sub set_image {
  my ($self,$zoneid,$imagedata)=@_;
  my $sth=$self->statement('setImage');
  $sth->bind_param(1,$imagedata,SQL_BLOB);
  $sth->bind_param(2,$zoneid);
  $sth->execute();
}

# zooms_total_size_transaction() returns the sum of all zooms
# images stored in the database, in bytes.

sub zooms_total_size_transaction {
  my ($self)=@_;
  $self->begin_read_transaction('ztsz');
  my $s=$self->sql_single($self->statement('zoomsTotalSize'),ZONE_BOX);
  $self->end_transaction('ztsz');
  return($s);
}

# zooms_cleanup_transaction() deletes all zooms images from the
# database.

sub zooms_cleanup_transaction {
  my ($self)=@_;
  $self->begin_transaction('zcln');
  my $n=$self->statement('zoomsCleanup')->execute(ZONE_BOX);
  $self->end_transaction('zcln');
  $self->vacuum();
  return($n);
}

1;
