
#  Copyright (C) 2002  Stanislav Sinyagin
#
#  This program is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  (at your option) any later version.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with this program; if not, write to the Free Software
#  Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.

# $Id$
# Stanislav Sinyagin <ssinyagin@yahoo.com>
#

# Random Collector Torrus plugin Automake script

SUBST = @abs_top_builddir@/substvars.sh

noinst_SCRIPTS = substvars.sh


#####   Perl modules  #####
myperlmoddir = $(perllibdir)/Torrus/Collector
dist_myperlmod_DATA = Random.pm


#####   Perl configuration files  #####
torruscfgdir = $(plugtorruscfgdir)
dist_torruscfg_DATA = randomcollector-torruscfg.pl

#####   CLI wrapper  #####
wrapperdir = $(plugwrapperdir)
dist_wrapper_DATA = randomcollector-wrapper.sh

#####   XML configuration   #####
myxmldir = $(distxmldir)/examples
dist_myxml_DATA = random.xml


#####   Executable scripts  #####
pkgbindir = @pkgbindir@
pkgbin_SCRIPTS = genrandomcfg
EXTRA_DIST = genrandomcfg.in
genrandomcfg: genrandomcfg.in
	$(SUBST) genrandomcfg.in > genrandomcfg


#####   HTML and text Templates   #####
tmpldir = @tmpldir@
dist_tmpl_DATA = genrandomcfg.xml


#####   Documentation files   #####
docdir  = @docdir@
dist_doc_DATA = tp-randomcollector.txt tp-randomcollector.pod 
SUFFIXES = .pod .txt
.pod.txt:
	pod2text $< $@ 



htdocs:
	for f in *.pod; do \
	  pod2html -css=../torrusdoc.css $$f > ../../htdocs/plugins/$$f.html; \
	done

UPLOADPATH = \
   ssinyagin@shell.sourceforge.net:/home/groups/t/to/torrus/htdocs/devel

upload: dist
	scp $(distdir).tar.gz $(UPLOADPATH)
