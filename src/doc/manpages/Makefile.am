
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
#  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 02111-1307, USA.

# $Id$
# Stanislav Sinyagin <ssinyagin@yahoo.com>
#

SUBST = @abs_top_builddir@/setup_tools/substvars.sh

EXTRA_DIST = $(SRCPOD)
CLEANFILES = $(PODMAN) $(POD_FILES)

SRCPOD = \
	torrus.pod.in \
	torrus_acledit.pod.in \
	torrus_action_printemail.pod.in \
	torrus_action_snmptrap.pod.in \
	torrus_clearcache.pod.in \
	torrus_collector.pod.in \
	torrus_compilexml.pod.in \
	torrus_configinfo.pod.in \
	torrus_configsnapshot.pod.in \
	torrus_devdiscover.pod.in \
	torrus_genddx.pod.in \
	torrus_monitor.pod.in \
	torrus_schedulerinfo.pod.in

POD_FILES = \
	torrus.pod \
	torrus_acledit.pod \
	torrus_action_printemail.pod \
	torrus_action_snmptrap.pod \
	torrus_clearcache.pod \
	torrus_collector.pod \
	torrus_compilexml.pod \
	torrus_configinfo.pod \
	torrus_configsnapshot.pod \
	torrus_devdiscover.pod \
	torrus_genddx.pod \
	torrus_monitor.pod \
	torrus_schedulerinfo.pod

PODMAN = \
	torrus.@mansec_usercmd@ \
	torrus_acledit.@mansec_usercmd@ \
	torrus_action_printemail.@mansec_misc@ \
	torrus_action_snmptrap.@mansec_misc@ \
	torrus_clearcache.@mansec_usercmd@ \
	torrus_collector.@mansec_usercmd@ \
	torrus_compilexml.@mansec_usercmd@ \
	torrus_configinfo.@mansec_usercmd@ \
	torrus_configsnapshot.@mansec_usercmd@ \
	torrus_devdiscover.@mansec_usercmd@ \
	torrus_genddx.@mansec_usercmd@ \
	torrus_monitor.@mansec_usercmd@ \
	torrus_schedulerinfo.@mansec_usercmd@



if POD2MAN_PRESENT
install-data-local: $(POD_FILES)
	for f in $(PODMAN); do \
	  base=`echo $$f | sed -e 's/\\.[0-9a-zA-Z]*$$//'`; \
	  ext=`echo $$f | sed -e 's/^.*\\.//'`; \
	  instdir=$(DESTDIR)$(mandir)/man$$ext; \
	  echo BASE=$$base EXT=$$ext INSTDIR=$$instdir; \
	  $(POD2MAN) --section=$$ext \
	     --release="$(PACKAGE_STRING)" --center=torrus \
             $$base.pod > $$f || exit 1; \
	  test -d $$instdir || $(mkinstalldirs) $$instdir || exit 1; \
	  $(INSTALL_DATA) $$f $$instdir; \
	  rm $$f; \
	done
endif


SUFFIXES = .pod.in .pod

.PRECIOUS: $(POD_FILES)

.pod.in.pod:
	$(SUBST) $<  > $@


