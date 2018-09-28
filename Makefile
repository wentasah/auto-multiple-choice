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

# Loads separate configuration file

include Makefile-all.conf

PACKAGE_DEB_TARGET = unstable
PACKAGE_DEB_DV ?= -1
# DATE/TIME to be substituted

DATE_RPMCHL:=$(shell LC_TIME=en date +"%a %b %e %Y")
DATE_DEBCHL:=$(shell LANG=en date "+%a, %d %b %Y %H:%M:%S %z")

# list variables to be substituted in *.in files

SUBST_VARS:=$(sort $(shell grep -h '=' $(SUB_MAKEFILES) | $(PERLPATH) -pe 's/\#.*//;s/\??\+?=.*//;' ) PACKAGE_DEB_DV PACKAGE_DEB_TARGET PERLPATH DATE_DEBCHL DATE_RPMCHL)
SUBST_VARS_FOR_TEX = PACKAGE_V_STY PACKAGE_V_DEB

# Some default values

GCC ?= gcc
GCC_PP ?= gcc
CFLAGS ?= -O2
CXXFLAGS ?= -O2

# try to find right names for OpenCV libs 

ifeq ($(GCC_OPENCV_LIBS),auto)
ifeq ($(shell echo 'int main(){}' | gcc -xc -lopencv_imgcodecs - && ( rm -f a.out ; echo "OK")),OK)
  GCC_OPENCV_LIBS:=-lopencv_core -lopencv_imgproc -lopencv_imgcodecs
else ifeq ($(shell echo 'int main(){}' | gcc -xc -lopencv_core - && ( rm -f a.out ; echo "OK")),OK)
  GCC_OPENCV_LIBS:=-lopencv_core -lopencv_highgui -lopencv_imgproc
else
  GCC_OPENCV_LIBS:=-lcv -lhighgui -lcxcore
endif
endif

GCC_OPENCV ?= $(shell pkg-config --cflags opencv)
GCC_OPENCV_LIBS ?= $(shell pkg-config --libs opencv)
GCC_PDF ?= $(shell pkg-config --cflags --libs cairo pangocairo poppler-glib)
GCC_POPPLER ?= $(shell pkg-config --cflags --libs poppler-glib gio-2.0)

#

SHELL=/bin/sh

DESTDIR ?=

# debug...

print-%: FORCE
	@echo "$*=$($*)"

# AMC components to build

BINARIES ?= AMC-detect AMC-buildpdf AMC-pdfformfields

MODS=AMC-*.pl
GLADE_FROMIN:=$(basename $(wildcard AMC-gui-*.glade.in))
GLADE_SIMPLE:=$(filter-out $(GLADE_FROMIN),$(wildcard AMC-gui-*.glade))
GLADE=$(GLADE_FROMIN) $(GLADE_SIMPLE)
STY=doc/sty/automultiplechoice.sty
DTX=doc/sty/automultiplechoice.dtx
MOS=$(wildcard I18N/lang/*.mo)
LANGS=$(notdir $(basename $(MOS)))
SUBMODS=$(notdir $(shell ls doc/modeles))

DOC_XML_IN=$(wildcard doc/auto-multiple-choice.*.in.xml)

# list *.in files for @/VAR/@ substitution

FROM_IN=auto-multiple-choice auto-multiple-choice.desktop $(GLADE_FROMIN) AMC-gui.pl AMC-latex-link.pl AMC-perl/AMC/Basic.pm doc/doc-xhtml-site.fr.xsl doc/doc-xhtml-site.ja.xsl doc/doc-xhtml-site.en.xsl doc/amcdocstyle.sty doc/doc-xhtml.xsl $(DOC_XML_IN:.in.xml=.xml) $(DTX)

# Is this a precomp tarball? If so, the PRECOMP file is present.

PRECOMP_FLAG_FILE=PRECOMP
PRECOMP_ARCHIVE:=$(wildcard $(PRECOMP_FLAG_FILE))

MAIN_LOGO=icons/auto-multiple-choice

# Sets user and group flags for install command

ifeq ($(INSTALL_USER),)
else
USER_GROUP = -o $(INSTALL_USER)
endif
ifeq ($(INSTALL_GROUP),)
else
USER_GROUP += -g $(INSTALL_GROUP)
endif

# Target switch (precomp archive or not)

ifeq ($(PRECOMP_ARCHIVE),)
all:
	$(MAKE) $(FROM_IN)
	$(MAKE) $(BINARIES) $(MAIN_LOGO).xpm $(MAIN_LOGO).svgz doc I18N
	chmod a+x auto-multiple-choice
else
all: all_precomp
	chmod a+x auto-multiple-choice
endif

all_precomp:
	$(MAKE) $(FROM_IN)
	$(MAKE) $(BINARIES)

MAJ: $(FROM_IN) ;

# Binaries

AMC-detect: AMC-detect.cc Makefile
	$(GCC_PP) -o $@ $< $(CPPFLAGS) $(CXXFLAGS) $(LDFLAGS) $(CXXLDFLAGS) -lstdc++ -lm $(GCC_OPENCV) $(GCC_OPENCV_LIBS)

AMC-buildpdf: AMC-buildpdf.cc buildpdf.cc Makefile
	$(GCC_PP) -o $@ $< $(CPPFLAGS) $(CXXFLAGS) $(LDFLAGS) $(CXXLDFLAGS) -lstdc++ -lm $(GCC_PDF) $(GCC_OPENCV) $(GCC_OPENCV_LIBS)

AMC-pdfformfields: pdfformfields.c Makefile
	$(GCC_PP) -o $@ $< $(CPPFLAGS) $(CXXFLAGS) $(LDFLAGS) $(CXXLDFLAGS) -lstdc++ -lm $(GCC_POPPLER)

rebuild: FORCE
	$(MAKE) $(BINARIES) -W Makefile

# substitution in *.in files

vars-subs.pl: $(SUB_MAKEFILES) authors-subs.xsl authors.xml
	@echo "Recording substitution variables from $(SUB_MAKEFILES)"
	$(file > $@,# Variables:)
	$(foreach varname,$(SUBST_VARS), $(file >> $@,s|@/$(varname)/@|$($(varname))|g;) )
	$(foreach varname,$(SUBST_VARS_FOR_TEX), $(file >> $@,s|@/$(varname)_TEX/@|$(subst ~,\\string~,$($(varname)))|g;) )
	$(file >> $@,s+/usr/share/xml/docbook/schema/dtd/4.5/docbookx.dtd+$(DOCBOOK_DTD)+g;)
	$(file >> $@,# From authors.xml:)
	xsltproc --nonet authors-subs.xsl authors.xml >> $@

%.xml: %.in.xml vars-subs.pl 
	$(PERLPATH) -p vars-subs.pl $< > $@

%: %.in vars-subs.pl
	$(PERLPATH) -p vars-subs.pl $< > $@

# some components

doc:
	$(MAKE) -C doc
	$(MAKE) -C doc/sty

I18N:
	$(MAKE) -C I18N

sync:
	$(MAKE) -C download-area all

# Individual rules

%.ps: %.dvi
	dvips $< -o $@

%.ppm: %.ps
	convert -density 300 $< $*-%03d.ppm

%.png: %.svg
	rsvg-convert -w 32 -h 32 $< -o $@

%.xpm: %.png
	pngtopnm $< | ppmtoxpm > $@

$(MAIN_LOGO).svgz: $(MAIN_LOGO).svg
	gzip -k -S z $<
	$(foreach SIZE, $(APPICONSIZES), rsvg-convert -a -w $(SIZE) -h $(SIZE) $< -o $(MAIN_LOGO)-$(SIZE).png ;)

# CLEAN

clean_IN: FORCE
	rm -rf debian/auto-multiple-choice
	rm -f local/deb-auto-changelog
	rm -f $(FROM_IN)

# When we are inside an extracted dist tarball, 'clean' will only remove the
# files that did not come with in the dist tarball (we keep Makefile.versions
# and doc/ for example). Otherwise, we remove everything.
clean: clean_IN $(if $(PRECOMP_ARCHIVE),,distclean)
	-rm -f $(BINARIES)
	-rm -f vars-subs.pl

distclean: clean_IN clean
	-rm -f $(MAIN_LOGO).xpm $(MAIN_LOGO).svgz $(MAIN_LOGO)-*.png
	-rm -f auto-multiple-choice.spec
	$(MAKE) -C doc/sty clean
	$(MAKE) -C doc clean
	$(MAKE) -C I18N clean

# INSTALL

install_lang_%: FORCE
	install -d -m 0755 $(USER_GROUP) $(DESTDIR)/$(LOCALEDIR)/$*/LC_MESSAGES
	install    -m 0644 $(USER_GROUP) I18N/lang/$*.mo $(DESTDIR)/$(LOCALEDIR)/$*/LC_MESSAGES/auto-multiple-choice.mo

install_lang: $(addprefix install_lang_,$(LANGS)) ;

install_models_%: FORCE
	install -d -m 0755 $(USER_GROUP) $(DESTDIR)/$(MODELSDIR)/$*
	-install    -m 0644 $(USER_GROUP) doc/modeles/$*/*.tgz $(DESTDIR)/$(MODELSDIR)/$*
	-install    -m 0644 $(USER_GROUP) doc/modeles/$*/*.xml $(DESTDIR)/$(MODELSDIR)/$*

install_models: $(addprefix install_models_,$(SUBMODS)) ;

install_nodoc: install_lang install_models FORCE
ifneq ($(SYSTEM_TYPE),deb) # with debian, done with dh_installmime
ifneq ($(SHARED_MIMEINFO_DIR),)
	install -d -m 0755 $(USER_GROUP) $(DESTDIR)/$(SHARED_MIMEINFO_DIR)
	install    -m 0644 $(USER_GROUP) interfaces/auto-multiple-choice.xml $(DESTDIR)/$(SHARED_MIMEINFO_DIR)
endif
endif
ifneq ($(LANG_GTKSOURCEVIEW_DIR),)
	install -d -m 0755 $(USER_GROUP) $(DESTDIR)/$(LANG_GTKSOURCEVIEW_DIR)
	install    -m 0644 $(USER_GROUP) interfaces/amc-txt.lang $(DESTDIR)/$(LANG_GTKSOURCEVIEW_DIR)
endif
	install -d -m 0755 $(USER_GROUP) $(DESTDIR)/$(MODSDIR)
	install -d -m 0755 $(USER_GROUP) $(DESTDIR)/$(MODSDIR)/perl
	install -d -m 0755 $(USER_GROUP) $(DESTDIR)/$(MODSDIR)/exec
	install    -m 0755 $(USER_GROUP) $(MODS) $(DESTDIR)/$(MODSDIR)/perl
	install    -m 0755 $(USER_GROUP) $(BINARIES) $(DESTDIR)/$(MODSDIR)/exec
	install    -m 0644 $(USER_GROUP) $(GLADE) $(DESTDIR)/$(MODSDIR)/perl
	install -d -m 0755 $(USER_GROUP) $(DESTDIR)/$(TEXDIR)
	install    -m 0644 $(USER_GROUP) $(STY) $(DESTDIR)/$(TEXDIR)
ifneq ($(DESKTOPDIR),)
	install -d -m 0755 $(USER_GROUP) $(DESTDIR)/$(DESKTOPDIR)
	install    -m 0644 $(USER_GROUP) -T auto-multiple-choice.desktop $(DESTDIR)/$(DESKTOPDIR)/auto-multiple-choice.desktop
endif
	install -d -m 0755 $(USER_GROUP) $(DESTDIR)/$(BINDIR)
	install    -m 0755 $(USER_GROUP) auto-multiple-choice $(DESTDIR)/$(BINDIR)
	install -d -m 0755 $(USER_GROUP) $(DESTDIR)/$(ICONSDIR)
	install    -m 0644 $(USER_GROUP) icons/*.svg $(DESTDIR)/$(ICONSDIR)
ifneq ($(APPICONDIR),)
	install	-d -m 0755 $(USER_GROUP) $(DESTDIR)/$(APPICONDIR)/scalable/apps
	install	   -m 0644 $(USER_GROUP) $(MAIN_LOGO).svgz $(DESTDIR)/$(APPICONDIR)/scalable/apps
	$(foreach SIZE, $(APPICONSIZES),\
	install	-d -m 0755 $(USER_GROUP) $(DESTDIR)/$(APPICONDIR)/$(SIZE)x$(SIZE)/apps ; \
	install	   -m 0644 $(USER_GROUP) -T $(MAIN_LOGO)-$(SIZE).png $(DESTDIR)/$(APPICONDIR)/$(SIZE)x$(SIZE)/apps/auto-multiple-choice.png ; )
endif
ifneq ($(PIXDIR),)
	install -d -m 0755 $(USER_GROUP) $(DESTDIR)/$(PIXDIR)
	install    -m 0644 $(USER_GROUP) -T $(MAIN_LOGO).xpm $(DESTDIR)/$(PIXDIR)/auto-multiple-choice.xpm
endif
	install -d -m 0755 $(USER_GROUP) $(DESTDIR)/$(PERLDIR)/AMC
	install -d -m 0755 $(USER_GROUP) $(DESTDIR)/$(PERLDIR)/AMC/Export
	install -d -m 0755 $(USER_GROUP) $(DESTDIR)/$(PERLDIR)/AMC/Export/register
	install -d -m 0755 $(USER_GROUP) $(DESTDIR)/$(PERLDIR)/AMC/Filter
	install -d -m 0755 $(USER_GROUP) $(DESTDIR)/$(PERLDIR)/AMC/Filter/register
	install -d -m 0755 $(USER_GROUP) $(DESTDIR)/$(PERLDIR)/AMC/DataModule
	install -d -m 0755 $(USER_GROUP) $(DESTDIR)/$(PERLDIR)/AMC/Gui
	install -d -m 0755 $(USER_GROUP) $(DESTDIR)/$(PERLDIR)/AMC/Print
	install    -m 0644 $(USER_GROUP) AMC-perl/AMC/*.pm $(DESTDIR)/$(PERLDIR)/AMC
	install    -m 0644 $(USER_GROUP) AMC-perl/AMC/Export/*.pm $(DESTDIR)/$(PERLDIR)/AMC/Export
	install    -m 0644 $(USER_GROUP) AMC-perl/AMC/Export/register/*.pm $(DESTDIR)/$(PERLDIR)/AMC/Export/register
	install    -m 0644 $(USER_GROUP) AMC-perl/AMC/Filter/*.pm $(DESTDIR)/$(PERLDIR)/AMC/Filter
	install    -m 0644 $(USER_GROUP) AMC-perl/AMC/Filter/register/*.pm $(DESTDIR)/$(PERLDIR)/AMC/Filter/register
	install    -m 0644 $(USER_GROUP) AMC-perl/AMC/DataModule/*.pm $(DESTDIR)/$(PERLDIR)/AMC/DataModule
	install    -m 0644 $(USER_GROUP) AMC-perl/AMC/Gui/*.pm $(DESTDIR)/$(PERLDIR)/AMC/Gui
	install    -m 0644 $(USER_GROUP) AMC-perl/AMC/Gui/*.glade $(DESTDIR)/$(PERLDIR)/AMC/Gui
	install    -m 0644 $(USER_GROUP) AMC-perl/AMC/Print/*.pm $(DESTDIR)/$(PERLDIR)/AMC/Print

install_doc: FORCE
	@echo "Installing doc..."
ifneq ($(TEXDOCDIR),)
	install -d -m 0755 $(USER_GROUP) $(DESTDIR)/$(TEXDOCDIR)
	install    -m 0644 $(USER_GROUP) doc/sty/*.pdf doc/sty/*.tex $(DESTDIR)/$(TEXDOCDIR)
endif
ifneq ($(SYSTEM_TYPE),deb) # with debian, done with dh_install{doc,man}
	install -d -m 0755 $(USER_GROUP) $(DESTDIR)/$(DOCDIR)
	install    -m 0644 $(USER_GROUP) $(wildcard doc/auto-multiple-choice.??.xml doc/auto-multiple-choice.??.pdf) $(DESTDIR)/$(DOCDIR)
	cp -r doc/html $(DESTDIR)/$(DOCDIR)
ifeq ($(INSTALL_USER),)
else
	chown -hR $(INSTALL_USER) $(DESTDIR)/$(DOCDIR)
endif
ifeq ($(INSTALL_GROUP),)
else
	chgrp -hR $(INSTALL_GROUP) $(DESTDIR)/$(DOCDIR)
endif
	install -d -m 0755 $(USER_GROUP) $(DESTDIR)/$(MAN1DIR)
	install    -m 0644 $(USER_GROUP) doc/*.1 $(DESTDIR)/$(MAN1DIR)
endif

install: install_nodoc install_doc ;

# Test

manual-test:
	$(MAKE) -C tests test

##############################################################################
# Following lines are only helpfull for source tarball and package building
# These targets run only with source from svn checkout
##############################################################################

LOCALDIR=$(shell pwd)

global: FORCE
	$(MAKE) -C I18N global LOCALEDIR=$(LOCALEDIR) LOCALDIR=$(LOCALDIR)
	-sudo rm /usr/share/perl5/AMC $(ICONSDIR) /usr/share/doc/auto-multiple-choice /usr/share/doc/auto-multiple-choice-doc $(LOCALEDIR)/fr/LC_MESSAGES/auto-multiple-choice.mo $(DESKTOPDIR)/auto-multiple-choice.desktop $(MODELSDIR) /usr/bin/auto-multiple-choice $(TEXDIR)/automultiplechoice.sty $(SHARED_MIMEINFO_DIR)/auto-multiple-choice.xml $(LANG_GTKSOURCEVIEW_DIR)/amc-txt.lang $(APPICONDIR)/auto-multiple-choice.svgz
	-sudo rm -r /usr/lib/AMC

local: global
	$(MAKE) -C I18N local LOCALEDIR=$(LOCALEDIR) LOCALDIR=$(LOCALDIR)
	test -d /usr/lib/AMC || sudo mkdir -p /usr/lib/AMC
	test -d /usr/lib/AMC/perl || sudo mkdir -p /usr/lib/AMC/perl
	test -d /usr/lib/AMC/exec || sudo mkdir -p /usr/lib/AMC/exec
	test -d /usr/share/auto-multiple-choice  || sudo mkdir -p /usr/share/auto-multiple-choice
	test -d $(TEXDIR) || sudo mkdir $(TEXDIR)
	sudo ln -s $(LOCALDIR)/AMC-perl/AMC /usr/share/perl5/AMC
	sudo ln -s $(LOCALDIR)/AMC-detect /usr/lib/AMC/exec/AMC-detect
	sudo ln -s $(LOCALDIR)/AMC-buildpdf /usr/lib/AMC/exec/AMC-buildpdf
	sudo ln -s $(LOCALDIR)/AMC-pdfformfields /usr/lib/AMC/exec/AMC-pdfformfields
	sudo ln -s $(LOCALDIR)/AMC-*.pl $(LOCALDIR)/AMC-*.glade /usr/lib/AMC/perl
	sudo ln -s $(LOCALDIR)/auto-multiple-choice /usr/bin
	sudo ln -s $(LOCALDIR)/icons $(ICONSDIR)
	sudo ln -s $(LOCALDIR)/doc /usr/share/doc/auto-multiple-choice-doc
	sudo ln -s $(LOCALDIR)/auto-multiple-choice.desktop $(DESKTOPDIR)/auto-multiple-choice.desktop
	sudo ln -s $(LOCALDIR)/doc/modeles $(MODELSDIR)
	sudo ln -s $(LOCALDIR)/$(STY) $(TEXDIR)/automultiplechoice.sty
	sudo ln -s $(LOCALDIR)/interfaces/amc-txt.lang $(LANG_GTKSOURCEVIEW_DIR)
	sudo ln -s $(LOCALDIR)/interfaces/auto-multiple-choice.xml $(SHARED_MIMEINFO_DIR)
	sudo ln -s $(LOCALDIR)/$(MAIN_LOGO).svgz $(APPICONDIR)

ifdef DEBSIGN_KEY
DEBSIGN=-k$(DEBSIGN_KEY)
else
DEBSIGN=--no-sign
endif

BUILDOPTS=-I.svn -Idownload_area -Ilocal $(DEBSIGN)

TMP_DIR=tmp
SOURCE_DIR=auto-multiple-choice-$(PACKAGE_V_DEB)
TMP_SOURCE_DIR=$(TMP_DIR)/$(SOURCE_DIR)
TARBALLS_DIR=tarballs
ORIG_SOURCES=$(TMP_DIR)/auto-multiple-choice_$(PACKAGE_V_DEB).orig.tar.gz

SRC_EXCL=--exclude debian '--exclude=*~' --exclude .hgignore --exclude .hgtags --exclude .gitignore --exclude .gitlab-ci.yml

version_files:
	$(PERLPATH) local/versions.pl
	$(MAKE) auto-multiple-choice.spec

tmp_copy:
	rm -rf $(TMP_SOURCE_DIR)
	mkdir $(TMP_SOURCE_DIR)
	rsync -aC --exclude '*~' --exclude .hg --exclude .git --exclude .gitlab-ci.yml --exclude download_area --exclude local --exclude tmp --exclude tarballs . $(TMP_SOURCE_DIR)
	$(MAKE) -C $(TMP_SOURCE_DIR) clean

portable_vok:
	$(eval TMP_PORTABLE:=$(shell mktemp -d /tmp/portable.XXXXXXXXXX))
	$(MAKE) tmp_copy
	make AMCCONF=portable INSTREP=$(TMP_PORTABLE)/AMC -C $(TMP_SOURCE_DIR)
	make AMCCONF=portable INSTREP=$(TMP_PORTABLE)/AMC -C $(TMP_SOURCE_DIR) install
	cd $(TMP_PORTABLE) ; tar cvzf auto-multiple-choice_$(PACKAGE_V_DEB)_portable.tar.gz $(SRC_EXCL) AMC
	mv $(TMP_PORTABLE)/auto-multiple-choice_$(PACKAGE_V_DEB)_portable.tar.gz $(TARBALLS_DIR)
	rm -rf $(TMP_PORTABLE)

ssources_vok:
	$(MAKE) tmp_copy
	cd $(TMP_DIR) ; tar cvzf auto-multiple-choice_$(PACKAGE_V_DEB)_sources.tar.gz $(SRC_EXCL) $(SOURCE_DIR)
	rm -rf $(TMP_SOURCE_DIR)

sources_vok:
	$(MAKE) tmp_copy
	cd $(TMP_DIR) ; tar cvzf auto-multiple-choice_$(PACKAGE_V_DEB)_sources.tar.gz $(SRC_EXCL) $(SOURCE_DIR)
	$(MAKE) -C $(TMP_SOURCE_DIR) MAJ
	$(MAKE) -C $(TMP_SOURCE_DIR) $(MAIN_LOGO).xpm $(MAIN_LOGO).svgz I18N doc
	$(MAKE) -C $(TMP_SOURCE_DIR) clean_IN
	$(MAKE) -C $(TMP_SOURCE_DIR) auto-multiple-choice.spec
	touch $(TMP_SOURCE_DIR)/$(PRECOMP_FLAG_FILE)
	cd $(TMP_DIR) ; tar cvzf auto-multiple-choice_$(PACKAGE_V_DEB)_precomp.tar.gz $(SRC_EXCL) $(SOURCE_DIR)
	mv $(TMP_DIR)/auto-multiple-choice_$(PACKAGE_V_DEB)_*.tar.gz $(TARBALLS_DIR)
	rm -rf $(TMP_SOURCE_DIR)

tmp_deb:
	$(MAKE) local/deb-auto-changelog
	$(MAKE) tmp_copy
	cd $(TMP_SOURCE_DIR) ; cp -r ppa debian
	cp local/deb-auto-changelog $(TMP_SOURCE_DIR)/debian/changelog
	$(PERLPATH) -pi -e 's/^DL=.*/DL=$(SRC_DOC_LANG)/' $(TMP_SOURCE_DIR)/debian/rules
ifneq (,$(SKIP_DEP))
	$(foreach onedep,$(SKIP_DEP),$(PERLPATH) -pi -e 's/(,\s*$(onedep)|$(onedep),)//' $(TMP_SOURCE_DIR)/debian/control)
endif
ifneq (,$(ADD_BUILD_DEP))
	$(foreach onedep,$(ADD_BUILD_DEP),$(PERLPATH) -pi -e 's/(?<=Build-Depends: )/$(onedep), /' $(TMP_SOURCE_DIR)/debian/control)
endif

debsrc_vok: ssources tmp_deb
	test -f $(ORIG_SOURCES) || cp $(TMP_DIR)/auto-multiple-choice_$(PACKAGE_V_DEB)_sources.tar.gz $(ORIG_SOURCES)
	cd $(TMP_SOURCE_DIR) ; dpkg-buildpackage -S $(BUILDOPTS) $(MORE_BUILDOPTS)
	rm -rf $(TMP_SOURCE_DIR)

deb_vok: tmp_deb
	cd $(TMP_SOURCE_DIR) ; dpkg-buildpackage -b $(BUILDOPTS) $(MORE_BUILDOPTS)
	rm -rf $(TMP_SOURCE_DIR)

# % : make sure version_files are rebuilt before calling target %_vok

$(foreach key,deb debsrc sources ssources portable,$(eval $(key): clean version_files ; $$(MAKE) $(key)_vok))

# debian repository

unstable:
	$(MAKE) -C download_area unstable sync

re_unstable:
	$(MAKE) -C download_area re_unstable sync

FORCE: ;

.PHONY: all all_precomp install version_files deb deb_vok debsrc debsrc_vok sources sources_vok clean clean_IN global local doc I18N tmp_copy tmp_deb unstable re_unstable FORCE MAJ manual-test


