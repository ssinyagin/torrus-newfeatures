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

SUBDIRS = . bin configs doc examples perllib sup xmlconfig 

EXTRA_DIST = \
	setup_tools/replace_rrfw.sh

noinst_SCRIPTS = \
	setup_tools/substvars.sh \
	setup_tools/mkvardir.sh \
	init.d/torrus

tmpldir = @tmpldir@
dist_tmpl_DATA = \
	templates/aclexport.xml \
	templates/adminfo.html \
	templates/default-chooser.html \
	templates/default-dir.html \
	templates/default-helptext.html \
	templates/default-login.html \
	templates/default-rrd.html \
	templates/default-tset.html \
	templates/expanded-dir.html \
	templates/overview-subleaves.html \
	templates/html-incblocks.txt \
	templates/tset-list.html \
	templates/email-alarm.txt



scriptsdir  = @scriptsdir@
dist_scripts_DATA = scripts/rrdup_notify.sh

xmlscriptsdir  = @scriptsdir@/xml
dist_xmlscripts_DATA = scripts/xml/extract-skeleton.xsl


discoverydir = @sitedir@/discovery
dist_discovery_DATA = discovery/README

mkvardir=@abs_top_builddir@/setup_tools/mkvardir.sh

install-data-local:
	@echo Testing if prefix has changed during make
	test "$(prefix)" = "@prefix@"
	$(mkvardir) $(DESTDIR)$(dbhome)
	$(mkvardir) $(DESTDIR)$(cachedir)
	$(mkvardir) $(DESTDIR)$(piddir)
	$(mkvardir) $(DESTDIR)$(logdir)
	$(mkvardir) $(DESTDIR)$(sesstordir)
	$(mkvardir) $(DESTDIR)$(seslockdir)	
	$(mkinstalldirs) $(DESTDIR)@tmpluserdir@

HTMLDIR = @abs_top_builddir@/../htdocs

htdocs:
	cd doc; make htdocs
	@for f in $(dist_mibs_DATA); do \
	  f2=$(HTMLDIR)/`basename $$f`; \
	  if test ! -f $$f2 -o $$f -nt $$f2; then \
	    echo "cp $$f $$f2"; \
	    cp $$f $$f2; \
	  fi; \
	done

UPLOADPATH = \
   ssinyagin@shell.sourceforge.net:/home/groups/t/to/torrus/htdocs/devel

upload: dist
	scp $(distdir).tar.gz TODO $(UPLOADPATH)
	  

dist-hook:
	date >DIST_REVISION
	cp DIST_REVISION $(distdir)/
