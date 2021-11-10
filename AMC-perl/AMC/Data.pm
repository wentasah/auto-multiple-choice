# -*- perl -*-
#
# Copyright (C) 2011-2021 Alexis Bienvenüe <paamc@passoire.fr>
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

package AMC::Data;

# AMC::Data handles data storage management for AMC. An AMC::Data can
# load several "modules" which are SQLite database files in a common
# directory $dir, with their associated methods to get/set data.

use Module::Load;
use AMC::Basic;
use DBI;

sub new {
    my ( $class, $dir, %oo ) = @_;

    my $self = {
        directory       => $dir,
        timeout         => 300000,
        dbh             => '',
        modules         => {},
        version_checked => {},
        files           => {},
        on_error        => 'stdout,stderr,die',
        progress        => '',
    };

    for ( keys %oo ) {
        $self->{$_} = $oo{$_} if ( exists( $self->{$_} ) );
    }

    bless( $self, $class );

    $self->connect;

    return $self;
}

# Connects to SQLite (first without any database: this will be done
# when loading the modules), and renew all modules

sub connect {
    my ($self) = @_;
    $self->{dbh} = DBI->connect(
        "dbi:SQLite:",
        undef, undef,
        {
            AutoCommit => 0,
            RaiseError => 0,
        }
    );
    $self->{dbh}->sqlite_busy_timeout( $self->{timeout} );
    $self->{dbh}->{sqlite_unicode} = 1;
    $self->{dbh}->{HandleError}    = sub {
        $self->sql_error(shift);
    };

    $self->{modules} = {};
    for my $m ( keys %{ $self->{version_checked} } ) {
        debug("Connects module $m ($self->{version_checked}->{$m})");
        $self->require_module( $m,
            version_checked => $self->{version_checked}->{$m} );
    }
}

# Disconnects...

sub disconnect {
    my ($self) = @_;
    $self->{version_checked} = {};
    if ( $self->{dbh} ) {

        # record the loaded modules, to be able to load them back with connect()
        for my $m ( keys %{ $self->{modules} } ) {
            $self->{version_checked}->{$m} =
              $self->{modules}->{$m}->{version_checked};
        }

        # disconnect and drop all references
        $self->{modules} = {};
        $self->{dbh}->disconnect;
        $self->{dbh} = '';
    }
}

# SQL errors...

sub sql_error {
    my ( $self, $e ) = @_;
    my $s = "SQL ERROR: $e\nSQL STATEMENT: " . $DBI::lasth->{Statement};
    debug "$s";
    print "$s\n"        if ( $self->{on_error} =~ /\bstdout\b/ );
    print STDERR "$s\n" if ( $self->{on_error} =~ /\bstderr\b/ );
    die "*SQL*"         if ( $self->{on_error} =~ /\bdie\b/ );
}

# directory returns the directory where databases files are stored.

sub directory {
    my ($self) = @_;
    return ( $self->{directory} );
}

# dbh returns the DBI object corresponding to the SQLite session with
# required modules attached.

sub dbh {
    my ($self) = @_;
    return ( $self->{dbh} );
}

# begin_transaction begins a transaction in immediate mode, to be used
# to eventually write to the database.

sub begin_transaction {
    my ( $self, $key ) = @_;
    $key = '----' if ( !$key );
    debug_and_stderr "WARNING: already opened transaction $self->{trans} when starting $key"
        if ( $self->{trans} );
    debug "[$key] BEGIN IMMEDIATE";
    $self->sql_do("BEGIN IMMEDIATE");
    $self->{trans} = $key;
}

# begin_read_transaction begins a transaction for reading data.

sub begin_read_transaction {
    my ( $self, $key ) = @_;
    $key = '----' if ( !$key );
    debug_and_stderr "WARNING: already opened transaction $self->{trans} when starting $key"
        if ( $self->{trans} );
    debug "[$key] BEGIN";
    $self->sql_do("BEGIN");
    $self->{trans} = $key;
}

# end_transaction end the transaction.

sub end_transaction {
    my ( $self, $key ) = @_;
    $key = '----' if ( !$key );
    debug_and_stderr
      "WARNING: closing transaction $self->{trans} declared as $key"
        if ( $self->{trans} ne $key );
    debug "[$key] COMMIT";
    $self->sql_do("COMMIT");
    $self->{trans} = '';
}

# sql_quote($string) can be used to quote a string before including it
# in a SQL query.

sub sql_quote {
    my ( $self, $string ) = @_;
    return $self->{dbh}->quote($string);
}

# sql_do($sql,@bind) executes the SQL query $sql, replacing ? by the
# elements of @bind.

sub sql_do {
    my ( $self, $sql, @bind ) = @_;
    debug_and_stderr "WARNING: sql_do with no transaction -- $sql"
      if ( $sql !~ /^\s*(attach|begin)/i && !$self->{trans} );
    $self->{dbh}->do( $sql, {}, @bind );
}

# sql_tables($tables) gets the list of tables matching pattern $tables.

sub sql_tables {
    my ( $self, $tables ) = @_;
    return ( $self->{dbh}->tables( '%', '%', $tables ) );
}

# require_module($module) loads the database file corresponding to
# module $module (found in the data directory), and associated methods
# defined in AMC::DataModule::$module perl package.

sub require_module {
    my ( $self, $module, %oo ) = @_;
    if ( !$self->{modules}->{$module} ) {
        my $filename = $self->{directory} . "/" . $module . ".sqlite";
        if ( !-f $filename ) {
            debug("Creating unexistant database file for module $module...");
        }

        debug "Connecting to database $module...";
        $self->{dbh}->{AutoCommit}     = 1;
        $self->{dbh}->{sqlite_unicode} = 0;
        $self->sql_do( "ATTACH DATABASE ? AS $module", $filename );
        $self->{dbh}->{sqlite_unicode} = 1;
        $self->{dbh}->{AutoCommit}     = 0;

        debug "Loading perl module $module...";
        load("AMC::DataModule::$module");
        $self->{modules}->{$module} =
          "AMC::DataModule::$module"->new( $self, %oo );
        $self->{files}->{$module} = $filename;

        debug "Module $module loaded.";
    }
}

# module($module) returns the module object associated to module
# $module (call the methods from module $module from this object).

sub module {
    my ( $self, $module, %oo ) = @_;
    $self->require_module( $module, %oo );
    return ( $self->{modules}->{$module} );
}

# module_path($module) returns the path of the SQLite database
# associated with this module, or undef if the module has not been
# loaded.

sub module_path {
    my ( $self, $module ) = @_;
    return ( $self->{files}->{$module} );
}

# progression is called by DataModule methods when long actions are
# beeing executed, to show the user the progression of this action.

sub progression {
    my ( $self, $action, $argument ) = @_;

    if ( ref( $self->{progress} ) eq 'CODE' ) {
        &{ $self->{progress} }( $action, $argument );
    } elsif ( ref( $self->{progress} ) eq 'HASH' ) {

        require Gtk3;

        if ( $action eq 'begin' ) {
            $self->{'progress.lasttext'} =
              $self->{progress}->{avancement}->get_text();
            $self->{progress}->{avancement}->set_text($argument);

            if ( $self->{progress}->{annulation} ) {
                $self->{'progress.lastcancel'} =
                  $self->{progress}->{annulation}->get_sensitive;
                $self->{progress}->{annulation}->set_sensitive(0);
            }

            $self->{'progress.lastfaction'} =
              $self->{progress}->{avancement}->get_fraction;

            $self->{progress}->{avancement}->set_fraction(0);

            $self->{'progress.lastvisible'} =
              $self->{progress}->{commande}->get_visible;
            $self->{progress}->{commande}->show();

            $self->{'progress.time'} = 0;

            "Gtk3::main_iteration"->() while ( "Gtk3::events_pending"->() );
        } elsif ( $action eq 'end' ) {
            $self->{progress}->{avancement}
              ->set_fraction( $self->{'progress.lastfaction'} );
            $self->{progress}->{commande}
              ->set_visible( $self->{'progress.lastvisible'} );
            $self->{progress}->{avancement}
              ->set_text( $self->{'progress.lasttext'} );
            if ( $self->{progress}->{annulation} ) {
                $self->{progress}->{annulation}
                  ->set_sensitive( $self->{'progress.lastcancel'} );
            }
            "Gtk3::main_iteration"->() while ( "Gtk3::events_pending"->() );
        } elsif ( $action eq 'fraction' ) {

            # Don't update progress bar more than once a second.
            if ( time > $self->{'progress.time'} ) {
                $self->{'progress.time'} = time;
                $self->{progress}->{avancement}->set_fraction($argument);
                "Gtk3::main_iteration"->() while ( "Gtk3::events_pending"->() );
            }
        }
    }
}

1;
