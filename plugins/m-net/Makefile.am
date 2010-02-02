
#  Copyright (C) 2010  Stanislav Sinyagin
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

# Torrus plugin Automake script


#####   Perl modules  #####
myperlmoddiscdir = $(perllibdir)/Torrus/DevDiscover
dist_myperlmoddisc_DATA = DevDiscover/M_net.pm


#####   Perl configuration files  #####
devdisccfgdir = $(plugdevdisccfgdir)
dist_devdisccfg_DATA = m-net-ddcfg.pl



#####   XML configuration   #####
myxmldir = $(distxmldir)/m-net
dist_myxml_DATA = 


#####   Documentation files   #####
pkgdocdir  = @pkgdocdir@
dist_pkgdoc_DATA = tp-m-net.txt tp-m-net.pod
SUFFIXES = .pod .txt
.pod.txt:
	pod2text $< $@ 


htdocs:
	for f in *.pod; do \
	  pod2html -css=../torrusdoc.css $$f > ../../htdocs/plugins/$$f.html; \
	done

UPLOADPATH = \
   ssinyagin,torrus@web.sourceforge.net:/home/groups/t/to/torrus/htdocs/devel

upload: dist
	scp $(distdir).tar.gz $(UPLOADPATH)
