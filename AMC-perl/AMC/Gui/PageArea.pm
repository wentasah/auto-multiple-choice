#! /usr/bin/perl -w
#
# Copyright (C) 2008-2017 Alexis Bienvenue <paamc@passoire.fr>
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

package AMC::Gui::PageArea;

use Gtk3;
use AMC::Basic;

@ISA=("Gtk3::DrawingArea");

sub add_feuille {
    my ($self,%oo)=@_;
    bless($self,"AMC::Gui::PageArea");

    $self->{image_file}='';
    $self->{text}='';
    $self->{background_color}='';

    $self->{'marks'}='';

    $self->{'i-src'}='';
    $self->{'tx'}=1;
    $self->{'ty'}=1;
    $self->{'yfactor'}=1;

    $self->{'min_render_size'}=10;

    $self->{'case'}='';
    $self->{'coches'}='';
    $self->{'editable'}=1;

    $self->{'onscan'}='';
    $self->{unticked_color_name}="#429DE5";
    $self->{question_color_name}="#47D265";
    $self->{scorezone_color_name}="#DE61E2";
    $self->{empty_color_name}="#78FFED";
    $self->{invalid_color_name}="#FFEF3B";
    $self->{drawings_color_name}="red";
    $self->{text_color_name}="black";

    $self->{linewidth_zone}=1;
    $self->{linewidth_box}=1;
    $self->{linewidth_box_scan}=2;
    $self->{box_external}=4;
    $self->{linewidth_special}=4;

    $self->{'font'}=Pango::FontDescription::from_string("128");

    for (keys %oo) {
	$self->{$_}=$oo{$_} if(defined($self->{$_}));
    }

    for my $type ('',qw/scorezone_ question_ unticked_ empty_ invalid_ drawings_ text_/) {
      $self->{$type.'color'}=
	Gtk3::Gdk::RGBA::parse($self->{$type.'color_name'}) if($type);
    }

    if($self->{'marks'}) {
	$self->{'colormark'}= Gtk3::Gdk::RGBA::parse($self->{'marks'});
    }

    $self->signal_connect('size-allocate'=>\&allocate_drawing);
    $self->signal_connect('draw'=>\&draw);

    return($self);
}

sub set_background {
  my ($self,$color)=@_;
  if($color) {
    $self->{background_color}=Gtk3::Gdk::RGBA::parse($color);
  } else {
    $self->{background_color}='';
  }
}

sub set_text {
  my ($self,$text)=@_;
  $self->{text}=$text;
}

sub set_image {
  my ($self,$image,$layinfo)=@_;
  $self->{image_file}=$image;
  if($image && -f $image) {
    eval { $self->{'i-src'} =
             Gtk3::Gdk::Pixbuf->new_from_file(Glib::filename_to_unicode($image));
         };
    if($@) {
      # Error loading scan...
      $self->{'i-src'}='';
    } else {
      $layinfo->{'page'}->{'width'}=$self->{'i-src'}->get_width
        if(!$layinfo->{'page'}->{'width'});
      $layinfo->{'page'}->{'height'}=$self->{'i-src'}->get_height
        if(!$layinfo->{'page'}->{'height'});
    }
  } else {
    $self->{'i-src'}='';
  }
  $self->{'layinfo'}=$layinfo;
  $self->{'modifs'}=0;
  $self->allocate_drawing();
  $self->queue_draw();
}

sub set_content {
  my ($self,%o)=@_;
  debug("PageArea content set to ".join(" ",%o));
  $self->set_background($o{background_color});
  $self->set_text($o{text});
  $self->set_image($o{image},$o{layout_info});
}

sub get_image {
   my ($self)=@_;
   return($self->{'i-src'});
 }

sub modifs {
    my $self=shift;
    return($self->{'modifs'});
}

sub sync {
    my $self=shift;
    $self->{'modifs'}=0;
}

sub modif {
    my $self=shift;
    $self->{'modifs'}=1;
}

sub choix {
  my ($self,$event)=(@_);

  if(!$self->{'editable'}) {
    return TRUE;
  }

  if($self->{'layinfo'}->{'block_message'}) {
    my $dialog = Gtk3::MessageDialog
      ->new(undef,
            'destroy-with-parent',
            'error','ok','');
    $dialog->set_markup($self->{'layinfo'}->{'block_message'});
    $dialog->run;
    $dialog->destroy;

    return TRUE;
  }

  if($self->{'layinfo'}->{'box'}) {

      if ($event->button == 1) {
	  my ($x,$y)=($event->x,$event->y);
	  debug "Click $x $y\n";
	  for my $i (@{$self->{'layinfo'}->{'box'}}) {

	      if($x<=$i->{'xmax'}*$self->{'rx'} && $x>=$i->{'xmin'}*$self->{'rx'}
		 && $y<=$i->{'ymax'}*$self->{'ry'} && $y>=$i->{'ymin'}*$self->{'ry'}) {
		  $self->{'modifs'}=1;

		  debug " -> box $i\n";
		  $i->{'ticked'}=!$i->{'ticked'};

                  $self->queue_draw();
	      }
	  }
      }

  }
  return TRUE;
}

sub extend {
  my ($external,@xy)=@_;
  return(@xy) if($external==0);
  # computes x and y means
  my $mx=0;
  my $my=0;
  for(my $ix = 0; $ix <= $#xy; $ix += 2) {
    $mx+=$xy[$ix];
    $my+=$xy[$ix+1];
  }
  my @centroid=($mx / ((1+$#xy)/2) , $my / ((1+$#xy)/2));
  # extend from the centroid
  for(my $ix = 0; $ix <= $#xy; $ix += 2) {
    my $l=sqrt( ($xy[$ix]-$centroid[0])**2 +
		($xy[$ix+1]-$centroid[1])**2 );
    my $alpha=($l+$external)/$l;
    for my $i (0,1) {
      $xy[$ix+$i]=$centroid[$i]+$alpha*($xy[$ix+$i]-$centroid[$i])
    }
  }
  return(@xy);
}

sub draw_box {
  my ($self,$context,$box,$fill,$external)=@_;
  $external=0 if(!$external);
  if($box->{'xy'}) {
    $context->new_path;
    $context->move_to($box->{'xy'}->[0]*$self->{'rx'},
		      $box->{'xy'}->[1]*$self->{'ry'});
    for my $i (1..3) {
      $context->line_to($box->{'xy'}->[$i*2]*$self->{'rx'},
			$box->{'xy'}->[$i*2+1]*$self->{'ry'});
    }
    $context->close_path;
    if($fill) { $context->fill; }
    else { $context->stroke; }
  } else {
    $context->new_path();
    $context->rectangle
      (
       $box->{'xmin'}*$self->{'rx'}-$external,
       $box->{'ymin'}*$self->{'ry'}-$external,
       ($box->{'xmax'}-$box->{'xmin'})*$self->{'rx'}+2*$external,
       ($box->{'ymax'}-$box->{'ymin'})*$self->{'ry'}+2*$external
      );
    if($fill) { $context->fill; }
    else { $context->stroke; }
  }
}

sub box_miny {
  my ($self,$box)=@_;
  my $miny=$self->{'ty'};
  if($box->{'xy'}) {
    for my $i (0..3) {
      my $y=$box->{'xy'}->[$i*2+1]*$self->{'ry'};
      $miny=$y if($y<$miny);
    }
  } else {
    $miny=$box->{'ymin'}*$self->{'ry'};
  }
  return($miny);
}

sub question_miny {
  my ($self,$question)=@_;
  my $miny=$self->{'ty'};
  for my $l (@{$self->{'layinfo'}->{'box'}}) {
    if($l->{question}==$question) {
      my $y=$self->box_miny($l);
      $miny=$y if($y<$miny);
    }
  }
  return($miny);
}

sub allocate_drawing {
  my ($self,$evenement,@donnees)=@_;
  my $r=$self->get_allocation();

  if($self->{'i-src'}) {

    $self->{'tx'}=$r->{width};
    $self->{'ty'}=$self->{'yfactor'}*$r->{height};

    debug("Rendering target size: ".$self->{'tx'}."x".$self->{'ty'});

    my $sx=$self->{'tx'}/$self->{'i-src'}->get_width;
    my $sy=$self->{'ty'}/$self->{'i-src'}->get_height;

    if($sx<$sy) {
      $self->{'ty'}=int($self->{'i-src'}->get_height*$sx);
      $sy=$self->{'ty'}/$self->{'i-src'}->get_height;
    }
    if($sx>$sy) {
      $self->{'tx'}=int($self->{'i-src'}->get_width*$sy);
      $sx=$self->{'tx'}/$self->{'i-src'}->get_width;
    }

    $self->{'sx'}=$sx;
    $self->{'sy'}=$sy;

    $self->set_size_request(-1,$self->{'ty'})
      if($self->{'yfactor'}>1);

  } else {
    $self->{tx}=$r->{width};
    $self->{ty}=$r->{height};
  }

  0;
}

sub context_color {
  my ($self,$context,$color_name)=@_;
  my $c=$self->{$color_name."_color"};
  $context->set_source_rgb($c->red,$c->green,$c->blue);
}

sub draw {
    my ($self,$context)=@_;

    $self->allocate_drawing() if(!$self->{'sx'} || !$self->{'sy'});

    return() if($self->{'tx'}<$self->{'min_render_size'}
		|| $self->{'ty'}<$self->{'min_render_size'});

    my $sx=$self->{'sx'};
    my $sy=$self->{'sy'};

    if($self->{background_color}) {
      debug("Background color");
      $self->context_color($context,'background');
      $context->paint();
    }

    if($self->{text}) {
      $self->context_color($context,'text');
      $context->set_font_size(20);
      my $ext=$context->text_extents($self->{text});
      my $r=$self->{'tx'}/$ext->{width};
      my $ry=$self->{'ty'}/$ext->{height};
      $r=$ry if($ry<$r);
      $context->set_font_size(20*$r);
      $ext=$context->text_extents($self->{text});
      $context->move_to(-$ext->{x_bearing}+int(($self->{tx}-$ext->{width})/2),
			-$ext->{y_bearing});
      $context->show_text($self->{text});
      $context->stroke();
    }

    if($self->{'i-src'}) {
      my $sx=$self->{'sx'};
      my $sy=$self->{'sy'};

      debug("Rendering with SX=$sx SY=$sy");

      my $i=Gtk3::Gdk::Pixbuf->new(GDK_COLORSPACE_RGB,1,8,$self->{'tx'},$self->{'ty'});

      $self->{'i-src'}->scale($i,0,0,$self->{'tx'},$self->{'ty'},0,0,
			      $sx,$sy,
			      GDK_INTERP_BILINEAR);

      Gtk3::Gdk::cairo_set_source_pixbuf($context,$i,0,0);
      $context->paint();

      debug "Done with rendering";
    }

    if(($self->{'layinfo'}->{'box'} || $self->{'layinfo'}->{'namefield'})
      && ($self->{'layinfo'}->{'page'}->{'width'})) {
	my $box;

	debug "Layout drawings...";

	$self->{'rx'}=$self->{'tx'}/$self->{'layinfo'}->{'page'}->{'width'};
	$self->{'ry'}=$self->{'ty'}/$self->{'layinfo'}->{'page'}->{'height'};

	# layout drawings

	if($self->{'marks'}) {
            Gtk3::Gdk::cairo_set_source_rgba($context,$self->{'colormark'});

	    for $box (@{$self->{'layinfo'}->{'namefield'}}) {
		$self->draw_box($context,$box,'',0);
	    }

	    $box=$self->{'layinfo'}->{'mark'};

	    if($box) {
              $context->new_path;
	      for my $i (0..3) {
		my $j=(($i+1) % 4);
		$context->move_to($box->[$i]->{'x'}*$self->{'rx'},
				  $box->[$i]->{'y'}*$self->{'ry'});
		$context->line_to($box->[$j]->{'x'}*$self->{'rx'},
				  $box->[$j]->{'y'}*$self->{'ry'});
	      }
	      $context->stroke;
	    }

	    for my $box (@{$self->{'layinfo'}->{'digit'}}) {
		$self->draw_box($context,$box,'',0);
	    }

	}

	## boxes drawings

        $context->set_line_width($self->{linewidth_special});
        $self->context_color($context,'invalid');
        for $box (grep { $_->{scoring}->{why} && $_->{scoring}->{why} =~ /E/ }
                  @{$self->{'layinfo'}->{'box'}}) {
          $self->draw_box($context,$box,'',$self->{box_external});
        }
        $self->context_color($context,'empty');
        for $box (grep { $_->{scoring}->{why} && $_->{scoring}->{why} =~ /V/ }
                  @{$self->{'layinfo'}->{'box'}}) {
          $self->draw_box($context,$box,'',$self->{box_external});
        }

	if($self->{'onscan'}) {
	  $context->set_line_width($self->{linewidth_box_scan});
	  $self->context_color($context,'drawings');
	  for $box (grep { $_->{'ticked'} }
		    @{$self->{'layinfo'}->{'box'}}) {
	    $self->draw_box($context,$box,'');
	  }
	  $self->context_color($context,'unticked');
	  for $box (grep { ! $_->{'ticked'} }
		    @{$self->{'layinfo'}->{'box'}}) {
	    $self->draw_box($context,$box,'');
	  }
	} else {
	  $context->set_line_width($self->{linewidth_box});
	  $self->context_color($context,'drawings');
	  for $box (@{$self->{'layinfo'}->{'box'}}) {
	    $self->draw_box($context,$box,$box->{'ticked'});
	  }
	  $context->set_line_width($self->{linewidth_zone});
	  $self->context_color($context,'question');
	  for $box (@{$self->{'layinfo'}->{'questionbox'}}) {
	    $self->draw_box($context,$box,'');
	  }
	}
	$context->set_line_width($self->{linewidth_zone});
	$self->context_color($context,'scorezone');
	for $box (@{$self->{'layinfo'}->{'scorezone'}}) {
	  $self->draw_box($context,$box,'');
	}

	debug "Done.";
    }
}

1;
