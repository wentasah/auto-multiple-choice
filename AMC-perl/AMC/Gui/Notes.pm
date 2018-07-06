#! /usr/bin/perl -w
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

package AMC::Gui::Notes;

use AMC::Basic;
use AMC::Gui::WindowSize;

use Encode;

use Gtk3 -init;

use constant {
    TAB_ID => 0,
    TAB_NOTE => 1,
    TAB_COLOR => 2,
    TAB_DETAIL => 3,
};

sub ajoute_colonne {
    my ($tree,$store,$titre,$i)=@_;
    my $renderer=Gtk3::CellRendererText->new;
    my $column = Gtk3::TreeViewColumn->new_with_attributes(
	$titre,
	$renderer,
	text=> $i,
	'background'=>TAB_COLOR );
    $column->set_sort_column_id($i);
    $tree->append_column($column);
    $store->set_sort_func($i,\&sort_num,$i);
}

sub formatte {
    my ($x)=@_;
    $x=(defined($x) ? sprintf("%.2f",$x) : '');
    $x =~ s/0+$//;
    $x =~ s/\.$//;
    return($x);
}

sub new {
    my %o=(@_);
    my $self={
              scoring=>'',
              layout=>'',
              size_prefs=>'',
             };
    my $it;

    for (keys %o) {
	$self->{$_}=$o{$_} if(defined($self->{$_}));
    }

    bless $self;

    my $glade_xml=__FILE__;
    $glade_xml =~ s/\.p[ml]$/.glade/i;

    $self->{'gui'}=Gtk3::Builder->new();
    $self->{'gui'}->set_translation_domain('auto-multiple-choice');
    $self->{'gui'}->add_from_file($glade_xml);

    for my $k (qw/general tableau/) {
	$self->{$k}=$self->{'gui'}->get_object($k);
    }

    if($self->{'general'}->get_direction() eq 'rtl') {
	$self->{'tableau'}->set_grid_lines('horizontal');
    }

    $self->{'gui'}->connect_signals(undef,$self);

    $self->{'scoring'}->begin_read_transaction;

    for (qw/student copy/) {
      $self->{'postcorrect_'.$_}=
	$self->{'scoring'}->variable('postcorrect_'.$_);
      $self->{'postcorrect_'.$_}=-1 if(!defined($self->{'postcorrect_'.$_}) || $self->{'postcorrect_'.$_} eq '');
    }

    my $code_digit_pattern = $self->{layout}->code_digit_pattern();
    my @codes=$self->{'scoring'}->codes;
    my @questions=sort { $a->{'title'} cmp $b->{'title'} }
      grep { $_->{'title'} !~ /$code_digit_pattern$/ }
      ($self->{'scoring'}->questions);

    my $store = Gtk3::ListStore->new ( map {'Glib::String' } (1..(3+1+$#codes+1+$#questions)) );

    $self->{'tableau'}->set_model($store);

    ajoute_colonne($self->{'tableau'},$store,
		   translate_column_title("copie"),TAB_ID);
    ajoute_colonne($self->{'tableau'},$store,
		   translate_column_title("note"),TAB_NOTE);

    my $i=TAB_DETAIL ;
    for((map { $_->{'title'}} @questions),@codes) {
	ajoute_colonne($self->{'tableau'},$store,decode('utf-8',$_),$i++);
    }

    my $row=0;
    my @vv;

  COPIE:for my $m ($self->{'scoring'}->marks) {
      my @sc=($m->{'student'},$m->{'copy'});
      @vv=(TAB_ID,studentids_string(@sc),
	      TAB_NOTE,formatte($m->{'mark'}),
	      TAB_COLOR,($sc[0]==$self->{'postcorrect_student'} &&
			 $sc[1]==$self->{'postcorrect_copy'}
			 ? '#CAEC87' : undef)
	      );
      $i=TAB_DETAIL ;
      for(@questions) {
	push @vv,$i++,
	  formatte($self->{'scoring'}->question_score(@sc,$_->{'question'}));
      }
      for(@codes) {
	push @vv,$i++,$self->{'scoring'}->student_code(@sc,$_);
      }

      $store->insert_with_values($row++,@vv);
  }

    # Average row

    @vv=(TAB_ID,translate_id_name('moyenne'),
	 TAB_NOTE,formatte($self->{'scoring'}->average_mark),
	);

    $i=TAB_DETAIL ;
    for(@questions) {
      my $p;
      if($self->{'scoring'}->one_indicative($_->{'question'})) {
	$p='-';
      } else {
	$p=$self->{'scoring'}->question_average($_->{'question'});
	if($p ne '-') {
	  $p=sprintf("%.0f%%",$p);
	} else {
	  $p='?';
	}
      }
      push @vv,$i++,$p;
    }
    for(@codes) {
      push @vv,$i++,'---';
    }

    $store->insert_with_values($row++,@vv);

    $self->{'scoring'}->end_transaction;

    AMC::Gui::WindowSize::size_monitor
        ($self->{general},{config=>$self->{size_prefs},
                           key=>'marks_window_size'});

    return($self);
}

sub quitter {
    my ($self)=(@_);

    if($self->{'global'}) {
	Gtk3->main_quit;
    } else {
	$self->{'general'}->destroy;
    }
}

1;

__END__
