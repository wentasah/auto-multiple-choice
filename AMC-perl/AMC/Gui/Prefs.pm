#! /usr/bin/perl
#
# Copyright (C) 2014-2017 Alexis Bienvenue <paamc@passoire.fr>
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

use Data::Dumper;

sub new {
  my (%o)=(@_);

  my $self={stores=>{},
	    shortcuts=>'',
            config=>'',
            kinds=>[qw/c cb ce col f s t v x fb p/],
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

sub default_object_options {
  my ($self,$o)=@_;
  $o->{store}=$o->{prefix} if(!$o->{store});
  $o->{store}='default' if(!$o->{store});
  $o->{prefix}='pref_' if(!$o->{prefix});
  $o->{keys}=[] if(!$o->{keys});
}

sub widget_store_set {
  my ($self,$full_key,$key,$kind,$widget,%o)=@_;
  $self->default_object_options(\%o);
  $self->{w}->{$o{store}}->{$full_key}=
    { widget=>$widget,
      full_key=>$full_key,
      key=>$key,
      kind=>$kind,
    };
}

sub widget_store_get {
  my ($self,$full_key,%o)=@_;
  $self->default_object_options(\%o);
  my $full_key_alt=$full_key;
  $full_key_alt =~ s+:+:/+ if($full_key_alt !~ s+:/+:+);
  my $ww=$self->{w}->{$o{store}}->{$full_key}
    || $self->{w}->{$o{store}}->{$full_key_alt};
  if($ww) {
    if($ww->{widget} && ref($ww->{widget}) =~ /^Gtk/) {
      return($ww);
    } else {
      debug "Non-Gtk widget store element: $ww";
    }
  }
  $Data::Dumper::Indent = 0;
  debug "STORE: ".Dumper($self->{w}->{$o{store}}) if($o{trace});
  return();
}

sub widget_store_clear {
  my ($self,%o)=@_;
  $self->{w}->{$o{store}}={};
}

sub widget_store_delete {
  my ($self,$key,%o)=@_;
  $self->default_object_options(\%o);
  delete $self->{w}->{$o{store}}->{$key};
}

sub widget_store_keys {
  my ($self,%o)=@_;
  $self->default_object_options(\%o);
  return(keys %{$self->{w}->{$o{store}}});
}

sub find_object {
  my ($self,$gap,$full_key,%o)=@_;
  $self->default_object_options(\%o);
  my $key=$full_key;
  $key =~ s/.*[\/:]//;

  if(!$gap) {
    my $record=$self->widget_store_get($full_key,%o);
    return($record->{widget},$record->{kind}) if($record);
  }

  for my $kind (@{$self->{kinds}}) {
    my $ww;
    if($gap) {
      $ww=$gap->get_object($o{prefix}.'_'.$kind.'_'.$key);
    }
    if(!$ww) {
      my $alt=$self->{alternate_w}->{$o{prefix}.'_'.$kind.'_'.$key};
      if($alt) {
        debug "  :alt: ".ref($alt);
        $ww=$alt;
      }
    }
    if($ww && ref($ww) =~ '^Gtk') {
      $self->widget_store_set($full_key,$key,$kind,$ww,%o);
      return($ww,$kind);
    }
  }

  return('');
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
# _p_ password (label)

sub transmet_pref {
  my ($self,$gap,%o)=@_;
  #,$prefix,$root,$alias,$seulement,$update)=@_;
  my $wp;

  $Data::Dumper::Indent = 0;
  debug "Updating GUI with options ".Dumper(\%o);

  $self->default_object_options(\%o);

  push @{$o{keys}},
    map { "$o{root}/$_" }
    $self->{config}->list_keys_from_root($o{root})
    if($o{root});

  $o{keys}=[keys %{$o{hash}}]
    if($o{hash} && !@{$o{keys}});

  for my $full_key (@{$o{keys}}) {

    my $value;

    if($o{hash}) {
      $value=$o{hash}->{$full_key};
    } else {
      $value=$self->{config}->get($full_key);
    }

    if($o{container}) {
      $full_key =~ s/^.*:/$o{container}:/;
    }

    my $key=$full_key;
    $key =~ s/.*[\/:]//;

    my ($w,$kind)=$self->find_object($gap,$full_key,%o);

    debug "Key $full_key --> "
      .($w ? "found widget ".ref($w) : "NONE")
      .($kind ? " {$kind}" : "")
      ." [$o{store}]";
    if(defined($value)) {
      debug "  gui <- $value" if($w);
    } else {
      debug_and_stderr "WARNING: undefined value for key $full_key\n";
    }

    if($w) {
      if ($kind eq 't') {
        $w->get_buffer->set_text($value);
      } elsif ($kind eq 'x') {
        $w->set_text($value);
      } elsif ($kind eq 'f') {
        my $path=$value;
        if ($self->{shortcuts}) {
          if ($key =~ /^projects_/) {
            $path=$self->{shortcuts}->absolu($path,'<HOME>');
          } elsif ($key !~ /^rep_/) {
            $path=$self->{shortcuts}->absolu($path);
          }
        }
        if ($w->get_action =~ /-folder$/i) {
          mkdir($path) if(!-e $path);
          $w->set_current_folder($path);
        } else {
          $w->set_filename($path);
        }
      } elsif ($kind eq 'v') {
        $w->set_active($value);
      } elsif ($kind eq 's') {
        $w->set_value($value);
      } elsif ($kind eq 'fb') {
        $w->set_font_name($value);
      } elsif ($kind eq 'col') {
        my $c=Gtk3::Gdk::Color::parse($value);
        $w->set_color($c);
      } elsif ($kind eq 'cb') {
        $w->set_active($value);
      } elsif ($kind eq 'c') {
        if ($self->store_get($key)) {
          debug "CB_STORE($key) modifie ($key=>$value)";
          $w->set_model($self->store_get($key));
          my $i=model_id_to_iter($w->get_model,COMBO_ID,$value);
          if ($i) {
            debug("[$key] find $i",
                  " -> ".$self->store_get($key)->get($i,COMBO_TEXT));
            $w->set_active_iter($i);
          }
        } else {
          $self->widget_store_delete($full_key,%o);
          debug "no CB_STORE for $key";
          $w->set_active($value);
        }
      } elsif ($kind eq 'ce') {
        if ($self->store_get($key)) {
          debug "CB_STORE($key) changed";
          $w->set_model($self->store_get($key));
        }
        my @we=grep { my (undef,$pr)=$_->class_path();$pr =~ /(yrtnE|Entry)/ } ($w->get_children());
        if (@we) {
          $we[0]->set_text($value);
          $self->widget_store_set($full_key,$key,'x',$we[0],%o);
        } else {
          print STDERR "$key/CE : cannot find text widget\n";
        }
      } elsif($kind eq 'p') {
        $w->set_text($self->{config}->get_passwd($key));
      }
    }
  }

  debug "End GUI update for <$o{prefix}>";
}

# met a jour les preferences depuis les widgets correspondants
sub reprend_pref {
  my ($self,%o)=@_;
  #$prefixe,$root,$oprefix,$seulement)=@_;

  $Data::Dumper::Indent = 0;
  debug "Update configuration from GUI with options ".Dumper(\%o);

  $self->default_object_options(\%o);
  $o{keys}=[$self->widget_store_keys(%o)]
    if(!@{$o{keys}});

  for my $key (@{$o{keys}}) {
    my $s=$self->widget_store_get($key,%o);
    if($s) {
      debug "Key $s->{full_key}: kind $s->{kind}";

      my $found=1;
      if ($s->{kind} eq 'x') {
	$n=$s->{widget}->get_text();
      } elsif($s->{kind} eq 't') {
	my $buf=$s->{widget}->get_buffer;
	$n=$buf->get_text($buf->get_start_iter,$buf->get_end_iter,1);
      } elsif($s->{kind} eq 'f') {
	if ($s->{widget}->get_action =~ /-folder$/i) {
	  if (-d $s->{widget}->get_filename()) {
	    $n=$s->{widget}->get_filename();
	  } else {
	    $n=$s->{widget}->get_current_folder();
	  }
	} else {
	  $n=$s->{widget}->get_filename();
	}
	if ($self->{shortcuts}) {
	  if ($s->{key} =~ /^projects_/) {
	    $n=$self->{shortcuts}->relatif($n,'<HOME>');
	  } elsif ($s->{key} !~ /^rep_/) {
	    $n=$self->{shortcuts}->relatif($n);
	  }
	}
      } elsif($s->{kind} eq 'v') {
	$n=$s->{widget}->get_active();
      } elsif($s->{kind} eq 's') {
	$n=$s->{widget}->get_value();
      } elsif($s->{kind} eq 'fb') {
	$n=$s->{widget}->get_font_name();
      } elsif($s->{kind} eq 'col') {
	$n=$s->{widget}->get_color()->to_string();
      } elsif($s->{kind} eq 'cb') {
	$n=$s->{widget}->get_active();
      } elsif($s->{kind} eq 'c') {
	if (my $model=$s->{widget}->get_model) {
          my ($ok,$iter)=$s->{widget}->get_active_iter;
	  if ($ok && $iter) {
	    $n=$s->{widget}->get_model->get($iter,COMBO_ID);
	  } else {
	    debug "No active iter for combobox $key [$o{store}]";
	    $n='';
	  }
	} else {
	  $n=$s->{widget}->get_active();
	}
      } elsif($s->{kind} eq 'p') {
        $self->{config}->set_passwd($s->{key},$s->{widget}->get_text());
        $found=0;
      } else {
        $found=0;
      }
      if($found) {
        debug "  gui -> $n";
        if($o{container}) {
          $key=$o{container}.":".$key if($key !~ s/.*:/$o{container}:/)
        }
        if($o{hash}) {
          $o{hash}->{$key}=$n;
        } else {
          $self->{config}->set($key,$n);
        }
      }
    } else {
      debug "Key $key: widget not found [$o{store}]";
    }
  }

  debug "Update <$o{prefix}> finished / changed: "
    .join(', ',$self->{config}->changed_keys());
}

1;
