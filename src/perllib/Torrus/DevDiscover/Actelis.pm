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

# Actelis Networks xDSL gateways
# Only interface indexing and naming is handled here.

package Torrus::DevDiscover::Actelis;

use strict;
use warnings;

use Torrus::Log;


$Torrus::DevDiscover::registry{'Actelis'} = {
    'sequence'     => 500,
    'checkdevtype' => \&checkdevtype,
    'discover'     => \&discover,
    'buildConfig'  => \&buildConfig
    };


our %oiddef =
    (
     'actelis_products'     => '1.3.6.1.4.1.5468.1',
     );


sub checkdevtype
{
    my $dd = shift;
    my $devdetails = shift;

    if( not $dd->oidBaseMatch
        ( 'actelis_products',
          $devdetails->snmpVar( $dd->oiddef('sysObjectID') ) ) )
    {
        return 0;
    }
    
    $devdetails->setCap('interfaceIndexingPersistent');
    
    # 64-bit counters are always zero, so we skip all of them
    $devdetails->setCap('suppressHCCounters');
    
    return 1;
}


sub discover
{
    my $dd = shift;
    my $devdetails = shift;

    my $data = $devdetails->data();
    my $session = $dd->session();
            
    $data->{'param'}{'snmp-oids-per-pdu'} = 10;
    $data->{'nameref'}{'ifSubtreeName'} = 'ifNameT';
    $data->{'nameref'}{'ifReferenceName'} = 'ifName';
    $data->{'nameref'}{'ifNick'} = 'ifName';
    $data->{'nameref'}{'ifNodeid'} = 'ifName';
    
    # Exlcude MLP interfaces as they never update ifIn/Out octet
    # counters anyway
    
    foreach my $ifIndex ( keys %{$data->{'interfaces'}})
    {
        my $interface = $data->{'interfaces'}{$ifIndex};
        next if $interface->{'excluded'};

        if( $interface->{'ifType'} == 169 ) # ifType: shdsl(169)
        {
            $interface->{'excluded'} = 1;
            next;
        }
        
        if( ($ifIndex == 2001) or ($ifIndex == 2002) )
        {
            $interface->{'ignoreHighSpeed'} = 1;
            $interface->{'ifSpeedMonitoring'} = 1;
        }
    }
   
    return 1;
}


sub buildConfig
{
    my $devdetails = shift;
    my $cb = shift;
    my $devNode = shift;
    return;
}



1;


# Local Variables:
# mode: perl
# indent-tabs-mode: nil
# perl-indent-level: 4
# End:
