#!/bin/bash
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

PACKAGE=tp-randomcollector
prefix=/usr/local
pkghome=
exec_prefix=${prefix}
perllibdir=
pluginsdir=
sysconfdir=${prefix}/etc
varprefix=
sitedir=
supdir=
styldir=/styling

devdiscover_config_pl=/devdiscover-config.pl
torrus_config_pl=/torrus-config.pl

torrus_siteconfig_pl=/torrus-siteconfig.pl
snmptrap_siteconfig_pl=/snmptrap-siteconfig.pl
email_siteconfig_pl=/email-siteconfig.pl
devdiscover_siteconfig_pl=/devdiscover-siteconfig.pl

/usr/bin/sed \
    -e "s,\@VERSION\@,1.0d,g" \
    -e "s,\@PERL\@,/usr/bin/perl,g" \
    -e "s,\@SHELL\@,/bin/bash,g" \
    -e "s,\@FIND\@,@FIND@,g" \
    -e "s,\@RM\@,@RM@,g" \
    -e "s,\@torrus_user\@,@torrus_user@,g" \
    -e "s,\@cfgdefdir\@,,g" \
    -e "s,\@siteconfdir\@,,g" \
    -e "s,\@perllibdirs\@,@perllibdirs@,g" \
    -e "s,\@pkgbindir\@,,g" \
    -e "s,\@pluginsdir\@,,g" \
    -e "s,\@plugtorruscfgdir\@,,g" \
    -e "s,\@plugdevdisccfgdir\@,,g" \
    -e "s,\@distxmldir\@,,g" \
    -e "s,\@sitedir\@,,g" \
    -e "s,\@sitexmldir\@,,g" \
    -e "s,\@tmpldir\@,,g" \
    -e "s,\@styldir\@,$styldir,g" \
    -e "s,\@dbhome\@,,g" \
    -e "s,\@cachedir\@,,g" \
    -e "s,\@piddir\@,,g" \
    -e "s,\@logdir\@,,g" \
    -e "s,\@sesstordir\@,,g" \
    -e "s,\@seslockdir\@,,g" \
    -e "s,\@devdiscover_config_pl\@,$devdiscover_config_pl,g" \
    -e "s,\@torrus_config_pl\@,$torrus_config_pl,g" \
    -e "s,\@devdiscover_siteconfig_pl\@,$devdiscover_siteconfig_pl,g" \
    -e "s,\@email_siteconfig_pl\@,$email_siteconfig_pl,g" \
    -e "s,\@snmptrap_siteconfig_pl\@,$snmptrap_siteconfig_pl,g" \
    -e "s,\@torrus_siteconfig_pl\@,$torrus_siteconfig_pl,g" \
    $1

# Local Variables:
# mode: shell-script
# indent-tabs-mode: nil
# perl-indent-level: 4
# End:
