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

SHELL=/bin/sh

include ../Makefile-all.conf

ALL_DOCBOOKS = $(filter-out $(wildcard *.in.xml),$(wildcard auto-multiple-choice.*.xml))
DOC_LANG ?= $(patsubst auto-multiple-choice.%.xml,%,$(ALL_DOCBOOKS))
SELECTED_DOCBOOKS = $(foreach onelang,$(DOC_LANG),auto-multiple-choice.$(onelang).xml)

IMAGES=$(addprefix html/images/,$(notdir $(wildcard img_src/*.svg))) $(addprefix html/images/callouts/,$(notdir $(wildcard img_src/callouts/*.svg)))
BLOCK_IMAGES=$(addprefix img_pdf/,$(notdir $(wildcard img_src/*.svg)))

MODELS=$(wildcard modeles/*/*.d)

all: $(SELECTED_DOCBOOKS:.xml=.pdf) $(SELECTED_DOCBOOKS:.xml=.x) $(IMAGES:.svg=.png) $(MODELS:.d=.tgz) html/index.html;

show_doc_lang:
	@echo "DOC_LANG = $(DOC_LANG)"

images: $(IMAGES:.svg=.png)

clean:
	rm -f $(foreach ext,1 aux cb cb2 glo idx log out toc tex html pdf ext man,*.$(ext))
	rm -f modeles/*.tgz
	rm -f modeles/**/*.tgz
	rm -f html/auto-multiple-choice.**/*.html
	rm -f html/images/callouts/*.png html/images/*.png img_pdf/*.pdf
	rm -f *~

html/images/callouts/%.png: img_src/callouts/%.svg
	rsvg-convert -w 12 -h 12 $< -o $@

html/images/%.png: img_src/%.svg
	rsvg-convert -w 24 -h 24 $< -o $@

img_pdf/%.pdf: img_src/%.svg
	rsvg-convert -f pdf $< -o $@

html/index.html: FORCE
	$(PERLPATH) ./index.pl $(SELECTED_DOCBOOKS:.xml=) > $@

%.tex: %.xml amcdocstyle.sty
	dblatex -P latex.encoding=utf8 -b xetex -t tex -p custom.xsl --texstyle=amcdocstyle --xslt-opts="--nonet" --xslt-opts="--catalogs" $(DBLATEX_OPT) $< -o $@

XELATEX=xelatex -halt-on-error -interaction=nonstopmode

%.pdf: export SOURCE_DATE_EPOCH=$(PACKAGE_V_EPOCH)
%.pdf: export SOURCE_DATE_EPOCH_TEX_PRIMITIVES=1
%.pdf: export FORCE_SOURCE_DATE=1
%.pdf: export TEXINPUTS=./img_pdf/:

%.pdf: %.tex $(BLOCK_IMAGES:.svg=.pdf)
	set -e ; $(XELATEX) $<; $(XELATEX) $<
	rm -f $(foreach ext,aux cb cb2 glo idx log out toc,$*.$(ext))

%.x: %.ext %.man %.html ;

%.ext: %.xml
	$(PERLPATH) extrait-fichiers.pl --liste $@ $<

%.man: %.xml
	xsltproc --nonet --catalogs --param man.charmap.use.subset "0" --param make.year.ranges "1" --param make.single.year.ranges "1" --param man.output.lang.in.name.enabled "1" $(DOCBOOK_MAN_XSL) $<
	date > $@

%.html: %.xml doc-xhtml.xsl
	rm -f html/$*/*.html
	xsltproc --nonet --catalogs --stringparam base.dir html/$*/ doc-xhtml.xsl $<
	date > $@

%.tgz: %.d
	find $< -type d -exec chmod 0755 '{}' \;
	find $< -type f -exec chmod 0644 '{}' \;
ifeq ($(TAR_REPRODUCIBLE_ARGS),nonreproducible)
	tar -cz -f $@ -C $< .
else
	tar cn -C $< $(TAR_REPRODUCIBLE_ARGS) -O . | gzip $(GZIP_REPRODUCIBLE_ARGS) -c > $@
endif

check: FORCE
	./check_xml

FORCE: ;

.PHONY: FORCE all images clean check
