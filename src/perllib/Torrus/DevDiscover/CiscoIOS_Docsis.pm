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

# DOCSIS interface, Cisco specific
# MIB used:
# CISCO-DOCS-EXT-MIB:cdxCmtsMacExtTable
# CISCO-DOCS-EXT-MIB:cdxIfUpstreamChannelExtTable

package Torrus::DevDiscover::CiscoIOS_Docsis;

use strict;
use Torrus::Log;

# Sequence number is 600 - we depend on RFC2670_DOCS_IF and CiscoIOS

$Torrus::DevDiscover::registry{'CiscoIOS_Docsis'} = {
    'sequence'     => 600,
    'checkdevtype' => \&checkdevtype,
    'discover'     => \&discover,
    'buildConfig'  => \&buildConfig
    };



sub checkdevtype
{
    my $dd = shift;
    my $devdetails = shift;

    if( $devdetails->isDevType('CiscoIOS') and
        $devdetails->isDevType('RFC2670_DOCS_IF') )
    {
        return 1;
    }

    return 0;
}


sub discover
{
    my $dd = shift;
    my $devdetails = shift;

    return 1;
}


sub buildConfig
{
    my $devdetails = shift;
    my $cb = shift;
    my $devNode = shift;

    my $data = $devdetails->data();

    # Build Docsis_Utilization subtree

    my $subtreeNode =
        $cb->addSubtree( $devNode, 'Docsis_Utilization', {},
                         ['CiscoIOS_Docsis::docsis-utilization-subtree'] );
    
}


1;


# Local Variables:
# mode: perl
# indent-tabs-mode: nil
# perl-indent-level: 4
# End:
