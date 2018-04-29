#
# Copyright (C) 2010-2016 Alexis Bienvenue <paamc@passoire.fr>
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

DOMAIN=auto-multiple-choice

XGETTO=

AMC=..

PERL=$(AMC)/*.pl $(AMC)/AMC-perl/AMC/*.pm $(AMC)/AMC-perl/AMC/**/*.pm $(AMC)/AMC-perl/AMC/**/**/*.pm 

GLADE=$(AMC)/AMC-*.glade $(AMC)/AMC-perl/AMC/**/*.glade

POS=$(wildcard lang/*.po)
MOS=$(POS:.po=.mo)
LANGS=$(basename $(notdir $(POS)))

all: $(MOS)

clean: FORCE
	rm -f $(MOS)
	rm -f *.bpot
	rm -f *.po

%.mo: %.po
	msgfmt $< -o $@

###############################################################
# The following targets are only for packaging :
# not used for building or installing

po-clean.pl: po-clean.pl.in ../Makefile.versions
	$(MAKE) -C .. I18N/po-clean.pl

%.pot: %.bpot po-clean.pl
	perl po-clean.pl $< $@

$(DOMAIN).bpot: $(PERL) $(GLADE)
	xgettext $(XGETTO) --from-code=UTF-8 --add-comments=TRANSLATORS: $(PERL) -k__ -k__p -k -o $@
	xgettext $(XGETTO) -j $(GLADE) -L Glade -o $@

list:
	grep -lr __ $(AMC) |grep '\.\(pl\|pm\)$$' | grep -v 'debian' ; ls $(GLADE)

%.merge: $(DOMAIN).pot
	msgmerge --no-wrap -U lang/$*.po $(DOMAIN).pot

merge: $(addsuffix .merge,$(LANGS)) ;

%.local: FORCE
	test -d $(LOCALEDIR)/$*/LC_MESSAGES || sudo mkdir -p $(LOCALEDIR)/$*/LC_MESSAGES
	sudo ln -s $(LOCALDIR)/I18N/lang/$*.mo $(LOCALEDIR)/$*/LC_MESSAGES/auto-multiple-choice.mo

local: $(foreach l,$(LANGS),$(l).local) ;

%.global: FORCE
	-sudo rm $(LOCALEDIR)/$*/LC_MESSAGES/auto-multiple-choice.mo

global: $(foreach l,$(LANGS),$(l).global) ;

###############################################################

FORCE: ;

.PHONY: all clean list merge FORCE

.INTERMEDIATE: $(DOMAIN).bpot
