
#  Copyright (C) 2003  Christian Schnidrig
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
# Christian Schnidrig <christian.schnidrig@bluewin.ch>
#

# HTTP Torrus plugin Automake script


#####   Perl modules  #####
myperlmoddir = $(perllibdir)/Torrus/Collector
dist_myperlmod_DATA = Http.pm

#####   Perl configuration files  #####
torruscfgdir = $(plugtorruscfgdir)
dist_torruscfg_DATA = httpcollector-torruscfg.pl

#####   XML configuration   #####
vendorxmldir = $(distxmldir)/vendor
dist_vendorxml_DATA = apache.httpd.xml

xmpxmldir = $(distxmldir)/examples
dist_xmpxml_DATA = localhost-apache2.xml localhost-apache1.xml


#####   Documentation files   #####
pkgdocdir  = @pkgdocdir@
dist_pkgdoc_DATA = tp-httpcollector.txt tp-httpcollector.pod 
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
