#  Copyright (C) 2011 Stanislav Sinyagin
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

# Technicolor Thomson xDSL gateways
# Only interface indexing and naming is handled here.

package Torrus::DevDiscover::Thomson_xDSL;

use strict;
use Torrus::Log;

our $VERSION = 1.0;

$Torrus::DevDiscover::registry{'Thomson_xDSL'} = {
    'sequence'     => 500,
    'checkdevtype' => \&checkdevtype,
    'discover'     => \&discover,
    'buildConfig'  => \&buildConfig
    };


our %oiddef =
    (
     'thomson_xDSL_products'     => '1.3.6.1.4.1.2863.405',
     );


sub checkdevtype
{
    my $dd = shift;
    my $devdetails = shift;

    if( not $dd->oidBaseMatch
        ( 'thomson_xDSL_products',
          $devdetails->snmpVar( $dd->oiddef('sysObjectID') ) ) )
    {
        return 0;
    }
    
    $devdetails->setCap('interfaceIndexingPersistent');

    &Torrus::DevDiscover::RFC2863_IF_MIB::addInterfaceFilter
        ($devdetails,
         {
             'BRG' => {
                 'ifType'  => 6,   # ethernetCsmacd
                 'ifDescr' => '^BRG:' } });
    
    return 1;
}


sub discover
{
    my $dd = shift;
    my $devdetails = shift;

    my $data = $devdetails->data();
    my $session = $dd->session();
            
    $data->{'nameref'}{'ifSubtreeName'} = 'ifNameT';
    $data->{'nameref'}{'ifReferenceName'} = 'ifName';
    $data->{'nameref'}{'ifNick'} = 'ifIndex';
    $data->{'nameref'}{'ifNodeid'} = 'ifIndex';

    undef $data->{'nameref'}{'ifComment'};
    
    $data->{'param'}{'snmp-oids-per-pdu'} = 10;
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
