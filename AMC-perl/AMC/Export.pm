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

package AMC::Export;

use AMC::Basic;
use AMC::Data;
use AMC::NamesFile;
use AMC::Messages;

our @ISA = ("AMC::Messages");

use_gettext;

my %sorting = (
    l => ['n:student.line'],
    'm' => [ 'n:mark', 's:student.name', 'n:student.line' ],
    'r' => [ 'nr:mark', 's:student.name', 'n:student.line' ],
    i => [ 'n:student', 'n:copy', 'n:student.line' ],
    n => [ 's:student.name', 'n:student.line' ],
);

sub new {
    my $class = shift;
    my $self  = {
        'fich.datadir'    => '',
        'fich.noms'       => '',
        'association.key' => '',

        noms => '',

        'noms.encodage'    => '',
        'noms.separateur'  => '',
        'noms.useall'      => 1,
        'noms.postcorrect' => '',
        'noms.abs'         => 'ABS',
        'noms.identifiant' => '',

        'out.rtl' => '',

        'sort.keys' => [ 's:student.name', 'n:student.line' ],
        'sort.cols' => 'smart',

        marks => [],

        messages => [],
    };
    bless( $self, $class );
    return $self;
}

sub set_options {
    my ( $self, $domaine, %f ) = @_;
    for ( keys %f ) {
        my $k = $domaine . '.' . $_;
        if ( defined( $self->{$k} ) ) {
            debug "Option $k = $f{$_}";
            $self->{$k} = $f{$_};
        } else {
            debug "Unusable option <$domaine.$_>\n";
        }
    }
}

sub opts_spec {
    my ( $self, $domaine ) = @_;
    my @o = ();
    for my $k ( grep { /^$domaine/ } ( keys %{$self} ) ) {
        my $kk = $k;
        $kk =~ s/^$domaine\.//;
        push @o, $kk, $self->{$k} if ( $self->{$k} );
    }
    return (@o);
}

sub load {
    my ($self) = @_;
    die "Needs data directory" if ( !-d $self->{'fich.datadir'} );

    $self->{_data}    = AMC::Data->new( $self->{'fich.datadir'} );
    $self->{_scoring} = $self->{_data}->module('scoring');
    $self->{_layout}  = $self->{_data}->module('layout');
    $self->{_assoc}   = $self->{_data}->module('association');

    if ( $self->{'fich.noms'} && !$self->{noms} ) {
        $self->{noms} = AMC::NamesFile::new( $self->{'fich.noms'},
            $self->opts_spec('noms'), );
    }
}

sub question_group {
    my ( $self, $question ) = @_;
    if ( $question->{title} =~ /^(.+?)\Q$self->{"out.groupsep"}\E/ ) {
        return ($1);
    } else {
        return (undef);
    }
}

sub group_sum_q {
    my ( $self, %g ) = @_;
    return (
        {
            question => -1,
            %g,
            title => "<" . $g{group_sum} . ">"
        }
    );
}

sub insert_groups_sum_headers {
    my ( $self, @questions ) = @_;
    if ( $self->{'out.groupsums'} ) {
        my %group = ();
        my @r     = ();
        for my $q (@questions) {
            my $g = $self->question_group($q);
            $q->{group} = $g if ( defined($g) );

            if ( defined($g) && $g eq $group{group_sum} ) {
                $group{indic0} = 1 if ( $q->{indic0} );
                $group{indic1} = 1 if ( $q->{indic1} );
                $group{n}++;
            } else {
                push @r, $self->group_sum_q(%group)
                  if ( defined( $group{group_sum} ) );
                %group = (
                    group_sum => $g,
                    n         => 1,
                    indic0    => $q->{indic0},
                    indic1    => $q->{indic1}
                );
            }
            push @r, $q;
        }
        push @r, $self->group_sum_q(%group) if ( defined( $group{group_sum} ) );
        return (@r);
    } else {
        return (@questions);
    }
}

sub test_indicative {
    my ( $self, $question ) = @_;
    for my $state ( 0, 1 ) {
        $question->{ 'indic' . $state } = 1
          if (
            $self->{_scoring}->one_indicative( $question->{question}, $state )
          );
    }
}

sub sort_cols {
    my ( $self, @x ) = @_;
    return ( sort { $self->cols_cmp( $a->{title}, $b->{title} ) } (@x) );
}

sub cols_cmp {
    my ( $self, $a, $b ) = @_;
    if ( $self->{'sort.cols'} eq 'smart' ) {
        if ( $a !~ /[^0-9\s]/ && $b !~ /[^0-9\s]/ ) {
            return ( $a <=> $b );
        } else {
            return ( $a cmp $b );
        }
    } else {
        return (0);
    }
}

sub codes_questions {
    my ( $self, $codes, $questions, $plain ) = @_;
    @$codes = $self->{_scoring}->codes();
    my $code_digit_pattern = $self->{_layout}->code_digit_pattern();
    if ($plain) {
        my $codes_re = "(" . join( "|", map { "\Q$_\E" } @$codes ) . ")";
        @$questions = $self->sort_cols(
            grep { $_->{title} !~ /^$codes_re$code_digit_pattern$/ }
              $self->{_scoring}->questions );
    } else {
        @$questions = $self->sort_cols( $self->{_scoring}->questions );
    }
    for (@$questions) { $self->test_indicative($_); }
    @$questions = $self->insert_groups_sum_headers(@$questions);
}

sub pre_process {
    my ($self) = @_;

    $self->{'sort.keys'} = $sorting{ lc($1) }
      if ( $self->{'sort.keys'} =~ /^\s*([lmrin])\s*$/i );
    $self->{'sort.keys'} = [] if ( !$self->{'sort.keys'} );

    $self->load();

    $self->{_scoring}->begin_read_transaction('EXPP');

    my $lk = $self->{'association.key'}
      || $self->{_assoc}->variable('key_in_list');
    my %keys         = ();
    my @marks        = ();
    my @post_correct = $self->{_scoring}->postcorrect_sc;

    # Get all students from the marks table

    my $sth = $self->{_scoring}->statement('marks');
    $sth->execute;
  STUDENT: while ( my $m = $sth->fetchrow_hashref ) {
        next STUDENT
          if ( ( !$self->{'noms.postcorrect'} )
            && $m->{student} == $post_correct[0]
            && $m->{copy} == $post_correct[1] );

        $m->{abs}            = 0;
        $m->{'student.copy'} = studentids_string( $m->{student}, $m->{copy} );

        # Association key for this sheet
        $m->{'student.key'} =
          $self->{_assoc}->get_real( $m->{student}, $m->{copy} );
        $keys{ $m->{'student.key'} } = 1 if ( $m->{'student.key'} );

        # find the corresponding name
        my $n;
        if ( $self->{noms} ) {
            ($n) = $self->{noms}
              ->data( $lk, $m->{'student.key'}, test_numeric => 1 );
        }
        if ($n) {
            $m->{'student.name'} = $n->{_ID_};
            $m->{'student.line'} = $n->{_LINE_};
            $m->{'student.all'}  = {%$n};

            # $n->{$lk} should be equal to $m->{'student.key'}, but in
            # some cases (older versions), the code stored in the database
            # has leading zeroes removed...
            $keys{ $n->{$lk} } = 1;
        } else {
            for (qw/name line/) {
                $m->{"student.$_"} = '?';
            }
        }
        push @marks, $m;
    }

    # Now, add students with no mark (if requested)

    if ( $self->{'noms.useall'} && $self->{noms} ) {
        for my $i ( $self->{noms}->liste($lk) ) {
            if ( !defined($i) || !$keys{$i} ) {
                my ($name) = $self->{noms}->data( $lk, $i, test_numeric => 1 );
                push @marks,
                  {
                    student        => '',
                    copy           => '',
                    'student.copy' => '',
                    abs            => 1,
                    'student.key'  => $name->{$lk},
                    mark           => $self->{'noms.abs'},
                    'student.name' => $name->{_ID_},
                    'student.line' => $name->{_LINE_},
                    'student.all'  => {%$name},
                  };
            }
        }
    }

    # sorting as requested

    debug "Sorting with keys " . join( ", ", @{ $self->{'sort.keys'} } );
    $self->{marks} = [ sort { $self->compare( $a, $b ); } @marks ];

    $self->{_scoring}->end_transaction('EXPP');

}

sub compare {
    my ( $self, $xa, $xb ) = @_;
    my $r = 0;

    for my $k ( @{ $self->{'sort.keys'} } ) {
        my $key  = $k;
        my $mode = 's';

        if ( $k =~ /^([nsr]+):(.*)/ ) {
            $mode = $1;
            $key  = $2;
        }

        my $default = ( $mode =~ /n/ ? 0 : '' );
        my $a       = $xa->{$key};
        my $b       = $xb->{$key};
        $a = $default if ( !defined($a) );
        $b = $default if ( !defined($b) );
        my $key_r;
        if ( $mode =~ /n/ ) {
            no warnings;
            $key_r = $a <=> $b;
        } else {
            $key_r = $a cmp $b;
        }
        $key_r = -$key_r if ( $mode =~ /r/ );
        $r     = $r || $key_r;
    }
    return ($r);
}

sub export {
    my ( $self, $fichier ) = @_;

    debug "WARNING: Base class export to $fichier\n";
}

1;

