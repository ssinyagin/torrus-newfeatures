
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

SUBDIRS = . manpages

docdir  = @docdir@

dist_doc_DATA = \
		install.txt           install.pod \
		rpnexpr.txt           rpnexpr.pod \
		scalability.pod	      scalability.txt \
		snmpdiscovery.txt     snmpdiscovery.pod \
		stylingprofile.txt    stylingprofile.pod \
		userguide.txt         userguide.pod \
		vendorsupport.txt     vendorsupport.pod \
		webintf.txt	      webintf.pod \
		xmlconfig.txt         xmlconfig.pod

devdocdir  = $(docdir)/devdoc

dist_devdoc_DATA = \
		devdoc/architecture.pod \
		devdoc/devdiscover.pod \
		devdoc/progstyle.pod \
		devdoc/reqs.0.0.pod \
		devdoc/reqs.0.1.pod \
		devdoc/torrus_roadmap.pod \
		devdoc/wd.distributed.pod \
		devdoc/wd.messaging.pod \
		devdoc/wd.monitor-escalation.pod \
		devdoc/wd.uptime-mon.pod


SUFFIXES = .pod .txt

.pod.txt:
	pod2text $< $@ 


htdocs:
	HTMLDIR=@abs_top_builddir@/../htdocs $(SHELL) mkhtdocs.sh

