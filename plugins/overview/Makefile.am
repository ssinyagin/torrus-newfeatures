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

# Overview Torrus plugin Automake script

SUBST = @abs_top_builddir@/ov_substvars.sh

CLEANFILES = \
	ov_substvars.sh \
	tp-overview.apache.conf

noinst_SCRIPTS = \
	ov_substvars.sh

EXTRA_DIST = \
	menu/credits.htm \
	menu/menu.xsl.in \
	menu/welcome.htm \
	overview/overview.xsl.in \
	xtree/xtree.css \
	xtree/xtree.js.in  \
	ov_substvars.sh.in \
	tp-overview.apache.conf.in

welcome_htm = $(webplaindir)/menu/welcome.htm
credits_htm = $(webplaindir)/menu/credits.htm

install-data-local:
	$(mkinstalldirs) $(DESTDIR)$(webplaindir)/menu
	if test ! -r $(DESTDIR)$(welcome_htm); then \
	  $(INSTALL_DATA) menu/welcome.htm $(DESTDIR)$(welcome_htm); \
	fi
	if test ! -r $(DESTDIR)$(credits_htm); then \
	  $(INSTALL_DATA) menu/credits.htm $(DESTDIR)$(credits_htm); \
	fi
	if test ! -d $(DESTDIR)$(aspglobal); then \
	  ( $(mkinstalldirs) $(DESTDIR)$(aspglobal) && \
	      chown $(aspglbowner) $(DESTDIR)$(aspglobal) && \
	      chmod $(aspglbmode) $(DESTDIR)$(aspglobal) ) || \
	  ( rmdir $(DESTDIR)$(aspglobal); false );\
	fi


#####   Documentation files   #####
mydocdir  = $(docdir)
dist_mydoc_DATA = tp-overview.txt tp-overview.pod
SUFFIXES = .pod .txt
.pod.txt:
	pod2text $< $@


#####   XSLT scripts  #####
scriptsdir = $(webscriptsdir)/tp-overview
scripts_DATA = \
	menu/menu.xsl \
	overview/overview.xsl

menu/menu.xsl: menu/menu.xsl.in
	$(SUBST) menu/menu.xsl.in > menu/menu.xsl

overview/overview.xsl: overview/overview.xsl.in
	$(SUBST) overview/overview.xsl.in > overview/overview.xsl

#####   Menu files   #####
menudir	= $(webplaindir)/menu
dist_menu_DATA = \
	menu/bg.jpg \
	menu/menu.css \
	menu/menu.js \
	menu/sampleMenu.xml

#####   Overview files   #####
overviewsdir	= $(webplaindir)/overviews
dist_overviews_DATA = \
	overview/common.inc \
	overview/sampleOverview.xml

#####   xtree files   #####
xtreedir	= $(webplaindir)/xtree
xtree_DATA = xtree/xtree.js xtree/xtree.css
xtree/xtree.js: xtree/xtree.js.in
	$(SUBST) xtree/xtree.js.in > xtree/xtree.js

xtreeimagesdir	= $(webplaindir)/xtree/images
dist_xtreeimages_DATA = \
	xtree/I.png \
	xtree/L.png \
	xtree/Lminus.png \
	xtree/Lplus.png \
	xtree/T.png \
	xtree/Tminus.png \
	xtree/Tplus.png \
	xtree/blank.png \
	xtree/file.png \
	xtree/foldericon.png \
	xtree/new.png \
	xtree/openfoldericon.png

#####   css files   #####
cssdir	= $(webplaindir)
dist_css_DATA = \
	css/ov-mozilla.css \
	css/ov-printer.css \
	css/ov.css \
	css/overview.css

#####   templates files   #####
mytmpldir = $(tmpldir)/ov
dist_mytmpl_DATA = \
	templates/item-rrd.html \
	templates/ov-chooser.html \
	templates/ov-dir.html \
	templates/ov-expanded-dir.html \
	templates/ov-html-incblocks.txt \
	templates/ov-inout-leaves.html \
	templates/ov-tset-list.html \
	templates/ov-tset.html \
	templates/sub-nodes-dir.html \
	templates/overview-subleaves.html \
	templates/tab-rrd.html

#####   xmlconfig files   #####
myxmldir = $(distxmldir)
dist_myxml_DATA = ovDefaults.xml

xmlsampledir	= $(distxmldir)/examples
dist_xmlsample_DATA = ovExample.xml

#####   icons   #####
iconsdir	= $(webplaindir)/icons
dist_icons_DATA = menu/menu.gif menu/torrus.ico

#####   Perl configuration files  #####
torruscfgdir = $(plugtorruscfgdir)
dist_torruscfg_DATA = overview-torruscfg.pl


##### Apache configuration #####

apachedir = $(supdir)/apache
nodist_apache_DATA = tp-overview.apache.conf

tp-overview.apache.conf: tp-overview.apache.conf.in
	$(SUBST) tp-overview.apache.conf.in > tp-overview.apache.conf


htdocs:
	for f in *.pod; do \
	  pod2html -css=../torrusdoc.css $$f > ../../htdocs/plugins/$$f.html; \
	done


UPLOADPATH = \
   ssinyagin@shell.sourceforge.net:/home/groups/t/to/torrus/htdocs/devel

upload: dist
	scp $(distdir).tar.gz $(UPLOADPATH)
