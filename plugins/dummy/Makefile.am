
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

# Dummy Torrus plugin Automake script

SUBST = @abs_top_builddir@/substvars.sh

noinst_SCRIPTS = substvars.sh


#####   Perl modules  #####
myperlmoddir = $(perllibdir)/Torrus
dist_myperlmod_DATA = DummyModule.pm

#####   Perl configuration files  #####
torruscfgdir = $(plugtorruscfgdir)
dist_torruscfg_DATA = dummy-torruscfg.pl
devdisccfgdir = $(plugdevdisccfgdir)
dist_devdisccfg_DATA = dummy-ddcfg.pl

#####   CLI wrapper  #####
wrapperdir = $(plugwrapperdir)
dist_wrapper_DATA = dummy-wrapper.sh


#####   XML configuration   #####
myxmldir = $(distxmldir)
dist_myxml_DATA = dummy.xml


#####   Executable scripts  #####
pkgbindir = @pkgbindir@
pkgbin_SCRIPTS = dummyscript 
EXTRA_DIST = dummyscript.in
dummyscript: dummyscript.in
	$(SUBST) dummyscript.in > dummyscript


#####   Documentation files   #####
docdir  = @docdir@
dist_doc_DATA = tp-dummy.txt tp-dummy.pod 
SUFFIXES = .pod .txt
.pod.txt:
	pod2text $< $@ 


#####   HTML and text Templates   #####
tmpldir = @tmpldir@
dist_tmpl_DATA = dummytemplate.html

#####   What you do not need after "make clean"  #####
CLEANFILES = $(pkgbin_SCRIPTS)


UPLOADPATH = \
   ssinyagin@shell.sourceforge.net:/home/groups/t/to/torrus/htdocs/devel

upload: dist
	scp $(distdir).tar.gz $(UPLOADPATH)
