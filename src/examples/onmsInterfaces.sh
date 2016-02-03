#!/bin/sh
#  Copyright (C) 2004 Gustavo Torres
#  Copyright (C) 2004 Stanislav Sinyagin
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

# Gustavo Torres <r3db34rd@yahoo.com>
# Stanislav Sinyagin <ssinyagin@k-open.com>
#

# This shell script extracts OpenNMS information about interfaces
# and builds the data file which you can use with onms.tmpl to generate
# Torrus XML configuration.

# Usage (RESPONSEDIR setting may be skipped if it's in the default path)
#
# RESPONSEDIR=/var/opennms/rrd/response
# export RESPONSEDIR
# cd /usr/local/torrus-0.1/share/torrus/
# ./examples/onmsInterfaces.sh > onms.data
# tpage --define data=onms.data examples/onms.tmpl > xmlconfig/onms.xml


if test x"$RESPONSEDIR" = x""; then
  RESPONSEDIR=/var/opennms/rrd/response
fi

echo '[% responsedir = "'$RESPONSEDIR'" %]'
echo '[% ifs = ['

for ipaddr in `ls ${RESPONSEDIR}`; do
  echo "  { addr => '$i',";
  echo "    services => [";
  for service in `ls ${RESPONSEDIR}/$i | awk -F. '{print $1}'`; do
    echo -n "      {name => '${service}', "
    legend=`echo $j | awk '{print toupper($1)}'`
    echo "legend => '${legend}'}"
  done
  echo '    ]';
  echo '  }';
done
echo '] %]'

# Local Variables:
# mode: shell-script
# indent-tabs-mode: nil
# perl-indent-level: 4
# End:
