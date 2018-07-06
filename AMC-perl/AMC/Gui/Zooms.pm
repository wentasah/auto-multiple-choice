#! /usr/bin/perl
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

package AMC::Gui::Zooms;

use File::Spec::Functions qw/tmpdir/;

use AMC::Basic;
use AMC::DataModule::capture ':zone';
use AMC::Gui::Prefs;

use Gtk3 -init;

use POSIX qw(ceil);

use constant {
  ID_AMC_BOX => 100,

  ZOOMS_EDIT_DND => 0,
  ZOOMS_EDIT_CLICK => 1,
};

my $col_manuel = Gtk3::Gdk::RGBA::parse("#DFE085");
my $col_modif = Gtk3::Gdk::RGBA::parse("#E2B8B2");

sub new {
    my %o=(@_);

    my $self={
	'n_cols'=>4,
	'factor'=>0.75,
	'seuil'=>0.15,
	'seuil_up'=>1.0,
	'prop_min'=>0.30,
	'prop_max'=>0.60,
	'global'=>0,
	'zooms_dir'=>"",
	'page_id'=>[],
	'data'=>'',
	'data-dir'=>'',
	'size-prefs'=>'',
	'encodage_interne'=>'UTF-8',
	'list_view'=>'',
	'zooms_edit_mode'=>ZOOMS_EDIT_DND,
	'global_options'=>'',
	'prefs'=>'',
    };

    for (keys %o) {
	$self->{$_}=$o{$_} if(defined($self->{$_}));
    }

    if($self->{global_options}) {
      $self->{zooms_edit_mode}=$self->{global_options}->get('zooms_edit_mode');
    }

    $self->{prefs}->store_register(
# TRANSLATORS: One of the ways to change a box's ticked state in the zooms window
				   'zooms_edit_mode'=>cb_model(ZOOMS_EDIT_DND,__"drag and drop",
# TRANSLATORS: One of the ways to change a box's ticked state in the zooms window
							       ZOOMS_EDIT_CLICK,__"click"),
				  );

    $self->{'ids'}=[];
    $self->{'pb_src'}={};
    $self->{'real_src'}={};
    $self->{'pb'}={};
    $self->{'image'}={};
    $self->{'label'}={};
    $self->{'n_ligs'}={};
    $self->{'position'}={};
    $self->{'eb'}={};
    $self->{'conforme'}=1;

    bless $self;

    if($self->{'data'}) {
	$self->{'_capture'}=$self->{'data'};
    } else {
	debug "Connecting to database...";
	$self->{'_capture'}=AMC::Data->new($self->{'data-dir'})
	  ->module('capture');
	debug "ok";
    }

    if($self->{'size-prefs'}) {
	$self->{'factor'}=$self->{'size-prefs'}->get('zoom_window_factor')
	if($self->{'size-prefs'}->get('zoom_window_factor'));
    }
    $self->{'factor'}=0.1 if($self->{'factor'}<0.1);
    $self->{'factor'}=5 if($self->{'factor'}>5);

    my $glade_xml=__FILE__;
    $glade_xml =~ s/\.p[ml]$/.glade/i;

    $self->{'gui'}=Gtk3::Builder->new();
    $self->{'gui'}->set_translation_domain('auto-multiple-choice');
    $self->{'gui'}->add_from_file($glade_xml);

    for(qw/main_window zooms_table_0 zooms_table_1 decoupage scrolled_0 scrolled_1 label_0 label_1 event_0 event_1 button_apply button_close info button_previous button_next /) {
	$self->{$_}=$self->{'gui'}->get_object($_);
    }

    $self->{prefs}->transmet_pref($self->{'gui'},
                                  prefix=>'zooms',hash=>$self);

    $self->{'label_0'}->set_markup('<b>'.$self->{'label_0'}->get_text.'</b>');
    $self->{'label_1'}->set_markup('<b>'.$self->{'label_1'}->get_text.'</b>');
    $self->{'info'}->set_markup('<b>'.sprintf(__("Boxes zooms for page %s"),
					      pageids_string(@{$self->{'page_id'}})).'</b>');

    for(0,1) {
      $self->{'event_'.$_}->drag_dest_set('all',
                                          [Gtk3::TargetEntry->new('STRING',0,ID_AMC_BOX)],
                                          [GDK_ACTION_MOVE],
                                         );
	$self->{'event_'.$_}->signal_connect(
	    'drag-data-received' => \&target_drag_data_received,[$self,$_]);
    }

    $self->{'gui'}->connect_signals(undef,$self);

    if($self->{'size-prefs'}) {
	my @s=$self->{'main_window'}->get_size();
	$s[1]=$self->{'size-prefs'}->get('zoom_window_height');
	$s[1]=200 if($s[1]<200);
	$self->{'main_window'}->resize(@s);
    }

    $self->load_boxes();

    return($self);
}

sub edit_mode_update {
  my ($self)=@_;

  $self->{prefs}->reprend_pref(prefix=>'zooms',hash=>$self);
  if($self->{global_options}) {
    $self->{global_options}->set('zooms_edit_mode',$self->{zooms_edit_mode});
  }
}

sub dnd_mode { # drag and drop
  my ($self)=@_;

  return($self->{zooms_edit_mode} == ZOOMS_EDIT_DND);
}

sub clear_boxes {
    my ($self)=@_;

    for(0,1) { $self->vide($_); }
    $self->{'ids'}=[];
    $self->{'pb_src'}={};
    $self->{'real_src'}={};
    $self->{'pb'}={};
    $self->{'image'}={};
    $self->{'label'}={};
    $self->{'n_ligs'}={};
    $self->{'position'}={};
    $self->{'eb'}={};
    $self->{'eff_pos'}={};
    $self->{'auto_pos'}={};
    $self->{'conforme'}=1;
    $self->{'button_apply'}->hide();
}

sub scrolled_update {
  my ($self)=@_;
  for my $cat (0,1) {
    $self->{'scrolled_'.$cat}->set_policy('never','automatic');
  }
}

sub get_page_info {
  my ($self)=@_;

  $self->{'page_info'}
    =$self->{'_capture'}->get_page(@{$self->{'page_id'}});
}

sub affect_box {
  my ($self,$z)=@_;

  my $id=$z->{'id_a'}.'-'.$z->{'id_b'};
  my $auto_pos=($z->{'black'} >= $z->{'total'}*$self->{'seuil'} &&
		$z->{'black'} <= $z->{'total'}*$self->{'seuil_up'} ? 1 : 0);
  my $eff_pos=($self->{'page_info'}->{'timestamp_manual'}
	       && $z->{'manual'}>=0 ? $z->{'manual'} :
	       $auto_pos);
  $self->{'eff_pos'}->{$id}=$eff_pos;
  $self->{'auto_pos'}->{$id}=$auto_pos;
}

sub load_positions {
  my ($self)=@_;
  $self->{'_capture'}->begin_read_transaction;

  $self->get_page_info();

  my $sth=$self->{'_capture'}->statement('pageZonesD');
  $sth->execute(@{$self->{'page_id'}},ZONE_BOX);
  while (my $z = $sth->fetchrow_hashref) {
    $self->affect_box($z);
  }

  $self->{'_capture'}->end_transaction;
}

sub safe_pixbuf {
  my ($self,$image)=@_;
  my $p='';
  if($image) {
    # first try with a PixbufLoader

    my $pxl=Gtk3::Gdk::PixbufLoader->new;
    $pxl->write([unpack 'C*', $image]);
    $pxl->close();
    $p=$pxl->get_pixbuf();
    return($p,1) if($p);

    # Then try using Graphics::Magick to convert to XPM
    my $i=magick_perl_module()->new();
    $i->BlobToImage($image);
    if( ! $i[0]) {
      # Try using temporary file to do the same
      my $tf=tmpdir()."/AMC-tempzoom";
      open TZ,">$tf";binmode TZ;print TZ $image;close TZ;
      $i->Read($tf);
    }
    my @b=$i->ImageToBlob("magick"=>'xpm');
    if($b[0]) {
      $b[0] =~ s:/\*.*\*/::g;
      $b[0] =~ s:static char.*::;
      $b[0] =~ s:};::;
      my @xpm=grep { $_ ne '' }
	map { s/^\"//;s/\",?$//;$_; }
	  split(/\n+/,$b[0]);
      eval { $p=Gtk3::Gdk::Pixbuf->new_from_xpm_data(@xpm); };
      return($p,1) if($p);
    }
  }
  # No success at all: replace the zoom image by a question mark
  my $g=$self->{'main_window'};
  my $layout=$g->create_pango_layout("?");
  my $colormap =$g->get_colormap;
  $layout->set_font_description(Pango::FontDescription->from_string("128"));
  my ($text_x,$text_y)=$layout->get_pixel_size();
  my $pixmap=Gtk3::Gdk::Pixmap->new(undef,$text_x,$text_y,$colormap->get_visual->depth);
  $pixmap->set_colormap($colormap);
  $pixmap->draw_rectangle($g->style->bg_gc(GTK_STATE_NORMAL),TRUE,0,0,$text_x,$text_y);
  $pixmap->draw_layout($g->style->fg_gc(GTK_STATE_NORMAL),0,0,$layout);
  $p=Gtk3::Gdk::Pixbuf->get_from_drawable($pixmap, $colormap,0,0,0,0, $text_x, $text_y);
  return($p,0);
}

sub buttons_availability {
  my ($self)=@_;
  if($self->{'conforme'}) {
    $self->{'button_apply'}->hide();
    $self->{'button_previous'}->set_sensitive($self->list_prev ? 1 : 0);
    $self->{'button_next'}->set_sensitive($self->list_next ? 1 : 0);
  } else {
    $self->{'button_apply'}->show();
    $self->{'button_previous'}->set_sensitive(0);
    $self->{'button_next'}->set_sensitive(0);
  }
}

sub load_boxes {
    my ($self)=@_;

    my @ids;

    $self->{'_capture'}->begin_read_transaction;

    $self->get_page_info();

    my $sth=$self->{'_capture'}->statement('pageZonesDI');
    $sth->execute(@{$self->{'page_id'}},ZONE_BOX);
    while (my $z = $sth->fetchrow_hashref) {

      $self->affect_box($z);

      my $id=$z->{'id_a'}.'-'.$z->{'id_b'};

      if($z->{imagedata}) {

	($self->{'pb_src'}->{$id},$self->{'real_src'}->{$id})
	  =$self->safe_pixbuf($z->{imagedata});

	$self->{'image'}->{$id}=Gtk3::Image->new();

	$self->{'label'}->{$id}=
	  Gtk3::Label->new(sprintf("%.3f",
				   $self->{'_capture'}
				   ->zone_darkness($z->{'zoneid'})));
	$self->{'label'}->{$id}->set_justify(GTK_JUSTIFY_LEFT);

	my $hb=Gtk3::HBox->new();
	$self->{'eb'}->{$id}=Gtk3::EventBox->new();
	$self->{'eb'}->{$id}->add($hb);

	$hb->add($self->{'image'}->{$id});
	$hb->add($self->{'label'}->{$id});

	$self->{'eb'}->{$id}->drag_source_set(GDK_BUTTON1_MASK,
					      [Gtk3::TargetEntry->new('STRING',0,ID_AMC_BOX)],
                                              [GDK_ACTION_MOVE],
                                             );
	$self->{'eb'}->{$id}
	  ->signal_connect('drag-data-get' => \&source_drag_data_get,
			   $id );
	$self->{'eb'}->{$id}
	  ->signal_connect('drag-begin'=>sub {
			     if($self->dnd_mode) {
			       $self->{'eb'}->{$id}
				 ->drag_source_set_icon_pixbuf($self->{'image'}->{$id}->get_pixbuf);
			     }
			   });

	$self->{'eb'}->{$id}
	  ->signal_connect('button_press_event'=>sub {
			     $self->{'button_event'}=$id; });
	$self->{'eb'}->{$id}
	  ->signal_connect('leave_notify_event'=>sub {
			     $self->{'button_event'}=''; });
	$self->{'eb'}->{$id}
	  ->signal_connect('button_release_event'=>sub {
			     my ($w,$event)=@_;
			     $self->click_action($id,$event); });

	$self->{'position'}->{$id}=$self->{'eff_pos'}->{$id};

	push @ids,$id;
      } else {
	debug_and_stderr "No zoom image: $id";
      }
    }

    $self->{'_capture'}->end_transaction;

    $self->{'ids'}=[@ids];

    $self->{'conforme'}=1;

    $self->remplit(0);
    $self->remplit(1);
    $self->zoom_it();

    $self->{'main_window'}->show_all();
    $self->{'button_apply'}->hide();

    Gtk3::main_iteration while ( Gtk3::events_pending );

    $self->ajuste_sep();

    my $va=$self->{'scrolled_0'}->get_vadjustment();
    $va->clamp_page($va->get_upper(),$va->get_upper());
    $va=$self->{'scrolled_1'}->get_vadjustment();
    $va->clamp_page($va->get_lower(),$va->get_lower());

    $self->buttons_availability;
}

sub refill {
    my ($self)=@_;
    $self->{'conforme'}=1;
    for(0,1) { $self->vide($_); }
    for(0,1) { $self->remplit($_); }
    $self->buttons_availability;
    $self->scrolled_update;
}

sub page {
    my ($self,$id,$zd,$forget_it)=@_;
    if(!$self->{'conforme'}) {
	return() if($forget_it);

	my $dialog = Gtk3::MessageDialog
	    ->new($self->{'main_window'},
                  'destroy-with-parent',
                  'warning','yes-no',
                  __("You moved some boxes to correct automatic data query, but this work is not saved yet.")." ".__("Do you want to save these modifications before looking at another page?")
	    );
	my $reponse=$dialog->run;
	$dialog->destroy;
	if($reponse eq 'yes') {
	    $self->apply;
	}
    }
    $self->clear_boxes;
    $self->{'page_id'}=$id;
    $self->{'zooms_dir'}=$zd;
    $self->{'info'}->set_markup('<b>'.sprintf(__("Boxes zooms for page %s"),
					      pageids_string(@{$self->{'page_id'}})).'</b>');
    $self->load_boxes;
}

sub click_action {
  my ($self,$id,$event)=@_;
  if((!$self->dnd_mode) && ($self->{'button_event'} eq $id)) {
    if($event->button==1) {
      $self->toggle($id);
    } elsif($event->button==3) {
      my $cat=$self->{'position'}->{$id};
      my @toggle_ids=();
      my $t=$cat;
      for my $i (@{$self->{'ids'}}) {
	$t=1 if($cat==0 && $id eq $i);
	if($t && $self->{'position'}->{$i} == $cat) {
	  push @toggle_ids,$i;
	}
	$t=0 if($cat==1 && $id eq $i);
      }
      for my $i (@toggle_ids) {
	$self->{'position'}->{$i}=1-$cat;
      }
      $self->refill;
    }
  }
}

sub toggle {
  my ($self,$id)=@_;
  $self->{'position'}->{$id}=1-$self->{'position'}->{$id};
  $self->refill;
}

sub source_drag_data_get {
    my ($widget, $context, $data, $info, $time,$string) = @_;
    $data->set_text($string,-1);
}

sub target_drag_data_received {
    my ($widget, $context, $x, $y, $data, $info, $time,$args) = @_;
    my ($self,$cat)=@$args;
    my $id=$data->get_text();
    if($self->dnd_mode()) {
      debug "Page ".pageids_string(@{$self->{'page_id'}})
	.": move $id to category $cat\n";
      if($self->{'position'}->{$id} != $cat) {
	$self->{'position'}->{$id}=$cat;
	$self->refill;
      }
    } else {
      debug "Drang and drop cancelled: CLICK mode";
    }
}

sub vide {
    my ($self,$cat)=@_;
    for($self->{'zooms_table_'.$cat}->get_children) {
	$self->{'zooms_table_'.$cat}->remove($_);
    }
}

sub remplit {
    my ($self,$cat)=@_;

    my @good_ids=grep { $self->{'position'}->{$_} == $cat } (@{$self->{'ids'}});

    my $n_ligs=ceil((@good_ids ? (1+$#good_ids)/$self->{'n_cols'} : 1));
    $self->{'n_ligs'}->{$cat}=$n_ligs;

    for my $i (0..$#good_ids) {
	my $id=$good_ids[$i];
	my $x=$i % $self->{'n_cols'};
	my $y=int($i/$self->{'n_cols'});

	if($self->{'eff_pos'}->{$id} != $cat) {
	    $self->{'eb'}->{$id}->override_background_color(GTK_STATE_FLAG_NORMAL,$col_modif);
	    $self->{'conforme'}=0;
	} else {
	    if($self->{'auto_pos'}->{$id} == $cat) {
		$self->{'eb'}->{$id}->override_background_color(GTK_STATE_FLAG_NORMAL,undef);
	    } else {
		$self->{'eb'}->{$id}->override_background_color(GTK_STATE_FLAG_NORMAL,$col_manuel);
	    }
	}

	$self->{'zooms_table_'.$cat}->attach($self->{'eb'}->{$id},
					     $x,$y,1,1);
    }
}

sub ajuste_sep {
    my ($self)=@_;
    my $s=$self->{'decoupage'}->get_property('max-position');
    my $prop=$self->{'n_ligs'}->{0}/($self->{'n_ligs'}->{0}+$self->{'n_ligs'}->{1});
    $prop=$self->{'prop_min'} if($prop<$self->{'prop_min'});
    $prop=$self->{'prop_max'} if($prop>$self->{'prop_max'});
    $self->{'decoupage'}->set_position($prop*$s);
}

sub zoom_it {
    my ($self)=@_;
    my $x=0;
    my $y=0;
    my $n=0;

    # show all boxes with scale factor $self->{'factor'}

    for my $id (grep { $self->{'real_src'}->{$_} }
      (@{$self->{'ids'}})) {
      my $tx=int($self->{'pb_src'}->{$id}->get_width * $self->{'factor'});
      my $ty=int($self->{'pb_src'}->{$id}->get_height * $self->{'factor'});
      $x+=$tx;$y+=$ty;$n++;
      $self->{'pb'}->{$id}=$self->{'pb_src'}->{$id}
	->scale_simple($tx,$ty,GDK_INTERP_BILINEAR);
      $self->{'image'}->{$id}->set_from_pixbuf($self->{'pb'}->{$id});
    }

    # compute average size of the images

    if($n>0) {
      $x=int($x/$n);$y=int($y/$n);
    } else {
      $x=32;$y=32;
    }

    # show false zooms (question mark replacing the zooms when the
    # zoom file couldn't be loaded) at this average size

    for my $id (grep { ! $self->{'real_src'}->{$_} }
      (@{$self->{'ids'}})) {
      my $fx=$x/$self->{'pb_src'}->{$id}->get_width;
      my $fy=$y/$self->{'pb_src'}->{$id}->get_height;
      $fx=$fy if($fy<$fx);
      my $tx=int($self->{'pb_src'}->{$id}->get_width * $fx);
      my $ty=int($self->{'pb_src'}->{$id}->get_height * $fx);
      $self->{'pb'}->{$id}=$self->{'pb_src'}->{$id}
	->scale_simple($tx,$ty,GDK_INTERP_BILINEAR);
      $self->{'image'}->{$id}->set_from_pixbuf($self->{'pb'}->{$id});
    }

    # resize window

    $self->{'event_0'}->queue_resize();
    $self->{'event_1'}->queue_resize();

    my @size=$self->{'main_window'}->get_size();
    $size[0]=1;
    $self->{'main_window'}->resize(@size);
}

sub zoom_avant {
    my ($self)=@_;
    $self->{'factor'} *= 1.25;
    $self->zoom_it();
}

sub zoom_arriere {
    my ($self)=@_;
    $self->{'factor'} /= 1.25;
    $self->zoom_it();
}

sub list_prev {
  my ($self)=@_;
  my ($path)=$self->{'list_view'}->get_cursor();
  if($path) {
    if($path->prev) {
      return($path);
    }
  }
}

sub list_next {
  my ($self)=@_;
  my ($path)=$self->{'list_view'}->get_cursor();
  if($path) {
    $path->next;
    my $next_iter=$self->{'list_view'}->get_model->get_iter($path);
    if($next_iter) {
      return($self->{'list_view'}->get_model->get_path($next_iter));
    }
  }
}

sub zoom_list_previous {
  my ($self)=@_;
  my $path_prev=$self->list_prev;
  if($path_prev) {
    $self->{'list_view'}->set_cursor($path_prev,undef,FALSE);
  }
}

sub zoom_list_next {
  my ($self)=@_;
  my $path_next=$self->list_next;
  if($path_next) {
    $self->{'list_view'}->set_cursor($path_next,undef,FALSE);
  }
}

sub quit {
    my ($self)=@_;

    if($self->{'size-prefs'}) {
	my ($x,$y)=$self->{'main_window'}->get_size();
	$self->{'size-prefs'}->set('zoom_window_factor',$self->{'factor'});
	$self->{'size-prefs'}->set('zoom_window_height',$y);
    }

    if(!$self->{'conforme'}) {
	my $dialog = Gtk3::MessageDialog
	    ->new($self->{'main_window'},
                  'destroy-with-parent',
                  'warning','yes-no',
                  __("You moved some boxes to correct automatic data query, but this work is not saved yet.")." ".__("Dou you really want to close and ignore these modifications?")
	    );
	my $reponse=$dialog->run;
	$dialog->destroy;
	return() if($reponse eq 'no');
    }

    if($self->{'global'}) {
        Gtk3->main_quit;
    } else {
        $self->{'main_window'}->destroy;
    }
}

sub actif {
    my ($self)=@_;
    return($self->{'main_window'} &&
	   $self->{'main_window'}->get_realized);
}

sub checked {
    my ($self,$id)=@_;
    if(defined($self->{'position'}->{$id})) {
	return($self->{'position'}->{$id});
    } else {
	$self->{'eff_pos'}->{$id};
    }
}

sub apply {
    my ($self)=@_;

    # save modifications to manual analysis data

    $self->{'_capture'}->begin_transaction;
    $self->{'_capture'}->outdate_annotated_page(@{$self->{'page_id'}});

    debug "Saving manual data for ".pageids_string(@{$self->{'page_id'}});

    $self->{'_capture'}
      ->statement('setManualPage')
	->execute(time(),
		  @{$self->{'page_id'}});

    my $sth=$self->{'_capture'}->statement('pageZonesD');
    $sth->execute(@{$self->{'page_id'}},ZONE_BOX);
    while (my $z = $sth->fetchrow_hashref) {

      my $id=$z->{'id_a'}.'-'.$z->{'id_b'};

      $self->{'_capture'}
	->statement('setManual')
	  ->execute($self->checked($id),
		    @{$self->{'page_id'}},
		    ZONE_BOX,$z->{'id_a'},$z->{'id_b'});
    }

    $self->{'_capture'}->end_transaction;

    $self->load_positions;
    $self->refill;
}

1;
