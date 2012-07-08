#  Copyright (C) 2012 Stanislav Sinyagin
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

# Comtech EF Data satellite modems

package Torrus::DevDiscover::ComtechEFData;

use strict;
use warnings;

use Torrus::Log;


$Torrus::DevDiscover::registry{'ComtechEFData'} = {
    'sequence'     => 500,
    'checkdevtype' => \&checkdevtype,
    'discover'     => \&discover,
    'buildConfig'  => \&buildConfig
    };


our %oiddef =
    (
     'ComtechEFData'     => '1.3.6.1.4.1.6247',
     'CDM-570::cdm570'   => '1.3.6.1.4.1.6247.24',
     );


sub checkdevtype
{
    my $dd = shift;
    my $devdetails = shift;

    my $sysObjectID = $devdetails->snmpVar( $dd->oiddef('sysObjectID') );
    
    if( not $dd->oidBaseMatch( 'ComtechEFData', $sysObjectID ) )
    {
        return 0;
    }

    if( $dd->oidBaseMatch( 'CDM-570::cdm570', $sysObjectID ) )
    {
        $devdetails->setCap('cdm570');
    }

    $devdetails->setCap('interfaceIndexingPersistent');
    
    &Torrus::DevDiscover::RFC2863_IF_MIB::addInterfaceFilter
        ($devdetails,
         {
             'loopback' => {
                 'ifType'  => 24,   # softwareLoopback
                 'ifDescr' => 'loopback'
             }
         });
    
    return 1;
}


sub discover
{
    my $dd = shift;
    my $devdetails = shift;

    my $data = $devdetails->data();
    my $session = $dd->session();
    
    $data->{'param'}{'snmp-oids-per-pdu'} = 10;

    return 1;
}


sub buildConfig
{
    my $devdetails = shift;
    my $cb = shift;
    my $devNode = shift;

    if( $devdetails->hasCap('cdm570') )
    {
        $cb->addTemplateApplication($devNode, 'ComtechEFData::cdm570');
    }
    
    return;
}



1;


# Local Variables:
# mode: perl
# indent-tabs-mode: nil
# perl-indent-level: 4
# End:
