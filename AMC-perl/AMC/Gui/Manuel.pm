#! /usr/bin/perl -w
#
# Copyright (C) 2008-2016 Alexis Bienvenue <paamc@passoire.fr>
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

package AMC::Gui::Manuel;

use Getopt::Long;
use Gtk2 -init;

use XML::Simple;
use File::Spec::Functions qw/splitpath catpath splitdir catdir catfile rel2abs tmpdir/;
use File::Temp qw/ tempfile tempdir /;

use AMC::Path;
use AMC::Basic;
use AMC::Gui::PageArea;
use AMC::Gui::WindowSize;
use AMC::Data;
use AMC::DataModule::capture qw/:zone/;

use constant {
    MDIAG_ID => 0,
    MDIAG_ID_BACK => 1,
    MDIAG_EQM => 2,
    MDIAG_DELTA => 3,
    MDIAG_EQM_BACK => 4,
    MDIAG_DELTA_BACK => 5,
    MDIAG_I => 6,
    MDIAG_STUDENT => 7,
    MDIAG_PAGE => 8,
    MDIAG_COPY => 9,
    MDIAG_WHY => 10,
};

use_gettext;

sub new {
    my %o=(@_);
    my $self={'data-dir'=>'',
	      'project-dir'=>'',
	      'sujet'=>'',
	      'etud'=>'',
	      'dpi'=>75,
	      'seuil'=>0.1,
	      'seuil_up'=>1.0,
	      'seuil_sens'=>8.0,
	      'seuil_eqm'=>3.0,
	      'fact'=>1/4,
	      'iid'=>0,
	      'displayed_iid'=>-1,
	      'global'=>0,
	      'en_quittant'=>'',
	      'encodage_interne'=>'UTF-8',
	      'image_type'=>'xpm',
	      'editable'=>1,
	      'multiple'=>0,
	      'onscan'=>'',
	      'size_monitor'=>'',
              'invalid_color_name'=>"#FFEF3B",
              'empty_color_name'=>"#78FFED",
	  };

    for (keys %o) {
	$self->{$_}=$o{$_} if(defined($self->{$_}));
    }

    bless $self;

    # recupere la liste des fichiers MEP des pages qui correspondent

    $self->{'data'}=AMC::Data->new($self->{'data-dir'});
    $self->{'layout'}=$self->{'data'}->module('layout');
    $self->{'capture'}=$self->{'data'}->module('capture');
    $self->{'scoring'}=$self->{'data'}->module('scoring');
    $self->{'scoring'}=$self->{'data'}->module('scoring');

    die "No PDF subject file" if(! $self->{'sujet'});
    die "Subject file ".$self->{'sujet'}." not found" if(! -f $self->{'sujet'});

    my $temp_loc=tmpdir();
    $self->{'temp-dir'} = tempdir( DIR=>$temp_loc,
				   CLEANUP => (!get_debug()) );

    $self->{'tmp-image'}=$self->{'temp-dir'}."/page";

    ## GUI

    my $glade_xml=__FILE__;
    $glade_xml =~ s/\.p[ml]$/.glade/i;

    $self->{'gui'}=Gtk2::Builder->new();
    $self->{'gui'}->set_translation_domain('auto-multiple-choice');
    $self->{'gui'}->add_from_file($glade_xml);

    for my $k (qw/general area navigation_h navigation_v goto goto_v diag_tree button_photocopy scan_view navigate/) {
	$self->{$k}=$self->{'gui'}->get_object($k);
    }

    $self->{'general'}->set_title(__"Page layout")
      if(!$self->{'editable'});

    $self->{'button_photocopy'}->hide() if(!$self->{'multiple'});

    if(!$self->{'editable'}) {
	$self->{'navigation_v'}->show();
    } else {
      $self->{'scan_view_model'}=cb_model(0,__("Original"),
					  1,__("Scan"));
      $self->{'scan_view'}->set_model($self->{'scan_view_model'});

# TRANSLATORS: This is one of the choices for pages navigation in manual data capture window. Here, navigation goes through all pages. Please keep this text very short (say less than 5 letters) so that the window is not too large
      $self->{navigate_model}=cb_model(0,__("all"),
 # TRANSLATORS: This is one of the choices for pages navigation in manual data capture window. Here, navigation goes through pages with some invalid answers. Please keep this text very short (say less than 5 letters) so that the window is not too large
                                       1,__("inv"),
# TRANSLATORS: This is one of the choices for pages navigation in manual data capture window. Here, navigation goes through pages with empty or invalid answers. Please keep this text very short (say less than 5 letters) so that the window is not too large
                                       2,__("i&e"));
      $self->{navigate}->set_model($self->{navigate_model});

      $self->{'navigation_h'}->show();
    }

    $self->{'cursor_watch'}=Gtk2::Gdk::Cursor->new('GDK_WATCH');

    Gtk2->main_iteration while ( Gtk2->events_pending );

    AMC::Gui::PageArea::add_feuille
	($self->{'area'},'',
	 'yfactor'=>2,
         invalid_color_name=>$self->{invalid_color_name},
         empty_color_name=>$self->{empty_color_name},
	 'editable'=>$self->{'editable'},
	 'marks'=>($self->{'editable'} ? '' : 'blue'));

    AMC::Gui::WindowSize::size_monitor
	($self->window,$self->{'size_monitor'})
	  if($self->{'size_monitor'});

    Gtk2->main_iteration while ( Gtk2->events_pending );

    ### modele DIAGNOSTIQUE SAISIE

    if($self->{'editable'}) {
	my ($renderer,$column);

	$renderer=Gtk2::CellRendererText->new;
	$column = Gtk2::TreeViewColumn->new_with_attributes (__"page",
							     $renderer,
							     text=> MDIAG_ID,
							     'background'=> MDIAG_ID_BACK);
	$column->set_sort_column_id(MDIAG_ID);
	$self->{'diag_tree'}->append_column ($column);

	$renderer=Gtk2::CellRendererText->new;
	$column = Gtk2::TreeViewColumn->new_with_attributes (__"MSE",
							     $renderer,
							     'text'=> MDIAG_EQM,
							     'background'=> MDIAG_EQM_BACK);
	$column->set_sort_column_id(MDIAG_EQM);
	$self->{'diag_tree'}->append_column ($column);

	$renderer=Gtk2::CellRendererText->new;
	$column = Gtk2::TreeViewColumn->new_with_attributes (__"sensitivity",
							     $renderer,
							     'text'=> MDIAG_DELTA,
							     'background'=> MDIAG_DELTA_BACK);
	$column->set_sort_column_id(MDIAG_DELTA);
	$self->{'diag_tree'}->append_column ($column);
    }

    $self->{'general'}->window()->set_cursor($self->{'cursor_watch'});
    Gtk2->main_iteration while ( Gtk2->events_pending );

    $self->maj_list_all;

    $self->{'general'}->window()->set_cursor(undef);

    $self->{'gui'}->connect_signals(undef,$self);

    $self->{'area'}->signal_connect('expose_event'=>\&AMC::Gui::Manuel::expose_area);

    $self->select_page(0);

    return($self);
}

sub new_diagstore {
  my ($self)=@_;
  $diag_store = Gtk2::ListStore->new ('Glib::String',
				      'Glib::String',
				      'Glib::String',
				      'Glib::String',
				      'Glib::String',
				      'Glib::String',
				      'Glib::String',
				      'Glib::String',
				      'Glib::String',
				      'Glib::String',
				      'Glib::String',
				     );
  $diag_store->set_sort_func(MDIAG_EQM,\&sort_num,MDIAG_EQM);
  $diag_store->set_sort_func(MDIAG_DELTA,\&sort_num,MDIAG_DELTA);
  $diag_store->set_sort_func(MDIAG_ID,\&sort_from_columns,
			     [{'type'=>'n','col'=>MDIAG_STUDENT},
			      {'type'=>'n','col'=>MDIAG_COPY},
			      {'type'=>'n','col'=>MDIAG_PAGE},
			     ]);
  $self->{'diag_store'}=$diag_store;
  return($diag_store);
}

sub sort_diagstore {
  my ($self)=@_;
  $self->{'diag_store'}->set_sort_column_id(MDIAG_ID,GTK_SORT_ASCENDING);
}

sub show_diagstore {
  my ($self)=@_;
  $self->{'diag_tree'}->set_model($self->{'diag_store'});
}

sub window {
  my ($self)=@_;
  return($self->{'general'});
}

###

sub scan_view_change {
  my ($self)=@_;
  $self->{'onscan'}=$self->{'scan_view'}->get_active();
  $self->ecrit();
  $self->{'area'}->{'onscan'}=$self->{'onscan'};
  $self->charge_i();
}

sub current_iter {
  my ($self)=@_;
  my @sel=$self->{'diag_tree'}->get_selection->get_selected_rows();
  if(@sel) {
    return( $self->{'diag_store'}->get_iter($sel[0]) );
  } else {
    return();
  }
}

sub iter_to_spc {
  my ($self,$iter)=@_;
  if($iter) {
    return($self->{'diag_store'}->get($iter,
				      MDIAG_STUDENT,MDIAG_PAGE,MDIAG_COPY));
  } else {
    return();
  }
}

sub current_spc {
  my ($self)=@_;
  return($self->iter_to_spc($self->current_iter));
}

sub displayed_iter {
  my ($self)=@_;
  if(defined($self->{'displayed_iid'}) &&
     $self->{'displayed_iid'}>=0) {
    return(model_id_to_iter($self->{'diag_store'},MDIAG_I,$self->{'displayed_iid'}));
  }
}

sub displayed_spc {
  my ($self)=@_;
  return($self->iter_to_spc($self->displayed_iter));
}

sub page_selected {
  my ($self)=@_;
  my $current=$self->current_iter;
  if($current) {
    $self->ecrit();
    $self->{'iid'}=$self->{'diag_store'}->get($current,MDIAG_I);
    $self->charge_i();
  }
  return TRUE;
}

sub select_page_from_iter {
  my ($self,$iter)=@_;
  $self->{'diag_tree'}->set_cursor($self->{'diag_store'}->get_path($iter))
    if($iter);
}

sub select_page {
  my ($self,$iid)=@_;
  $self->select_page_from_iter(model_id_to_iter($self->{'diag_store'},MDIAG_I,$iid));
}

sub maj_list_all {
  my ($self,$select_spc)=@_;

  $self->{'capture'}->begin_read_transaction;
  my $summary=$self->{'capture'}
    ->summaries('darkness_threshold'=>$self->{'seuil'},
		'darkness_threshold_up'=>$self->{'seuil_up'},
		'sensitivity_threshold'=>$self->{'seuil_sens'},
		'mse_threshold'=>$self->{'seuil_eqm'},
                'why'=>1);
  my $capture_free=[];
  push @$capture_free,@{$self->{'capture'}->question_only_pages} if(!$self->{editable});
  push @$capture_free,@{$self->{'capture'}->no_capture_pages};
  $self->{'capture'}->end_transaction;

  $diag_store = $self->new_diagstore;

  debug "Adding ".(1+$#$summary)." summaries to list...";
  my $select_iid=-1;
  my $i=0;
  for my $p (@$summary) {
    $diag_store
      ->insert_with_values($i,
	    MDIAG_I,$i,
	    MDIAG_ID,pageids_string($p->{'student'},$p->{'page'},$p->{'copy'}),
	    MDIAG_STUDENT,$p->{'student'},
	    MDIAG_PAGE,$p->{'page'},
	    MDIAG_COPY,$p->{'copy'},
	    MDIAG_ID_BACK,$p->{'color'},
	    MDIAG_EQM,$p->{'mse_string'},
	    MDIAG_EQM_BACK,$p->{'mse_color'},
	    MDIAG_DELTA,$p->{'sensitivity_string'},
            MDIAG_DELTA_BACK,$p->{'sensitivity_color'},
            MDIAG_WHY,$p->{why},
           );
    $select_iid=$i if($select_spc &&
		      $select_spc->[0]==$p->{'student'} &&
		      $select_spc->[1]==$p->{'page'} &&
		      $select_spc->[2]==$p->{'copy'});
    $i++;
  }
  debug "Adding ".(1+$#$capture_free)." free captures...";
  for my $p (@$capture_free) {
    $diag_store
      ->insert_with_values($i,
	    MDIAG_I,$i,
	    MDIAG_ID,pageids_string(@$p),
	    MDIAG_STUDENT,$p->[0],
	    MDIAG_PAGE,$p->[1],
	    MDIAG_COPY,$p->[2],
	    MDIAG_ID_BACK,undef,
	    MDIAG_EQM,'',
	    MDIAG_EQM_BACK,undef,
	    MDIAG_DELTA,'',
            MDIAG_DELTA_BACK,undef,
            MDIAG_WHY,'',
	   );
    $select_iid=$i if($select_spc &&
		      $select_spc->[0]==$p->[0] &&
		      $select_spc->[1]==$p->[1] &&
		      $select_spc->[2]==$p->[2]);
    $i++;
  }
  debug "Sorting...";
  $self->sort_diagstore;
  debug "List complete.";
  $self->show_diagstore;

  $self->select_page($select_iid) if($select_iid);
}

sub maj_list_i {
    my ($self)=@_;
    return if(!$self->{'editable'});

    my $iter=$self->displayed_iter;
    return if(!$iter);
    my @spc=$self->iter_to_spc($iter);
    return if(!@spc);

    debug "List update for SPC=".join(',',@spc);

    $self->{'capture'}->begin_read_transaction('lUPD');
    my %ps=$self->{'capture'}
      ->page_summary(@spc,
		     'mse_threshold'=>$self->{'seuil_eqm'},
		     'darkness_threshold'=>$self->{'seuil'},
		     'darkness_threshold_up'=>$self->{'seuil_up'},
		     'sensitivity_threshold'=>$self->{'seuil_sens'},
		    );
    $self->{'capture'}->end_transaction('lUPD');
    for my $k (keys %ps) {
      debug(" - $k = ".(defined($ps{$k}) ? $ps{$k} : '<undef>'));
    }

    $self->{'diag_store'}->set($iter,
			       MDIAG_ID_BACK,$ps{'color'},
			       MDIAG_EQM,$ps{'mse_string'},
			       MDIAG_EQM_BACK,$ps{'mse_color'},
			       MDIAG_DELTA,$ps{'sensitivity_string'},
			       MDIAG_DELTA_BACK,$ps{'sensitivity_color'},
			       );
}

sub choix {
    my ($self,$widget,$event)=(@_);
    $widget->choix($event);
}

sub expose_area {
    my ($widget,$evenement,@donnees)=@_;

    $widget->expose_drawing($evenement,@donnees);
}

sub une_modif {
    my ($self)=@_;
    $self->{'area'}->modif();
}

sub page_id {
    my $i=shift;
    return("+".join('/',map { $i->{$_} } (qw/student page checksum/))."+");
}

sub charge_i {
    my ($self)=@_;

    $self->{'layinfo'}={};

    my $current_iter=$self->current_iter;
    my @spc=$self->iter_to_spc($current_iter);

    if(!@spc) {
      $self->{'area'}->set_image('NONE');
      $self->{'displayed_iid'}=-1;
      return();
    }

    $self->{'displayed_iid'}=$self->{'diag_store'}->get($current_iter,MDIAG_I);

    debug "ID ".pageids_string(@spc);

    $self->{'layout'}->begin_read_transaction;

    debug "page_info";

    my @ep=@spc[0,1];

    $self->{'info'}=$self->{'layout'}->page_info(@ep);
    my $page=$self->{'info'}->{'subjectpage'};

    my $scan_file=proj2abs({'%PROJET'=>$self->{'project-dir'}},
			   $self->{'capture'}->get_scan_page(@spc));

    debug "PAGE $page";

    ################################
    # fabrication du xpm
    ################################

    my $display_image='';
    my $tmp_image='';
    my $tmp_ppm='';

    debug "Making XPM";

    if($self->{'onscan'} && -f $scan_file) {

      $display_image=$scan_file;

    } else {

      $self->{'general'}->window()->set_cursor($self->{'cursor_watch'});
      Gtk2->main_iteration while ( Gtk2->events_pending );

      system("pdftoppm","-f",$page,"-l",$page,
	     "-r",$self->{'dpi'},
	     $self->{'sujet'},
	     $self->{'temp-dir'}."/page");
      # recherche de ce qui a ete fabrique...
      opendir(TDIR,$self->{'temp-dir'}) || die "can't opendir $self->{'temp-dir'} : $!";
      my @candidats = grep { /^page-.*\.ppm$/ && -f $self->{'temp-dir'}."/$_" } readdir(TDIR);
      closedir TDIR;
      debug "Candidates : ".join(' ',@candidats);
      $tmp_ppm=$self->{'temp-dir'}."/".$candidats[0];
      $tmp_image=$tmp_ppm;

      if($self->{'image_type'} && $self->{'image_type'} ne 'ppm') {
	$tmp_image=$self->{'tmp-image'}.".".$self->{'image_type'};
	debug "ppmto".$self->{'image_type'}." : $tmp_ppm -> $tmp_image";
	system("ppmto".$self->{'image_type'}." \"$tmp_ppm\" > \"$tmp_image\"");
      }

      $display_image=$tmp_image;

    }

    ################################
    # synchro variables
    ################################

    if($spc[2]==0 && $self->{'multiple'} && $self->{'editable'}) {
      $self->{'layinfo'}->{'block_message'}=sprintf(__"This is a template exam that you cannot edit. To create a new exam from this one to be edited, use the '%s' button.",__"Add photocopy");
    } else {

      debug "Getting layout info";

      for (qw/box questionbox namefield digit scorezone/) { $self->{'layinfo'}->{$_}=[]; }

      if($self->{'onscan'}) {
	my %ci=();
	for my $c (@{$self->{'capture'}->get_zones_corners(@spc)}) {
	  %ci=(%$c,'xy'=>[],
	       'xmin'=>$c->{'x'},'xmax'=>$c->{'x'},
	       'ymin'=>$c->{'y'},'ymax'=>$c->{'y'},
	      ) if($c->{'corner'}==1);
	  push @{$ci{xy}},$c->{'x'},$c->{'y'};
	  $ci{'xmax'}=$c->{'x'} if($c->{'x'}>$ci{'xmax'});
	  $ci{'ymax'}=$c->{'y'} if($c->{'y'}>$ci{'ymax'});
	  $ci{'xmin'}=$c->{'x'} if($c->{'x'}<$ci{'xmin'});
	  $ci{'ymin'}=$c->{'y'} if($c->{'y'}<$ci{'ymin'});
	  push @{$self->{'layinfo'}->{'box'}},{%ci} if($c->{'corner'}==4);
	}
      } else {
	my $c;
	my $sth;

	for my $type (qw/box questionbox scorezone digit namefield/) {
	  for my $c ($self->{'layout'}->type_info($type,@ep)) {
	    push @{$self->{'layinfo'}->{$type}},{%$c};
	  }
	}

	$self->{'layinfo'}->{'page'}=$self->{'layout'}->page_info(@ep);
      }

      if($self->{editable}) {
	# gets scoring results to highlight empty and invalid answers

	for my $a (@{$self->{layinfo}->{box}}) {
	  $a->{scoring}=$self->{scoring}->question_result(@spc[0,2],$a->{question});
	}

	# mise a jour des cases suivant saisies deja presentes

	for my $i (@{$self->{'layinfo'}->{'box'}}) {
	  my $id=$i->{'question'}."."
	    .$i->{'answer'};
	  my $t=$self->{'capture'}
	    ->ticked(@spc[0,2],$i->{'question'},$i->{'answer'},
		     $self->{'seuil'},$self->{'seuil_up'});
	  $t='' if(!defined($t));
	  debug "Q=$id R=$t";
	  $i->{'id'}=[@spc];
	  $i->{'ticked'}=$t;
	}
      }
    }

    $self->{'layout'}->end_transaction;

    # utilisation

    $self->{'area'}->set_image($display_image,
			       $self->{'layinfo'});

    unlink($tmp_ppm) if($tmp_ppm);
    unlink($tmp_image) if($tmp_image && ($tmp_ppm ne $tmp_image) && !get_debug());

    # fin du traitement...

    $self->{'general'}->window()->set_cursor(undef);
}

sub ecrit {
    my ($self)=(@_);

    return if(!$self->{'editable'});

    my @spc=$self->displayed_spc;
    return if(!@spc);

    if($self->{'area'}->modifs()) {
      debug "Saving ".pageids_string(@spc);

      $self->{'capture'}->begin_transaction('manw');
      $self->{'capture'}->outdate_annotated_page(@spc);

      $self->{'capture'}->set_page_manual(@spc,time());

      for my $i (@{$self->{'layinfo'}->{'box'}}) {
	$self->{'capture'}
	  ->set_manual(@{$i->{'id'}},
		       ZONE_BOX,$i->{'question'},$i->{'answer'},
		       ($i->{'ticked'} ? 1 : 0));
      }

      $self->{'capture'}->end_transaction('manw');

      $self->synchronise();
    }
}

sub synchronise {
    my ($self)=(@_);

    $self->{'area'}->sync();

    $self->maj_list_i;
  }

sub navigate_ok {
  my ($self,$nav_mode,$path)=@_;
  return(1) if($nav_mode==0);
  my $iter=$self->{diag_store}->get_iter($path);
  my $why=$self->{diag_store}->get($iter,MDIAG_WHY);
  return(0) if($nav_mode==1 && $why !~ /E/);
  return(0) if($nav_mode==2 && $why !~ /[EV]/);
  return(1);
}

sub passe_precedent {
  my ($self)=@_;
  my $nav=$self->{navigate}->get_active();
  my ($path)=$self->{'diag_tree'}->get_cursor();
  if($path) {
    my $ok;
    do {
      $ok=$path->prev();
    } while($ok && !$self->navigate_ok($nav,$path));
    $self->{'diag_tree'}->set_cursor($path) if($ok);
  }
}

sub passe_suivant {
  my ($self)=@_;
  my $nav=$self->{navigate}->get_active();
  my ($path)=$self->{'diag_tree'}->get_cursor();
  my $n=$self->{diag_store}->iter_n_children(undef);
  if($path) {
    do {
      $path->next();
    } while($path->to_string<$n && !$self->navigate_ok($nav,$path));
    $self->{'diag_tree'}->set_cursor($path) if($path->to_string<$n);
  }
}

sub annule {
    my ($self)=(@_);

    $self->charge_i();
}

sub efface_saisie {
    my ($self)=(@_);

    my @spc=$self->displayed_spc;
    return if(!@spc);

    debug "Ereasing manual data for SPC=".join(',',@spc);

    $self->{'capture'}->begin_transaction('manx');
    $self->{'capture'}->outdate_annotated_page(@spc);
    $self->{'capture'}->remove_manual(@spc);
    $self->{'capture'}->end_transaction('manx');

    $self->synchronise();
    $self->charge_i();
}

sub duplique_saisie {
   my ($self)=@_;

   my ($student,$page,$copy)=$self->displayed_spc;
   return if(!defined($student));

   $self->{'capture'}->begin_transaction;
   $copy=$self->{'capture'}->new_page_copy($student,$page);
   annotate_source_change($self->{'capture'});
   $self->{'capture'}->set_page_manual($student,$page,$copy,-1);
   $self->{'capture'}->end_transaction;

   $self->maj_list_all([$student,$page,$copy]);
}

sub ok_quitter {
    my ($self)=(@_);

    $self->ecrit();
    $self->quitter();
}

sub quitter {
    my ($self)=(@_);
    if($self->{'global'}) {
	Gtk2->main_quit;
    } else {
	$self->{'general'}->destroy;
	if($self->{'en_quittant'}) {
	  &{$self->{'en_quittant'}}();
	}
    }
}

sub goto_activate_cb {
    my ($self)=(@_);

    my $dest=$self->{($self->{'editable'} ? 'goto' : 'goto_v')}->get_text();
    my $iid=-1;

    $self->ecrit();

    debug "Go to $dest";

    # recherche d'un ID correspondant
    $dest.='/' if($dest !~ m:/:);

    $self->select_page_from_iter(model_id_to_iter($self->{'diag_store'},
						  're:'.MDIAG_ID,$dest));
}

1;

__END__
