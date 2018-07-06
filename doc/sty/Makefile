#
# Copyright (C) 2011-2017 Alexis Bienvenue <paamc@passoire.fr>
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

include ../../Makefile-all.conf

PACK=automultiplechoice

SAMPLES=$(wildcard sample-*.tex)

all %.pdf: export SOURCE_DATE_EPOCH=$(PACKAGE_V_EPOCH)
all %.pdf: export SOURCE_DATE_EPOCH_TEX_PRIMITIVES=1
all %.pdf: export FORCE_SOURCE_DATE=1

PDFLATEX=pdflatex -halt-on-error -interaction=nonstopmode
all: FORCE
	$(PDFLATEX) $(PACK).dtx
	$(MAKE) $(SAMPLES:.tex=.pdf)
	$(PDFLATEX) $(PACK).dtx
	makeindex -s gglo.ist -o $(PACK).gls $(PACK).glo
	makeindex -s gind.ist -o $(PACK).ind $(PACK).idx
	$(PDFLATEX) $(PACK).dtx
	$(PDFLATEX) $(PACK).dtx
	$(MAKE) postclean

styonly: $(PACK).dtx
	$(PDFLATEX) $<
	$(MAKE) postclean

sample-%.datetex.in: sample-%.tex
	$(PERLPATH) -pe 's!\\begin\{document\}!\\begin{document}\\pdfinfo{/CreationDate (D:@/PACKAGE_V_PDFDATE/@) /ModDate (D:@/PACKAGE_V_PDFDATE/@)}!;' < $< > $@

sample-%.datetex: sample-%.datetex.in
	$(MAKE) -C ../.. doc/sty/$@

sample-%.pdf: sample-%.datetex
	pdflatex -jobname sample-$* $<

postclean:
	-rm -f pexa-*
	-rm -f $(foreach ext,amc aux dvi glo gls idx ilg ind log out toc xy xy1 xy2 xy3,*.$(ext))

clean: postclean
	rm -f *~
	rm -f $(PACK).sty
	rm -f *.pdf

FORCE: ;

.PHONY: all clean postclean FORCE
