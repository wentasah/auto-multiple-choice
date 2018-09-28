# -*- perl -*-
#
# Copyright (C) 2017 Alexis Bienvenue <paamc@passoire.fr>
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

package AMC::Config;

use AMC::Basic;
use XML::Simple;
use Module::Load;
use Glib;

# This package helps handling AMC configuration.
#
# Sources: global options file (from some profile), state file,
# project options file, command-line options.

use_gettext();

sub new {
  my (%o)=(@_);

  my $self={state=>{},
            global=>{},
            project=>{},
            local=>{},
            profile=>'',
            o_dir=>amc_user_confdir(),
            state_file=>'',
            system_encoding=>'UTF-8',
            shortcuts=>'',
            home_dir=>'',
            empty=>0,
            gui=>0,
           };

  for my $k (keys %o) {
    $self->{$k}=$o{$k} if(defined($self->{$k}));
  }

  bless $self;

  if(!$empty) {
    $self->defaults();
    $self->check_odir();
    $self->load_state();
    $self->load_profile();
  }

  return($self);
}

sub connect_to_window {
  my ($self,$window)=@_;
  $self->{gui}=$window;
}

sub check_odir {
  my ($self)=@_;

  # Creates general options directory if not present

  if(! -d $self->{o_dir}) {
    mkdir($self->{o_dir}) or die "Error creating $self->{o_dir} : $!";

    # gets older verions (<=0.254) main configuration file and move it
    # to the new location

    if(-f $self->{home_dir}.'/.AMC.xml') {
      debug "Moving old configuration file";
      move($self->{home_dir}.'/.AMC.xml',$self->{o_dir}."/cf.default.xml");
    }
  }

  for my $o_sub (qw/plugins/) {
    mkdir($self->{o_dir}."/$o_sub") if(! -d $self->{o_dir}."/$o_sub");
  }
}

sub subdir {
  my ($self,$path)=@_;
  return($self->{o_dir}."/".$path);
}

sub set_local_keys {
  my ($self,@keys)=@_;
  $self->{local}={};
  for my $k (@keys) {
    $self->{local}->{$k}=undef;
  }
}

# Handling passwords

sub passwd_file {
  my ($self,$usage)=@_;
  my $file=$self->{o_dir}."/cf.".$self->{profile}.".p_$usage";
  utf8::downgrade($file);
  return($file);
}

sub set_passwd {
  my ($self,$usage,$pass)=@_;
  my $file=$self->passwd_file($usage);
  if(open my $fh,">",$file) {
    chmod(0600,$file);
    print $fh $pass;
    print $fh "\n";
    print $fh "*" x (64-length($pass)) if(length($pass)<64);
    close $fh;
  } else {
    debug "ERROR: Can't open file $file to save passwd";
  }
}

sub get_passwd {
  my ($self,$usage)=@_;
  my $file=$self->passwd_file($usage);
  my $pass='';
  if(-f $file) {
    $pass=file_content($file);
    $pass =~ s/\n.*//s;
  }
  return($pass);
}

# Read/write options XML files

sub pref_xml_lit {
  my ($file)=@_;
  utf8::downgrade($file);
  if((! -f $file) || (! -r $file) || -z $file) {
    return();
  } else {
    debug("Reading XML config file $file ...");
    my $data=XMLin($file,SuppressEmpty => '',
		   ForceArray=>['docs','email_attachment','printer']);
    return(%$data);
  }
}

sub pref_xml_ecrit {
  my ($data,$name,$file)=@_;
  utf8::downgrade($file);
  if(open my $fh,">:encoding(utf-8)",$file) {
    XMLout($data,
           "XMLDecl"=>'<?xml version="1.0" encoding="UTF-8" standalone="yes"?>',
           "RootName"=>$name,'NoAttr'=>1,
           "OutputFile" => $fh,
          );
    close $fh;
    return(0);
  } else {
    return(1);
  }
}

# state file

sub load_state {
  my ($self)=@_;

  $self->{state_file}=$self->{o_dir}.'/state.xml'
    if(!$self->{state_file});

  $self->{state}={ pref_xml_lit($self->{state_file}) };
  $self->{state}->{apprentissage}={} if(!$self->{state}->{apprentissage});

  # set profile from options, or from state file
  if($self->{profile}) {
    $self->{state}->{profile}=$self->{profile};
  } else {
    $self->{profile}=$self->{state}->{profile} || 'default';
  }
}

# profile global options

sub defaults {
  my ($self)=@_;

  $self->{home_dir}=Glib::get_home_dir() if(!$self->{home_dir});

  # perl -le 'use Gtk3 -init; print Gtk3::Gdk::Color::parse("blue")->to_string()'
  my $hex_black="#000000000000";
  my $hex_red="#ffff00000000";
  my $hex_blue="#00000000ffff";

  $self->{o_default} =
    {
     pdf_viewer=>['command',
                  'evince','acroread','gpdf','okular','xpdf',
                 ],
     img_viewer=>['command',
                  'eog','ristretto','gpicview','mirage','gwenview',
                 ],
     csv_viewer=>['command',
                  'gnumeric','kspread','libreoffice','localc','oocalc',
                 ],
     ods_viewer=>['command',
                  'libreoffice','localc','oocalc',
                 ],
     xml_viewer=>['command',
                  'gedit','kedit','kwrite','mousepad','leafpad',
                 ],
     tex_editor=>['command',
                  'texmaker','kile','gummi','emacs','gedit','kedit','kwrite','mousepad','leafpad',
                 ],
     txt_editor=>['command',
                  'gedit','kedit','kwrite','mousepad','emacs','leafpad',
                 ],
     html_browser=>['command',
                    'sensible-browser %u',
                    'firefox %u',
                    'galeon %u',
                    'konqueror %u',
                    'dillo %u',
                    'chromium %u',
                   ],
     dir_opener=>['command',
                  'nautilus file://%d',
                  'pcmanfm %d',
                  'Thunar %d',
                  'konqueror file://%d',
                  'dolphin %d',
                 ],
     print_command_pdf=>['command',
                         'cupsdoprint %f','lpr %f',
                        ],
     print_extract_with=>['command','qpdf','pdftk','gs'],
     # TRANSLATORS: directory name for projects. This directory will be created (if needed) in the home directory of the user. Please use only alphanumeric characters, and - or _. No accentuated characters.
     rep_projets=>$self->{home_dir}.'/'.__"MC-Projects",
     projects_home=>$self->{home_dir}.'/'.__"MC-Projects",
     rep_modeles=>$self->{o_dir}."/Models",

     seuil_eqm=>3.0,
     seuil_sens=>8.0,
     saisie_dpi=>150,
     vector_scan_density=>250,
     force_convert=>'',
     n_procs=>0,
     delimiteur_decimal=>',',
     defaut_encodage_liste=>'UTF-8',
     encodage_interne=>'UTF-8',
     defaut_encodage_csv=>'UTF-8',
     encodage_latex=>'',
     defaut_moteur_latex_b=>'pdflatex',
     defaut_seuil=>0.15,
     defaut_seuil_up=>1.0,
     assoc_window_size=>'',
     mailing_window_size=>'',
     preferences_window_size=>'',
     checklayout_window_size=>'',
     manual_window_size=>'',
     marks_window_size=>'',
     conserve_taille=>1,
     methode_impression=>'CUPS',
     imprimante=>'',
     printer_useful_options=>'Staple Stapling StapleLocation StapleSet StapleOption',
     options_impression=>{sides=>'two-sided-long-edge',
                          'number-up'=>1,
                          repertoire=>'/tmp',
                          print_answersheet=>'',
                         },
     manuel_image_type=>'xpm',
     assoc_ncols=>4,
     tolerance_marque_inf=>0.2,
     tolerance_marque_sup=>0.2,
     box_size_proportion=>0.8,
     bw_threshold=>0.6,
     ignore_red=>0,
     try_three=>1,

     prepare_solution=>1,
     prepare_indiv_solution=>1,
     prepare_catalog=>1,

     symboles_trait=>2,
     symboles_indicatives=>'',
     symbole_0_0_type=>'none',
     symbole_0_0_color=>$hex_black,
     symbole_0_1_type=>'circle',
     symbole_0_1_color=>$hex_red,
     symbole_1_0_type=>'mark',
     symbole_1_0_color=>$hex_red,
     symbole_1_1_type=>'mark',
     symbole_1_1_color=>$hex_blue,

     annote_font_name=>'Linux Libertine O 12',
     annote_ecart=>5.5,
     annote_chsign=>4,

     nonascii_projectnames=>'',
     ascii_filenames=>1,

     defaut_note_null=>0,
     defaut_note_min=>'',
     defaut_note_max=>20,
     defaut_note_max_plafond=>1,
     defaut_note_grain=>"0.5",
     defaut_note_arrondi=>'inf',

     defaut_annote_rtl=>'',
# TRANSLATORS: This is the default text to be written on the top of the first page of each paper when annotating. From this string, %s will be replaced with the student final mark, %m with the maximum mark he can obtain, %S with the student total score, and %M with the maximum score the student can obtain.
     defaut_verdict=>"%(ID)\n".__("Mark: %s/%m (total score: %S/%M)"),
     defaut_verdict_q=>"\"%"."s/%"."m\"",
     defaut_verdict_qc=>"\"X\"",
     embedded_max_size=>'1000x1500',
     embedded_format=>'jpeg',
     embedded_jpeg_quality=>75,

     zoom_window_height=>400,
     zoom_window_factor=>1.0,
     zooms_ncols=>4,
     zooms_edit_mode=>0,

     email_sender=>'',
     email_cc=>'',
     email_bcc=>'',
     email_transport=>'sendmail',
     email_sendmail_path=>['command',
                           '/usr/sbin/sendmail','/usr/bin/sendmail',
                           '/sbin/sendmail','/bin/sendmail'],
     email_smtp_host=>'smtp',
     email_smtp_port=>25,
     email_smtp_ssl=>0,
     email_smtp_user=>'',
     SMTP=>'',
# TRANSLATORS: Subject of the emails which can be sent to the students to give them their annotated completed answer sheet.
     defaut_email_subject=>__"Exam result",
# TRANSLATORS: Body text of the emails which can be sent to the students to give them their annotated completed answer sheet.
     defaut_email_text=>__"Please find enclosed your annotated completed answer sheet.\nRegards.",
     email_delay=>0,

     csv_surname_headers=>'',
     csv_name_headers=>'',
     notify_documents=>0,
     notify_capture=>1,
     notify_grading=>1,
     notify_annotation=>1,
     notify_desktop=>lc($^O) ne 'darwin', # macOS does not handle libnotify
     notify_command=>'',

     project_icon_size=>16,

     view_invalid_color=>"#FFEF3B",
     view_empty_color=>"#78FFED",
    };

  $self->{project_default} =
    {
     texsrc=>'',
     data=>'data',
     cr=>'cr',
     listeetudiants=>'',
     notes=>'notes.xml',
     seuil=>'',
     seuil_up=>'',
     encodage_csv=>'',
     encodage_liste=>'',
     maj_bareme=>1,
     doc_question=>'DOC-sujet.pdf',
     doc_solution=>'DOC-corrige.pdf',
     doc_indiv_solution=>'DOC-indiv-solution.pdf',
     doc_setting=>'DOC-calage.xy',
     doc_catalog=>'DOC-catalog.pdf',
     filter=>'',
     filtered_source=>'DOC-filtered.tex',

     modele_regroupement=>'',
     regroupement_compose=>0,
     regroupement_type=>'STUDENTS',
     regroupement_copies=>'ALL',

     note_null=>0,
     note_min=>'',
     note_max=>20,
     note_max_plafond=>1,
     note_grain=>"0.5",
     note_arrondi=>'inf',

     liste_key=>'',
     assoc_code=>'',

     moteur_latex_b=>'',

     nom_examen=>'',
     code_examen=>'',

     nombre_copies=>0,

     postcorrect_student=>0,
     postcorrect_copy=>0,
     postcorrect_set_multiple=>'',

     format_export=>'ods',

     after_export=>'file',
     export_include_abs=>'',

     annote_position=>'marges',

     verdict=>'',
     verdict_q=>'',
     verdict_qc=>'',
     annote_rtl=>'',

     export_sort=>'n',

     auto_capture_mode=>-1,
     allocate_ids=>0,

     email_col=>'',
     email_subject=>"",
     email_text=>"",
     email_attachment=>[],
     email_use_html=>'',

     pdfform=>0,
    };

  # MacOSX universal command to open files or directories : /usr/bin/open
  if(lc($^O) eq 'darwin') {
    for my $k (qw/pdf_viewer img_viewer csv_viewer ods_viewer xml_viewer tex_editor txt_editor dir_opener/) {
      $self->{o_default}->{$k}=['command','/usr/bin/open','open'];
    }
    $self->{o_default}->{html_browser}=['command','/usr/bin/open %u','open %u'];
  }

  # Add default project options for each export module:

  my @export_modules=perl_module_search('AMC::Export::register');
  for my $m (@export_modules) {
    load("AMC::Export::register::$m");
    my %d="AMC::Export::register::$m"->options_default;
    for(keys %d) {
      $self->{project_default}->{$_}=$d{$_};
    }
  }

  $self->{export_modules}=[@export_modules];

}

sub load_profile {
  my ($self)=@_;

  debug "Profile: $self->{profile}";
  $self->{global_file}=$self->{o_dir}."/cf.".$self->{profile}.".xml";

  $self->{global}={ pref_xml_lit($self->{global_file}) };

  $self->set_global_options_to_default();

  $self->test_commands();
}

sub set_global_options_to_default {
  my ($self)=@_;

  for my $k (keys %{$self->{o_default}}) {
    $self->set_global_option_to_default($k);
  }

  # some options were renamed to defaut_* between 0.226 and 0.227
  for(qw/encodage_liste encodage_csv/) {
    if($self->{global}->{$_} && ! $self->{global}->{"defaut_$_"}) {
      $self->{global}->{"defaut_$_"}=$self->{global}->{$_};
      delete($self->{global}->{$_});
    }
  }

  # Replace old (pre 0.280) rep_modeles value with new one
  if($self->{global}->{rep_modeles} eq '/usr/share/doc/auto-multiple-choice/exemples') {
    $self->{global}->{rep_modeles}=$self->{o_default}->{rep_modeles};
  }
}

sub set_global_option_to_default {
  my ($self,$key,$subkey,$force)=@_;
  if($subkey) {
    if($force || ! exists($self->{global}->{$key}->{$subkey})) {
      $self->{global}->{$key}->{$subkey}=$self->{o_default}->{$key}->{$subkey};
      debug "New sub-global parameter : $key/$subkey = $self->{global}->{$key}->{$subkey}";
    }
  } else {
    if($force || ! exists($self->{global}->{$key})) {
      # set to default
      if(ref($self->{o_default}->{$key}) eq 'ARRAY') {
        my ($kind,@values)=@{$self->{o_default}->{$key}};
        # [ 'command' , <commands> ] --> choose the first existing command
        if($kind eq 'command') {
        UC: for my $c (@values) {
            if(commande_accessible($c)) {
              $self->{global}->{$key}=$c;
              last UC;
            }
          }
          if(!$self->{global}->{$key}) {
            debug "No available command for option $key: using the first one";
            $self->{global}->{$key}=$values[0];
          }
        } else {
          debug "ERR: unknown option kind : $kind";
        }
      } elsif(ref($self->{o_default}->{$key}) eq 'HASH') {
        # HASH value: copy it
        $self->{global}->{$key}={ %{$self->{o_default}->{$key}} };
      } else {
        $self->{global}->{$key}=$self->{o_default}->{$key};

        # default value for encoding options:
        $self->{global}->{$key}=$self->{system_encoding}
          if($key =~ /^encodage_/ && !$self->{global}->{$key});
      }
      debug "New global parameter : $key = $self->{global}->{$key}"
        if($self->{global}->{$key});
    } else {
      # already defined option: go with sub-options if any
      if(ref($self->{o_default}->{$key}) eq 'HASH') {
        for my $kk (keys %{$self->{o_default}->{$key}}) {
          $self->set_global_option_to_default($key,$kk,$force);
        }
      }
    }
  }
}

sub set_project_options_to_default {
  my ($self)=@_;

  for my $k (keys %{$self->{project_default}}) {
    $self->set_project_option_to_default($k);
  }
}

sub set_project_option_to_default {
  my ($self,$key,$force)=@_;
  if($force || ! exists($self->{project}->{$key})) {
    if(exists($self->{global}->{"defaut_".$key})) {
      $self->{project}->{$key}=$self->{global}->{"defaut_".$key};
    } elsif(exists($self->{o_default}->{"defaut_".$key})) {
      $self->{project}->{$key}=$self->{o_default}->{"defaut_".$key};
    } else {
      $self->{project}->{$key}=$self->{project_default}->{$key};
    }
    $self->{project}->{_changed} .= ",$key";
  }
}

sub unavailable_commands_keys {
  my ($self)=@_;
  my @uc=();

  for my $k (grep { /_(viewer|editor|opener)$/ } keys(%{$self->{global}})) {
    my $nc=$self->{global}->{$k};
    $nc =~ s/^\s+//;
    $nc =~ s/\s.*//;
    if(!commande_accessible($nc)) {
      push @uc,$k;
    }
  }

  return(@uc);
}

sub test_commands {
  my ($self,$dont_warn)=@_;

  for my $k ($self->unavailable_commands_keys()) {
    set_global_option_to_default($k,'','FORCE');
  }

  my @uc=$self->unavailable_commands_keys();

  if(@uc && !$dont_warn) {
    if($self->{gui}) {
      my $dialog = Gtk3::MessageDialog
        ->new($self->{gui},
              'destroy-with-parent',
              'warning','ok','');
      $dialog->set_markup(
# TRANSLATORS: Message (first part) when some of the commands that are given in the preferences cannot be found.
                          __("Some commands allowing to open documents can't be found:")
                          ." ".join(", ",map { "<b>".$self->get($_)."</b>"; } @uc).". "
# TRANSLATORS: Message (second part) when some of the commands that are given in the preferences cannot be found.
                          .__("Please check its correct spelling and install missing software.")." "
# TRANSLATORS: Message (third part) when some of the commands that are given in the preferences cannot be found. The %s will be replaced with the name of the menu entry "Preferences" and the name of the menu "Edit".
                          .sprintf(__"You can change used commands following <i>%s</i> from menu <i>%s</i>.",
# TRANSLATORS: "Preferences" menu
                                   __"Preferences",
# TRANSLATORS: "Edit" menu
                                   __"Edit"));
      $dialog->run;
      $dialog->destroy;
    } else {
      debug "WARNING: Some commands allowing to open documents can't be found: "
        .join(", ",@uc);
    }
  }
}

# project options

sub project_options_file {
  my ($self,$name,$dir)=@_;
  $dir=$self->{global}->{rep_projets} if(!$dir);
  return "$dir/$name/options.xml";
}

sub open_project {
  my ($self,$name)=@_;
  $self->{project_file}=$self->project_options_file($name);
  $self->{project}={ pref_xml_lit($self->{project_file}) };

  # Get old style working documents names
  if(ref($self->{project}->{docs}) eq 'ARRAY') {
    $self->{project}->{doc_question}=$self->{project}->{docs}->[0];
    $self->{project}->{doc_solution}=$self->{project}->{docs}->[1];
    $self->{project}->{doc_setting}=$self->{project}->{docs}->[2];
    delete($self->{project}->{docs});
    $self->{project}->{_changed}=1;
  }

  # clear deprecated bug-related stuff
  for(keys %{$self->{project}}) {
    delete($self->{project}->{$_})
      if($_ !~ /^ext_/ && !exists($self->{project_default}->{$_}));
    $self->{project}->{_changed}=1;
  }

  # Convert old style CSV ticked option
  if($self->{project}->{cochees} && !$self->{project}->{ticked}) {
    $self->{project}->{ticked}='01';
    delete($self->{project}->{cochees});
    $self->{project}->{_changed}=1;
  }

  # Convert old style ODS group sum options
  if(!defined($self->{project}->{export_ods_group})) {
    $self->{project}->{export_ods_group} =
      ($self->{project}->{export_ods_groupsep} eq '' ? 0 : 1);
    $self->{project}->{export_ods_groupsep} = '.'
      if(!$self->{project}->{export_ods_groupsep});
  }

  $self->{shortcuts}->set(project_name=>$name)
    if($self->{shortcuts});

  $self->set_project_options_to_default();

  $self->save();
}

sub close_project {
  my ($self)=@_;
  $self->save();
  $self->{project}={};
  $self->{project_file}='';
}

# get/set options

sub path_end {
  my ($h,$create,@path)=@_;
  for my $k (@path) {
    if($create) {
      if(ref($h) eq 'HASH') {
        $h->{$k}={} if(!$h->{$k});
        $h=$h->{$k};
      } else {
        die "Unable to create path ".join('/',@path);
      }
    } else {
      if(ref($h) eq 'HASH' && exists($h->{$k})) {
        $h=$h->{$k};
      } else {
        return(undef);
      }
    }
  }
  return($h);
}

sub parse_key {
  my ($self,$key,$create)=@_;
  my $k={};

  if($key =~ /([a-z]+):(.*)/) {
    $k->{container}=$1;
    $key=$2;
  }
  $k->{path}=[];
  $k->{length}=0;
  while($key =~ /(.*?)\/(.*)/) {
    my ($pre,$end)=($1,$2);
    push @{$k->{path}},$pre if($pre);
    $key=$end;
    $k->{length}++;
  }
  $k->{key}=$key;
  if(!$k->{container}) {
  CONT: for my $c (qw/project global state/) {
      my $e=path_end($self->{$c},'',@{$k->{path}});
      if(defined($e) && ($k->{length}>0 || exists($e->{$k->{key}})) ) {
        $k->{container}=$c;
        last CONT;
      }
    }
  }
  if($k->{container}) {
    $k->{location}=path_end($self->{$k->{container}},$create,@{$k->{path}});
  }
  return($k);
}

sub get {
  my ($self,$key,$value_if_not_found)=@_;
  my $k=$self->parse_key($key);
  if($k->{container} && defined($k->{location})) {
    return($k->{location}->{$k->{key}});
  } else {
    return($value_if_not_found);
  }
}

sub get_absolute {
  my ($self,$key)=@_;
  return( $self->{shortcuts}->absolu($self->get($key)) );
}

sub set {
  my ($self,$key,$value)=@_;
  my $k=$self->parse_key($key,'create');
  my $old='';
  if($k->{container}) {
    $old=$k->{location}->{$k->{key}};
    $k->{location}->{$k->{key}}=$value;
    $self->{$k->{container}}->{_changed} .= ",".$k->{key}
      if(!defined($old) || ($old ne $value));
  } else {
    die "Unknown container for key $key";
  }
}

sub key_changed {
  my ($self,$key)=@_;
  my $k=$self->parse_key($key);

  if($k->{container}) {
    return($self->{$k->{container}}->{_changed} &&
           $self->{$k->{container}}->{_changed} =~ /\b$k->{key}\b/);
  } else {
    return(0);
  }
}

sub changed_keys {
  my ($self,$container)=@_;
  if($container) {
    if($self->{$container}->{_changed}) {
      return(grep { $_ } split(/,/,$self->{$container}->{_changed}));
    } else {
      return();
    }
  } else {
    my @r=();
    for my $c (qw/global project state/) {
      push @r,$self->changed_keys($c);
    }
    return(@r);
  }
}

sub list_hash_keys {
  my ($e,$prefix)=@_;
  my @all=();
  my $nonroot_prefix=($prefix && $prefix !~ /:$/);
  push @all,$prefix if($nonroot_prefix);
  if(ref($e) eq 'HASH') {
    for my $k (sort { $a cmp $b } (keys %$e)) {
      push @all,list_hash_keys($e->{$k},
                               ($nonroot_prefix ? "$prefix/$k"
                                : $prefix ? $prefix.$k : $k));
    }
  }
  return(@all);
}

sub list_keys_from_root {
  my ($self,$root)=@_;
  if($root) {
    my $k=$self->parse_key($root);
    return(list_hash_keys(($k->{key} ? $k->{location}->{$k->{key}}
                           : $k->{location}),""));
  } else {
    return($self->list_all_keys());
  }
}

sub list_all_keys {
  my ($self,$container_prefix)=@_;
  my @all=();
  for my $c (qw/state global project/) {
    push @all,list_hash_keys($self->{$c},($container_prefix ? "$c:" : ""));
  }
  return(@all);
}

# save back options

sub save {
  my ($self,$dont_warn)=@_;

  for my $c (qw/project global state/) {
    if($self->{$c}->{_changed}) {
      my $file=$self->{$c."_file"};
      if($file) {
        delete($self->{$c}->{_changed});
        if(pref_xml_ecrit($self->{$c},$c,$file) && !$dont_warn) {
          if($self->{gui}) {
            my $dialog = Gtk3::MessageDialog
              ->new($self->{gui},
                    'destroy-with-parent',
                    'error','ok',
# TRANSLATORS: Error writing one of the configuration files (global or project). The first %s will be replaced with the path of that file, and the second with the error text.
                    __"Error writing configuration file %s: %s",
                    $file,$!);
	    $dialog->run;
	    $dialog->destroy;
          } else {
            debug "ERROR writing <$c> options file: $!";
          }
        }
      } else {
        debug "ERROR: I don't know where to save <$c> options file!";
      }
    }
  }
}

1;
