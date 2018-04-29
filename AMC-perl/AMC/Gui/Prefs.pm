#! /usr/bin/perl
#
# Copyright (C) 2014-2016 Alexis Bienvenue <paamc@passoire.fr>
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

package AMC::Gui::Prefs;

use AMC::Basic;

sub new {
  my (%o)=(@_);

  my $self={stores=>{},
	    shortcuts=>'',
	    w=>{},
	    alternate_w=>'',
	   };

  for my $k (keys %o) {
    $self->{$k}=$o{$k} if(defined($self->{$k}));
  }

  bless $self;

  return($self);
}

sub store_register {
  my ($self,%c)=@_;
  for my $key (keys %c) {
    $self->{stores}->{$key}=$c{$key};
  }
}

sub store_get {
  my ($self,$key)=@_;
  return($self->{stores}->{$key});
}

sub find_object {
  my ($self,$gap,$prefix,$type,$ta,$t,$keep)=@_;
  my $ww;

  $ww=$gap->get_object($prefix.$type.$ta) if(!$keep);
  if(!$ww && $self->{alternate_w}) {
    $ww=$self->{alternate_w}->{$prefix.$type.$ta};
  }
  if ($ww) {
    $self->{w}->{$prefix.$type.$ta}=$ww;
    $self->{w}->{$prefix.$type.$t}=$ww;
  }

  return($self->{w}->{$prefix.$type.$ta});
}

# transmet les preferences vers les widgets correspondants
# _c_ combo box (menu)
# _cb_ check button
# _ce_ combo box entry
# _col_ color chooser
# _f_ file name
# _s_ spin button
# _t_ text
# _v_ check button
# _x_ one line text
# _fb_ font button

sub transmet_pref {
  my ($self,$gap,$prefixe,$h,$alias,$seulement,$update)=@_;
  my $wp;

  debug "Updating GUI for <$prefixe>";

  for my $t (keys %$h) {
    if (!$seulement || $seulement->{$t}) {
      my $ta=$t;
      $ta=$alias->{$t} if($alias->{$t});

      if ($wp=$self->find_object($gap,$prefixe,'_t_',$ta,$t,$update)) {
	$wp->get_buffer->set_text($h->{$t});
      } elsif ($wp=$self->find_object($gap,$prefixe,'_x_',$ta,$t,$update)) {
	$wp->set_text($h->{$t});
      } elsif ($wp=$self->find_object($gap,$prefixe,'_f_',$ta,$t,$update)) {
	my $path=$h->{$t};
	if ($self->{shortcuts}) {
	  if ($t =~ /^projects_/) {
	    $path=$self->{shortcuts}->absolu($path,'<HOME>');
	  } elsif ($t !~ /^rep_/) {
	    $path=$self->{shortcuts}->absolu($path);
	  }
	}
	if ($wp->get_action =~ /-folder$/i) {
	  mkdir($path) if(!-e $path);
	  $wp->set_current_folder($path);
	} else {
	  $wp->set_filename($path);
	}
      } elsif ($wp=$self->find_object($gap,$prefixe,'_v_',$ta,$t,$update)) {
	$wp->set_active($h->{$t});
      } elsif ($wp=$self->find_object($gap,$prefixe,'_s_',$ta,$t,$update)) {
	$wp->set_value($h->{$t});
      } elsif ($wp=$self->find_object($gap,$prefixe,'_fb_',$ta,$t,$update)) {
	$wp->set_font_name($h->{$t});
      } elsif ($wp=$self->find_object($gap,$prefixe,'_col_',$ta,$t,$update)) {
	$wp->set_color(Gtk2::Gdk::Color->parse($h->{$t}));
      } elsif ($wp=$self->find_object($gap,$prefixe,'_cb_',$ta,$t,$update)) {
	$wp->set_active($h->{$t});
      } elsif ($wp=$self->find_object($gap,$prefixe,'_c_',$ta,$t,$update)) {
	if ($self->store_get($ta)) {
	  debug "CB_STORE($t) ALIAS $ta modifie ($t=>$h->{$t})";
	  $wp->set_model($self->store_get($ta));
	  my $i=model_id_to_iter($wp->get_model,COMBO_ID,$h->{$t});
	  if ($i) {
	    debug("[$t] find $i",
		  " -> ".$self->store_get($ta)->get($i,COMBO_TEXT));
	    $wp->set_active_iter($i);
	  }
	} else {
	  $self->{w}->{$prefixe.'_c_'.$t}='';
	  debug "no CB_STORE for $ta";
	  $wp->set_active($h->{$t});
	}
      } elsif ($wp=$self->find_object($gap,$prefixe,'_ce_',$ta,$t,$update)) {
	if ($self->store_get($ta)) {
	  debug "CB_STORE($t) ALIAS $ta changed";
	  $wp->set_model($self->store_get($ta));
	}
	my @we=grep { my (undef,$pr)=$_->class_path();$pr =~ /(yrtnE|Entry)/ } ($wp->get_children());
	if (@we) {
	  $we[0]->set_text($h->{$t});
	  $self->{w}->{$prefixe.'_x_'.$t}=$we[0];
	} else {
	  print STDERR $prefixe.'_ce_'.$t." : cannot find text widget\n";
	}
      }
      debug "Key $t --> $ta : ".(defined($wp) ? "found widget $wp" : "NONE");
    }
  }

  debug "End GUI update for <$prefixe>";
}

# met a jour les preferences depuis les widgets correspondants
sub reprend_pref {
  my ($self,$prefixe,$h,$oprefix,$seulement)=@_;
  $h->{'_modifie'}=($h->{'_modifie'} ? 1 : '');

  debug "Restricted search: ".join(',',keys %$seulement)
    if ($seulement);
  for my $t (keys %$h) {
    if (!$seulement || $seulement->{$t}) {
      my $tgui=$t;
      $tgui =~ s/$oprefix$// if($oprefix);
      debug "Looking for widget <$tgui> in domain <$prefixe>";
      my $n;
      my $wp;
      my $found=1;
      if ($wp=$self->{w}->{$prefixe.'_x_'.$tgui}) {
	debug "Found string entry";
	$n=$wp->get_text();
      } elsif($wp=$self->{w}->{$prefixe.'_t_'.$tgui}) {
	debug "Found text entry";
	my $buf=$wp->get_buffer;
	$n=$buf->get_text($buf->get_start_iter,$buf->get_end_iter,1);
      } elsif($wp=$self->{w}->{$prefixe.'_f_'.$tgui}) {
	debug "Found file chooser";
	if ($wp->get_action =~ /-folder$/i) {
	  if (-d $wp->get_filename()) {
	    $n=$wp->get_filename();
	  } else {
	    $n=$wp->get_current_folder();
	  }
	} else {
	  $n=$wp->get_filename();
	}
	if ($self->{shortcuts}) {
	  if ($tgui =~ /^projects_/) {
	    $n=$self->{shortcuts}->relatif($n,'<HOME>');
	  } elsif ($tgui !~ /^rep_/) {
	    $n=$self->{shortcuts}->relatif($n);
	  }
	}
      } elsif($wp=$self->{w}->{$prefixe.'_v_'.$tgui}) {
	debug "Found (v) check button";
	$n=$wp->get_active();
      } elsif($wp=$self->{w}->{$prefixe.'_s_'.$tgui}) {
	debug "Found spin button";
	$n=$wp->get_value();
      } elsif($wp=$self->{w}->{$prefixe.'_fb_'.$tgui}) {
	debug "Found font button";
	$n=$wp->get_font_name();
      } elsif($wp=$self->{w}->{$prefixe.'_col_'.$tgui}) {
	debug "Found color chooser";
	$n=$wp->get_color()->to_string();
      } elsif($wp=$self->{w}->{$prefixe.'_cb_'.$tgui}) {
	debug "Found checkbox";
	$n=$wp->get_active();
      } elsif($wp=$self->{w}->{$prefixe.'_c_'.$tgui}) {
	debug "Found combobox";
	if ($wp->get_model) {
	  if ($wp->get_active_iter) {
	    $n=$wp->get_model->get($wp->get_active_iter,COMBO_ID);
	  } else {
	    debug "No active iter for combobox ".$prefixe.'_c_'.$tgui;
	    $n='';
	  }
	} else {
	  $n=$wp->get_active();
	}
      } else {
        $found=0;
      }
      if($found) {
        $h->{$t}='' if(!defined($h->{$t}));
	$h->{'_modifie'}.=",$t" if($h->{$t} ne $n);
	$h->{$t}=$n;
      }
    } else {
      debug "Skip widget <$t>";
    }
  }

  debug "Changes : $h->{'_modifie'}";
}

1;
