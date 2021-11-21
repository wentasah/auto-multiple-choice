#
# Copyright (C) 2009-2021 Alexis Bienvenüe <paamc@passoire.fr>
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

package AMC::Export::ods;

use AMC::Basic;
use AMC::Export;
use Encode;
use File::Spec;

use Module::Load::Conditional qw/can_load/;

use OpenOffice::OODoc;

our @ISA = ("AMC::Export");

sub new {
    my $class = shift;
    my $self  = $class->SUPER::new();
    $self->{'out.nom'}        = "";
    $self->{'out.code'}       = "";
    $self->{'out.columns'}    = 'student.key,student.name';
    $self->{'out.font'}       = "Arial";
    $self->{'out.stats'}      = '';
    $self->{'out.statsindic'} = '';
    $self->{'out.groupsums'}  = 0;
    $self->{'out.groupsep'}   = ':';

    if ( can_load( modules => { Pango => undef, Cairo => undef } ) ) {
        debug "Using Pango/Cairo to compute column width";
        $self->{'calc.Cairo'} = 1;
    }
    bless( $self, $class );
    return $self;
}

sub load {
    my ($self) = @_;
    $self->SUPER::load();
    $self->{_capture} = $self->{_data}->module('capture');
    $self->{_layout}  = $self->{_data}->module('layout');
}

# returns the column width (in cm) to use when including the given texts.

sub text_width {
    my ( $self, $size, $title, @t ) = @_;
    my $width  = 0;
    my $height = 0;

    if ( $self->{'calc.Cairo'} ) {

        my $font = Pango::FontDescription->from_string(
            $self->{'out.font'} . " " . ( 10 * $size ) );
        $font->set_stretch('normal');

        my $surface = Cairo::ImageSurface->create( 'argb32', 10, 10 );
        my $cr      = Cairo::Context->create($surface);
        my $layout  = Pango::Cairo::create_layout($cr);

        $font->set_weight('bold');
        $layout->set_font_description($font);
        $layout->set_text($title);
        ( $width, $height ) = $layout->get_pixel_size();

        $font->set_weight('normal');
        $layout->set_font_description($font);
        for my $text (@t) {
            $layout->set_text($text);
            my ( $text_x, $text_y ) = $layout->get_pixel_size();
            $width  = $text_x if ( $text_x > $width );
            $height = $text_y if ( $text_y > $height );
        }

        return ( 0.002772 * $width + 0.019891 + 0.3,
            0.002772 * $height + 0.019891 );

    } else {
        $width = length($title);
        for my $text (@t) {
            $width = length($text) if ( length($text) > $width );
        }
        return ( 0.22 * $width + 0.3, 0.5 );
    }
}

sub parse_num {
    my ( $self, $n ) = @_;
    if ( $self->{'out.decimal'} ne '.' ) {
        $n =~ s/\./$self->{'out.decimal'}/;
    }
    return ( $self->parse_string($n) );
}

sub parse_string {
    my ( $self, $s ) = @_;
    if ( $self->{'out.entoure'} ) {
        $s =~
s/$self->{'out.entoure'}/$self->{'out.entoure'}$self->{'out.entoure'}/g;
        $s = $self->{'out.entoure'} . $s . $self->{'out.entoure'};
    }
    return ($s);
}

sub x2ooo {
    my ($x) = @_;
    my $c   = '';
    my $d   = int( $x / 26 );
    $x = $x % 26;
    $c .= chr( ord("A") + $d - 1 ) if ( $d > 0 );
    $c .= chr( ord("A") + $x );
    return ($c);
}

sub yx2ooo {
    my ( $y, $x, $fy, $fx ) = @_;
    return ( ( $fx ? '$' : '' ) . x2ooo($x) . ( $fy ? '$' : '' ) . ( $y + 1 ) );
}

sub subcolumn_range {
    my ( $column, $a, $b ) = @_;
    if ( $a == $b ) {
        return ( "[." . $column . ( $a + 1 ) . "]" );
    } else {
        return ("[."
              . $column
              . ( $a + 1 ) . ":" . "."
              . $column
              . ( $b + 1 )
              . "]" );
    }
}

sub subrow_range {
    my ( $row, $a, $b ) = @_;
    if ( $a == $b ) {
        return ( "[." . x2ooo($a) . ( $row + 1 ) . "]" );
    } else {
        return ("[."
              . x2ooo($a)
              . ( $row + 1 ) . ":" . "."
              . x2ooo($b)
              . ( $row + 1 )
              . "]" );
    }
}

sub condensed {
    my ( $range, $column, @lines ) = @_;
    my @l     = sort { $a <=> $b } @lines;
    my $debut = '';
    my $fin   = '';
    my @sets  = ();
    for my $i (@l) {
        if ($debut) {
            if ( $i == $fin + 1 ) {
                $fin = $i;
            } else {
                push @sets, &$range( $column, $debut, $fin );
                $debut = $i;
                $fin   = $i;
            }
        } else {
            $debut = $i;
            $fin   = $i;
        }
    }
    push @sets, &$range( $column, $debut, $fin );
    return ( join( ";", @sets ) );
}

sub subcolumn_condensed {
    my ( $column, @rows ) = @_;
    return ( condensed( \&subcolumn_range, $column, @rows ) );
}

sub subrow_condensed {
    my ( $row, @columns ) = @_;
    return ( condensed( \&subrow_range, $row, @columns ) );
}

my %largeurs = (
    qw/ASSOC 4cm
      note 1.5cm
      total 1.2cm
      max 1cm
      heads 3cm/
);

my %style_col = (
    qw/student.key CodeA
      NOM General
      NOTE NoteF
      student.copy NumCopie
      TOTAL NoteQ
      GS NoteGS
      GSp NoteGSp
      MAX NoteQ
      HEAD General
      /
);
my %style_col_abs = (
    qw/NOTE General
      ID NoteX
      TOTAL NoteX
      MAX NoteX
      /
);

my %fonction_arrondi = (
    qw/i ROUNDDOWN
      n ROUND
      s ROUNDUP
      /
);

sub set_cell {
    my ( $doc, $feuille, $jj, $ii, $abs, $x, $value, %oo ) = @_;

    $doc->cellStyle(
        $feuille, $jj, $ii,
        (
              $abs && $style_col_abs{$x}
            ? $style_col_abs{$x}
            : ( $style_col{$x} ? $style_col{$x} : $style_col{HEAD} )
        )
    );
    $value = encode( 'utf-8', $value ) if ( $oo{'utf8'} );
    $doc->cellValueType( $feuille, $jj, $ii, 'float' )
      if ( $oo{numeric} && !$abs );
    $doc->cellValueType( $feuille, $jj, $ii, 'percentage' )
      if ( $oo{pc} && !$abs );
    if ( $oo{formula} ) {
        $doc->cellFormula( $feuille, $jj, $ii, $oo{formula} );
    } else {
        $doc->cellValue( $feuille, $jj, $ii, $value );
    }
}

sub build_stats_table {
    my ( $self, $direction, $cts, $correct_data, $doc, $stats, @q ) = @_;

    my $vertical_flow = $direction =~ /^v/i;

    my %y_item = ( all => 2, empty => 3, invalid => 4 );

    my %y_name = (
        all => __(
            # TRANSLATORS: this is a row label in the table with
            # questions basic statistics in the ODS exported
            # spreadsheet. The corresponding row contains the total
            # number of sheets. Please let this label short.
            "ALL"
        ),

        empty => __(
           # TRANSLATORS: this is a row label in the table with
           # questions basic statistics in the ODS exported
           # spreadsheet. The corresponding row contains the number of
           # sheets for which the question did not get an
           # answer. Please let this label short.
            "NA"
        ),

        invalid => __(
           # TRANSLATORS: this is a row label in the table with
           # questions basic statistics in the ODS exported
           # spreadsheet. The corresponding row contains the number of
           # sheets for which the question got an invalid
           # answer. Please let this label short.
            "INVALID"
        )
    );
    my %y_style = ( empty => 'qidE', invalid => 'qidI' );

    my $n_answers   = 1 + $#{$cts};
    my $n_questions = 1 + $#q;

    if ($vertical_flow) {
        $doc->expandTable( $stats, 6 * $n_questions + $n_answers, 5 );
    } else {
        $doc->expandTable( $stats, 50, 5 * $n_questions );
    }

    my $ybase = 0;
    my $x     = 0;

    $self->{_layout}->begin_read_transaction('Xods');

    for my $q (@q) {

        # QUESTION HEADERS

        $doc->cellSpan( $stats, $ybase, $x, 4 );
        $doc->cellStyle( $stats, $ybase, $x,
            'StatsQName' . ( !$correct_data ? 'I' : 'S' ) );
        $doc->cellValue( $stats, $ybase, $x, encode( 'utf-8', $q->{title} ) );

        $doc->cellStyle( $stats, $ybase + 1, $x, 'statCol' );

        $doc->cellValue(
            $stats,
            $ybase + 1,
            $x,
            encode(
                'utf-8',
                __(
                   # TRANSLATORS: this is a head name in the table
                   # with questions basic statistics in the ODS
                   # exported spreadsheet. The corresponding column
                   # contains the reference of the boxes. Please let
                   # this name short.
                    "Box"
                )
            )
        );
        $doc->cellStyle( $stats, $ybase + 1, $x + 1, 'statCol' );

        $doc->cellValue(
            $stats,
            $ybase + 1,
            $x + 1,
            encode(
                'utf-8',
                __(
                   # TRANSLATORS: this is a head name in the table
                   # with questions basic statistics in the ODS
                   # exported spreadsheet. The corresponding column
                   # contains the number of items (ticked boxes, or
                   # invalid or empty questions). Please let this name
                   # short.
                    "Nb"
                )
            )
        );
        $doc->cellStyle( $stats, $ybase + 1, $x + 2, 'statCol' );

        $doc->cellValue(
            $stats,
            $ybase + 1,
            $x + 2,
            encode(
                'utf-8',
                __(
                   # TRANSLATORS: this is a head name in the table
                   # with questions basic statistics in the ODS
                   # exported spreadsheet. The corresponding column
                   # contains percentage of questions for which the
                   # corresponding box is ticked over all
                   # questions. Please let this name short.
                    "/all"
                )
            )
        );
        $doc->cellStyle( $stats, $ybase + 1, $x + 3, 'statCol' );

        $doc->cellValue(
            $stats,
            $ybase + 1,
            $x + 3,
            encode(
                'utf-8',
                __(
                   # TRANSLATORS: this is a head name in the table
                   # with questions basic statistics in the ODS
                   # exported spreadsheet. The corresponding column
                   # contains percentage of questions for which the
                   # corresponding box is ticked over the expressed
                   # questions (counting only questions that did not
                   # get empty or invalid answers). Please let this
                   # name short.
                    "/expr"
                )
            )
        );

        $doc->columnStyle( $stats, $x + 4, "col.Space" );

        # ANSWERS DATA

        my $amax = 0;

        for my $counts (
            sort { $a->{answer} eq "0" ? 1 : $b->{answer} eq "0" ? -1 : 0 }
            grep { $_->{question} eq $q->{question} } @$cts
          )
        {

            my $ya    = $y_item{ $counts->{answer} };
            my $name  = $y_name{ $counts->{answer} };
            my $style = $y_style{ $counts->{answer} };

            if ( !$ya ) {
                if ( $counts->{answer} > 0 ) {
                    $amax = $counts->{answer}
                      if ( $counts->{answer} > $amax );
                    $ya   = 4 + $counts->{answer};
                    $name = $self->{_layout}
                      ->char( $q->{question}, $counts->{answer} );
                    $name = chr( ord("A") + $counts->{answer} - 1 )
                      if ( !defined($name) || $name eq '' );
                } else {
                    $amax++;
                    $ya = 4 + $amax;

                    $name = __
                      # TRANSLATORS: this is a row label in the table
                      # with questions basic statistics in the ODS
                      # exported spreadsheet. The corresponding row
                      # contains the number of sheets for which the
                      # question got the "none of the above are
                      # correct" answer. Please let this label short.
                      "NONE";
                }
            }

            $doc->cellStyle( $stats, $ybase + $ya, $x + 1, 'NumCopie' );
            $doc->cellValueType( $stats, $ybase + $ya, $x + 1, 'float' );
            $doc->cellValue( $stats, $ybase + $ya, $x + 1, $counts->{nb} );
            $doc->cellStyle( $stats, $ybase + $ya,
                $x, ( $style ? $style : 'General' ) );
            $doc->cellValue( $stats, $ybase + $ya,
                $x, encode( 'utf-8', $name ) );
        }

        # FORMULAS FOR EMPTY/INVALID

        for my $ya ( 3, 4 ) {
            $doc->cellStyle( $stats, $ybase + $ya, $x + 2, 'Qpc' );
            $doc->cellValueType( $stats, $ybase + $ya, $x + 2, 'percentage' );
            $doc->cellFormula(
                $stats,
                $ybase + $ya,
                $x + 2,
                "oooc:=[."
                  . yx2ooo( $ybase + $ya, $x + 1 ) . "]/[."
                  . yx2ooo( $ybase + 2,   $x + 1 ) . "]"
            );
        }

        # FORMULAS FOR STANDARD ANSWERS

        for my $i ( 1 .. $amax ) {
            my $yy = $ybase + 4 + $i;
            $doc->cellValueType( $stats, $yy, $x + 2, 'percentage' );
            $doc->cellFormula( $stats, $yy, $x + 2,
                    "oooc:=[."
                  . yx2ooo( $yy,        $x + 1 ) . "]/[."
                  . yx2ooo( $ybase + 2, $x + 1 )
                  . "]" );
            $doc->cellStyle( $stats, $yy, $x + 2, 'Qpc' );

            $doc->cellValueType( $stats, $yy, $x + 3, 'percentage' );
            $doc->cellFormula( $stats, $yy, $x + 3,
                    "oooc:=[."
                  . yx2ooo( $yy,        $x + 1 ) . "]/([."
                  . yx2ooo( $ybase + 2, $x + 1 ) . "]-[."
                  . yx2ooo( $ybase + 3, $x + 1 ) . "]-[."
                  . yx2ooo( $ybase + 4, $x + 1 )
                  . "])" );
            $doc->cellStyle( $stats, $yy, $x + 3, 'Qpc' );
        }

        # SETS COLOR FOR CORRECT OR NOT ANSWERS

        for my $c ( grep { $_->{question} eq $q->{question} } @$correct_data ) {
            my $ya = 4 + $c->{answer};
            $ya = 4 + $amax if ( $c->{answer} == 0 );
            $doc->cellStyle( $stats, $ybase + $ya, $x,
                  $c->{correct_max} == 0 ? 'qidW'
                : $c->{correct_min} == 1 ? 'qidC'
                :                          'qidX' );
        }

        # TRANSLATION...

        if ($vertical_flow) {
            $ybase += 4 + $amax + 2;
        } else {
            $x += 5;
        }

    }

    $self->{_layout}->end_transaction('Xods');

}

sub ods_locked_file {
    my ( $self, $fichier ) = @_;
    $fichier =~ s:([^/]+)$:.~lock.$1\#:;
    return ( -e $fichier );
}

sub export {
    my ( $self, $fichier ) = @_;

    $self->pre_process();

    $self->{_scoring}->begin_read_transaction('XODS');

    my $rd = $self->{_scoring}->variable('rounding');
    $rd = '' if ( !defined($rd) );

    my $arrondi = '';
    if ( $rd =~ /^([ins])/i ) {
        $arrondi = $fonction_arrondi{$1};
    } elsif ($rd) {
        debug "Unknown rounding type: $rd";
    }

    my $grain = $self->{_scoring}->variable('granularity');
    $grain = 0 if ( !defined($grain) );

    my $ndg = 0;
    $grain =~ s/,/./;
    if ( $grain <= 0 ) {
        debug "Invalid grain=$grain: cancel rounding";
        $grain   = 1;
        $arrondi = '';
        $ndg     = 3;
    } elsif ( !$rd ) {
        $ndg = 3;
    } elsif ( $grain =~ /[.,]([0-9]*[1-9])/ ) {
        $ndg = length($1);
    }

    my $lk = $self->{'association.key'}
      || $self->{_assoc}->variable('key_in_list');

    my $notemin = $self->{_scoring}->variable('mark_floor');
    my $plafond = $self->{_scoring}->variable('ceiling');

    $notemin = '' if ( !defined($notemin) || $notemin =~ /[a-z]/i );

    my $la_date = odfLocaltime();

    my $archive = odfContainer(
        $fichier,
        create   => 'spreadsheet',
        work_dir => File::Spec->tmpdir
    );

    my $doc = odfConnector(
        container => $archive,
        part      => 'content',
    );
    my $styles = odfConnector(
        container => $archive,
        part      => 'styles',
    );

    my %col_styles = ();

    $doc->createStyle(
        'col.notes',
        family     => 'table-column',
        properties => {
            -area          => 'table-column',
            'column-width' => "1cm",
        },
    );
    $col_styles{notes} = 1;

    for ( keys %largeurs ) {
        $doc->createStyle(
            'col.' . $_,
            family     => 'table-column',
            properties => {
                -area          => 'table-column',
                'column-width' => $largeurs{$_},
            },
        );
        $col_styles{$_} = 1;
    }

    $styles->createStyle(
        'DeuxDecimales',
        namespace  => 'number',
        type       => 'number-style',
        properties => {
            'number:decimal-places'     => "2",
            'number:min-integer-digits' => "1",
            'number:grouping'           => 'true',  # espace tous les 3 chiffres
            'number:decimal-replacement' =>
              "",    # n'ecrit pas les decimales nulles
        },
    );

    my $pc = $styles->createStyle(
        'Percentage',
        namespace  => 'number',
        type       => 'percentage-style',
        properties => {
            'number:decimal-places'     => "0",
            'number:min-integer-digits' => "1",
        },
    );
    $styles->appendElement( $pc, 'number:text', text => '%' );

    $styles->createStyle(
        'NombreVide',
        namespace  => 'number',
        type       => 'number-style',
        properties => {
            'number:decimal-places'     => "0",
            'number:min-integer-digits' => "0",
            'number:grouping'           => 'true',  # espace tous les 3 chiffres
            'number:decimal-replacement' =>
              "",    # n'ecrit pas les decimales nulles
        },
    );

    $styles->createStyle(
        'numNote',
        namespace  => 'number',
        type       => 'number-style',
        properties => {
            'number:decimal-places'     => $ndg,
            'number:min-integer-digits' => "1",
            'number:grouping'           => 'true',  # espace tous les 3 chiffres
        },
    );

    $styles->createStyle(
        'Tableau',
        parent     => 'Default',
        family     => 'table-cell',
        properties => {
            -area       => 'table-cell',
            'fo:border' => "0.039cm solid \#000000"
            ,    # epaisseur trait / solid|double / couleur
        },
    );

    # General
    $styles->createStyle(
        'General',
        parent     => 'Tableau',
        family     => 'table-cell',
        properties => {
            -area            => 'paragraph',
            'fo:text-align'  => "start",
            'fo:margin-left' => "0.1cm",
        },
        references => { 'style:data-style-name' => 'Percentage' },
    );

    # Qpc : pourcentage de reussite global pour une question
    $styles->createStyle(
        'Qpc',
        parent     => 'Tableau',
        family     => 'table-cell',
        properties => {
            -area           => 'paragraph',
            'fo:text-align' => "center",
        },
        references => { 'style:data-style-name' => 'Percentage' },
    );

    # QpcGS : pourcentage de reussite global pour un groupe
    $styles->createStyle(
        'QpcGS',
        parent     => 'Qpc',
        family     => 'table-cell',
        properties => {
            -area                 => 'table-cell',
            'fo:background-color' => "#c4eeba",
        },
    );

    # StatsQName : nom de question
    $styles->createStyle(
        'StatsQName',
        parent     => 'Tableau',
        family     => 'table-cell',
        properties => {
            -area           => 'paragraph',
            'fo:text-align' => "center",
        },
    );
    $styles->updateStyle(
        'StatsQName',
        properties => {
            -area            => 'text',
            'fo:font-weight' => 'bold',
            'fo:font-size'   => "14pt",
        },
    );
    $styles->createStyle(
        'StatsQNameS',
        parent     => 'StatsQName',
        family     => 'table-cell',
        properties => {
            -area                 => 'table-cell',
            'fo:background-color' => "#c4ddff",
        },
    );
    $styles->createStyle(
        'StatsQNameM',
        parent     => 'StatsQName',
        family     => 'table-cell',
        properties => {
            -area                 => 'table-cell',
            'fo:background-color' => "#f5c4ff",
        },
    );
    $styles->createStyle(
        'StatsQNameI',
        parent     => 'StatsQName',
        family     => 'table-cell',
        properties => {
            -area                 => 'table-cell',
            'fo:background-color' => "#e6e6ff",
        },
    );

    $styles->createStyle(
        'statCol',
        parent     => 'Tableau',
        family     => 'table-cell',
        properties => {
            -area           => 'paragraph',
            'fo:text-align' => "center",
        },
    );
    $styles->updateStyle(
        'statCol',
        properties => {
            -area            => 'text',
            'fo:font-weight' => 'bold',
        },
    );

    $styles->createStyle(
        'qidW',
        parent     => 'General',
        family     => 'table-cell',
        properties => {
            -area                 => 'table-cell',
            'fo:background-color' => "#ffc8a0",
        },
    );
    $styles->createStyle(
        'qidC',
        parent     => 'General',
        family     => 'table-cell',
        properties => {
            -area                 => 'table-cell',
            'fo:background-color' => "#c9ffd1",
        },
    );
    $styles->createStyle(
        'qidX',
        parent     => 'General',
        family     => 'table-cell',
        properties => {
            -area                 => 'table-cell',
            'fo:background-color' => "#e2e2e2",
        },
    );
    $styles->createStyle(
        'qidI',
        parent     => 'General',
        family     => 'table-cell',
        properties => {
            -area                 => 'table-cell',
            'fo:background-color' => "#ffbaba",
        },
    );
    $styles->createStyle(
        'qidE',
        parent     => 'General',
        family     => 'table-cell',
        properties => {
            -area                 => 'table-cell',
            'fo:background-color' => "#ffff99",
        },
    );

    $doc->createStyle(
        "col.Space",
        family     => 'table-column',
        properties => {
            -area          => 'table-column',
            'column-width' => "4mm",
        },
    );

    # NoteQbase
    $styles->createStyle(
        'NoteQbase',
        parent     => 'Tableau',
        family     => 'table-cell',
        properties => {
            -area           => 'paragraph',
            'fo:text-align' => "center",
        },
    );

    # NoteQ : note pour une question
    $styles->createStyle(
        'NoteQ',
        parent     => 'NoteQbase',
        family     => 'table-cell',
        references => { 'style:data-style-name' => 'DeuxDecimales' },
    );

    # NoteQp : note pour une question, en pourcentage
    $styles->createStyle(
        'NoteQp',
        parent     => 'NoteQbase',
        family     => 'table-cell',
        references => { 'style:data-style-name' => 'Percentage' },
    );

    # NoteV : note car pas de reponse
    $styles->createStyle(
        'NoteV',
        parent     => 'NoteQ',
        family     => 'table-cell',
        properties => {
            -area                 => 'table-cell',
            'fo:background-color' => "#ffff99",
        },
        references => { 'style:data-style-name' => 'NombreVide' },
    );

    # NoteC : question annulee (par un allowempty)
    $styles->createStyle(
        'NoteC',
        parent     => 'NoteQ',
        family     => 'table-cell',
        properties => {
            -area                 => 'table-cell',
            'fo:background-color' => "#b1e3e9",
        },
        references => { 'style:data-style-name' => 'NombreVide' },
    );

    # NoteE : note car erreur "de syntaxe"
    $styles->createStyle(
        'NoteE',
        parent     => 'NoteQ',
        family     => 'table-cell',
        properties => {
            -area                 => 'table-cell',
            'fo:background-color' => "#ffbaba",
        },
        references => { 'style:data-style-name' => 'NombreVide' },
    );

    # NoteGS : score total pour un groupe
    $styles->createStyle(
        'NoteGS',
        parent     => 'NoteQbase',
        family     => 'table-cell',
        properties => {
            -area                 => 'table-cell',
            'fo:background-color' => "#c4eeba",
        },
        references => { 'style:data-style-name' => 'DeuxDecimales' },
    );

    # NoteGSp : pourcentage global pour un groupe
    $styles->createStyle(
        'NoteGSp',
        parent     => 'NoteQbase',
        family     => 'table-cell',
        properties => {
            -area                 => 'table-cell',
            'fo:background-color' => "#c4eeba",
        },
        references => { 'style:data-style-name' => 'Percentage' },
    );

    # NoteGSx : pourcentage maximal = 100%
    $styles->createStyle(
        'NoteGSx',
        parent     => 'NoteGSp',
        family     => 'table-cell',
        properties => {
            -area          => 'text',
            'fo:font-size' => "6pt",
        },
    );

    # NoteX : pas de note car la question ne figure pas dans cette copie la
    $styles->createStyle(
        'NoteX',
        parent     => 'Tableau',
        family     => 'table-cell',
        properties => {
            -area           => 'paragraph',
            'fo:text-align' => "center",
        },
        references => { 'style:data-style-name' => 'NombreVide' },
    );

    $styles->updateStyle(
        'NoteX',
        properties => {
            -area                 => 'table-cell',
            'fo:background-color' => "#b3b3b3",
        },
    );

    # CodeV : entree de AMCcode
    $styles->createStyle(
        'CodeV',
        parent     => 'Tableau',
        family     => 'table-cell',
        properties => {
            -area           => 'paragraph',
            'fo:text-align' => "center",
        },
    );

    $styles->updateStyle(
        'CodeV',
        properties => {
            -area                 => 'table-cell',
            'fo:background-color' => "#e6e6ff",
        },
    );

    # CodeA : code d'association
    $styles->createStyle(
        'CodeA',
        parent     => 'Tableau',
        family     => 'table-cell',
        properties => {
            -area           => 'paragraph',
            'fo:text-align' => "center",
        },
    );

    $styles->updateStyle(
        'CodeA',
        properties => {
            -area                 => 'table-cell',
            'fo:background-color' => "#ffddc4",
        },
    );

    # NoteF : note finale pour la copie
    $styles->createStyle(
        'NoteF',
        parent     => 'Tableau',
        family     => 'table-cell',
        properties => {
            -area           => 'paragraph',
            'fo:text-align' => "right",
        },
        references => { 'style:data-style-name' => 'numNote' },
    );

    $styles->updateStyle(
        'NoteF',
        properties => {
            -area              => 'table-cell',
            'fo:padding-right' => "0.2cm",
        },
    );

    $styles->createStyle(
        'Titre',
        parent     => 'Default',
        family     => 'table-cell',
        properties => {
            -area            => 'text',
            'fo:font-weight' => 'bold',
            'fo:font-size'   => "16pt",
        },
    );

    $styles->createStyle(
        'NumCopie',
        parent     => 'Tableau',
        family     => 'table-cell',
        properties => {
            -area           => 'paragraph',
            'fo:text-align' => "center",
        },
    );

    $styles->createStyle(
        'Entete',
        parent     => 'Default',
        family     => 'table-cell',
        properties => {
            -area              => 'table-cell',
            'vertical-align'   => "bottom",
            'horizontal-align' => "middle",
            'fo:padding'       => '1mm',          # espace entourant le contenu
            'fo:border' => "0.039cm solid \#000000"
            ,    # epaisseur trait / solid|double / couleur
        },
    );

    $styles->updateStyle(
        'Entete',
        properties => {
            -area            => 'text',
            'fo:font-weight' => 'bold',
        },
    );

    $styles->updateStyle(
        'Entete',
        properties => {
            -area           => 'paragraph',
            'fo:text-align' => "center",
        },
    );

    # EnteteVertical : en-tete, ecrit verticalement
    $styles->createStyle(
        'EnteteVertical',
        parent     => 'Entete',
        family     => 'table-cell',
        properties => {
            -area                  => 'table-cell',
            'style:rotation-angle' => "90",
        },
    );

    # EnteteIndic : en-tete d'une question indicative
    $styles->createStyle(
        'EnteteIndic',
        parent     => 'EnteteVertical',
        family     => 'table-cell',
        properties => {
            -area                 => 'table-cell',
            'fo:background-color' => "#e6e6ff",
        },
    );

    # EnteteGS : en-tete pour les groupes
    $styles->createStyle(
        'EnteteGS',
        parent     => 'EnteteVertical',
        family     => 'table-cell',
        properties => {
            -area                 => 'table-cell',
            'fo:background-color' => "#c4eeba",
        },
    );

    my @student_columns = split( /,+/, $self->{'out.columns'} );

    my @codes;
    my @questions;
    $self->codes_questions( \@codes, \@questions, 1 );

    my @questions_0 = grep { $_->{indic0} } @questions;
    my @questions_1 = grep { $_->{indic1} } @questions;

    debug "Questions: "
      . join( ', ', map { $_->{question} . '=' . $_->{title} } @questions );
    debug "Questions PLAIN: " . join( ', ', map { $_->{title} } @questions_0 );
    debug "Questions INDIC: " . join( ', ', map { $_->{title} } @questions_1 );

    my $nq = 1 + $#student_columns + 1 + $#questions_0 + 1 + $#questions_1;

    my $dimx = 3 + $nq + 1 + $#codes;
    my $dimy = 6 + 1 + $#{ $self->{marks} };

    my $feuille = $doc->getTable( 0, $dimy, $dimx );
    $doc->expandTable( $feuille, $dimy, $dimx );
    $doc->renameTable(
        $feuille,
        encode(
            'utf-8',
            (
                $self->{'out.code'} ? $self->{'out.code'}
                :
             __(
                # TRANSLATORS: table name in the exported ODS
                # spreadsheet for the table that contains the marks.
                "Marks")
            )
        )
    );

    if ( $self->{'out.nom'} ) {
        $doc->cellStyle( $feuille, 0, 0, 'Titre' );
        $doc->cellValue( $feuille, 0, 0,
            encode( 'utf-8', $self->{'out.nom'} ) );
    }

    my $x0 = 0;
    my $x1 = 0;
    my $y0 = 2;
    my $y1 = 0;
    my $ii;
    my %code_col    = ();
    my %code_row    = ();
    my %col_cells   = ();
    my %col_content = ();

    my $notemax;
    my $notenull;

    my $jj = $y0;

    my @titles = ();

    sub get_title {
        my ($o) = @_;
        my $t;
        if ( ref($o) eq 'HASH' ) {
            $t = encode( 'utf-8', $o->{title} );
        } else {
            $t = encode( 'utf-8', $o );
        }
        return $t;
    }

    ##########################################################################
    # first row: titles
    ##########################################################################

    $ii = $x0;
    for ( @student_columns, qw/note total max/ ) {
        $doc->cellStyle( $feuille, $y0, $ii, 'Entete' );

        $code_col{$_} = $ii;
        my $name = $_;
        $name = "A:" . encode( 'utf-8', $lk )   if ( $name eq 'student.key' );
        $name = translate_column_title('nom')   if ( $name eq 'student.name' );
        $name = translate_column_title('copie') if ( $name eq 'student.copy' );

        $col_content{$_} = [$name];
        $doc->cellValue( $feuille, $y0, $ii, encode( 'utf-8', $name ) );

        $ii++;
    }

    $x1 = $ii;

    for (@questions_0) {
        $doc->columnStyle( $feuille, $ii, 'col.notes' );
        $doc->cellStyle( $feuille, $y0, $ii,
            ( $_->{group_sum} ? 'EnteteGS' : 'EnteteVertical' ) );
        my $t = get_title($_);
        push @titles, $t;
        $doc->cellValue( $feuille, $y0, $ii++, $t );
    }
    for (@questions_1) {
        $doc->columnStyle( $feuille, $ii, 'col.notes' );
        $doc->cellStyle( $feuille, $y0, $ii, 'EnteteIndic' );
        my $t = get_title($_);
        push @titles, $t;
        $doc->cellValue( $feuille, $y0, $ii++, $t );
    }
    for (@codes) {
        $doc->cellStyle( $feuille, $y0, $ii, 'EnteteIndic' );
        my $t = get_title($_);
        push @titles, $t;
        $doc->cellValue( $feuille, $y0, $ii++, $t );
    }

    ##########################################################################
    # optional row: null score
    ##########################################################################

    my $mark_null = $self->{_scoring}->variable('mark_null');
    $mark_null = 0 if ( !defined($mark_null) );

    if ( $mark_null != 0 ) {
        $jj++;

        $doc->cellSpan( $feuille, $jj, $code_col{total}, 2 );
        $doc->cellStyle( $feuille, $jj, $code_col{total}, 'General' );
        $doc->cellValue( $feuille, $jj, $code_col{total},
            encode( 'utf-8', translate_id_name('null') ) );

        $doc->cellStyle( $feuille, $jj, $code_col{note}, 'NoteF' );
        $doc->cellValueType( $feuille, $jj, $code_col{note}, 'float' );
        $doc->cellValue( $feuille, $jj, $code_col{note}, $mark_null );
        $notenull = '[.' . yx2ooo( $jj, $code_col{note}, 1, 1 ) . ']';

        $code_row{null} = $jj;
    } else {
        $notenull = '';
    }

    ##########################################################################
    # second row: maximum
    ##########################################################################

    $jj++;

    $doc->cellSpan( $feuille, $jj, $code_col{total}, 2 );
    $doc->cellStyle( $feuille, $jj, $code_col{total}, 'General' );
    $doc->cellValue( $feuille, $jj, $code_col{total},
        encode( 'utf-8', translate_id_name('max') ) );

    $doc->cellStyle( $feuille, $jj, $code_col{note}, 'NoteF' );
    $doc->cellValueType( $feuille, $jj, $code_col{note}, 'float' );
    $doc->cellValue( $feuille, $jj, $code_col{note},
        $self->{_scoring}->variable('mark_max') );
    $notemax = '[.' . yx2ooo( $jj, $code_col{note}, 1, 1 ) . ']';

    $ii = $x1;
    for (@questions_0) {
        if ( defined( $_->{group_sum} ) ) {
            $ii++;
        } else {
            $doc->cellStyle( $feuille, $jj, $ii, 'NoteQ' );
            $doc->cellValueType( $feuille, $jj, $ii, 'float' );
            $doc->cellValue( $feuille, $jj, $ii++,
                $self->{_scoring}->question_maxmax( $_->{question} ) );
        }
    }

    $code_row{max} = $jj;

    ##########################################################################
    # third row: mean
    ##########################################################################

    $jj++;

    $doc->cellSpan( $feuille, $jj, $code_col{total}, 2 );
    $doc->cellStyle( $feuille, $jj, $code_col{total}, 'General' );
    $doc->cellValue( $feuille, $jj, $code_col{total},
        encode( 'utf-8', translate_id_name('moyenne') ) );
    $code_row{average} = $jj;

    ##########################################################################
    # following rows: students sheets
    ##########################################################################

    my @presents = ();
    my %scores;
    my @scores_columns;
    my %group_single = ();

    $y1 = $jj + 1;

    for my $m ( @{ $self->{marks} } ) {
        $jj++;

        # @presents collects the indices of the rows corresponding to
        # students that where present at the exam.
        push @presents, $jj if ( !$m->{abs} );

        # for current student sheet, @score_columns collects the
        # indices of the columns where questions scores (only those
        # that are to be summed up to get the total student score, not
        # those from indicative questions)
        # are. $scores{$question_number} is set to one when a question
        # score is added to this list.
        %scores         = ();
        @scores_columns = ();

        # first: special columns (association key, name, mark, sheet
        # number, total score, max score)

        $ii = $x0;

        for (@student_columns) {
            my $value = ( $m->{$_} ? $m->{$_} : $m->{'student.all'}->{$_} );
            push @{ $col_content{$_} }, $value;
            set_cell( $doc, $feuille, $jj, $ii++, $m->{abs}, $_,
                $value, 'utf8' => 1 );
        }

        if ( $m->{abs} ) {
            set_cell( $doc, $feuille, $jj, $ii, 1, 'NOTE', $m->{mark} );
        } else {
            set_cell(
                $doc, $feuille, $jj, $ii, 0, 'NOTE',
                '',
                numeric => 1,
                formula => "oooc:=IF($notemax>0;"
                  . ( $notemin ne '' ? "MAX($notemin;" : "" )
                  . ( $plafond       ? "MIN($notemax;" : "" )
                  . ( $notenull      ? $notenull . "+" : "" )
                  . "$arrondi([."
                  . yx2ooo( $jj, $code_col{total} ) . "]/[."
                  . yx2ooo( $jj, $code_col{max} ) . "]*"
                  . (
                    $notenull
                    ? "(" . $notemax . "-" . $notenull . ")"
                    : $notemax
                  )
                  . "/$grain)*$grain"
                  . ( $plafond       ? ")"             : "" )
                  . ( $notemin ne '' ? ")"             : "" ) . ";"
                  . ( $notemin ne '' ? "MAX($notemin;" : "" )
                  . ( $notenull      ? $notenull . "+" : "" )
                  . "$arrondi([."
                  . yx2ooo( $jj, $code_col{total} )
                  . "]/$grain)*$grain"
                  . ( $notemin ne '' ? ")" : "" ) . ")"
            );
        }
        $ii++;

        $ii++;    # see later for SUM column value...
        set_cell( $doc, $feuille, $jj, $ii++, $m->{abs},
            'MAX', $m->{max}, numeric => 1 );

        # second: columns for all questions scores

        my @group_columns = ();
        my $group_maxsum  = 0;

        for my $q ( @questions_0, @questions_1 ) {
            if ( $m->{abs} ) {
                $doc->cellStyle( $feuille, $jj, $ii, 'NoteX' );
            } else {
                if ( defined( $q->{group_sum} ) ) {

                    # this is a group total column...
                    if (@group_columns) {
                        if ( defined( $group_single{ $q->{group_sum} } ) ) {
                            $group_single{ $q->{group_sum} }->{ok} = 0
                              if ( $group_maxsum !=
                                $group_single{ $q->{group_sum} }->{maxsum} );
                        } else {
                            $group_single{ $q->{group_sum} } =
                              { ii => $ii, maxsum => $group_maxsum, ok => 1 };
                        }
                        if ( $self->{'out.groupsums'} == 2 ) {

                            # as a percentage
                            set_cell(
                                $doc,  $feuille, $jj, $ii, $m->{abs},
                                'GSp', '',
                                pc      => 1,
                                formula => "oooc:=SUM("
                                  . subrow_condensed( $jj, @group_columns )
                                  . ")/"
                                  . $group_maxsum
                            );
                        } else {

                            # value
                            set_cell(
                                $doc, $feuille, $jj, $ii, $m->{abs},
                                'GS', '',
                                numeric => 1,
                                formula => "oooc:=SUM("
                                  . subrow_condensed( $jj, @group_columns )
                                  . ")"
                            );
                        }
                        push @{ $col_cells{$ii} }, $jj;
                    } else {
                        $doc->cellStyle( $feuille, $jj, $ii, 'NoteX' );
                    }
                    @group_columns = ();
                    $group_maxsum  = 0;
                } else {
                    my $r =
                      $self->{_scoring}
                      ->question_result( $m->{student}, $m->{copy},
                        $q->{question} );
                    $doc->cellValueType( $feuille, $jj, $ii, 'float' );
                    if ( $self->{_scoring}
                        ->indicative( $m->{student}, $q->{question} ) )
                    {
                        $doc->cellStyle( $feuille, $jj, $ii, 'CodeV' );
                    } else {
                        if ( defined( $r->{score} ) ) {
                            if ( !$scores{ $q->{question} } ) {
                                $scores{ $q->{question} } = 1;
                                push @scores_columns, $ii;
                                push @{ $col_cells{$ii} }, $jj;
                                if ( $q->{group} ) {
                                    push @group_columns, $ii;
                                    $group_maxsum += $r->{max};
                                }
                                if ( $r->{why} =~ /c/i ) {
                                    $doc->cellStyle( $feuille, $jj, $ii,
                                        'NoteC' );
                                } elsif ( $r->{why} =~ /v/i ) {
                                    $doc->cellStyle( $feuille, $jj, $ii,
                                        'NoteV' );
                                } elsif ( $r->{why} =~ /e/i ) {
                                    $doc->cellStyle( $feuille, $jj, $ii,
                                        'NoteE' );
                                } else {
                                    $doc->cellStyle( $feuille, $jj, $ii,
                                        'NoteQ' );
                                }
                            } else {
                                $doc->cellStyle( $feuille, $jj, $ii, 'NoteX' );
                            }
                        } else {
                            $doc->cellStyle( $feuille, $jj, $ii, 'NoteX' );
                        }
                    }
                    $doc->cellValue( $feuille, $jj, $ii, $r->{score} );
                }
            }
            $ii++;
        }

        # third: codes values

        for (@codes) {
            $doc->cellStyle( $feuille, $jj, $ii, 'CodeV' );
            $doc->cellValue( $feuille, $jj, $ii++,
                $self->{_scoring}->student_code( $m->{student}, $m->{copy}, $_ )
            );
        }

        # come back to add sum of the scores
        set_cell(
            $doc,    $feuille, $jj, $code_col{total}, $m->{abs},
            'TOTAL', '',
            numeric => 1,
            formula => "oooc:=SUM("
              . subrow_condensed( $jj, @scores_columns ) . ")"
        );
    }

    ##########################################################################
    # back to row for means
    ##########################################################################

    $ii = $x1;
    for my $q (@questions_0) {
        $doc->cellStyle( $feuille, $code_row{average}, $ii, 'Qpc' );
        $doc->cellFormula( $feuille, $code_row{average}, $ii,
                "oooc:=AVERAGE("
              . subcolumn_condensed( x2ooo($ii), @{ $col_cells{$ii} } )
              . ")/[."
              . yx2ooo( $code_row{max}, $ii )
              . "]" );

        $ii++;
    }

    $doc->cellStyle( $feuille, $code_row{average}, $code_col{note}, 'NoteF' );
    $doc->cellFormula( $feuille, $code_row{average}, $code_col{note},
            "oooc:=AVERAGE("
          . subcolumn_condensed( x2ooo( $code_col{note} ), @presents )
          . ")" );

    $self->{_scoring}->end_transaction('XODS');

    ##########################################################################
    # back to row for groups max
    ##########################################################################

    for my $g ( keys %group_single ) {
        my $j0 = $code_row{max};
        my $i0 = $group_single{$g}->{ii};
        if ( $self->{'out.groupsums'} == 2 ) {

            # for each student, percentages are reported, so that maximal
            # value is 100%
            $doc->cellStyle( $feuille, $j0, $i0, 'NoteGSx' );
            $doc->cellValueType( $feuille, $j0, $i0, 'percentage' );
            $doc->cellValue( $feuille, $j0, $i0, 1 );
            $doc->cellStyle( $feuille, $code_row{average}, $i0, 'QpcGS' );
        } elsif ( $group_single{$g}->{ok} ) {
            $doc->cellStyle( $feuille, $j0, $i0, 'NoteGS' );
            $doc->cellValueType( $feuille, $j0, $i0, 'float' );
            $doc->cellValue( $feuille, $j0, $i0, $group_single{$g}->{maxsum} );
            $doc->cellStyle( $feuille, $code_row{average}, $i0, 'QpcGS' );
        } else {
            $doc->cellStyle( $feuille, $j0, $i0, 'NoteX' );
            $doc->cellStyle( $feuille, $code_row{average}, $i0, 'NoteX' );
        }
    }

    ##########################################################################
    # try to set right column width
    ##########################################################################

    for (@student_columns) {
        if ( $col_styles{$_} ) {
            $doc->columnStyle( $feuille, $code_col{$_},
                "col." . $col_styles{$_} );
        } else {
            my ( $cm, $cmh ) = $self->text_width( 10, @{ $col_content{$_} } );
            debug "Column width [$_] = $cm cm";
            $doc->createStyle(
                "col.X.$_",
                family     => 'table-column',
                properties => {
                    -area          => 'table-column',
                    'column-width' => $cm . "cm",
                },
            );
            $doc->columnStyle( $feuille, $code_col{$_}, "col.X.$_" );
        }
    }

    ##########################################################################
    # try to set right line height for titles
    ##########################################################################

    {
        my ( $cm, $cmh ) = $self->text_width( 10, @titles );
        debug "Titles height = $cm cm";
        $doc->createStyle(
            "row.Titles",
            family     => 'table-row',
            properties => {
                -area                    => 'table-row',
                'row-height'             => $cm . "cm",
                'use-optimal-row-height' => "false",
            },
        );
        $doc->rowStyle( $feuille, $y0, "row.Titles" );

        ( $cm, $cmh ) =
          $self->text_width( 16, encode( 'utf-8', $self->{'out.nom'} ) );
        debug "Name height = $cmh cm";
        $doc->createStyle(
            "row.Head",
            family     => 'table-row',
            properties => {
                -area                    => 'table-row',
                'row-height'             => $cmh . "cm",
                'use-optimal-row-height' => "false",
            },
        );
        $doc->rowStyle( $feuille, 0, "row.Head" );
    }

    ##########################################################################
    # tables for questions basic statistics
    ##########################################################################

    my ( $dt, $dtu, $cts, $man, $correct_data );

    if ( $self->{'out.stats'} || $self->{'out.statsindic'} ) {
        $self->{_scoring}->begin_read_transaction('XsLO');
        $dt  = $self->{_scoring}->variable('darkness_threshold');
        $dtu = $self->{_scoring}->variable('darkness_threshold_up');

        # comming back to old projects, the darkness_threshold_up was
        # not stored but now we need a value: use the default value 1
        # (which produces the same behavior as when it was not defined).
        $dtu = 1 if ( !defined($dtu) );

        $cts          = $self->{_capture}->ticked_sums( $dt, $dtu );
        $man          = $self->{_capture}->max_answer_number();
        $correct_data = $self->{_scoring}->correct_for_all
          if ( $self->{'out.stats'} );
        $self->{_scoring}->end_transaction('XsLO');
    }

    if ( $self->{'out.stats'} ) {

        my $stats_0 = $doc->appendTable(
            encode(
                'utf-8',
                __(
                   # TRANSLATORS: Label of the table with questions
                   # basic statistics in the exported ODS spreadsheet.
                    "Questions statistics"
                )
            )
        );

        $self->build_stats_table( $self->{'out.stats'}, $cts, $correct_data,
            $doc, $stats_0, @questions_0 );
    }

    if ( $self->{'out.statsindic'} ) {

        my $stats_1 = $doc->appendTable(
            encode(
                'utf-8',
                __(
                   # TRANSLATORS: Label of the table with indicative
                   # questions basic statistics in the exported ODS
                   # spreadsheet.
                    "Indicative questions statistics"
                )
            )
        );

        $self->build_stats_table( $self->{'out.statsindic'},
            $cts, [], $doc, $stats_1, @questions_1 );
    }

    ##########################################################################
    # Legend table
    ##########################################################################

    my $legend = $doc->appendTable(
        encode(
            'utf-8',
            __(
               # TRANSLATORS: Label of the table with a legend
               # (explaination of the colors used) in the exported ODS
               # spreadsheet.
                "Legend"
            )
        ),
        9,
        2
    );

    $doc->cellSpan( $legend, 0, 0, 2 );
    $doc->cellStyle( $legend, 0, 0, 'Titre' );
    $doc->cellValue( $legend, 0, 0, encode( 'utf-8', __("Legend") ) );

    $jj = 2;

    $doc->cellStyle( $legend, $jj, 0, 'NoteX' );

    $doc->cellValue(
        $legend, $jj, 1,
        encode(
            'utf-8',
            __(
               # TRANSLATORS: From the legend in the exported ODS
               # spreadsheet. This refers to the questions that have
               # not been asked to some students.
                "Non applicable"
            )
        )
    );
    $jj++;
    $doc->cellStyle( $legend, $jj, 0, 'NoteV' );

    $doc->cellValue(
        $legend, $jj, 1,
        encode(
            'utf-8',
            __(
               # TRANSLATORS: From the legend in the exported ODS
               # spreadsheet. This refers to the questions that have
               # not been answered.
                "No answer"
            )
        )
    );
    $jj++;
    $doc->cellStyle( $legend, $jj, 0, 'NoteC' );

    $doc->cellValue(
        $legend, $jj, 1,
        encode(
            'utf-8',
            __(
               # TRANSLATORS: From the legend in the exported ODS
               # spreadsheet. This refers to the questions that have
               # not been answered, but are cancelled by the use of
               # allowempty scoring strategy.
                "Cancelled"
            )
        )
    );
    $jj++;
    $doc->cellStyle( $legend, $jj, 0, 'NoteE' );

    $doc->cellValue(
        $legend, $jj, 1,
        encode(
            'utf-8',
            __(
               # TRANSLATORS: From the legend in the exported ODS
               # spreadsheet. This refers to the questions that got an
               # invalid answer.
                "Invalid answer"
            )
        )
    );
    $jj++;
    if ( $self->{'out.stats'} ) {
        $doc->cellStyle( $legend, $jj, 0, 'qidC' );

        $doc->cellValue(
            $legend, $jj, 1,
            encode(
                'utf-8',
                __(
                    # TRANSLATORS: From the legend in the exported ODS
                    # spreadsheet. This refers to the questions that
                    # got an invalid answer.
                    "Correct answer"
                )
            )
        );
        $jj++;
        $doc->cellStyle( $legend, $jj, 0, 'qidW' );

        $doc->cellValue(
            $legend, $jj, 1,
            encode(
                'utf-8',
                __(
                   # TRANSLATORS: From the legend in the exported ODS
                   # spreadsheet. This refers to the questions that
                   # got an invalid answer.
                    "Wrong answer"
                )
            )
        );
        $jj++;
    }
    $doc->cellStyle( $legend, $jj, 0, 'CodeV' );

    $doc->cellValue(
        $legend, $jj, 1,
        encode(
            'utf-8',
            __(
               # TRANSLATORS: From the legend in the exported ODS
               # spreadsheet. This refers to the indicative questions.
                "Indicative"
            )
        )
    );
    $jj++;

    $doc->createStyle(
        "col.X.legend",
        family     => 'table-column',
        properties => {
            -area          => 'table-column',
            'column-width' => "6cm",
        },
    );
    $doc->columnStyle( $legend, 1, "col.X.legend" );

    ##########################################################################
    # set meta-data and write to file
    ##########################################################################

    my $meta = odfMeta( container => $archive );

    $meta->title( encode( 'utf-8', $self->{'out.nom'} ) );
    $meta->subject('');
    $meta->creator( $ENV{USER} );
    $meta->initial_creator( $ENV{USER} );
    $meta->creation_date($la_date);
    $meta->date($la_date);

    $archive->save;

    if ( $self->ods_locked_file($fichier) ) {
        $self->add_message(
            'INFO',
            __(
"An old state of the exported file seems to be already opened. Use File/Reload from OpenOffice/LibreOffice to refresh."
            )
        );
    }

}

1;
