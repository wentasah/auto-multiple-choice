# -*- perl -*-
#
# Copyright (C) 2021 Alexis Bienvenue <paamc@passoire.fr>
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

package AMC::Gui::Main;

use parent 'AMC::Gui';

use AMC::Basic;

use AMC::DataModule::capture ':zone';
use AMC::DataModule::report ':const';
use AMC::Encodings;
use AMC::FileMonitor;
use AMC::Gui::APropos;
use AMC::Gui::Association;
use AMC::Gui::AutoCapture;
use AMC::Gui::ChooseColumns;
use AMC::Gui::Cleanup;
use AMC::Gui::Commande;
use AMC::Gui::CreateProject;
use AMC::Gui::FilterDetails;
use AMC::Gui::Learning;
use AMC::Gui::Mailing;
use AMC::Gui::Manuel;
use AMC::Gui::Notes;
use AMC::Gui::Overwritten;
use AMC::Gui::Postcorrect;
use AMC::Gui::Preferences;
use AMC::Gui::Prefs;
use AMC::Gui::Printing;
use AMC::Gui::ProjectManager;
use AMC::Gui::SelectStudents;
use AMC::Gui::StudentsList;
use AMC::Gui::Template;
use AMC::Gui::Unrecognized;
use AMC::Gui::WindowSize;
use AMC::Gui::Zooms;
use AMC::State;

use File::Spec::Functions
  qw/splitpath catpath splitdir catdir catfile rel2abs tmpdir/;
use File::Path qw/remove_tree/;
use Module::Load;
use Module::Load::Conditional qw/check_install/;

use POSIX qw/strftime/;
use Time::Local;

use constant {
    DIAG_ID         => 0,
    DIAG_ID_BACK    => 1,
    DIAG_MAJ        => 2,
    DIAG_MAJ_NUM    => 3,
    DIAG_EQM        => 4,
    DIAG_EQM_BACK   => 5,
    DIAG_DELTA      => 6,
    DIAG_DELTA_BACK => 7,
    DIAG_ID_STUDENT => 8,
    DIAG_ID_PAGE    => 9,
    DIAG_ID_COPY    => 10,
    DIAG_SCAN_FILE  => 11,
};

# Reads filter plugins list

my @filter_modules = perl_module_search('AMC::Filter::register');
for my $m (@filter_modules) {
    load("AMC::Filter::register::$m");
}
@filter_modules = sort {
    "AMC::Filter::register::$a"->weight <=> "AMC::Filter::register::$b"->weight
} @filter_modules;

sub new {
    my ( $class, %oo ) = @_;

    my $self = $class->SUPER::new(%oo);
    bless( $self, $class );

    $self->merge_config(
        {
            do_nothing      => '',
            project         => '',
            libnotify_error => '',
        },
        %oo
    );

    $self->stores();
    $self->main_window();
    $self->set_css();
    $self->{config}->connect_to_window($self->get_ui('main_window'));
    $self->test_debian_amc();
    $self->test_magick();
    $self->test_libnotify();

    $self->{monitor} = AMC::FileMonitor->new();

    $self->gui_no_project();

    return $self;
}

sub set_css {
    my ($self) = @_;
    my $css = Gtk3::CssProvider->new();
    $css->load_from_data( '
infobar.info, infobar.info box {
    background-color: @success_color;
    background-image: none;
}
infobar.warning, infobar.warning box {
    background-color: @warning_color;
    background-image: none;
}
infobar.error, infobar.error box {
    background-color: @error_color;
    background-image: none;
}
infobar.info button box, infobar.warning button box, infobar.error button box {
    background-color: transparent;
}
' );

    Gtk3::StyleContext::add_provider_for_screen(
        $self->get_ui('main_window')->get_screen(),
        $css, Gtk3::STYLE_PROVIDER_PRIORITY_APPLICATION );
}

# tests if debian package auto-multiple-choice-common is installed but
# not auto-multiple-choice...

sub deb_is_installed {
    my ($package_name) = @_;
    my $v = '';
    open( QUERY, "-|", "dpkg-query", "-W", '--showformat=${Version}\n',
        $package_name );
    while (<QUERY>) {
        $v = $1 if (/^\s*([^\s]+)\s*$/);
    }
    close(QUERY);
    return ($v);
}

sub test_debian_amc {
    my ($self) = @_;
    if ( commande_accessible("dpkg-query") ) {
        if ( deb_is_installed("auto-multiple-choice-common")
            && !deb_is_installed("auto-multiple-choice") )
        {
            debug "ERROR: auto-multiple-choice package not installed!";
            my $dialog = Gtk3::MessageDialog->new( $self->get_ui('main_window'),
                'destroy-with-parent', 'error', 'ok', '' );
            $dialog->set_markup( __
"The package <i>auto-multiple-choice-common</i> is installed, but not <i>auto-multiple-choice</i>.\n<b>AMC won't work properly until you install auto-multiple-choice package!</b>"
            );
            $dialog->run;
            $dialog->destroy;
        }
    }
}

# Test whether the magick perl package is installed

sub test_magick {
    my ($self) = @_;
    if ( !magick_perl_module(1) ) {
        my $dialog = Gtk3::MessageDialog->new( $self->get_ui('main_window'),
            'destroy-with-parent', 'error', 'ok', '' );
        $dialog->set_markup( __
"None of the perl modules <b>Graphics::Magick</b> and <b>Image::Magick</b> are installed: AMC won't work properly!"
        );
        $dialog->run;
        $dialog->destroy;
    }
}

# Warn if Notify is not available
sub test_libnotify {
    my ($self) = @_;

    return () if ( $self->{libnotify_error} );

    my $initted = eval { Notify::is_initted() };
    if ( !$initted ) {
        eval {
            Glib::Object::Introspection->setup(
                basename => 'Notify',
                version  => '0.7',
                package  => 'Notify'
            ) if ( !defined($initted) );

            # Set application name for notifications
            Notify::init('Auto Multiple Choice');
        };
        $self->{libnotify_error} = $@;

        if ( $self->{libnotify_error} && $self->{config}->get('notify_desktop') ) {
            debug "libnotify loading error: $self->{libnotify_error}";
            my $dialog = Gtk3::MessageDialog->new( $self->get_ui('main_window'),
                'destroy-with-parent', 'warning', 'ok', '' );
            $dialog->set_markup( __
"Please install <b>libnotify</b> to make desktop notifications available."
            );
            $dialog->run;
            $dialog->destroy;
            $self->{config}->set( 'notify_desktop', '' );
        }
    }
}

my $cb_model_vide_key =

    # TRANSLATORS: you can omit the [...] part, just here to explain context
    cb_model( '' => __p "(none) [No primary key found in association list]" );

my $cb_model_vide_code =
    
    # TRANSLATORS: you can omit the [...] part, just here to explain context
    cb_model( '' => __p "(none) [No code found in LaTeX file]" );

sub stores {
    my ($self) = @_;

    $self->store_register(

        liste_key     => $cb_model_vide_key,
        assoc_code    => $cb_model_vide_code,
        format_export => cb_model(
            map { $_ => "AMC::Export::register::$_"->name() } (@{$self->{config}->{export_modules}})
        ),
        filter => cb_model(
            map { $_ => "AMC::Filter::register::$_"->name() } (@filter_modules)
        ),

        after_export => cb_model(

# TRANSLATORS: One of the actions that can be done after exporting the marks. Here, do nothing more. This is a menu entry.
            "" => __ "that's all",

# TRANSLATORS: One of the actions that can be done after exporting the marks. Here, open the exported file. This is a menu entry.
            file => __ "open the file",

# TRANSLATORS: One of the actions that can be done after exporting the marks. Here, open the directory where the file is. This is a menu entry.
            dir => __ "open the directory",
        ),

        export_sort => cb_model(

# TRANSLATORS: One of the possible sorting criteria for students in the exported spreadsheet with scores: the student name. This is a menu entry.
            n => __ "name",

# TRANSLATORS: One of the possible sorting criteria for students in the exported spreadsheet with scores: the student sheet number. This is a menu entry.
            i => __ "exam copy number",

# TRANSLATORS: One of the possible sorting criteria for students in the exported spreadsheet with scores: the line where one can find this student in the students list file. This is a menu entry.
            l => __ "line in students list",

# TRANSLATORS: you can omit the [...] part, just here to explain context
# One of the possible sorting criteria for students in the exported spreadsheet with scores: the student mark. This is a menu entry.
            m => __p("mark [student mark, for sorting]"),
        ),

        regroupement_type => cb_model(

# TRANSLATORS: One of the possible way to group annotated answer sheets together to PDF files: make one PDF file per student, with all his pages. This is a menu entry.
            STUDENTS => __ "One file per student",

# TRANSLATORS: One of the possible way to group annotated answer sheets together to PDF files: make only one PDF with all students sheets. This is a menu entry.
            ALL => __ "One file for all students",
        ),

        regroupement_compose => cb_model(

# TRANSLATORS: One of the possible way to annotate answer sheets: here we only select pages where the student has written something (in separate answer sheet mode, these are the pages from the answer sheet and not the pages from the subject).
            0 => __ "Only pages with answers",

# TRANSLATORS: One of the possible way to annotate answer sheets: here we take the pages were the students has nothing to write (often question pages from a subject with separate answer sheet option) from the subject.
            1 => __ "Question pages from subject",

# TRANSLATORS: One of the possible way to annotate answer sheets: here we take the pages were the students has nothing to write (often question pages from a subject with separate answer sheet option) from the correction.
            2 => __ "Question pages from correction",
        ),

# TRANLATORS: For which students do you want to annotate papers? This is a menu entry.
        regroupement_copies => cb_model(
            ALL => __ "All students",

# TRANLATORS: For which students do you want to annotate papers? This is a menu entry.
            SELECTED => __ "Selected students",
        ),

    );
}

my @widgets_only_when_opened =
  (qw/cleanup_menu menu_projet_enreg menu_projet_modele/);

sub main_window {
    my ($self) = @_;

    my $glade_xml = __FILE__;
    $glade_xml =~ s/\.p[ml]$/.glade/i;

    $self->read_glade( $glade_xml,
        qw/main_window
          onglets_projet onglet_preparation
          documents_popover toggle_documents
          but_question but_solution but_indiv_solution but_catalog doc_line1
          prepare_docs prepare_layout prepare_src
          send_subject_config_button send_subject_action
          menu_popover header_bar
          state_layout state_layout_label
          state_docs state_docs_label
          state_unrecognized state_unrecognized_label
          state_marking state_marking_label state_assoc state_assoc_label
          state_overwritten state_overwritten_label
          button_edit_src
          button_unrecognized button_show_missing
          edition_latex
          onglet_notation onglet_saisie onglet_reports
          log_general commande avancement annulation button_mep_warnings
          liste_filename liste_edit liste_setfile liste_refresh
          menu_debug menu_popover menu_columns
          toggle_column_updated toggle_column_mse
          toggle_column_sensitivity toggle_column_file
          diag_tree state_capture state_capture_label
          maj_bareme regroupement_corriges
          groupe_model
          pref_assoc_c_assoc_code pref_assoc_c_liste_key
          export_c_format_export
          export_c_export_sort export_cb_export_include_abs
          config_export_modules standard_export_options
          notation_c_regroupement_type notation_c_regroupement_compose
          pref_prep_s_nombre_copies pref_prep_c_filter
          /, @widgets_only_when_opened
    );

    # Grid lines are not well-positioned in RTL environments, I don't know
    # why... so I remove them.
    if ( $self->get_ui('main_window')->get_direction() eq 'rtl' ) {
        debug "RTL mode: removing vertical grids";
        for (qw/documents diag inconnu/) {
            my $w = $self->{main}->get_object( $_ . '_tree' );
            $w->set_grid_lines('horizontal') if ($w);
        }
    }

    $self->get_ui('commande')->hide();
    $self->get_ui('menu_debug')->set_active( get_debug() ? 1 : 0 );

    $self->{learning} = AMC::Gui::Learning->new(
        config      => $self->{config},
        main_window => $self->get_ui('main_window')
    );

    $self->new_diagstore();
    $self->sort_diagstore();
    $self->show_diagstore();
    $self->set_diagtree();

    $self->set_export();
}

sub set_debug_mode {
    my ($self, $debug) = @_;
    set_debug($debug);
    if ($debug) {
        my $date = strftime( "%c", localtime() );
        debug( '#' x 40 );
        debug "# DEBUG - $date";
        debug( '#' x 40 );
        debug "GUI module is located at " . __FILE__;
    }
}

sub debug_set {
    my ($self) = @_;
    my $debug = $self->get_ui('menu_debug')->get_active;

    debug "DEBUG MODE : OFF" if ( !$debug );
    $self->set_debug_mode($debug);
    if ( $debug && !$self->{do_nothing} ) {
        debug "DEBUG MODE : ON";

        my $dialog = Gtk3::MessageDialog->new(
            $self->get_ui('main_window'),
            'destroy-with-parent',
            'info', 'ok',

            # TRANSLATORS: Message when switching to debugging mode.
            __("Debugging mode.") . " "

              . sprintf(

# TRANSLATORS: Message when switching to debugging mode. %s will be replaced with the path of the log file.
                __ "Debugging informations will be written in file %s.",
                AMC::Basic::debug_file()
              )
        );
        $dialog->run;
        $dialog->destroy;
    }
    Glib::Timeout->add( 500,
        sub { $self->get_ui('menu_popover')->hide(); return (0); } );
}

sub open_menu {
    my ($self) = @_;

    $self->get_ui('menu_popover')->show_all();
}

sub annule_apprentissage {
    my ($self) = @_;

    $self->{learning}->forget();
}

#########################################################################
# DATA CAPTURE REPORTS TABLE
#########################################################################

my %diag_menu = (

# TRANSLATORS: One of the popup menu that appears when right-clicking on a page in the data capture diagnosis table. Choosing this entry, an image will be opened to see where the corner marks were detected.
    page => { text => __ "page adjustment", icon => 'gtk-zoom-fit' },

# TRANSLATORS: One of the popup menu that appears when right-clicking on a page in the data capture diagnosis table. Choosing this entry, a window will be opened were the user can see all boxes on the scans and how they were filled by the students, and correct detection of ticked-or-not if needed.
    zoom => { text => __ "boxes zooms", icon => 'gtk-zoom-in' },
);

sub new_diagstore {
    my ($self) = @_;

    $self->{diag_store} = Gtk3::ListStore->new(
        'Glib::String', 'Glib::String', 'Glib::String', 'Glib::String',
        'Glib::String', 'Glib::String', 'Glib::String', 'Glib::String',
        'Glib::String', 'Glib::String', 'Glib::String', 'Glib::String'
    );
    $self->{diag_store}->set_sort_func( DIAG_EQM,   \&sort_num, DIAG_EQM );
    $self->{diag_store}->set_sort_func( DIAG_DELTA, \&sort_num, DIAG_DELTA );
    $self->{diag_store}
      ->set_sort_func( DIAG_SCAN_FILE, \&sort_string, DIAG_SCAN_FILE );
    $self->{diag_store}->set_sort_func( DIAG_ID,
        \&sort_from_columns,
        [
            { type => 'n', col => DIAG_ID_STUDENT },
            { type => 'n', col => DIAG_ID_COPY },
            { type => 'n', col => DIAG_ID_PAGE },
        ]
    );
}

sub sort_diagstore {
    my ($self) = @_;

    $self->{diag_store}->set_sort_column_id( DIAG_ID, 'ascending' );
}

sub show_diagstore {
    my ($self) = @_;

    $self->get_ui('diag_tree')->set_model($self->{diag_store});
}

sub set_diagtree {
    my ($self) = @_;

    my $diag_tree = $self->get_ui('diag_tree');

    my %capture_column = ();
    $self->{capture_column} = \%capture_column;

    my ( $renderer, $column );

    $renderer = Gtk3::CellRendererText->new;

    $column = Gtk3::TreeViewColumn->new_with_attributes(

# TRANSLATORS: This is the title of the column containing student/copy identifier in the table showing the results of data captures.
        __ "identifier",
        $renderer,
        text       => DIAG_ID,
        background => DIAG_ID_BACK
    );
    $column->set_sort_column_id(DIAG_ID);
    $diag_tree->append_column($column);

    $renderer = Gtk3::CellRendererText->new;

    $capture_column{updated} =

# TRANSLATORS: This is the title of the column containing data capture date/time in the table showing the results of data captures.
      Gtk3::TreeViewColumn->new_with_attributes( __ "updated", $renderer,
        text => DIAG_MAJ );
    $capture_column{updated}->set_sort_column_id(DIAG_MAJ_NUM);
    $diag_tree->append_column( $capture_column{updated} );

    $renderer = Gtk3::CellRendererText->new;

    $capture_column{mse} = Gtk3::TreeViewColumn->new_with_attributes(

# TRANSLATORS: This is the title of the column containing Mean Square Error Distance (some kind of mean distance between the location of the four corner marks on the scan and the location where they should be if the scan was not distorted at all) in the table showing the results of data captures.
        __ "MSE",
        $renderer,
        text       => DIAG_EQM,
        background => DIAG_EQM_BACK
    );
    $capture_column{mse}->set_sort_column_id(DIAG_EQM);
    $diag_tree->append_column( $capture_column{mse} );

    $renderer = Gtk3::CellRendererText->new;

    $capture_column{sensitivity} = Gtk3::TreeViewColumn->new_with_attributes(

# TRANSLATORS: This is the title of the column containing so-called "sensitivity" (an indicator telling the user if the darkness ratio of some boxes on the page are very near the threshold. A great value tells that some darkness ratios are very near the threshold, so that the capture is very sensitive to the threshold. A small value is a good thing) in the table showing the results of data captures.
        __ "sensitivity",
        $renderer,
        text       => DIAG_DELTA,
        background => DIAG_DELTA_BACK
    );
    $capture_column{sensitivity}->set_sort_column_id(DIAG_DELTA);
    $diag_tree->append_column( $capture_column{sensitivity} );

    $renderer = Gtk3::CellRendererText->new;
    $capture_column{file} =
      Gtk3::TreeViewColumn->new_with_attributes( __ "scan file",
        $renderer, text => DIAG_SCAN_FILE );
    $capture_column{file}->set_sort_column_id(DIAG_SCAN_FILE);
    $diag_tree->append_column( $capture_column{file} );

    $diag_tree->get_selection->set_mode('multiple');

    # Columns that should be hidden at startup:

    for my $c (qw/updated file/) {
        $self->get_ui( "toggle_column_" . $c )->set_active(0);
    }

    #

    $self->get_ui('diag_tree')->signal_connect(
        button_release_event => sub {
            my ( $w, $event ) = @_;
            $self->select_diagtree_line( $w, $event );
        }
    );
}

sub select_diagtree_line {
    my ( $self, $w, $event ) = self_first(@_);

    return 0 unless $event->button == 3;

    my ( $path, $column, $cell_x, $cell_y ) =
      $self->get_ui('diag_tree')->get_path_at_pos( $event->x, $event->y );
    if ($path) {
        my $iter = $self->{diag_store}->get_iter($path);
        my $id   = [ map { $self->{diag_store}->get( $iter, $_ ) }
              ( DIAG_ID_STUDENT, DIAG_ID_PAGE, DIAG_ID_COPY ) ];

        my $menu    = Gtk3::Menu->new;
        my $c       = 0;
        my @actions = ('page');

        # new zooms viewer

        $self->{project}->capture->begin_read_transaction('ZnIm');
        my @bi =
          grep {
            -f $self->{config}->{shortcuts}->absolu('%PROJET/cr/zooms') . "/"
              . $_
          } $self->{project}
          ->capture->zone_images( $id->[0], $id->[2], ZONE_BOX );
        $self->{project}->capture->end_transaction('ZnIm');

        if (@bi) {
            $c++;
            my $item = Gtk3::ImageMenuItem->new( $diag_menu{zoom}->{text} );
            $item->set_image(
                Gtk3::Image->new_from_icon_name(
                    $diag_menu{zoom}->{icon}, 'menu'
                )
            );
            $menu->append($item);
            $item->show;
            $item->signal_connect(
                activate => sub {
                    my ( undef, $sortkey ) = @_;
                    $self->zooms_display(@$id);
                },

                #                $_
            );
        } else {
            push @actions, 'zoom';
        }

        # page viewer and old zooms viewer

        foreach $a (@actions) {
            my $f;
            if ( $a eq 'page' ) {
                $self->{project}->capture->begin_read_transaction('gLIm');
                $f = $self->{config}->get_absolute('cr') . '/'
                  . $self->{project}->capture->get_layout_image(@$id);
                $self->{project}->capture->end_transaction('gLIm');
            } else {
                $f = $self->id2file( $id, $a, 'jpg' );
            }
            if ( -f $f ) {
                $c++;
                my $item =
                  Gtk3::ImageMenuItem->new( $diag_menu{$a}->{text} );
                $item->set_image(
                    Gtk3::Image->new_from_icon_name(
                        $diag_menu{$a}->{icon}, 'menu'
                    )
                );
                $menu->append($item);
                $item->show;
                $item->signal_connect(
                    activate => sub {
                        my ( undef, $sortkey ) = @_;
                        debug "Looking at $f...";
                        $self->commande_parallele(
                            $self->{config}->get('img_viewer'), $f );
                    },
                    $_
                );
            }
        }

        $menu->popup( undef, undef, undef, undef, $event->button, $event->time )
          if ( $c > 0 );
        return 1;    # stop propagation!

    }
}

# columns to be shown...

sub toggle_column {
    my ( $self, $item ) = self_first(@_);
    if ( $item->get_name() =~ /toggle_column_(.*)/ ) {
        my $type    = $1;
        my $checked = $item->get_active();
        if($self->{capture_column}->{$type}) {
            $self->{capture_column}->{$type}->set_visible($checked);
        } else {
            debug_and_stderr "WARNING: unknown capture_column $type";
        }
    } else {
        debug "ERROR: unknown toggle_column name: " . $item->get_name();
    }
}

sub detecte_analyse {
    my ( $self, %oo ) = (@_);
    my $iter;
    my $row;

    $self->new_diagstore();

    $self->get_ui('commande')->show();
    my $av_text = $self->get_ui('avancement')->get_text();
    my $frac;
    my $total;
    my $i;

    $self->{project}->capture->begin_read_transaction('ADCP');

    my $summary = $self->{project}->capture->summaries(
        darkness_threshold    => $self->{config}->get('seuil'),
        darkness_threshold_up => $self->{config}->get('seuil_up'),
        sensitivity_threshold => $self->{config}->get('seuil_sens'),
        mse_threshold         => $self->{config}->get('seuil_eqm')
    );

    $total = $#{$summary} + 1;
    $i     = 0;
    $frac  = 0;
    if ( $total > 0 ) {
        $self->get_ui('avancement')->set_text( __ "Looking for analysis..." );
        Gtk3::main_iteration while (Gtk3::events_pending);
    }
    for my $p (@$summary) {
        $self->{diag_store}->insert_with_values(
            $i,
            DIAG_ID,
            pageids_string( $p->{student}, $p->{page}, $p->{copy} ),
            DIAG_ID_STUDENT,
            $p->{student},
            DIAG_ID_PAGE,
            $p->{page},
            DIAG_ID_COPY,
            $p->{copy},
            DIAG_ID_BACK,
            $p->{color},
            DIAG_EQM,
            $p->{mse_string},
            DIAG_EQM_BACK,
            $p->{mse_color},
            DIAG_MAJ,
            format_date( $p->{timestamp} ),
            DIAG_MAJ_NUM,
            $p->{timestamp},
            DIAG_DELTA,
            $p->{sensitivity_string},
            DIAG_DELTA_BACK,
            $p->{sensitivity_color},
            DIAG_SCAN_FILE,
            path_to_filename( $p->{src} ),
        );
        if ( $i / $total >= $frac + .05 ) {
            $frac = $i / $total;
            $self->get_ui('avancement')->set_fraction($frac);
            Gtk3::main_iteration while (Gtk3::events_pending);
        }
    }

    $self->sort_diagstore();
    $self->show_diagstore();

    $self->get_ui('avancement')->set_text($av_text);
    $self->get_ui('avancement')->set_fraction(0) if ( !$oo{interne} );
    $self->get_ui('commande')->hide()            if ( !$oo{interne} );
    Gtk3::main_iteration while (Gtk3::events_pending);

    my $r = $self->update_analysis_summary();

    $self->{project}->capture->end_transaction('ADCP');

    # dialogue apprentissage :

    if ( $oo{apprend} ) {
        $self->{learning}->lesson( 'SAISIE_AUTO', $r );
    }

}

#########################################################################
# EXPORT
#########################################################################

# set export GUI for all modules

sub set_export {
    my ($self) = @_;

    for my $m ( @{ $self->{config}->{export_modules} } ) {
        my $x = "AMC::Export::register::$m"
          ->build_config_gui( $self->{ui}, $self->{prefs} );
        if ($x) {
            $self->{ui}->{ 'config_export_module_' . $m } = $x;
            $self->{ui}->{config_export_modules}->pack_start( $x, 0, 0, 0 );
        }
    }

}

sub maj_export {
    my ( $self, @args ) = self_first(@_);

    my $old_format = $self->{config}->get('format_export');

    $self->{prefs}->valide_options_for_domain( 'export', '', @args );

    if ( $self->{config}->key_changed("export_sort") ) {
        annotate_source_change( $self->{project}->capture, 1 );
    }

    debug "Format : " . $self->{config}->get('format_export');

    for ( @{ $self->{config}->{export_modules} } ) {
        if ( $self->get_ui( 'config_export_module_' . $_ ) ) {
            if ( $self->{config}->get('format_export') eq $_ ) {
                $self->get_ui( 'config_export_module_' . $_ )->show;
            } else {
                $self->get_ui( 'config_export_module_' . $_ )->hide;
            }
        }
    }

    my %hide =
      ( "AMC::Export::register::" . $self->{config}->get('format_export') )
      ->hide();
    for (qw/standard_export_options/) {
        if ( $hide{$_} ) {
            $self->get_ui($_)->hide();
        } else {
            $self->get_ui($_)->show();
        }
    }
}

sub choose_columns {
    my ($self, $type) = @_;

    AMC::Gui::ChooseColumns->new(
        parent_window => $self->get_ui('main_window'),
        config        => $self->{config},
        type          => $type,
        students_list => $self->{project}->students_list,
    );
}

sub choose_columns_current {
    my ($self) = @_;
    $self->choose_columns( lc( $self->{config}->get('format_export') ) );
}

sub exporte {
    my ($self) = @_;

    $self->maj_export();

    my $format  = $self->{config}->get('format_export');
    my @options = ();
    my $ext     = "AMC::Export::register::$format"->extension();
    if ( !$ext ) {
        $ext = lc($format);
    }
    my $type = "AMC::Export::register::$format"->type();
    my $code = $self->{config}->get('code_examen');
    $code = $self->{project}->name if ( !$code );

    my $output       = $self->{config}->{shortcuts}->absolu( '%PROJET/exports/' . $code . $ext );
    my @needs_module = ();

    my %ofc =
      "AMC::Export::register::$format"->options_from_config( $self->{config} );
    my $needs_catalog =
      "AMC::Export::register::$format"->needs_catalog( $self->{config} );
    for ( keys %ofc ) {
        push @options, "--option-out", $_ . '=' . $ofc{$_};
    }
    push @needs_module, "AMC::Export::register::$format"->needs_module();

    if (@needs_module) {

        # teste si les modules necessaires sont disponibles

        my @manque = ();

        for my $m (@needs_module) {
            if ( !check_install( module => $m ) ) {
                push @manque, $m;
            }
        }

        if (@manque) {
            debug 'Exporting to '
              . $format
              . ': Needs perl modules '
              . join( ', ', @manque );

            my $dialog = Gtk3::MessageDialog->new(
                $self->get_ui('main_window'),
                'destroy-with-parent',
                'error', 'ok',
                __(
"Exporting to '%s' needs some perl modules that are not installed: %s. Please install these modules or switch to another export format."
                ),
                "AMC::Export::register::$format"->name(),
                join( ', ', @manque )
            );
            $dialog->run;
            $dialog->destroy;

            return ();
        }
    }

    # If some data involving detailed results (concerning some
    # particular answers) is required, then check that the catalog
    # document is prepared, or propose to build it.  This way, answers
    # will be identified by the character drawn in the boxes in the
    # catalog document. These characters default to A, B, C and so on,
    # but can be others if requested in the source file.

    if ($needs_catalog) {
        if ( !$self->{project}->layout->nb_chars_transaction() ) {
            my $dialog = Gtk3::MessageDialog->new( $self->get_ui('main_window'),
                'destroy-with-parent', 'question', 'yes-no', '' );
            $dialog->set_markup( __
"When referring to a particular answer in the export, the letter used will be the one found in the catalog. However, the catalog has not yet been built. Do you want to build it now?"
            );
            $dialog->get_widget_for_response('yes')->get_style_context()
              ->add_class("suggested-action");
            my $reponse = $dialog->run;
            $dialog->destroy;
            if ( $reponse eq 'yes' ) {
                $self->{project}->update_catalog();
            }
        }
    }

    # wait for GUI update before going on with the table
    Glib::Idle->add(
        sub {
            $self->{project}->export(
                {
                    format        => $format,
                    output        => $output,
                    o             => \@options,
                    type          => $type,
                    callback      => \&export_done_callback,
                    callback_self => $self,
                }
            );
        },
        Glib::G_PRIORITY_LOW
    );
}

sub export_done_callback {
    my ( $self, $c, %data ) = self_first(@_);
    my $output = $c->{o}->{output};
    my $type   = $c->{o}->{type};
    if ( -f $output ) {

        # shows export messages

        my $t = $c->higher_message_type();
        if ($t) {
            my $dialog = Gtk3::MessageDialog->new(
                $self->get_ui('main_window'),
                'destroy-with-parent',
                ( $t eq 'ERR' ? 'error' : $t eq 'WARN' ? 'warning' : 'info' ),
                'ok',
                join( "\n", $c->get_messages($t) )
            );
            $dialog->run;
            $dialog->destroy;
        }

        if ( $self->{config}->get('after_export') eq 'file' ) {
            my $cmd = commande_accessible(
                [
                    $self->{config}->get( $type . '_viewer' ),
                    $self->{config}->get( $type . '_editor' ),
                    'xdg-open',
                    'open'
                ]
            );
            $self->commande_parallele( $cmd, $output ) if ($cmd);
        } elsif ( $self->{config}->get('after_export') eq 'dir' ) {
            view_dir(
                $self->{config}->{shortcuts}->absolu('%PROJET/exports/') );
        }
    } else {
        my $dialog = Gtk3::MessageDialog->new( $self->get_ui('main_window'),
            'destroy-with-parent',
            'warning', 'ok',
            __ "Export to %s did not work: file not created...", $output );
        $dialog->run;
        $dialog->destroy;
    }
}

#########################################################################
# HELPERS
#########################################################################

# reorder arguments to have $self first

sub self_first {
    my (@args) = @_;
    if (@args) {
        if ( $args[0]->isa("AMC::Gui") ) {

            # Called from AMC: $self is first
            return (@args);
        } elsif ( $args[-1]->isa("AMC::Gui") ) {

            # Called from a Gtk signal : $self is the last argument
            my $self = pop @args;
            return ( $self, @args );
        } elsif ( $args[0]->isa("AMC::Gui::Commande" ) ) {
            # Called from a AMC::Gui::commande callback
            return ( $args[0]->{o}->{callback_self}, @args );
        } else {
            my ($package, $filename, $line) = caller;
            die "Can't find self at $package $filename L$line: " . join( ", ", @args );
        }
    } else {
        return ();
    }
}

sub mini { ( $_[0] < $_[1] ? $_[0] : $_[1] ) }

sub best_filter_for_file {
    my ($file) = @_;
    my $mmax   = '';
    my $max    = -10;
    for my $m (@filter_modules) {
        my $c = "AMC::Filter::register::$m"->claim($file);
        if ( $c > $max ) {
            $max  = $c;
            $mmax = $m;
        }
    }
    return ($mmax);
}

sub glib_project_name {
    my ($self) = @_;
    return ( glib_filename( $self->{project}->name ) );
}

# Open directory (in another application)

sub view_dir {
    my ( $self, $dir ) = @_;

    debug "Look at $dir";
    my $seq = 0;
    my @c   = map { $seq += s/[%]d/$dir/g; $_; }
      split( /\s+/, $self->{config}->get('dir_opener') );
    push @c, $dir if ( !$seq );

    $self->commande_parallele(@c);
}

sub open_exports_dir {
    my ($self) = @_;

    $self->view_dir( $self->{config}->{shortcuts}->absolu('%PROJET/exports/') );
}

sub open_templates_dir {
    my ($self) = @_;

    $self->view_dir( $self->{config}->get('rep_modeles') );
}

sub regarde_regroupements {
    my ($self) = @_;

    $self->view_dir( $self->{config}->get_absolute('cr') . "/corrections/pdf" );
}

sub plugins_browse {
    my ($self) = @_;

    $self->view_dir( $self->{config}->subdir("plugins") );
}

sub check_for_tmp_disk_space {
    my ( $self, $needs_mo ) = @_;
    my $tmp_path = tmpdir();
    my $space    = free_disk_mo($tmp_path);
    if ( defined($space) && $space < $needs_mo ) {
        my $dialog = Gtk3::MessageDialog->new( $self->get_ui('main_window'),
            'destroy-with-parent', 'error', 'ok', '' );
        $dialog->set_markup(
            sprintf(
                (
                    __
"There is too little space left in the temporary disk directory (%s). <b>Please clean this directory and try again.</b>"
                ),
                $tmp_path
            )
        );
        $dialog->run;
        $dialog->destroy;
        return 0;
    }
    return 1;
}

sub commande_parallele {
    my ( $self, @c ) = (@_);
    if ( commande_accessible( $c[0] ) ) {
        my $pid = fork();
        if ( $pid == 0 ) {
            debug "Command // [$$] : " . join( " ", @c );
            exec(@c)
              || debug "Exec $$ : error";
            exit(0);
        }
    } else {
        my $dialog = Gtk3::MessageDialog->new( $self->get_ui('main_window'),
            'destroy-with-parent', 'error', 'ok', '' );
        $dialog->set_markup(
            sprintf(
                __
"Following command could not be run: <b>%s</b>, perhaps due to a poor configuration?",
                $c[0]
            )
        );
        $dialog->run;
        $dialog->destroy;

    }
}

sub id2file {
    my ( $self, $id, $prefix, $extension ) = (@_);
    $id =~ s/\+//g;
    $id =~ s/\//-/g;
    return ( $self->{config}->get_absolute('cr') . "/$prefix-$id.$extension" );
}

sub file_maj {
    my (@f)     = @_;
    my $present = 1;
    my $oldest  = 0;
    for my $file (@f) {
        if ( $file && -f $file ) {
            if ( -r $file ) {
                my @s = stat($file);
                $oldest = $s[9] if ( $s[9] > $oldest );
            } else {
                return ('UNREADABLE');
            }
        } else {
            return ('NOTFOUND');
        }
    }
    return ( format_date($oldest) );
}

sub fich_options {
    my ( $self, $nom, $rp ) = @_;

    $rp = $self->{config}->get('rep_projets') if ( !$rp );
    $rp .= "/$nom/options.xml";

    debug "Options file: " . show_utf8($rp);

    return ($rp);
}

sub set_state {
    my ( $self, $k, $type, $message ) = @_;
    my $w = $self->get_ui( 'state_' . $k );
    if ( defined($type) && $w ) {
        if ( $type eq 'none' ) {
            $w->hide();
        } else {
            $w->show();
            $w->set_message_type($type);
        }
    }
    $w = $self->get_ui( 'state_' . $k . '_label' );
    $w->set_text($message)
      if ( defined($message) && $w );
}

sub cursor_wait {
    my ($self) = @_;

    $self->{cursor_watch} = Gtk3::Gdk::Cursor->new('GDK_WATCH')
      if ( !$self->{cursor_watch} );
    $self->get_ui('main_window')->get_window()
      ->set_cursor( $self->{cursor_watch} )
      if ( $self->get_ui('main_window') );
    Gtk3::main_iteration while (Gtk3::events_pending);
}

sub cursor_standard {
    my ($self) = @_;

    $self->get_ui('main_window')->get_window()->set_cursor(undef)
      if ( $self->get_ui('main_window') );
    Gtk3::main_iteration while (Gtk3::events_pending);
}

sub format_markup {
    my ( $self, $t ) = @_;
    $t =~ s/\&/\&amp;/g;
    return ($t);
}

sub commande_annule {
    my ($self) = @_;
    $self->{project}->commande_annule();
}

sub clear_processing {
    my ($self, $steps) = @_;
    my $next    = '';
    my %s       = ();
    for my $k (qw/doc mep capture mark assoc/) {
        if ( $steps =~ /\b$k:/ ) {
            $next = 1;
            $s{$k} = 1;
        } elsif ( $next || $steps =~ /\b$k\b/ ) {
            $s{$k} = 1;
        }
    }

    if ( $s{doc} ) {
        for (qw/question solution setting catalog/) {
            my $f = $self->{config}->get_absolute( 'doc_' . $_ );
            unlink($f) if ( -f $f );
        }
        $self->detecte_documents();
    }

    delete( $s{doc} );
    return () if ( !%s );

    # data to remove...

    $self->{project}->data->begin_transaction('CLPR');

    if ( $s{mep} ) {
        $self->{project}->layout->clear_all;
    }

    if ( $s{capture} ) {
        $self->{project}->capture->clear_all;
    }

    if ( $s{mark} ) {
        $self->{project}->scoring->clear_strategy;
        $self->{project}->scoring->clear_score;
    }

    if ( $s{assoc} ) {
        $self->{project}->association->clear;
    }

    $self->{project}->data->end_transaction('CLPR');

    # files to remove...

    if ( $s{capture} ) {

        # remove zooms
        remove_tree(
            $self->{config}->{shortcuts}->absolu('%PROJET/cr/zooms'),
            { verbose => 0, safe => 1, keep_root => 1 }
        );

        # remove namefield extractions and page layout image
        my $crdir = $self->{config}->{shortcuts}->absolu('%PROJET/cr');
        opendir( my $dh, $crdir );
        my @cap_files = grep { /^(name-|page-)/ } readdir($dh);
        closedir($dh);
        for (@cap_files) {
            unlink "$crdir/$_";
        }
    }

    # update gui...

    if ( $s{mep} ) {
        $self->detecte_mep();
    }
    if ( $s{capture} ) {
        $self->detecte_analyse();
    }
    if ( $s{mark} ) {
        $self->noter_resultat();
    }
    if ( $s{assoc} ) {
        $self->assoc_state();
    }
}

## Notifications

sub notify_end_of_work {
    my ( $self, $action, $message ) = @_;

    if ( $self->{config}->get( 'notify_' . $action ) ) {
        if ( $self->{config}->get('notify_desktop') ) {
            if ( $self->{libnotify_error} ) {
                debug "Notification ignored: $self->{libnotify_error}";
            } else {
                eval {
                    my $notification =
                      Notify::Notification->new( 'Auto Multiple Choice',
                        $message, '/usr/share/auto-multiple-choice/icons/auto-multiple-choice.svg' );
                    $notification->show;
                };
                $self->{libnotify_error} = $@;
            }
        }
        if ( $self->{config}->get('notify_command') ) {
            my @cmd = map { s/[%]m/$message/g; s/[%]a/$action/g; $_; }
              quotewords( '\s+', 0, $self->{config}->get('notify_command') );
            if ( commande_accessible( $cmd[0] ) ) {
                commande_parallele(@cmd);
            } else {
                debug
                  "ERROR: command '$cmd[0]' not found when trying to notify";
            }
        }
    }
}

#########################################################################
# DATA CAPTURE
#########################################################################

### Actions des boutons de la partie SAISIE

sub saisie_manuelle {
    my ( $self, $w, $event, $regarder ) = self_first(@_);

    $self->{project}->layout->begin_read_transaction('PGCN');
    my $c = $self->{project}->layout->pages_count();
    $self->{project}->layout->end_transaction('PGCN');
    if ( $c > 0 ) {

        if ( !$regarder ) {

            # if auto_capture_mode is not set, ask the user...
            my $ok = AMC::Gui::AutoCapture->new(
                parent_window => $self->get_ui('main_window'),
                config        => $self->{config},
            )->choose_mode();
            return () if ( !$ok );
        }

        # go for capture

        my $gm = AMC::Gui::Manuel::new(
            multiple         => $self->{config}->get('auto_capture_mode'),
            'data-dir'       => $self->{config}->get_absolute('data'),
            'project-dir'    => $self->{config}->{shortcuts}->absolu('%PROJET'),
            sujet            => $self->{config}->get_absolute('doc_question'),
            etud             => '',
            dpi              => $self->{config}->get('saisie_dpi'),
            seuil            => $self->{config}->get('seuil'),
            seuil_up         => $self->{config}->get('seuil_up'),
            seuil_sens       => $self->{config}->get('seuil_sens'),
            seuil_eqm        => $self->{config}->get('seuil_eqm'),
            global           => 0,
            encodage_interne => $self->{config}->get('encodage_interne'),
            image_type       => $self->{config}->get('manuel_image_type'),
            retient_m        => 1,
            editable         => ( $regarder ? 0 : 1 ),
            en_quittant      => (
                $regarder
                ? ''
                : sub { detecte_analyse(); assoc_state(); }
            ),
            size_monitor => {
                config => $self->{config},
                key    => "global:"
                  . ( $regarder ? 'checklayout' : 'manual' )
                  . '_window_size'
            },
            invalid_color_name => $self->{config}->get("view_invalid_color"),
            empty_color_name   => $self->{config}->get("view_empty_color"),
        );
    } else {
        my $dialog = Gtk3::MessageDialog->new( $self->get_ui('main_window'),
            'destroy-with-parent', 'error', 'ok', '' );
        $dialog->set_markup(
            __("No layout for this project.") . " "

              . sprintf(

# TRANSLATORS: Here, the first %s will be replaced with "Layout detection" (a button title), and the second %s with "Preparation" (the tab title where one can find this button).
                __(
"Please use button <i>%s</i> in <i>%s</i> before manual data capture."
                ),
                __ "Layout detection",
                __ "Preparation"
              )
        );
        $dialog->run;
        $dialog->destroy;
    }
}

sub saisie_automatique {
    my ($self) = @_;

    AMC::Gui::AutoCapture->new(
        parent_window => $self->get_ui('main_window'),
        config        => $self->{config},
        capture       => $self->{project}->capture,
        callback_self => $self,
        callback      => \&auto_data_capture_callback,
    )->dialog();

}

sub auto_data_capture_callback {
    my ($args) = @_;
    my $self = $args->{self};

    $self->clear_old( 'diagnostic',
        $self->{config}->{shortcuts}->absolu('%PROJET/cr/diagnostic') );

    $self->get_ui('annulation')->set_sensitive(1);

    $self->{overwritten} = 0;

    $self->analyse_call(
        f         => $args->{files},
        getimages => 1,
        copy => ( $args->{copy_files} ? $self->{config}->{shortcuts}->absolu('scans/') : '' ),
        text => __("Automatic data capture..."),
        progres => 'analyse',
        allocate =>
          ( $self->{config}->get('allocate_ids') ? $args->{mcopy} : 0 ),
        overwritten => \$self->{overwritten},
        fin         => \&auto_data_capture_final_callback,
    );

}

# Auto data capture STEP 1 : detect PDF forms

sub analyse_call {
    my ( $self, %oo ) = @_;

    # meeds a little tmp disk space (for zooms), and first decent space
    # for AMC-getimages...
    return ()
      if ( !$self->check_for_tmp_disk_space( $oo{getimages} ? 20 : 2 ) );

    $oo{callback}      = \&analyse_call_callback;
    $oo{callback_self} = $self;

    $self->{project}->data_capture_detect_pdfform(%oo);
}

sub analyse_call_callback {
    my ( $self, $c, %data ) = self_first(@_);

    ${ $c->{o}->{overwritten} } += $c->variable('overwritten')
      if ( $c->{o}->{overwritten} && $c->variable('overwritten') );
    if ( !$data{cancelled} ) {
        $self->analyse_call_images( %{ $c->{o} } );
    }
}

# Auto data capture STEP 2 : extract scan images

sub analyse_call_images {
    my ( $self, %oo ) = @_;

    $oo{callback} = \&analyse_call_images_callback;
    $self->{project}->data_capture_get_images(%oo);
}

sub analyse_call_images_callback {
    my ( $self, $c, %data ) = self_first(@_);

    if ( !$data{cancelled} ) {
        $self->analyse_call_go( %{ $c->{o} } );
    }
}

# Auto data capture STEP 3 (end) : scan images analysis itself

sub analyse_call_go {
    my ( $self, %oo ) = @_;

    $oo{callback} = \&analyse_call_go_callback;
    $self->{project}->data_capture_from_images(%oo);
}

sub analyse_call_go_callback {
    my ( $self, $c, %data ) = self_first(@_);

    if ( !$c->{o}->{diagnostic} ) {
        $self->report_analyse_errors($c);
    }
    debug "Overall [SCAN] overwritten pages @" . $c . ": "
      . ( $c->variable('overwritten') || "(none)" );
    ${ $c->{o}->{overwritten} } += $c->variable('overwritten')
      if ( $c->{o}->{overwritten} && $c->variable('overwritten') );
    debug "Calling original <fin> hook from analyse_call_go";
    &{ $c->{o}->{fin} }( $c, %data )
      if ( $c->{o}->{fin} );
}

sub auto_data_capture_final_callback {
    my ( $self, $c, %data ) = self_first(@_);

    close( $c->{o}->{fh} );
    my @err = $c->erreurs();
    $self->decode_name_fields();
    $self->detecte_analyse( apprend => 1 );
    $self->assoc_state();
    if ( !$data{cancelled} && !@err ) {
        $self->notify_end_of_work( 'capture',
            __ "Automatic data capture has been completed" );
    }
    my $ov = ${ $c->{o}->{overwritten} };
    if ( $ov > 0 ) {
        my $dialog = Gtk3::MessageDialog->new( $self->get_ui('main_window'),
            'destroy-with-parent', 'warning', 'ok', '' );
        $dialog->set_markup(
            sprintf(
                __
"Some of the pages you submitted (%d of them) have already been processed before. Old data has been overwritten.",
                $ov
            )
        );
        $dialog->run;
        $dialog->destroy;
    }
}

sub report_analyse_errors {
    my ( $self, $c ) = @_;
    my @err = $c->erreurs();
    if (@err) {
        debug "Errors with AMC-analyse!";
        $self->notify_end_of_work( 'capture', __("Data capture errors") );

        my $message = __("AMC had problems with your scans.");

        $message .= "\n\n"
          . __("<b>Errors</b>") . "\n"
          . join( "\n",
            map { $self->format_markup($_) } ( @err[ 0 .. mini( 9, $#err ) ] ) )
          . (
            $#err > 9
            ? "\n\n<i>(" . __("Only first ten errors written") . ")</i>"
            : ""
          );

        $message .=
          "\n\n<b>" . __("Please have a look at these scans.") . "</b>";

        debug($message);
        my $dialog = Gtk3::MessageDialog->new( $self->get_ui('main_window'),
            'destroy-with-parent', 'error', 'ok', '' );
        $dialog->set_markup($message);
        $dialog->run;
        $dialog->destroy;
    }
    return (@err);
}

sub update_analysis_summary {
    my ($self) = @_;

    my $n = $self->{project}->capture->n_pages;

    my %r = $self->{project}->capture->counts;

    $r{npages} = $n;

    my $failed_nb =
      $self->{project}
      ->capture->sql_single( $self->{project}->capture->statement('failedNb') );

    my $ow = $self->{project}->capture->n_overwritten || 0;

    $self->get_ui('onglet_notation')->set_sensitive( $n > 0 );

    # resume

    my $tt = '';
    my $ok = 'info';
    if ( $r{incomplete} ) {
        $tt = sprintf(
            __ "Data capture from %d complete papers and %d incomplete papers",
            $r{complete}, $r{incomplete} );
        $ok = 'error';
        $self->get_ui('button_show_missing')->show();
    } elsif ( $r{complete} ) {
        $tt =
          sprintf( __("Data capture from %d complete papers"), $r{complete} );
        $ok = 'info';
        $self->get_ui('button_show_missing')->hide();
    } else {

     # TRANSLATORS: this text points out that no data capture has been made yet.
        $tt = sprintf( __ "No data" );
        $ok = 'error';
        $self->get_ui('button_show_missing')->hide();
    }
    $self->set_state( 'capture', $ok, $tt );

    if ( $ow > 0 ) {
        $self->set_state( 'overwritten', 'warning',
            sprintf( __ "Overwritten pages: %d", $ow ) );
        $self->get_ui('state_overwritten')->show();
    } else {
        $self->get_ui('state_overwritten')->hide();
    }

    if ( $failed_nb <= 0 ) {
        if ( $r{complete} ) {
            $tt = __ "All scans were properly recognized.";
            $ok = 'none';
        } else {
            $tt = "";
            $ok = 'none';
        }
    } else {
        $tt = sprintf( __ "%d scans were not recognized.", $failed_nb );
        $ok = 'question';
    }
    $self->set_state( 'unrecognized', $ok, $tt );

    return ( \%r );
}

sub show_missing_pages {
    my ($self) = @_;

    $self->{project}->capture->begin_read_transaction('cSMP');
    my %r = $self->{project}->capture->counts;
    $self->{project}->capture->end_transaction('cSMP');

    my $l  = '';
    my @sc = ();
    for my $p ( @{ $r{missing} } ) {
        if ( $sc[0] != $p->{student} || $sc[1] != $p->{copy} ) {
            @sc = ( $p->{student}, $p->{copy} );
            $l .= "\n";
        }
        $l .= "  " . pageids_string( $p->{student}, $p->{page}, $p->{copy} );
    }

    my $dialog = Gtk3::MessageDialog->new( $self->get_ui('main_window'),
        'destroy-with-parent', 'info', 'ok', '' );
    $dialog->set_markup( "<b>"
          . ( __ "Pages that miss data capture to complete students sheets:" )
          . "</b>"
          . $l );
    $dialog->run;
    $dialog->destroy;
}

sub overwritten_clear {
    my ($self) = @_;

    $self->{project}->capture->begin_transaction('OWcl');
    $self->{project}->capture->clear_overwritten();
    $self->update_analysis_summary();
    $self->{project}->capture->end_transaction('OWcl');
}

sub overwritten_look {
    my ($self) = @_;

    AMC::Gui::Overwritten->new(
        parent_window => $self->get_ui('main_window'),
        config        => $self->{config},
        capture       => $self->{project}->capture
    );
}

sub open_unrecognized {
    my ($self) = @_;

    AMC::Gui::Unrecognized->new(
        parent_window            => $self->get_ui('main_window'),
        config                   => $self->{config},
        capture                  => $self->{project}->capture,
        callback_self            => $self,
        update_analysis_callback => \&update_analysis_summary,
        analysis_callback        => \&analyse_call,
    );

}

#########################################################################
# DECODE NAME FIELDS
#########################################################################

sub decode_name_fields_again {
    my ($self) = @_;
    $self->decode_name_fields(1);
}

sub decode_name_fields {
    my ( $self, $all ) = @_;

    my $type = $self->{config}->get('name_field_type');
    if ($type) {
        my $reg  = "AMC::Decoder::register::$type"->new();
        my $deps = $reg->check_dependencies();
        if ( !$deps->{ok} ) {
            my $message = sprintf(
                __(
"You selected the decoder \"<i>%s</i>\", which requires some tools that are missing on your system:"
                ),
                $reg->name()
            ) . "\n";
            if ( @{ $deps->{perl_modules} } ) {
                $message .= __("<b>Perl module(s):</b>") . " "
                  . join( ", ", @{ $deps->{perl_modules} } ) . "\n";
            }
            if ( @{ $deps->{commands} } ) {
                $message .= __("<b>Command(s):</b>") . " "
                  . join( ", ", @{ $deps->{commands} } ) . "\n";
            }
            $message .= __ "Install these dependencies and try again";

            my $dialog = Gtk3::MessageDialog->new( $self->get_ui('main_window'),
                'destroy-with-parent', 'error', 'ok', '' );
            $dialog->set_markup($message);
            $dialog->run;
            $dialog->destroy;

            return ();
        }
    }

    $self->{project}->decode_name_fields(
        all           => $all,
        callback_self => $self,
        callback      => \&decode_name_fields_callback,
    );

}

sub decode_name_fields_callback {
    my ($self, $c) = self_first(@_);

    $self->update_available_codes();
}

my $assoc_code_name = {

# TRANSLATORS: menu item when choosing the code to use for association from the completed answer sheets. This item corresponds to pre-association (each student has an individualized sheet)
    '<preassoc>' => __ "Pre-association",

# TRANSLATORS: menu item when choosing the code to use for association from the completed answer sheets. This item corresponds to the decoded name field (eg. when a barcode identifying the student has been sticked in the name field)
    '_namefield' => __ "Decoded name field",
};

sub update_available_codes {
    my ($self) = @_;

    $self->{project}->scoring->begin_read_transaction('CODE');

    my @codes     = $self->{project}->scoring->codes;
    my $pre_assoc = $self->{project}->layout->pre_association();

    $self->{project}->scoring->end_transaction('CODE');

    if ($pre_assoc) {
        push @codes, '<preassoc>';
    }

    debug "Codes : " . join( ',', @codes );

    # TRANSLATORS: you can omit the [...] part, just here to explain context
    my @cbs = ( '' => __p("(none) [No code found in LaTeX file]") );
    if ( my $el = get_enc( $self->{config}->get('encodage_latex') ) ) {
        push @cbs,
          map { $_ => $assoc_code_name->{$_} || decode( $el->{iso}, $_ ) }
          (@codes);
    } else {
        push @cbs, map { $_ => $assoc_code_name->{$_} || $_ } (@codes);
    }
    $self->store_register( assoc_code => cb_model(@cbs) );
    $self->{prefs}->transmet_pref(
        $self->{main},
        prefix => 'pref_assoc',
        keys   => ['project:assoc_code']
    );
}

#########################################################################
# CONTEXT MENU ON DATA CAPTURE REPORTS
#########################################################################

sub zooms_display {
    my ( $self, $student, $page, $copy, $forget_it ) = @_;

    debug "Zooms view for " . pageids_string( $student, $page, $copy ) . "...";
    my $zd = $self->{config}->{shortcuts}->absolu('%PROJET/cr/zooms');
    debug "Zooms directory $zd";
    if (   $self->{zooms_window}
        && $self->{zooms_window}->actif )
    {
        $self->{zooms_window}
          ->page( [ $student, $page, $copy ], $zd, $forget_it );
    } elsif ( !$forget_it ) {
        $self->{zooms_window} = AMC::Gui::Zooms::new(
            seuil     => $self->{config}->get('seuil'),
            seuil_up  => $self->{config}->get('seuil_up'),
            n_cols    => $self->{config}->get('zooms_ncols'),
            zooms_dir => $zd,
            page_id   => [ $student, $page, $copy ],
            'size-prefs', $self->{config},
            encodage_interne => $self->{config}->get('encodage_interne'),
            data             => $self->{project}->capture,
            'cr-dir'         => $self->{config}->get_absolute('cr'),
            list_view        => $self->get_ui('diag_tree'),
            global_options   => $self->{config},
            prefs            => $self->{prefs},
        );
    }
}

sub zooms_line_base {
    my ( $self, $forget_it ) = @_;
    my @selected = $self->get_ui('diag_tree')->get_selection->get_selected_rows;
    my $first_selected = $selected[0]->[0];
    if ( defined($first_selected) ) {
        my $iter = $self->{diag_store}->get_iter($first_selected);
        my $id   = $self->{diag_store}->get( $iter, DIAG_ID );
        $self->zooms_display(
            (
                map { $self->{diag_store}->get( $iter, $_ ) }
                  ( DIAG_ID_STUDENT, DIAG_ID_PAGE, DIAG_ID_COPY )
            ),
            $forget_it
        );
    }
}

sub zooms_line {
    my ($self) = @_;

    $self->zooms_line_base(1);
}

sub zooms_line_open {
    my ($self) = @_;

    $self->zooms_line_base(0);
}

sub layout_line {
    my ($self) = @_;

    my @selected = $self->{diag_tree}->get_selection->get_selected_rows;
    for my $s ( @{ $selected[0] } ) {
        my $iter = $self->{diag_store}->get_iter($s);
        my @id   = map { $self->{diag_store}->get( $iter, $_ ); }
          ( DIAG_ID_STUDENT, DIAG_ID_PAGE, DIAG_ID_COPY );
        $self->{project}->capture->begin_read_transaction('Layl');
        my $f = $self->{config}->get_absolute('cr') . '/'
          . $self->{project}->capture->get_layout_image(@id);
        $self->{project}->capture->end_transaction('Layl');

        $self->commande_parallele( $self->{config}->get('img_viewer'), $f )
          if ( -f $f );
    }
}

sub delete_line {
    my ($self) = @_;

    my @selected = $self->get_ui('diag_tree')->get_selection->get_selected_rows;
    my $f;
    if ( @{ $selected[0] } ) {
        my $dialog = Gtk3::MessageDialog->new( $self->get_ui('main_window'),
            'destroy-with-parent', 'question', 'yes-no', '' );
        $dialog->set_markup(
            sprintf(
                (
                    __
"You requested to delete all data capture results for %d page(s)"
                ),
                1 + $#{ $selected[0] }
              )
              . "\n" . '<b>'
              . (
                __
"All data and image files related to these pages will be deleted."
              )
              . "</b>\n"
              . ( __ "Do you really want to continue?" )
        );
        $dialog->get_widget_for_response('yes')->get_style_context()
          ->add_class("destructive-action");
        my $reponse = $dialog->run;
        $dialog->destroy;
        if ( $reponse eq 'yes' ) {
            my @iters = ();
            $self->{project}->capture->begin_transaction('rmAN');
            for my $s ( @{ $selected[0] } ) {
                my $iter = $self->{diag_store}->get_iter($s);
                my @id   = map { $self->{diag_store}->get( $iter, $_ ); }
                  ( DIAG_ID_STUDENT, DIAG_ID_PAGE, DIAG_ID_COPY );
                debug "Removing data capture for " . pageids_string(@id);
                #
                # 1) get image files generated, and remove them
                #
                my $crdir = $self->{config}->get_absolute('cr');
                my @files = ();
                #
                # scan file
                push @files,
                  $self->{config}->{shortcuts}
                  ->absolu( $self->{project}->capture->get_scan_page(@id) );
                #
                # layout image, in cr directory
                push @files,
                  $crdir . '/'
                  . $self->{project}->capture->get_layout_image(@id);
                #
                # annotated scan
                if ( my $a = $self->{project}->capture->get_annotated_page(@id) ) {
                    push @files, $crdir . '/corrections/jpg/' . $a;
                }
                #
                # zooms
                push @files,
                  map { $crdir . '/zooms/' . $_ } grep { defined($_) }
                  ( $self->{project}->capture->get_zones_images( @id, ZONE_BOX )
                  );
                #
                for (@files) {
                    if ( -f $_ ) {
                        debug "Removing $_";
                        unlink($_);
                    }
                }
                #
                # 2) remove data from database
                #
                $self->{project}->capture->delete_page_data(@id);

                if ( $self->{config}->get('auto_capture_mode') == 1 ) {
                    $self->{project}
                      ->scoring->delete_scoring_data( @id[ 0, 2 ] );
                    $self->{project}
                      ->association->delete_association_data( @id[ 0, 2 ] );
                }

                push @iters, $iter;
            }

            for (@iters) { $self->{diag_store}->remove($_); }
            $self->update_analysis_summary();
            $self->{project}->capture->end_transaction('rmAN');

            $self->assoc_state();
        }
    }
}

#########################################################################
# ASSOCIATION
#########################################################################

sub valide_options_association {
    my ($self, @args) = self_first(@_);
    $self->{previous_liste_key} = $self->{config}->get('liste_key');
    $self->{prefs}->valide_options_for_domain( 'pref_assoc', '', @args );
}

sub choisit_liste {
    my ($self) = @_;

    AMC::Gui::StudentsList->new(
        parent_window => $self->get_ui('main_window'),
        config        => $self->{config},
        callback_self => $self,
        callback      => \&valide_liste
    )->dialog();

}

sub edite_liste {
    my ($self) = @_;

    my $f = $self->{config}->get_absolute('listeetudiants');
    debug "Editing $f...";
    $self->commande_parallele( $self->{config}->get('txt_editor'), $f );
}

sub students_list_show {
    my ($self) = @_;

    $self->get_ui('liste_refresh')->show();
    $self->{monitor}->remove_key( 'type', 'StudentsList' );
}

sub students_list_hide {
    my ($self) = @_;

    $self->get_ui('liste_refresh')->hide();
    $self->{monitor}->remove_key( 'type', 'StudentsList' );
    $self->{monitor}->add_file(
        $self->{config}->get_absolute('listeetudiants'),
        sub { $self->students_list_show(); },
        type => 'StudentsList'
    ) if ( $self->{config}->get('listeetudiants') );
}

sub valide_liste {
    my ( $self, %oo ) = @_;

    $oo{prefix} = 'pref_assoc'   if ( !$oo{prefix} );
    $oo{gui}    = $self->{main}  if ( !$oo{gui} );
    $oo{key}    = 'liste_key'    if ( !$oo{key} );
    $oo{prefs}  = $self->{prefs} if ( !$oo{prefs} );

    debug "* valide_liste";

    if ( defined( $oo{set} ) && !$oo{nomodif} ) {
        $self->{config}->set( 'listeetudiants',
            $self->{config}->{shortcuts}->relatif( $oo{set} ) );
    }

    my $fl = $self->{config}->get_absolute('listeetudiants');
    $fl = '' if ( !$self->{config}->get('listeetudiants') );

    my $fn = $fl;
    $fn =~ s/.*\///;

    # For proper markup rendering escape '<', '>' and '&' characters
    # in filename with \<, \gt;, and \&
    $fn = Glib::Markup::escape_text( glib_filename($fn) );

    if ( !$oo{nolabel} ) {
        if ($fl) {
            $self->get_ui('liste_filename')->set_markup("<b>$fn</b>");
            $self->get_ui('liste_filename')
              ->set_tooltip_text( glib_filename($fl) );
            for (qw/liste_edit/) {
                $self->get_ui($_)->set_sensitive(1);
            }
        } else {

            # TRANSLATORS: Names list file : (none)
            $self->get_ui('liste_filename')->set_markup( __ "(none)" );
            $self->get_ui('liste_filename')->set_tooltip_text('');
            for (qw/liste_edit/) {
                $self->get_ui($_)->set_sensitive(0);
            }
        }
    }

    my ( $err, $errlig ) = $self->{project}->set_students_list($fl);

    if ($err) {
        $self->students_list_show();
        if ( !$oo{noinfo} ) {
            my $dialog = Gtk3::MessageDialog->new( $self->get_ui('main_window'),
                'destroy-with-parent', 'error', 'ok', '' );
            $dialog->set_markup(
                sprintf(
                    __ "Unsuitable names file: %d errors, first on line %d.",
                    $err, $errlig
                )
            );
            $dialog->run;
            $dialog->destroy;
        }
        $oo{prefs}->store_register( $oo{key} => $cb_model_vide_key );
    } else {

        # problems with ID (name/surname)
        my $e = $self->{project}->students_list->problem('ID.empty');
        if ( $e > 0 ) {
            debug "NamesFile: $e empty IDs";
            $self->students_list_show();
            my $dialog = Gtk3::MessageDialog->new( $self->get_ui('main_window'),
                'destroy-with-parent', 'warning', 'ok', '' );
            $dialog->set_markup(

# TRANSLATORS: Here, do not translate 'name' and 'surname' (except in french), as the column names in the students list file has to be named in english in order to be properly detected.
                sprintf( __
"Found %d empty names in names file <i>%s</i>. Check that <b>name</b> or <b>surname</b> column is present, and always filled.",
                    $e, $fn )
                  . " "
                  . __ "Edit the names file to correct it, and re-read."
            );
            $dialog->run;
            $dialog->destroy;
        } else {
            my $d = $self->{project}->students_list->problem('ID.dup');
            if (@$d) {
                debug "NamesFile: duplicate IDs [" . join( ',', @$d ) . "]";
                if ( $#{$d} > 8 ) {
                    @$d = ( @{$d}[ 0 .. 8 ], '(and more)' );
                }
                $self->students_list_show();
                my $dialog =
                  Gtk3::MessageDialog->new( $self->get_ui('main_window'),
                    'destroy-with-parent', 'warning', 'ok', '' );
                $dialog->set_markup(
                    sprintf(
                        __
"Found duplicate names: <i>%s</i>. Check that all names are different.",
                        join( ', ', @$d )
                      )
                      . " "
                      . __ "Edit the names file to correct it, and re-read."
                );
                $dialog->run;
                $dialog->destroy;
            } else {

                # OK, no need to refresh
                $self->students_list_hide();
            }
        }

        # transmission liste des en-tetes
        my @heads = $self->{project}->students_list->heads_for_keys();
        debug "sorted heads: " . join( ",", @heads );

        # TRANSLATORS: you can omit the [...] part, just here to explain context
        $oo{prefs}->store_register(
            $oo{key} => cb_model(
                '',
                __p("(none) [No primary key found in association list]"),
                map { ( $_, $_ ) } (@heads)
            )
        );
    }
    $oo{prefs}->transmet_pref(
        $oo{gui},
        prefix => $oo{prefix},
        keys   => ["project:$oo{key}"]
    );
    $self->assoc_state();
}

sub change_liste_key {
    my ($self) = @_;

    $self->valide_options_association();

    debug "New liste_key: " . $self->{config}->get('liste_key');
    if ( $self->{project}
        ->students_list->head_n_duplicates( $self->{config}->get('liste_key') )
      )
    {
        debug "Invalid key: back to old value $self->{previous_liste_key}";

        my $dialog = Gtk3::MessageDialog->new(
            $self->get_ui('main_window'),
            'destroy-with-parent',
            'error', 'ok',
            __
"You can't choose column '%s' as a key in the students list, as it contains duplicates (value '%s')",
            $self->{config}->get('liste_key'),
            $self->{project}->students_list->head_first_duplicate(
                $self->{config}->get('liste_key')
            ),
        );
        $dialog->run;
        $dialog->destroy;

        $self->{config}->set(
            'liste_key',
            (
                $self->{previous_liste_key} ne $self->{config}->get('liste_key')
                ? $self->{previous_liste_key}
                : ""
            )
        );
        $self->{prefs}->transmet_pref(
            $self->{main},
            prefix => 'pref_assoc',
            keys   => ['project:liste_key']
        );
        return ();
    }
    if ( $self->{config}->get('liste_key') ) {

        $self->{project}->association->begin_read_transaction('cLky');
        my $assoc_liste_key =
          $self->{project}->association->variable('key_in_list');
        $assoc_liste_key = '' if ( !$assoc_liste_key );
        my ( $auto, $man, $both ) = $self->{project}->association->counts();
        $self->{project}->association->end_transaction('cLky');

        debug
"Association [$assoc_liste_key] counts: AUTO=$auto MANUAL=$man BOTH=$both";

        if (   $assoc_liste_key ne $self->{config}->get('liste_key')
            && $auto + $man > 0 )
        {
            # liste_key has changed and some association has been
            # made with another liste_key

            if ( $man > 0 ) {

                # manual association work has been made

                my $dialog =
                  Gtk3::MessageDialog->new( $self->get_ui('main_window'),
                    'destroy-with-parent', 'warning', 'yes-no', '' );
                $dialog->set_markup(
                    sprintf(
                        __(
"The primary key from the students list has been set to \"%s\", which is not the value from the association data."
                        ),
                        $self->{config}->get('liste_key')
                      )
                      . " "
                      . sprintf(
                        __(
"Some manual association data has be found, which will be lost if the primary key is changed. Do you want to switch back to the primary key \"%s\" and keep association data?"
                        ),
                        $assoc_liste_key
                      )
                );
                $dialog->get_widget_for_response('yes')->get_style_context()
                  ->add_class("suggested-action");
                my $resp = $dialog->run;
                $dialog->destroy;

                if ( $resp eq 'no' ) {

                    # clears association data
                    $self->clear_processing('assoc');

                    # automatic association run
                    if ( $self->{config}->get('assoc_code') && $auto > 0 ) {
                        $self->associe_auto;
                    }
                } else {
                    $self->{config}->set( 'liste_key', $assoc_liste_key );
                    $self->{prefs}->transmet_pref(
                        $self->{main},
                        prefix => 'pref_assoc',
                        keys   => ['project:liste_key']
                    );
                }
            } else {
                if ( $self->{config}->get('assoc_code') ) {

                    # only automated association, easy to re-run
                    my $dialog =
                      Gtk3::MessageDialog->new( $self->get_ui('main_window'),
                        'destroy-with-parent', 'info', 'ok', '' );
                    $dialog->set_markup(
                        sprintf(
                            __(
"The primary key from the students list has been set to \"%s\", which is not the value from the association data."
                            ),
                            $self->{config}->get('liste_key')
                          )
                          . " "
                          . __(
"Automatic papers/students association will be re-run to update the association data."
                          )
                    );
                    $dialog->run;
                    $dialog->destroy;

                    $self->clear_processing('assoc');
                    $self->associe_auto();
                }
            }
        }
    }
    $self->assoc_state();
}

### Actions des boutons de la partie NOTATION

sub check_possible_assoc {
    my ( $self, $code ) = @_;
    if ( !-s $self->{config}->get_absolute('listeetudiants') ) {
        my $dialog = Gtk3::MessageDialog->new( $self->get_ui('main_window'),
            'destroy-with-parent', 'error', 'ok', '' );
        $dialog->set_markup(

            sprintf(
# TRANSLATORS: Here, %s will be replaced with the name of the tab "Data capture".
                __
"Before associating names to papers, you must choose a students list file in tab \"%s\".",
                __ "Data capture"
            )
        );
        $dialog->run;
        $dialog->destroy;
    } elsif ( !$self->{config}->get('liste_key') ) {
        my $dialog = Gtk3::MessageDialog->new( $self->get_ui('main_window'),
            'destroy-with-parent', 'error', 'ok', '' );
        $dialog->set_markup(
            __(
"Please choose a key from primary keys in students list before association."
            )
        );
        $dialog->run;
        $dialog->destroy;
    } elsif ( $code && !$self->{config}->get('assoc_code') ) {
        my $dialog = Gtk3::MessageDialog->new( $self->get_ui('main_window'),
            'destroy-with-parent', 'error', 'ok', '' );
        $dialog->set_markup(
            __(
"Please choose a code (made with LaTeX command \\AMCcodeGrid or equivalent) before automatic association."
            )
        );
        $dialog->run;
        $dialog->destroy;
    } else {
        return (1);
    }
    return (0);
}

# manual association

sub associe {
    my ($self) = @_;

    return () if ( !$self->check_possible_assoc(0) );
    if ( -f $self->{config}->get_absolute('listeetudiants') ) {
        my $ga = AMC::Gui::Association::new(
            cr          => $self->{config}->get_absolute('cr'),
            data_dir    => $self->{config}->get_absolute('data'),
            liste       => $self->{config}->get_absolute('listeetudiants'),
            liste_key   => $self->{config}->get('liste_key'),
            identifiant => $self->{project}->csv_build_name(),

            'fichier-liens'  => $self->{config}->get_absolute('association'),
            global           => 0,
            'assoc-ncols'    => $self->{config}->get('assoc_ncols'),
            encodage_liste   => $self->{project}->bon_encodage('liste'),
            encodage_interne => $self->{config}->get('encodage_interne'),
            rtl              => $self->{config}->get('annote_rtl'),
            fin              => sub {
                $self->assoc_state();
            },
            size_prefs => (
                $self->{config}->get('conserve_taille') ? $self->{config} : ''
            ),
        );
        if ( $ga->{erreur} ) {
            my $dialog = Gtk3::MessageDialog->new( $self->get_ui('main_window'),
                'destroy-with-parent', 'error', 'ok', $ga->{erreur} );
            $dialog->run;
            $dialog->destroy;
        }
    } else {
        my $dialog = Gtk3::MessageDialog->new(
            $self->get_ui('main_window'),
            'destroy-with-parent',
            'info', 'ok',

            sprintf(
# TRANSLATORS: Here, %s will be replaced with "Students identification", which refers to a paragraph in the tab "Marking" from AMC main window.
                __
"Before associating names to papers, you must choose a students list file in paragraph \"%s\".",
                __ "Students identification"
            )
        );
        $dialog->run;
        $dialog->destroy;

    }
}

# automatic association

sub associe_auto {
    my ($self) = @_;
    return () if ( !$self->check_possible_assoc(1) );

    $self->{project}->auto_association(
        callback_self => $self,
        callback      => \&associe_auto_callback
    );
}

sub associe_auto_callback {
    my ( $self, $c, %data ) = self_first(@_);

    $self->assoc_state();
    $self->assoc_resultat() if ( !$data{cancelled} );
}

# automatic association finished : explain what to do after
sub assoc_resultat {
    my ($self) = @_;
    my $mesg = 1;

    $self->{project}->association->begin_read_transaction('ARCC');
    my ( $auto, $man, $both ) = $self->{project}->association->counts();
    $self->{project}->association->end_transaction('ARCC');

    my $dialog = Gtk3::MessageDialog->new( $self->get_ui('main_window'),
        'destroy-with-parent', 'info', 'ok', '' );
    $dialog->set_markup(
        sprintf(
            __("Automatic association completed: %d students recognized."),
            $auto
          )
          .

          (
            $auto == 0
            ? "\n<b>" . sprintf(

# TRANSLATORS: Here %s and %s will be replaced with two parameters names: "Primary key from this list" and "Code name for automatic association".
                __("Please check \"%s\" and \"%s\" values and try again."),
                __("Primary key from this list"),
                __("Code name for automatic association")
              )
              . "</b>"
            : ""
          )
    );
    $dialog->run;
    $dialog->destroy;

    $self->{learning}->lesson('ASSOC_AUTO_OK') if ( $auto > 0 );
}

sub assoc_state {
    my ($self) = @_;

    my $i    = 'question';
    my $t    = '';
    my $some = 0;
    if ( !-s $self->{config}->get_absolute('listeetudiants') ) {
        $t = __ "No students list file";
    } elsif ( !$self->{config}->get('liste_key') ) {
        $t = __ "No primary key from students list file";
    } else {
        $self->{project}->association->begin_read_transaction('ARST');
        my $mc = $self->{project}->association->missing_count;
        my ( $auto, $man, $both ) = $self->{project}->association->counts();
        $self->{project}->association->end_transaction('ARST');
        $some = ( $auto > 0 || $man > 0 );
        if ($mc) {
            $t = sprintf(
                ( __ "Missing identification for %d answer sheets" ),
                $mc
            );
        } else {
            $t = __
              "All completed answer sheets are associated with a student name";
            $i = 'info';
        }
    }
    $self->set_state( 'assoc', $i, $t );
    if ($some) {
        $self->get_ui('send_subject_config_button')->hide();
    } else {
        $self->get_ui('send_subject_config_button')->show();
    }
}

#########################################################################
# PROJECT
#########################################################################

sub projet_nouveau {
    my ($self) = @_;

    AMC::Gui::ProjectManager->new(
        parent_window => $self->get_ui('main_window'),
        config        => $self->{config},
        action        => 'new',
        callback_self => $self,
        new_callback  => \&create_new_project
    );
}

sub projet_charge {
    my ($self) = @_;

    AMC::Gui::ProjectManager->new(
        parent_window => $self->get_ui('main_window'),
        config        => $self->{config},
        action        => 'open',
        callback_self => $self,
        open_callback => \&open_project
    );
}

sub projet_gestion {
    my ($self) = @_;

    AMC::Gui::ProjectManager->new(
        parent_window   => $self->get_ui('main_window'),
        config          => $self->{config},
        action          => 'manage',
        current_project => $self->{projet}->name,
        progress_widget => $self->get_ui('avancement'),
        command_widget  => $self->get_ui('commande')
    );
}

sub open_project {
    my ( $self, $dir, $project ) = @_;

    my $reponse      = 'yes';
    my $options_file = $self->fich_options( $project, $dir );
    if ( !-f $options_file ) {
        debug_and_stderr "Options file not found: " . show_utf8($options_file);
        my $dialog = Gtk3::MessageDialog->new( $self->get_ui('main_window'),
            'destroy-with-parent', 'warning', 'yes-no', '' );
        $dialog->set_markup(
            sprintf(
                __("You selected directory <b>%s</b> as a project to open.")
                  . " "
                  . __(
"However, this directory does not seem to contain a project. Do you still want to try?"
                  ),
                $project
            )
        );
        $reponse = $dialog->run;
        $dialog->destroy;
    }
    if ( $reponse eq 'yes' ) {
        $self->quitte_projet() or return ();

        # If the project to open lies on a removable media, suggest
        # to copy it first to the user standard projects directory:

        if (   $dir =~ /^\/media\//
            && $self->{config}->get_absolute('projects_home') !~ /^\/media\// )
        {
            my $dialog = Gtk3::MessageDialog->new( $self->get_ui('main_window'),
                'destroy-with-parent', 'warning', 'yes-no', '' );
            $dialog->set_markup(
                sprintf(
                    __(
"You selected project <b>%s</b> from directory <i>%s</i>."
                      )
                      . " "
                      . __(
"Do you want to copy this project to your projects directory before opening it?"
                      ),
                    $project, $dir
                )
            );
            my $r = $dialog->run;
            $dialog->destroy;
            if ( $r eq 'yes' ) {
                my $proj_dest = new_filename(
                        $self->{config}->get_absolute('projects_home') . '/'
                      . $project );
                if ( project_copy( $dir . '/' . $project, $proj_dest ) ) {
                    ( undef, undef, $proj_dest ) = splitpath($proj_dest);
                    $dir     = $self->{config}->get_absolute('projects_home');
                    $project = $proj_dest;
                }
            }
        }

        # OK, now, open the project!

        $self->{config}->set_projects_home($dir);
        $self->projet_ouvre($project);
    }
}

sub source_latex_choisir {
    my ($self, %oo) = @_;

    my $create = AMC::Gui::CreateProject->new(
        parent_window  => $self->get_ui('main_window'),
        config         => $self->{config},
        filter_modules => \@filter_modules,
    );

    return ( $create->install_source(%oo) );
}

# Open project.
#
# if $deja, then the project is a new project to be created.

sub projet_ouvre {
    my ( $self, $proj, $deja ) = (@_);

    my $new_source = 0;

    return () if ( !$proj );

    my ( $ok, $texsrc );

    $self->quitte_projet();

    if ($deja) {

        # Select/create the source file

        ( $ok, $texsrc ) = $self->source_latex_choisir( nom => $proj );
        if ( !$ok ) {
            $self->cursor_standard;
            return (0);
        }
        if ( $ok == 1 ) {
            $new_source = 1;
        } elsif ( $ok == 2 ) {
            $deja = '';
        }
    }

    $self->cursor_wait;

    $self->{project}->open( $proj, $texsrc, $self->{ui} );

    $self->get_ui('onglets_projet')->set_sensitive(1);

    $self->valide_projet();

    $self->set_source_tex(1) if ($new_source);

    $self->cursor_standard;

    return (1);
}

sub create_new_project {
    my ( $self, $dir, $project ) = @_;

    $self->quitte_projet() or return ();

    $self->{config}->set_projects_home($dir);
    if ( $self->projet_ouvre( $project, 1 ) ) {
        $self->projet_sauve();
    }
}

sub projet_sauve {
    my ($self) = @_;

    debug "Saving project...";

    $self->{config}->save();
}

sub projet_check_and_save {
    my ($self) = @_;

    if ( $self->{projet}->name ) {
        $self->valide_options_notation();
        $self->{config}->save();
    }
}

sub gui_no_project {
    my ($self) = @_;

    for my $k (@widgets_only_when_opened) {
        $self->get_ui($k)->set_sensitive(0);
    }
}

sub quitte_projet {
    my ($self) = @_;

    if ( $self->{project}->name ) {

        $self->maj_export();
        $self->valide_options_notation();

        $self->{config}->close_project();

        $self->{project}->close;

        $self->gui_no_project();
    }

    return (1);
}

sub is_local {
    my ( $self, $f, $proj ) = @_;
    my $prefix = $self->{config}->get('rep_projets') . "/";
    $prefix .= $self->{project}->name() . "/" if ($proj);
    if ( defined($f) ) {
        return ( $f !~ /^[\/%]/ || $f =~ /^$prefix/ || $f =~ /[\%]PROJET\// );
    } else {
        return ('');
    }
}

sub importe_source {
    my ($self) = @_;

    my $file = $self->{config}->get('texsrc');
    my ( $fxa, $fxb, $fb ) = splitpath($file);
    my $dest = $self->{config}->{shortcuts}->absolu($fb);

    # fichier deja dans le repertoire projet...
    return () if ( $self->is_local( $file, 1 ) );

    if ( -f $dest ) {
        my $dialog = Gtk3::MessageDialog->new(
            $self->get_ui('main_window'),
            'destroy-with-parent',
            'error', 'yes-no',
            __(
"File %s already exists in project directory: do you want to replace it?"
              )
              . " "
              . __(
"Click yes to replace it and loose pre-existing contents, or No to cancel source file import."
              ),
            $fb
        );
        my $reponse = $dialog->run;
        $dialog->destroy;

        if ( $reponse eq 'no' ) {
            return (0);
        }
    }

    if (
        AMC::Gui::CreateProject->copy_latex(
            $self->{config}->get_absolute('texsrc'), $dest,
            $self->{config}->get('encodage_latex')
        )
      )
    {
        $self->{config}->set( 'project:texsrc',
            $self->{config}->{shortcuts}->relatif($dest) );
        $self->set_source_tex();
        my $dialog = Gtk3::MessageDialog->new(
            $self->get_ui('main_window'),
            'destroy-with-parent',
            'info', 'ok',
            __("The source file has been copied to project directory.") . " "
              . sprintf(
                __ "You can now edit it with button \"%s\" or with any editor.",
                __ "Edit source file"
              )
        );
        $dialog->run;
        $dialog->destroy;
    } else {
        my $dialog = Gtk3::MessageDialog->new( $self->get_ui('main_window'),
            'destroy-with-parent',
            'error', 'ok', __ "Error copying source file: %s", $! );
        $dialog->run;
        $dialog->destroy;
    }
}

sub set_source_tex {
    my ( $self, $importe ) = @_;

    $self->importe_source() if ($importe);
    $self->valide_source_tex();
}

sub valide_source_tex {
    my ($self) = @_;

    debug "* valide_source_tex";

    $self->get_ui('button_edit_src')
      ->set_tooltip_text(
        glib_filename( $self->{config}->get_absolute('texsrc') ) );

    if ( !$self->{config}->get('filter') ) {
        $self->{config}->set( 'filter',
            best_filter_for_file( $self->{config}->get_absolute('texsrc') ) );
    }

    $self->detecte_documents();
}

sub valide_projet {
    my ($self) = @_;

    $self->set_source_tex();

    $self->detecte_mep();
    $self->detecte_analyse( premier => 1 );

    debug "Correction options : MB" . $self->{config}->get('maj_bareme');
    $self->get_ui('maj_bareme')
      ->set_active( $self->{config}->get('maj_bareme') );

    $self->{prefs}->transmet_pref(
        $self->{main},
        prefix => 'notation',
        root   => 'project:'
    );

    $self->get_ui('header_bar')
      ->set_title( $self->glib_project_name . ' - ' . 'Auto Multiple Choice' );

    $self->noter_resultat();

    $self->valide_liste( noinfo => 1, nomodif => 1 );

    # options specific to some export module:
    $self->{prefs}->transmet_pref( '', prefix => 'export', root => 'project:' );

    # standard export options:
    $self->{prefs}
      ->transmet_pref( $self->{main}, prefix => 'export', root => 'project:' );

    $self->{prefs}
      ->transmet_pref( $self->{main}, prefix => 'pref_prep', root => 'project:' );

    for my $k (@widgets_only_when_opened) {
        $self->get_ui($k)->set_sensitive(1);
    }
}

#########################################################################
# MAIN
#########################################################################

sub quitter {
    my ($self) = @_;

    $self->quitte_projet() or return (1);

    Gtk3->main_quit;
}

sub bug_report {
    my ($self) = @_;

    my $dialog = Gtk3::MessageDialog->new( $self->get_ui('main_window'),
        'destroy-with-parent', 'info', 'ok', '' );
    $dialog->set_markup(
        __(
"In order to send a useful bug report, please attach the following documents:"
          )
          . "\n" . "- "
          . __(
"an archive (in some compressed format, like ZIP, 7Z, TGZ...) containing the <b>project directory</b>, <b>scan files</b> and <b>configuration directory</b> (.AMC.d in home directory), so as to reproduce and analyse this problem."
          )
          . "\n" . "- "
          . __(
"the <b>log file</b> produced when the debugging mode (in Help menu) is checked. Please try to reproduce the bug with this mode activated."
          )
          . "\n\n"
          . sprintf(
            __("Bug reports can be filled at %s or sent to the address below."),
            "<i>" . __("AMC community site") . "</i>",
          )
    );
    my $ma  = $dialog->get('message-area');
    my $web = Gtk3::LinkButton->new_with_label(
"http://project.auto-multiple-choice.net/projects/auto-multiple-choice/issues",
        __("AMC community site")
    );
    $ma->add($web);
    my $mail = Gtk3::LinkButton->new_with_label( 'mailto:paamc@passoire.fr',
        'paamc@passoire.fr' );
    $ma->add($mail);
    $ma->show_all();

    $dialog->run;
    $dialog->destroy;
}

#########################################################################
# WORKING DOCUMENTS
#########################################################################

sub edit_src {
    my ($self) = @_;

    my $f = $self->{config}->get_absolute('texsrc');

    # create new one if necessary

    if ( !-f $f ) {
        debug "Creating new empty source file...";
        ( "AMC::Filter::register::" . $self->{config}->get('filter') )
          ->default_content($f);
    }

    #

    debug "Editing $f...";
    my $editor = $self->{config}->get('txt_editor');
    if ( $self->{config}->get('filter') ) {
        my $type =
          ( "AMC::Filter::register::" . $self->{config}->get('filter') )->filetype();
        $editor = $self->{config}->get( $type . '_editor' )
          if ( $self->{config}->get( $type . '_editor' ) );
    }
    $self->commande_parallele( $editor, $f );
}

sub valide_options_preparation {
    my ($self, @args) = self_first(@_);
    $self->{prefs}->valide_options_for_domain( 'pref_prep', '', @args );
}

sub filter_details {
    my ($self) = @_;

    AMC::Gui::FilterDetails->new(
        parent_window => $self->get_ui('main_window'),
        config        => $self->{config},
        main_gui      => $self->{main},
        main_prefs    => $self->{prefs},
    );

}

sub filter_changed {
    my ( $self, @args ) = self_first(@_);

    # check it is a different value...

    my $old_filter = $self->{config}->get('filter');

    debug "Filter changed callback / old=$old_filter";

    $self->{config}->set_local_keys();
    $self->{config}->set( 'local:filter', $old_filter );
    $self->{prefs}->valide_options_for_domain( 'pref_prep', 'local', @args );
    my $new_filter = $self->{config}->get('local:filter');
    return if ( $old_filter eq $new_filter );

    debug "Filter changed -> " . $new_filter;

    # working document already built: ask for confirmation

    if ( -f $self->{config}->get_absolute('doc_question') ) {
        debug "Ask for confirmation";
        my $text;
        if ( $self->{project}->capture->n_pages_transaction() > 0 ) {
            $text = __(
"The working documents are already prepared with the current file format. If you change the file format, working documents and all other data for this project will be ereased."
              )
              . ' '
              . __("Do you wish to continue?") . " "
              . __(
"Click on Ok to erease old working documents and change file format, and on Cancel to get back to the same file format."
              )
              . "\n<b>"
              . __("To allow the use of an already printed question, cancel!")
              . "</b>";
        } else {
            $text = __(
"The working documents are already prepared with the current file format. If you change the file format, working documents will be ereased."
              )
              . ' '
              . __("Do you wish to continue?") . " "
              . __(
"Click on Ok to erease old working documents and change file format, and on Cancel to get back to the same file format."
              );
        }
        my $dialog =
          Gtk3::MessageDialog->new( $self->get_ui('main_window'), 'destroy-with-parent',
            'question', 'ok-cancel', '' );
        $dialog->set_markup($text);
        my $reponse = $dialog->run;
        $dialog->destroy;

        if ( $reponse eq 'cancel' ) {
            $self->{prefs}->transmet_pref(
                $self->{main},
                prefix => 'pref_prep',
                root   => 'project:'
            );
            return (0);
        }

        $self->clear_processing('doc:');

    }

    $self->valide_options_preparation(@args);

    # No source created: change source filename

    if (  !-f $self->{config}->get_absolute('texsrc')
        || -z $self->{config}->get_absolute('texsrc') )
    {
        $self->{config}->set( 'project:texsrc',
            '%PROJET/'
              . ( "AMC::Filter::register::" . $self->{config}->get('filter') )
              ->default_filename() );
        $self->get_ui('button_edit_src')
          ->set_tooltip_text(
            glib_filename( $self->{config}->get_absolute('texsrc') ) );
    }

}

my %component_name = (
    latex_packages => __("LaTeX packages:"),
    commands       => __("Commands:"),
    fonts          => __("Fonts:"),
);

sub doc_maj {
    my ($self) = @_;

    my $sur = 0;
    if ( $self->{project}->capture->n_pages_transaction() > 0 ) {
        my $dialog = Gtk3::MessageDialog->new( $self->get_ui('main_window'),
            'destroy-with-parent', 'warning', 'ok-cancel', '' );
        $dialog->set_markup(
            __(
"Papers analysis was already made on the basis of the current working documents."
              )
              . " "
              . __(
"You already made the examination on the basis of these documents."
              )
              . " "
              . __(
"If you modify working documents, you will not be capable any more of analyzing the papers you have already distributed!"
              )
              . " "
              . __("Do you wish to continue?") . " "
              . __(
"Click on OK to erase the former layouts and update working documents, or on Cancel to cancel this operation."
              )
              . " " . "<b>"
              . __("To allow the use of an already printed question, cancel!")
              . "</b>"
        );
        $dialog->get_widget_for_response('ok')->get_style_context()
          ->add_class("destructive-action");
        my $reponse = $dialog->run;
        $dialog->destroy;

        if ( $reponse ne 'ok' ) {
            return (0);
        }

        $sur = 1;
    }

    # Is the document layout already detected?
    $self->{project}->layout->begin_transaction('DMAJ');
    my $pc = $self->{project}->layout->pages_count;
    $self->{project}->layout->end_transaction('DMAJ');
    if ( $pc > 0 ) {
        if ( !$sur ) {
            my $dialog = Gtk3::MessageDialog->new( $self->get_ui('main_window'),
                'destroy-with-parent', 'question', 'ok-cancel', '' );
            $dialog->set_markup(
                __("Layouts are already calculated for the current documents.")
                  . " "
                  . __(
"Updating working documents, the layouts will become obsolete and will thus be erased."
                  )
                  . " "
                  . __("Do you wish to continue?") . " "
                  . __(
"Click on OK to erase the former layouts and update working documents, or on Cancel to cancel this operation."
                  )
                  . " <b>"
                  . __(
                    "To allow the use of an already printed question, cancel!")
                  . "</b>"
            );
            $dialog->get_widget_for_response('ok')->get_style_context()
              ->add_class("destructive-action");
            my $reponse = $dialog->run;
            $dialog->destroy;

            if ( $reponse ne 'ok' ) {
                return (0);
            }
        }

        $self->clear_processing('mep:');
    }

    # new layout document : XY (from LaTeX)

    if ( $self->{config}->get('doc_setting') =~ /\.pdf$/ ) {
        $self->{config}
          ->set_project_option_to_default( 'doc_setting', 'FORCE' );
    }

    # check for filter dependencies

    my $filter_register =
      ( "AMC::Filter::register::" . $self->{config}->get('filter') )->new();

    my $check = $filter_register->check_dependencies();

    if ( !$check->{ok} ) {
        my $message = sprintf(
            __(
"To handle properly <i>%s</i> files, AMC needs the following components, that are currently missing:"
            ),
            $filter_register->name()
        ) . "\n";
        for my $k (qw/latex_packages commands fonts/) {
            if ( @{ $check->{$k} } ) {
                $message .= "<b>" . $component_name{$k} . "</b> ";
                if ( $k eq 'fonts' ) {
                    $message .=
                      join( ', ', map { @{ $_->{family} } } @{ $check->{$k} } );
                } else {
                    $message .= join( ', ', @{ $check->{$k} } );
                }
                $message .= "\n";
            }
        }
        $message .=
          __("Install these components on your system and try again.");

        my $dialog = Gtk3::MessageDialog->new( $self->get_ui('main_window'),
            'destroy-with-parent', 'error', 'ok', '' );
        $dialog->set_markup($message);
        $dialog->run;
        $dialog->destroy;

        return (0);
    }

    # set options from filter:

    if ( $self->{config}->get('filter') ) {
        $filter_register->set_oo( $self->{config} );
        $filter_register->configure();
    }

    # remove pre-existing DOC-corrected.pdf (built by AMC-annotate)
    my $pdf_corrected =
      $self->{config}->{shortcuts}->absolu("DOC-corrected.pdf");
    if ( -f $pdf_corrected ) {
        debug "Removing pre-existing $pdf_corrected";
        unlink($pdf_corrected);
    }

    #
    my $mode_s = 's[';
    $mode_s .= 's' if ( $self->{config}->get('prepare_solution') );
    $mode_s .= 'c' if ( $self->{config}->get('prepare_catalog') );
    $mode_s .= ']';
    $mode_s .= 'k' if ( $self->{config}->get('prepare_indiv_solution') );

    $self->update_document( $mode_s );
}

sub check_sty_version {
    my ( $self, $c ) = @_;
    my $sty_v = $c->variable('styversion');
    $sty_v = '' if ( !defined($sty_v) );
    my $sty_p = $c->variable('stypath');
    my $amc_v = '2020/12/19 v1.4.0+git2020-12-19 r:202b3bb';
    if ( ( $sty_p || $sty_v ) && $sty_v ne $amc_v ) {
        $sty_v = 'unknown' if ( !$sty_v );
        $sty_p = 'unknown' if ( !$sty_p );
        my $dialog = Gtk3::MessageDialog->new( $self->get_ui('main_window'),
            'destroy-with-parent', 'warning', 'ok', '' );
        $dialog->set_markup(
            __(
"Your AMC version and LaTeX style file version differ. Even if the documents are properly generated, this can lead to many problems using AMC."
              )
              . "\n"
              . __(
"<b>Please check your installation to get matching AMC and LaTeX style file versions.</b>"
              )
              . "\n"
              . sprintf(
                __("AMC version: %s\nsty version: %s\nsty path: %s"),
                $amc_v, $sty_v, $sty_p
              )
        );
        $dialog->run;
        $dialog->destroy;
    }
}

sub document_updated_callback {
    my ( $self, $c, %data ) = self_first(@_);

    $self->detecte_documents();

    if ( $data{cancelled} ) {
        debug "Prepare documents: CANCELLED!";
        return ();
    }

    $self->check_sty_version($c);

    my @err  = $c->erreurs();
    my @warn = $c->warnings();
    if ( @err || @warn ) {
        debug "Errors preparing documents!";
        $self->notify_end_of_work( 'documents',
            __ "Problems while preparing documents" );

        my $message = __("Problems while processing the source file.");
        if ( !$c->{o}->{partial} ) {
            $message .= " "
              . __(
"You have to correct the source file and re-run documents update."
              );
        }

        if (@err) {
            $message .= "\n\n"
              . __("<b>Errors</b>") . "\n"
              . join( "\n",
                map { format_markup($_) } ( @err[ 0 .. mini( 9, $#err ) ] ) )
              . (
                $#err > 9
                ? "\n\n<i>(" . __("Only first ten errors written") . ")</i>"
                : ""
              );
        }
        if (@warn) {
            $message .= "\n\n"
              . __("<b>Warnings</b>") . "\n"
              . join( "\n",
                map { format_markup($_) } ( @warn[ 0 .. mini( 9, $#warn ) ] ) )
              . (
                $#warn > 9
                ? "\n\n<i>(" . __("Only first ten warnings written") . ")</i>"
                : ""
              );
        }

        $message .= "\n\n" .

          sprintf(
# TRANSLATORS: Here, %s will be replaced with the translation of "Command output details", and refers to the small expandable part at the bottom of AMC main window, where one can see the output of the commands lauched by AMC.
            __("See also the processing log in '%s' below."),

# TRANSLATORS: Title of the small expandable part at the bottom of AMC main window, where one can see the output of the commands lauched by AMC.
            __ "Command output details"
          );
        $message .=
          " " . __("Use LaTeX editor or latex command for a precise diagnosis.")
          if ( $self->{config}->get('filter') eq 'latex' );

        debug($message);
        my $dialog = Gtk3::MessageDialog->new( $self->get_ui('main_window'),
            'destroy-with-parent', 'error', 'ok', '' );
        $dialog->set_markup($message);
        $dialog->run;
        $dialog->destroy;

        return ();
    }

    $self->notify_end_of_work( 'documents', __ "Documents have been prepared" );

    if ( $c->{o}->{partial} ) {
        debug "Partial: return";
        return ();
    }

    # verif que tout y est

    my $ok = 1;
    for (qw/question setting/) {
        $ok = 0 if ( !-f $self->{config}->get_absolute( 'doc_' . $_ ) );
    }
    if ($ok) {

        debug "All documents are successfully generated";

        # set project option from filter requests

        my %vars = $c->variables;
        for my $k ( keys %vars ) {
            if ( $k =~ /^project:(.*)/ ) {
                my $kk = $1;
                debug "Configuration: $k = $vars{$k}";
                $self->{config}->set( $k, $vars{$k} );
                $self->{prefs}->transmet_pref(
                    $self->{main},
                    prefix => 'pref_prep',
                    keys   => [$kk]
                );
            }
        }

        # success message

        $self->{learning}->lesson('MAJ_DOCS_OK');

        # Try to guess the best place to write question
        # scores when annotating. This option can be
        # changed later in the Edit/Preferences window.
        my $ap = 'marges';
        if ( $c->variable('scorezones') ) {
            $ap = 'zones';
        } elsif ( $c->variable('ensemble') ) {
            $ap = 'cases';
        }
        $self->{config}->set( 'annote_position', $ap );

        my $ensemble = $c->variable('ensemble') && !$c->variable('outsidebox');
        if ( ( $ensemble || $c->variable('insidebox') )
            && $self->{config}->get('seuil') < 0.4 )
        {
            my $dialog = Gtk3::MessageDialog->new( $self->get_ui('main_window'),
                'destroy-with-parent', 'question', 'yes-no', '' );
            $dialog->set_markup(
                sprintf(
                    (
                        $ensemble
                        ? __("Your question has a separate answers sheet.")
                          . " "
                          . __("In this case, letters are shown inside boxes.")
                        : __(
"Your question is set to present labels inside the boxes to be ticked."
                        )
                    )
                    . " "

# TRANSLATORS: Here, %s will be replaced with the translation of "darkness threshold".
                      . __(
"For better ticking detection, ask students to fill out completely boxes, and choose parameter \"%s\" around 0.5 for this project."
                      )
                      . " "
                      . __("At the moment, this parameter is set to %.02f.")
                      . " "
                      . __("Would you like to set it to 0.5?")

                    ,

# TRANSLATORS: This parameter is the ratio of dark pixels number over total pixels number inside box above which a box is considered to be ticked.
                    __ "darkness threshold",
                    $self->{config}->get('seuil')
                )
            );
            my $reponse = $dialog->run;
            $dialog->destroy;
            if ( $reponse eq 'yes' ) {
                $self->{config}->set( 'seuil',    0.5 );
                $self->{config}->set( 'seuil_up', 1.0 );
            }
        }
    }

}

sub open_documents_popover {
    my ($self) = @_;
    if ( $self->get_ui('toggle_documents')->get_active() ) {
        $self->get_ui('documents_popover')->show_all();
    } else {
        $self->get_ui('documents_popover')->hide();
    }
    return (1);
}

sub popover_hidden {
    my ($self) = @_;
    $self->get_ui('toggle_documents')->set_active(0)
      if ( $self->get_ui('toggle_documents') );
    return (1);
}

sub check_document {
    my ( $self, $filename, $k ) = @_;
    debug( "Document $filename " . ( -f $filename ? "exists" : "NOT FOUND" ) );
    $self->get_ui( 'but_' . $k )->set_sensitive( -f $filename );
}

sub update_document {
    my ( $self, $mode, $partial ) = @_;
    $self->{project}->update_document(
        $mode,
        callback      => \&document_updated_callback,
        callback_self => $self,
        partial       => $partial
    );
}

sub update_catalog {
    my ($self) = @_;
    $self->update_document( "C", 1 );
}

sub update_solution {
    my ($self) = @_;
    $self->update_document( "S", 1 );
}

sub update_indiv_solution {
    my ($self) = @_;
    $self->update_document( "k", 1 );
}

sub detecte_documents {
    my ($self) = @_;

    $self->check_document( $self->{config}->get_absolute('doc_question'),
        'question' );
    $self->check_document( $self->{config}->get_absolute('doc_solution'),
        'solution' );
    $self->check_document( $self->{config}->get_absolute('doc_indiv_solution'),
        'indiv_solution' );
    $self->check_document( $self->{config}->get_absolute('doc_catalog'),
        'catalog' );
    my $s = file_maj( map { $self->{config}->get_absolute( 'doc_' . $_ ) }
          (qw/question setting/) );
    my $ok;
    if ( $s eq 'UNREADABLE' ) {
        $s  = __("Working documents are not readable");
        $ok = 'error';
    } elsif ( $s eq 'NOTFOUND' ) {
        $s  = __("No working documents");
        $ok = 'warning';
    } else {
        $s  = __("Working documents last update:") . " " . $s;
        $ok = 'info';
    }
    if ( $ok eq 'info' ) {
        $self->get_ui('toggle_documents')->show();
    } else {
        $self->get_ui('toggle_documents')->set_active(0);
        $self->get_ui('toggle_documents')->hide();
    }
    $self->set_state( 'docs', $ok, $s );
}

sub show_document {
    my ($self, $sel) = @_;
    my $f = $self->{config}->get_absolute( 'doc_' . $sel );
    debug "Looking at $f...";
    $self->commande_parallele( $self->{config}->get('pdf_viewer'), $f );
}

sub show_question {
    my ($self) = @_;
    $self->show_document('question');
}

sub show_solution {
    my ($self) = @_;
    $self->show_document('solution');
}

sub show_indiv_solution {
    my ($self) = @_;
    $self->show_document('indiv_solution');
}

sub show_catalog {
    my ($self) = @_;
    $self->show_document('catalog');
}

#########################################################################
# MAILING
#########################################################################

sub send_subjects {
    my ($self) = @_;
    if ( $self->{project}->students_list->taille == 0 ) {
        $self->send_subjects_config();
    }
    $self->valide_liste( nolabel => 1, noinfo => 1, nomodif => 1 );
    $self->do_mailing(REPORT_PRINTED_COPY);
}

sub send_emails {
    my ($self) = @_;
    $self->do_mailing(REPORT_ANNOTATED_PDF);
}

sub do_mailing {
    my ($self, $kind) = @_;

    my $kind_s = {
        &REPORT_PRINTED_COPY  => 'subjectemail',
        &REPORT_ANNOTATED_PDF => 'annotatedemail'
    }->{$kind}
      || 'unknown';

    my @ids = AMC::Gui::Mailing->new(
        parent_window => $self->get_ui('main_window'),
        config        => $self->{config},
        kind          => $kind,
        kind_s        => $kind_s,
        project_name  => $self->{project}->name,
        report        => $self->{project}->report,
        capture       => $self->{project}->capture,
        association   => $self->{project}->association,
        students_list => $self->{project}->students_list,
    )->dialog();

    if (@ids) {
        $self->{project}->mailing(
            kind   => $kind,
            kind_s => $kind_s,
            ids => \@ids,
            callback_self => $self,
            callback      => \&do_mailing_callback
        );
    }
}

sub do_mailing_callback {
    my ( $self, $c, %data ) = self_first(@_);

    close( $c->{o}->{fh} );

    my $ok     = $c->variable('OK')     || 0;
    my $failed = $c->variable('FAILED') || 0;
    my @message;
    push @message, "<b>" . ( __ "Cancelled." ) . "</b>"
      if ( $data{cancelled} );
    push @message,
      "<b>"
      . ( __
          "SMTP authentication failed: check SMTP configuration and password." )
      . "</b>"
      if ( $c->variable('failed_auth') );
    push @message, sprintf( __ "%d message(s) has been sent.", $ok );

    if ( $failed > 0 ) {
        push @message,
          "<b>"
          . sprintf( "%d message(s) could not be sent.", $failed ) . "</b>";
    }
    my $dialog = Gtk3::MessageDialog->new(
        $self->get_ui('main_window'),
        'destroy-with-parent', ( $failed > 0 ? 'warning' : 'info' ),
        'ok', ''
    );
    $dialog->set_markup( join( "\n", @message ) );
    $dialog->run;
    $dialog->destroy;
}

sub send_subjects_config {
    my ($self) = @_;

    AMC::Gui::StudentsList->new(
        parent_window => $self->get_ui('main_window'),
        config        => $self->{config},
        callback_self => $self,
        callback      => \&valide_liste,
        main_gui      => $self->{main},
        main_prefs    => $self->{prefs},
    )->dialog_with_key();

}

#########################################################################
# LAYOUT
#########################################################################

sub calcule_mep {
    my ($self) = @_;

    if ( $self->{config}->get('doc_setting') !~ /\.xy$/ ) {

        # OLD STYLE WORKING DOCUMENTS... Not supported anymore: update!
        my $dialog = Gtk3::MessageDialog->new(
            $self->get_ui('main_window'),
            'destroy-with-parent',
            'error',    # message type
            'ok',       # which set of buttons?
            ''
        );
        $dialog->set_markup(
            __(
"Working documents are in an old format, which is not supported anymore."
              )
              . " <b>"
              . __("Please generate again the working documents!") . "</b>"
        );
        $dialog->run;
        $dialog->destroy;

        return;
    }

    $self->{project}->detect_layout(
        callback_self => $self,
        callback      => \&calcule_mep_callback
    );

}

sub calcule_mep_callback {
    my ( $self, $c, %data ) = self_first(@_);

    if ( $data{cancelled} ) {
        $self->detecte_mep();
    } else {
        $self->{project}->layout->begin_read_transaction('PGCN');
        my $c = $self->{project}->layout->pages_count();
        my $sl_file =
          $self->{project}->layout->variable("build:studentslistfile");
        my $sl_key =
          $self->{project}->layout->variable("build:studentslistkey");
        my $extract_only =
          $self->{project}->layout->variable("build:extractonly");
        $self->{project}->layout->end_transaction('PGCN');

        $self->detecte_mep();

        if ( $c < 1 ) {

            # avertissement...
            my $dialog = Gtk3::MessageDialog->new(
                $self->get_ui('main_window'),
                'destroy-with-parent',
                'error',    # message type
                'ok',       # which set of buttons?
                ''
            );
            $dialog->set_markup(
                __("No layout detected.") . " "
                  . __(
"<b>Don't go through the examination</b> before fixing this problem, otherwise you won't be able to use AMC for correction."
                  )
            );
            $dialog->run;
            $dialog->destroy;

        } else {
            if ($sl_file) {
                debug "SL_FILE=" . show_utf8($sl_file);
                debug "SL_KEY =" . show_utf8($sl_key);
                $self->{config}->set( 'listeetudiants',
                    $self->{config}->{shortcuts}->relatif_base($sl_file) );
                $self->{config}->set( 'liste_key', $sl_key ) if ($sl_key);
            }
            if ($extract_only) {
                $self->{project}->scoring_strategy_update(0);
            }

            $self->{learning}->lesson('MAJ_MEP_OK');
        }
    }
}

sub verif_mep {
    my ($self) = @_;
    $self->saisie_manuelle( 0, 0, 1 );
}

sub detecte_mep {
    my ($self) = @_;

    $self->{project}->layout->begin_read_transaction('LAYO');
    $self->{_mep_defauts} = { $self->{project}->layout->defects() };
    my $c                = $self->{project}->layout->pages_count;
    my $subjects_printed = $self->{project}->report->n_printed() > 0;
    $self->{project}->layout->end_transaction('LAYO');
    my @def = ( keys %{ $self->{_mep_defauts} } );
    if (@def) {
        $self->get_ui('button_mep_warnings')->show();
    } else {
        $self->get_ui('button_mep_warnings')->hide();
    }
    $self->get_ui('onglet_saisie')->set_sensitive( $c > 0 );
    my $s;
    my $ok;
    if ( $c < 1 ) {
        $s  = __("No layout");
        $ok = 'error';
    } else {
        $s = sprintf( __("Processed %d pages"), $c );
        if (@def) {
            $s .= ", " . __("but some defects were detected.");
            $ok = $self->defects_class(@def);
        } else {
            $s .= '.';
            $ok = 'info';
        }
    }
    $self->set_state( 'layout', $ok, $s );

    if ($subjects_printed) {
        $self->get_ui('send_subject_action')->show();
    } else {
        $self->get_ui('send_subject_action')->hide();
    }
}

my %defect_text = (
    NO_NAME => __(
"The \\namefield command is not used. Writing subjects without name field is not recommended"
    ),
    SEVERAL_NAMES => __(
"The \\namefield command is used several times for the same subject. This should not be the case, as each student should write his name only once"
    ),
    NO_BOX              => __("No box to be ticked"),
    DIFFERENT_POSITIONS => __(
"The corner marks and binary boxes are not at the same location on all pages"
    ),
    OUT_OF_PAGE => __(
"Some material has been placed out of the page. This is often a result of a multiple columns question group starting too close from the page bottom. In such a case, use \"needspace\"."
    ),
);

sub defects_class {
    my ( $self, @defects ) = @_;
    my $w = 0;
    my $e = 0;
    for my $k (@defects) {
        if ( $k eq 'NO_NAME' ) {
            $w++;
        } else {
            $e++;
        }
    }
    return ( $e ? 'error' : $w ? 'question' : 'info' );
}

sub mep_warnings {
    my ($self) = @_;

    my $m   = '';
    my @def = ( keys %{ $self->{_mep_defauts} } );
    if (@def) {
        $m = __(
"Some potential defects were detected for this subject. Correct them in the source and update the working documents."
        );
        for my $k ( keys %defect_text ) {
            my $dd = $self->{_mep_defauts}->{$k};
            if ($dd) {
                if ( $k eq 'DIFFERENT_POSITIONS' ) {
                    $m .= "\n<b>"
                      . $defect_text{$k} . "</b> "
                      . sprintf(
                        __('(See for example pages %s and %s)'),
                        pageids_string( $dd->{student_a}, $dd->{page_a} ),
                        pageids_string( $dd->{student_b}, $dd->{page_b} )
                      ) . '.';
                } elsif ( $k eq 'OUT_OF_PAGE' ) {
                    $m .= "\n<b>"
                      . $defect_text{$k} . "</b> "
                      . sprintf(
                        __('(Concerns %1$d pages, see for example page %2$s)'),
                        1 + $#{$dd},
                        pageids_string( $dd->[0]->{student}, $dd->[0]->{page} )
                      ) . '.';
                } else {
                    my @e = sort { $a <=> $b } ( @{$dd} );
                    if (@e) {
                        $m .= "\n<b>"
                          . $defect_text{$k} . "</b> "
                          . sprintf(
                            __(
'(Concerns %1$d exams, see for example sheet %2$d)'
                            ),
                            1 + $#e,
                            $e[0]
                          ) . '.';
                    }
                }
            }
        }
    } else {

        # should not be possible to go there...
        return ();
    }
    my $dialog = Gtk3::MessageDialog->new( $self->get_ui('main_window'),
        'destroy-with-parent', 'warning', 'ok', '' );
    $dialog->set_markup($m);
    $dialog->run;
    $dialog->destroy;

}

#########################################################################
# ANNOTATION
#########################################################################

sub select_students {
    my ( $self, $id_file ) = @_;

    AMC::Gui::SelectStudents->new(
        parent_window => $self->get_ui('main_window'),
        config        => $self->{config},
        capture       => $self->{project}->capture,
        association   => $self->{project}->association,
        students_list => $self->{project}->students_list,
        id_file       => $id_file,
    );

}

sub annote_copies {
    my ($self) = @_;

    my $id_file = '';

    if ( $self->{config}->get('regroupement_copies') eq 'SELECTED' ) {

        # use a file in project directory to store students ids for which
        # sheets will be annotated
        $id_file = $self->{config}->{shortcuts}->absolu('%PROJET/selected-ids');
        return () if ( !$self->select_students($id_file) );
    }

    $self->{project}->annotate(
        id_file       => $id_file,
        callback_self => $self,
        callback      => \&annote_copies_callback
    );

}

sub annote_copies_callback {
    my ( $self, $c, %data ) = self_first(@_);

    $self->notify_end_of_work( 'annotation',
        __ "Annotations have been completed" )
      if ( !$data{cancelled} );
}

sub valide_options_notation {
    my ($self, @args) = self_first(@_);
    $self->{prefs}->valide_options_for_domain( 'notation', '', @args );
    if ( $self->{config}->key_changed("regroupement_compose") ) {
        annotate_source_change( $self->{project}->capture, 1 );
    }
    $self->get_ui('groupe_model')
      ->set_sensitive(
        $self->{config}->get('regroupement_type') eq 'STUDENTS' );
}

sub annotate_papers {
    my ($self) = @_;

    $self->valide_options_notation();
    $self->maj_export();

    $self->annote_copies;
}

#########################################################################
# PRINTING
#########################################################################

sub sujet_impressions {
    my ($self) = @_;

    my $g = AMC::Gui::Printing->new(
        config         => $self->{config},
        parent_window  => $self->get_ui('main_window'),
        layout         => $self->{project}->layout,
        callback_self  => $self,
        print_callback => \&print_exams,
    );

    if ( $g->{preassoc} ) {
        $self->valide_liste(
            nolabel => 1,
            gui     => $g->{main},
            prefs   => $g->{prefs},
            prefix  => 'impfpu',
            key     => 'pdf_password_key',
        );
    }
}

sub print_exams {
    my ( $self, $options ) = @_;

    return () if ( !@{ $options->{exams} } );

    $self->{project}->print_exams(
        %$options,
        callback_self => $self,
        callback      => \&print_exams_callback
    );
}

sub print_exams_callback {
    my ( $self, $c, %data ) = self_first(@_);

    close( $c->{o}->{fh} );
    $self->save_state_after_printing( $c->{o} );
}

sub save_state_after_printing {
    my ( $self, $c ) = @_;
    my $st = AMC::State::new( directory => $self->{config}->{shortcuts}->absolu('%PROJET/') );

    $st->read();

    my @files = grep { -f $self->{config}->{shortcuts}->absolu($_) }
      map { $self->{config}->get( 'doc_' . $_ ) }
      (qw/question solution setting catalog/);
    push @files, $self->{config}->get_absolute('texsrc');

    push @files, $self->{config}->get_absolute('filtered_source')
      if ( -f $self->{config}->get_absolute('filtered_source') );

    if ( !$st->check_local_md5(@files) ) {
        $st = AMC::State::new( directory => $self->{config}->{shortcuts}->absolu('%PROJET/') );
        $st->add_local_files(@files);
    }

    $st->add_print(
        printer => $c->{printer},
        method  => $c->{method},
        content => join( ',', @{ $c->{etu} } )
    );
    $st->write();

    $self->detecte_mep();
}

#########################################################################
# MARKING
#########################################################################

sub valide_options_correction {
    my ( $self, $ww, $o ) = self_first(@_);
    my $name = $ww->get_name();
    debug "Options validation from $name";
    if ( !$self->get_ui($name) ) {
        debug "WARNING: Option validation failed, unknown name $name.";
    } else {
        $self->{config}
          ->set( "project:$name", $self->get_ui($name)->get_active() ? 1 : 0 );
    }
}

sub voir_notes {
    my ($self) = @_;

    $self->{project}->scoring->begin_read_transaction('smMC');
    my $c = $self->{project}->scoring->marks_count;
    $self->{project}->scoring->end_transaction('smMC');
    if ( $c > 0 ) {
        my $n = AMC::Gui::Notes::new(
            scoring    => $self->{project}->scoring,
            layout     => $self->{project}->layout,
            size_prefs => (
                $self->{config}->get('conserve_taille') ? $self->{config} : ''
            ),
        );
    } else {
        my $dialog = Gtk3::MessageDialog->new(
            $self->get_ui('main_window'),
            'destroy-with-parent',
            'info', 'ok',
            sprintf(
                __ "Papers are not yet corrected: use button \"%s\".",

# TRANSLATORS: This is a button: "Mark" is here an action to be called by the user. When clicking this button, the user requests scores to be computed for all students.
                __ "Mark"
            )
        );
        $dialog->run;
        $dialog->destroy;
    }
}

sub noter {
    my ($self) = @_;

    if ( $self->{config}->get('maj_bareme') ) {

        $self->{project}->scoring_strategy_update(
            $self->{config}->get('prepare_indiv_solution'),
            o   => { callback_self => $self },
            fin => \&noter_callback,
        );

    } else {
        $self->{project}->compute_marks(
            callback_self => $self,
            callback      => \&compute_marks_callback
        );
    }
}

sub noter_callback {
    my ( $self, $c, %data ) = self_first(@_);
    $self->check_sty_version($c);
    $self->detecte_documents();

    if ( !$data{cancelled} ) {
        $self->noter_postcorrect();
    }
}

sub noter_postcorrect {
    my ($self) = @_;

    # check marking scale data: in PostCorrect mode, ask for a sheet
    # number to get right answers from...

    if ( $self->{project}->scoring->variable_transaction('postcorrect_flag') ) {

        debug "PostCorrect option ON";

        # Let the user choose the reference copy

        my $pc = AMC::Gui::Postcorrect->new(
            parent_window => $self->get_ui('main_window'),
            config        => $self->{config},
            capture       => $self->{project}->capture
        );
        $pc->choose_reference(
            sub {
                $self->{project}->compute_marks(
                    callback_self => $self,
                    callback      => \&compute_marks_callback,
                    postcorrect   => [@_]
                );
            }
        );

    } else {
        $self->{project}->compute_marks(
            callback_self => $self,
            callback      => \&compute_marks_callback
        );
    }
}

sub compute_marks_callback {
    my ( $self, $c, %data ) = self_first(@_);

    $self->notify_end_of_work( 'grading', __ "Grading has been completed" )
      if ( !$data{cancelled} );
    $self->noter_resultat();
}

sub noter_resultat {
    my ($self) = @_;
    
    $self->{project}->scoring->begin_read_transaction('MARK');
    my $avg = $self->{project}->scoring->average_mark;
    $self->{project}->scoring->end_transaction('MARK');

    my $ok;
    my $text;
    if ( defined($avg) ) {
        $ok = 'info';

        # TRANSLATORS: This is the marks mean for all students.
        $text = sprintf( __ "Mean: %.2f", $avg );
    } else {
        $ok   = 'error';
        $text = __("No marks computed");
    }
    $self->set_state( 'marking', $ok, $text );
    $self->update_available_codes();
    $self->get_ui('onglet_reports')->set_sensitive( defined($avg) );
}

#########################################################################
# PREFERENCES
#########################################################################

sub edit_preferences {
    my ($self) = @_;

    AMC::Gui::Preferences->new(
        parent_window            => $self->get_ui('main_window'),
        config                   => $self->{config},
        widgets                  => $self->{ui},
        capture                  => $self->{project}->capture,
        callback_self            => $self,
        decode_callback          => \&decode_name_fields_again,
        detect_analysis_callback => \&detecte_analyse,
        open_project_name        => $self->{project}->name,
    );
}

sub sauve_pref_generales {
    my ($self) = @_;
    $self->{config}->save();
}

#########################################################################
# DOCUMENTATION
#########################################################################

# add doc list menu

my $docs_menu = Gtk3::Menu->new();

my @doc_langs = ();

my $hdocdir = amc_specdir('doc/auto-multiple-choice') . "/html/";
if ( opendir( DOD, $hdocdir ) ) {
    push @doc_langs,
      map  { s/auto-multiple-choice\.//; $_; }
      grep { /auto-multiple-choice\...(_..)?/ } readdir(DOD);
    closedir(DOD);
} else {
    debug("DOCUMENTATION : Can't open directory $hdocdir: $!");
}

my %ltext_loc = (
# TRANSLATORS: One of the documentation languages.
    French => __ "French",

    # TRANSLATORS: One of the documentation languages.
    English => __ "English",

    # TRANSLATORS: One of the documentation languages.
    Japanese => __ "Japanese",
                );

sub activate_apropos {
    my ($self) = @_;
    AMC::Gui::APropos->new( parent_window => $$self->get_ui('main_window') );
}

sub activate_doc {
    my ( $self, $w, $lang ) = self_first(@_);

    if ( !$lang ) {
        my $n = $w->Gtk3::Buildable::get_name;
        if ( $n =~ /_([a-z]{2})$/ ) {
            $lang = $1;
        }
    }

    my $url = 'file://' . $hdocdir;
    $url .= "auto-multiple-choice.$lang/index.html"
      if ( $lang && -f $hdocdir . "auto-multiple-choice.$lang/index.html" );

    my $seq = 0;
    my @c   = map { $seq += s/[%]u/$url/g; $_; }
      split( /\s+/, $self->{config}->get('html_browser') );
    push @c, $url if ( !$seq );

    $self->commande_parallele(@c);
}

#########################################################################
# PLUGINS
#########################################################################

sub plugins_add {
    my ($self) = @_;

    my $d = Gtk3::FileChooserDialog->new(
        __("Install an AMC plugin"),
        $self->get_ui('main_window'), 'open',
        'gtk-cancel' => 'cancel',
        'gtk-ok'     => 'ok'
    );
    my $filter = Gtk3::FileFilter->new();
    $filter->set_name( __ "Plugins (zip, tgz)" );
    for my $ext (qw/ZIP zip TGZ tgz tar.gz TAR.GZ/) {
        $filter->add_pattern("*.$ext");
    }
    $d->add_filter($filter);

    my $r = $d->run;
    if ( $r eq 'ok' ) {
        my $plugin = clean_gtk_filenames( $d->get_filename );
        $d->destroy;

        # unzip in a temporary directory

        my ( $temp_dir, $error ) = unzip_to_temp($plugin);

        if ($error) {
            my $dialog = Gtk3::MessageDialog->new(
                $self->get_ui('main_window'),
                'destroy-with-parent',
                'error', 'ok',
                sprintf(
                    __(
"An error occured while trying to extract files from the plugin archive: %s."
                    ),
                    $error
                )
            );
            $dialog->run;
            $dialog->destroy;
            return ();
        }

        # checks validity

        my ( $nf, $main ) = n_fich($temp_dir);
        if ( $nf < 1 ) {
            my $dialog = Gtk3::MessageDialog->new(
                $self->get_ui('main_window'),
                'destroy-with-parent',
                'error',
                'ok',
                __ "Nothing extracted from the plugin archive. Check it."
            );
            $dialog->run;
            $dialog->destroy;
            return ();
        }
        if ( $nf > 1 || !-d $main ) {
            my $dialog = Gtk3::MessageDialog->new(
                $self->get_ui('main_window'),
                'destroy-with-parent',
                'error',
                'ok',
                __
"This is not a valid plugin, as it contains more than one directory at the first level."
            );
            $dialog->run;
            $dialog->destroy;
            return ();
        }

        if ( !-d "$main/perl/AMC" ) {
            my $dialog = Gtk3::MessageDialog->new(
                $self->get_ui('main_window'),
                'destroy-with-parent',
                'error',
                'ok',
                __
"This is not a valid plugin, as it does not contain a perl/AMC subdirectory."
            );
            $dialog->run;
            $dialog->destroy;
            return ();
        }

        my $name = $main;
        $name =~ s/.*\///;

        # already installed?

        if ( $name =~ /[^.]/ && -e $self->{config}->subdir("plugins/$name") ) {
            my $dialog = Gtk3::MessageDialog->new( $self->get_ui('main_window'),
                'destroy-with-parent', 'question', 'yes-no', '' );
            $dialog->set_markup(
                sprintf(
                    __(
"A plugin is already installed with the same name (%s). Do you want to delete the old one and overwrite?"
                    ),
                    "<b>$name</b>"
                )
            );
            my $r = $dialog->run;
            $dialog->destroy;
            return if ( $r ne 'yes' );

            remove_tree(
                $self->{config}->subdir("plugins/$name"),
                { verbose => 0, safe => 1, keep_root => 0 }
            );
        }

        # go!

        debug "Installing plugin $name to "
          . $self->{config}->subdir("plugins");

        if ( system( 'mv', $main, $self->{config}->subdir("plugins") ) != 0 ) {
            my $dialog = Gtk3::MessageDialog->new(
                $self->get_ui('main_window'),
                'destroy-with-parent',
                'error', 'ok',
                sprintf(
                    __(
"Error while moving the plugin to the user plugin directory: %s"
                    ),
                    $!
                )
            );
            my $r = $dialog->run;
            $dialog->destroy;
            return ();
        }

        my $dialog = Gtk3::MessageDialog->new( $self->get_ui('main_window'),
            'destroy-with-parent',
            'info', 'ok',
            __ "Please restart AMC before using the new plugin..." );
        my $r = $dialog->run;
        $dialog->destroy;

    } else {
        $d->destroy;
    }
}

#########################################################################
# TEMPLATE
#########################################################################

sub make_template {
    my ($self) = @_;

    if ( !$self->{project}->name ) {
        debug "Make template: no opened project";
        return ();
    }

    $self->projet_check_and_save();

    AMC::Gui::Template->new(
        parent_window => $self->get_ui('main_window'),
        config        => $self->{config},
        project_name  => $self->{project}->name,
    );

}

#########################################################################
# CLEANUP
#########################################################################

sub cleanup_dialog {
    my ($self) = @_;
    AMC::Gui::Cleanup->new(
        config        => $self->{config},
        parent_window => $self->get_ui('main_window'),
        capture       => $self->{project}->capture
    );
}


1;
