#  Copyright (C) 2006  Jon Nistor
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
# Jon Nistor <nistor@snickers.org>

# Juniper JunOS Discovery Module

package Torrus::DevDiscover::JunOS;

use strict;
use Torrus::Log;


$Torrus::DevDiscover::registry{'JunOS'} = {
    'sequence'     => 500,
    'checkdevtype' => \&checkdevtype,
    'discover'     => \&discover,
    'buildConfig'  => \&buildConfig
    };


our %oiddef =
    (
     # JUNIPER-SMI
     'jnxProducts'          => '1.3.6.1.4.1.2636.1',
     # JUNIPER-MIB::jnxBoxDescr.0
     'jnxBoxDescr'          => '1.3.6.1.4.1.2636.3.1.2.0',
     # JUNIPER-MIB::jnxBoxSerialNo.0
     'jnxBoxSerialNo'       => '1.3.6.1.4.1.2636.3.1.3.0'
     );


sub checkdevtype
{
    my $dd = shift;
    my $devdetails = shift;

    if( not $dd->oidBaseMatch
        ( 'jnxProducts',
          $devdetails->snmpVar( $dd->oiddef('sysObjectID') ) ) )
    {
        return 0;
    }

    $devdetails->setCap('interfaceIndexingManaged');

    return 1;
}


sub discover
{
    my $dd = shift;
    my $devdetails = shift;

    my $session = $dd->session();
    my $data = $devdetails->data();

    # Comments and Serial number of device
    my $chassisSerial =
        $dd->retrieveSnmpOIDs( 'jnxBoxDescr', 'jnxBoxSerialNo' );
    if( defined( $chassisSerial ) )
    {
        $data->{'param'}{'comment'} =
            $chassisSerial->{'jnxBoxDescr'} . ', Hw Serial#: ' .
            $chassisSerial->{'jnxBoxSerialNo'};
    }

    return 1;
}


sub buildConfig
{
    my $devdetails = shift;
    my $cb = shift;
    my $devNode = shift;

}




1;


# Local Variables:
# mode: perl
# indent-tabs-mode: nil
# perl-indent-level: 4
# End:
