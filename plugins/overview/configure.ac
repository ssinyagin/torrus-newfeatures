#  Copyright (C) 2003  Stanislav Sinyagin
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

# Http Torrus plugin Autoconf script

AC_INIT(tp-overview, 1.0d, ssinyagin@users.sourceforge.net)
AC_CONFIG_AUX_DIR(conftools)
AC_CANONICAL_HOST
AM_INIT_AUTOMAKE(1.6)

AC_PATH_PROG(PERL, perl, no)
AC_PATH_PROG(SED, sed, no)

AC_ARG_ENABLE(pkgonly,
        [AC_HELP_STRING([--enable-pkgonly],
                        [Skip all checking])])

if test "$enable_pkgonly" != yes; then
  AC_MSG_CHECKING([environment variables])
  if test -z "$pkghome" -o -z "$sitedir"; then
    AC_MSG_ERROR([Missing mandatory environment variables]);
  else
    AC_MSG_RESULT([Ok])
  fi

  AC_MSG_CHECKING([presence of Apache::ASP])
  if ${PERL} -e 'use Apache::ASP' 2>/dev/null; then
    AC_MSG_RESULT([Ok])
  else
    AC_MSG_ERROR([Perl cannot find Apache::ASP]);
  fi

  AC_MSG_CHECKING([presence of XML::LibXSLT])
  if ${PERL} -e 'use Apache::ASP' 2>/dev/null; then
    AC_MSG_RESULT([Ok])
  else
    AC_MSG_ERROR([Perl cannot find Apache::ASP]);
  fi

  AC_MSG_CHECKING([presence of XML::Sablotron])
  if ${PERL} -e 'use Apache::ASP' 2>/dev/null; then
    AC_MSG_RESULT([Ok])
  else
    AC_MSG_ERROR([Perl cannot find Apache::ASP]);
  fi
fi


AC_ARG_VAR(pkghome,   [[PREFIX/torrus] Place for Torrus static files])
AC_ARG_VAR(pkgbindir,   [[PKGHOME/bin] Torrus executables])
AC_ARG_VAR(cfgdefdir,   [[PKGHOME/conf_defaults] torrus-config.pl and others])
AC_ARG_VAR(docdir, [[PKGHOME/doc] Documentation files])
AC_ARG_VAR(exmpdir, [[PKGHOME/examples] Examples])
AC_ARG_VAR(perllibdir,  [[PKGHOME/perllib] Torrus Perl libraries])
AC_ARG_VAR(pluginsdir,   [[PKGHOME/plugins] Plugin configurations])
AC_ARG_VAR(plugtorruscfgdir, [[PLUGINSDIR/torrus-config]])
AC_ARG_VAR(plugdevdisccfgdir, [[PLUGINSDIR/devdiscover-config]])
AC_ARG_VAR(scriptsdir, [[PKGHOME/scripts] Script files])
AC_ARG_VAR(supdir, [[PKGHOME/sup] Supplementary files])
AC_ARG_VAR(webplaindir, [[SUPDIR/webplain] Web interface plain files path])
AC_ARG_VAR(webscriptsdir, [[SUPDIR/webscripts] Directory for web scripts])
AC_ARG_VAR(tmpldir, [[PKGHOME/templates] Template files])
AC_ARG_VAR(tmpluserdir, [[SITEDIR/templates] User-defined Template files])
AC_ARG_VAR(distxmldir, [[PKGHOME/xmlconfig] Distribution XML config files])
AC_ARG_VAR(sitedir, [[SYSCONFDIR/torrus] Site configuration files])
AC_ARG_VAR(siteconfdir, [[SITEDIR/conf] Site configuration files])
AC_ARG_VAR(sitexmldir, [[SITEDIR/xmlconfig] Site XML configs])
AC_ARG_VAR(logdir, [[/var/log/torrus] Log files])
AC_ARG_VAR(piddir, [[/var/run/torrus] PID files])
AC_ARG_VAR(varprefix, [[/var/torrus] Common prefix for runtime data])
AC_ARG_VAR(cachedir, [[VARPREFIX/cache] Renderer cache])
AC_ARG_VAR(dbhome, [[VARPREFIX/db] Berkeley DB files])
AC_ARG_VAR(seslockdir, [[VARPREFIX/session_data/lock] Web session locks])
AC_ARG_VAR(sesstordir, [[VARPREFIX/session_data/store] Web session storage])
AC_ARG_VAR(wrapperdir, [[BINDIR] CLI wrapper])

# Plugin specific variables

AC_ARG_VAR(rendererUrl, [[/torrus] Renderer URL])
if test -z "$rendererUrl"; then
   rendererUrl='/torrus'; fi

AC_ARG_VAR(plainUrl, [[/torrus/plain] Plain URL])
if test -z "$plainUrl"; then
   plainUrl='${rendererUrl}/plain'; fi

AC_ARG_VAR(aspglobal, [[VARPREFIX/asp] Apache::ASP Global storage])
if test -z "$aspglobal"; then
   aspglobal='${varprefix}/asp'; fi

AC_ARG_VAR(aspglbowner, [[torrus:torrus] Apache::ASP Global directory owner])
if test -z "$aspglbowner"; then
   aspglbowner='torrus:torrus'; fi

AC_ARG_VAR(aspglbmode, [[775] Apache::ASP Global directory mode])
if test -z "$aspglbmode"; then
   aspglbmode='775'; fi


AC_CONFIG_FILES([Makefile])
AC_CONFIG_FILES([ov_substvars.sh], [chmod +x ov_substvars.sh])

AC_OUTPUT
