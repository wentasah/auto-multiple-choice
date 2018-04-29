# -*- perl -*-
#
# Copyright (C) 2011 Alexis Bienvenue <paamc@passoire.fr>
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

package AMC::State;

# This package helps storing state of important files after the user
# has printed exam sheets. All requested files are stored in a archive
# file, along with MD5 sum of each of these files and printing
# information. When printing again, if all the files are unchanged,
# only printing information is added. If some of the files has been
# modified since the last print, a new ARCHIVE file is created.

use AMC::Basic;

use Archive::Zip qw( :ERROR_CODES :CONSTANTS );
use Digest::MD5;
use XML::Simple;

sub new {
    my (%o)=(@_);

    my $self={'directory'=>'',
	      'archivefile'=>'', # absolute
	      'descfile'=>'state.xml',
          };

    for my $k (keys %o) {
        $self->{$k}=$o{$k} if(defined($self->{$k}));
    }

    $self->{'archive'}=Archive::Zip->new();
    $self->{'data'}={};

    $self->{'directory'} =~ s/\/$//;
    
    bless $self;
    
    return($self);
}

sub archive {
    my ($self)=@_;
    return($self->{'archive'});
}

# reads the ARCHIVE file. If no filename is given, looks for the last ARCHIVE
# file created in given directory.
sub read {
    my ($self,$archivefile)=@_;
    if(!$archivefile) {
	$archivefile=$self->{'archivefile'};
    }
    if(!$archivefile) {
	# look for the last one in the directory
	opendir(my $dh, $self->{'directory'})
	    or debug "Error opening directory $directory: $!";
	my @st = sort { $b cmp $a }
	grep { /^saved-[0-9-]+\.zip$/ && -f $self->{'directory'}."/$_" } readdir($dh);
	closedir $dh;
	
	if(@st) {
	    debug "Archive file found: $st[0]";
	    $archivefile=$self->{'directory'}."/".$st[0];
	} else {
	    debug "No ARCHIVE file";
	    $archivefile='';
	}
    }
    
    $self->{'data'}={'md5'=>{},'print'=>[]};
    
    if(-f $archivefile) {
	# opens the ARCHIVE file to look at the content
	debug "Reading ARCHIVE $archivefile";
	if( $self->{'archive'}->read($archivefile) != AZ_OK ) {
	    debug "Error reading $archivefile";
	} else {
	    # look for XML description file, with MD5 sums and
	    # printing information, and read it
	    my $xml = $self->{'archive'}->contents($self->{'descfile'});
	    if($xml) {
		$self->{'data'}=XMLin($xml,ForceArray => 1,ContentKey=>'content',KeyAttr =>['file']);
		$self->{'archivefile'}=$archivefile;
	    }
	}
    } else {
	debug "No file $archivefile";
	$self->{'archivefile'}='';
    }
}

# writes ARCHIVE file to disk, including XML file with MD5 sums and
# printing information
sub write {
    my ($self,$archivefile)=@_;
    if($archivefile) {
	$self->{'archivefile'}=$archivefile;
    } else {
	$archivefile=$self->{'archivefile'};
    }
    if(!$archivefile) {
	# if no filename is given, create it from date and time
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) =
	    localtime(time);
	
	$archivefile=$self->{'directory'}."/".
	    sprintf("saved-%d-%02d-%02d-%02d-%02d-%02d.zip",
		    $year+1900,$mon+1,$mday,$hour,$min,$sec);
	$self->{'archivefile'}=$archivefile;
    }

    # adds XML file to ARCHIVE
    my $xml=XMLout(
	$self->{'data'},
	ContentKey=>'content',KeyAttr =>['file'],
	RootName=>'state',
	);
    $self->{'archive'}->removeMember($self->{'descfile'});
    $self->{'archive'}->addString($xml,$self->{'descfile'});
    
    # writes to disk
    debug "Writing ARCHIVE to $archivefile ...";
    unless ( $self->{'archive'}->overwriteAs($archivefile) == AZ_OK ) {
	debug "Error writing to $archivefile";
    }
}

# adds printing information
sub add_print {
    my ($self,%oo)=@_;
    
    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) =
	localtime(time);
    
    push @{$self->{'data'}->{'print'}},{%oo,'date'=>sprintf("%d-%02d-%02d %02d:%02d:%02d",$year+1900,$mon+1,$mday,$hour,$min,$sec)};

}

# clears all MD5 sums from current state
sub clear_md5 {
     my ($self)=@_;
     $self->{'data'}->{'md5'}={};
}

# returns MD5 sum stocked in the ARCHIVE state for a given file
sub get_md5 {
    my ($self,$file)=@_;
    my $r=$self->{'data'}->{'md5'}->{$file}->{'content'};
    return(defined($r) ? $r : '');
}

# sets MD5 sum in current state
sub set_md5 {
    my ($self,$file,$sum)=@_;
    $self->{'data'}->{'md5'}->{$file}->{'content'}=$sum;
}

# check if given files are all unchanged
sub check_local_md5 {
    my ($self,@files)=@_;
    my $ok=1;
    
  FILE:for(@files) {
      if(!$self->check_md5($_)) {
	  $ok=0;
	  last FILE;
      }
  }
    return($ok);
}

# check if given file is unchanged. $localfile is the absolute path of
# the on-disk file, and $file is the name of the in-ARCHIVE file. Un empty
# $localfile is set to file $file in state directory (given when using
# new)
sub check_md5 {
    my ($self,$file,$localfile)=@_;

    if(!$localfile) {
	if($file =~ /^\//) {
	    $localfile=$file;
	    $file =~ s/.*\///;
	} else {
	    $localfile=$self->{'directory'}."/".$file;
	}
    }

    my $z=$self->get_md5($file);
    debug "Archive MD5: $z";

    if($z) {
	if(open(FILE, $localfile)) {
	    binmode(FILE);
	    my $md5_local=Digest::MD5->new->addfile(*FILE)->hexdigest;
	    close(FILE);

	    debug "Local MD5: $md5_local";

	    return($z eq $md5_local);
	} else {
	    debug "Open failed for $localfile";
	    return(0);
	}
    } else {
	debug "No ARCHIVE MD5 for $file";
	return(0);
    }
}

# adds MD5 sum of given on-disk file to current state
sub add_md5 {
    my ($self,$file,$localfile)=@_;

    if(!$localfile) {
	if($file =~ /^\//) {
	    $localfile=$file;
	    $file =~ s/.*\///;
	} else {
	    $localfile=$self->{'directory'}."/".$file;
	}
    }

    if(open(FILE, $localfile)) {
	binmode(FILE);
	my $md5_local=Digest::MD5->new->addfile(*FILE)->hexdigest;
	close(FILE);

	debug "Adding MD5: $md5_local";
	
	$self->set_md5($file,$md5_local);
    } else {
	debug "Open failed for $localfile";
    }
}

# adds file to ARCHIVE and sets corresponding MD5 sum in current state
sub add_file {
    my ($self,$file,$localfile)=@_;

    if(!$localfile) {
	if($file =~ /^\//) {
	    $localfile=$file;
	    $file =~ s/.*\///;
	} else {
	    $localfile=$self->{'directory'}."/".$file;
	}
    }

    if(-f $localfile) {
	debug "Adding $localfile [$file]...";
	if($self->{'archive'}->addFile($localfile,$file)) {
	    $self->add_md5($file,$localfile);
	    debug "OK.";
	    return(1);
	} else {
	    debug "Error adding $localfile : $!";
	    return(0);
	}
    } else {
	debug "ARCHIVE: No file $localfile";
	return(0);
    }
}

# adds a list of files all in the state sirectory
sub add_local_files {
    my ($self,@files)=@_;
    my $i=0;
    for(@files) { $i+=$self->add_file($_); }
    return($i);
}

1;
