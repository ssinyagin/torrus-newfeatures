
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

XFORM_STRINGS = xformstrings.sed

SUBST = $(SHELL) -c '$(top_srcdir)/setup_tools/substvars.sh $$0 | \
	$(SED) -f $(XFORM_STRINGS)'

CMDNAMES = \
	acledit \
	action_printemail \
	action_snmptrap \
	action_snmpv1trap \
	clearcache \
	collector \
	compilexml \
	configinfo \
	configsnapshot \
	devdiscover \
	genddx \
	monitor \
	schedulerinfo

SRCPOD = \
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

XFORMEDPOD = \
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
	torrus_acledit.1 \
	torrus_action_printemail.7 \
	torrus_action_snmptrap.7 \
	torrus_clearcache.1 \
	torrus_collector.1 \
	torrus_compilexml.1 \
	torrus_configinfo.1 \
	torrus_configsnapshot.1 \
	torrus_devdiscover.1 \
	torrus_genddx.1 \
	torrus_monitor.1 \
	torrus_schedulerinfo.1


EXTRA_DIST = $(SRCPOD)
CLEANFILES = $(PODMAN) $(XFORMEDPOD) $(XFORM_STRINGS)

if POD2MAN_PRESENT
  man_MANS = $(PODMAN)
endif

$(XFORM_STRINGS): Makefile
	rm -f $(XFORM_STRINGS)
	for f in $(CMDNAMES); do \
	  xx=`echo $$f | $(SED) -e '$(program_transform_name)'`; \
	  echo "s,\@XFORM_$$f\@,"$$xx"," >>$(XFORM_STRINGS); \
	done

SUFFIXES = .pod.in .pod .1 .7

.PRECIOUS: $(XFORMEDPOD)

.pod.in.pod:
	$(MAKE) $(XFORM_STRINGS)
	$(SUBST) $<  > $@

.pod.1:
	$(POD2MAN) --release="$(PACKAGE_STRING)" --center=torrus $<  > $@

.pod.7:
	$(POD2MAN) --section=7 \
	   --release="$(PACKAGE_STRING)" --center=torrus $<  > $@


