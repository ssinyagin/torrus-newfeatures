
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

# Torrus plugin Automake script


#####   Perl modules  #####
myperlmoddiscdir = $(perllibdir)/Torrus/DevDiscover
dist_myperlmoddisc_DATA = DevDiscover/CiscoIOS_cbQoS.pm

myperlmodcoldir = $(perllibdir)/Torrus/Collector
dist_myperlmodcol_DATA = \
	Collector/Cisco_cbQoS.pm \
	Collector/Cisco_cbQoS_Params.pm


#####   Perl configuration files  #####
torruscfgdir = $(plugtorruscfgdir)
dist_torruscfg_DATA = cisco-cbqos-torruscfg.pl
devdisccfgdir = $(plugdevdisccfgdir)
dist_devdisccfg_DATA = cisco-cbqos-ddcfg.pl



#####   XML configuration   #####
myxmldir = $(distxmldir)/vendor
dist_myxml_DATA = cisco.ios.cbqos.xml


#####   Documentation files   #####
pkgdocdir  = @pkgdocdir@
dist_pkgdoc_DATA = tp-cisco-cbqos.txt tp-cisco-cbqos.pod 
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
