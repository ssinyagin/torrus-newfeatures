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

# AxxessIT Ethernet over SDH switches, also known as
# Cisco ONS 15305 and 15302 (by January 2005)
# Probably later Cisco will update the software and it will need
# another Torrus discovery module.
# Company website: http://www.axxessit.no/

# Tested with:
#
# Cisco ONS 15305

# TODO:
# Interface descriptions
# axxEdgePortDescription
# axxEdgeWanPortDescription
# axxEdgeEthPortDescription
    
    

package Torrus::DevDiscover::AxxessIT;

use strict;
use Torrus::Log;


$Torrus::DevDiscover::registry{'AxxessIT'} = {
    'sequence'     => 500,
    'checkdevtype' => \&checkdevtype,
    'discover'     => \&discover,
    'buildConfig'  => \&buildConfig
    };


our %oiddef =
    (
     # AXXEDGE-MIB
     'axxEdgeTypes'                  => '1.3.6.1.4.1.7546.1.4.1.1',
     'axxEdgeDcnIpOverDccMapTable'   => '1.3.6.1.4.1.7546.1.4.1.2.3.1.2',
     'axxEdgeDcnIpOverDccMapIfIndex' => '1.3.6.1.4.1.7546.1.4.1.2.3.1.2.1.1',
     'axxEdgeDcnIpOverDccMapSlot'    => '1.3.6.1.4.1.7546.1.4.1.2.3.1.2.1.2',
     'axxEdgeDcnIpOverDccMapSdhPort' => '1.3.6.1.4.1.7546.1.4.1.2.3.1.2.1.3',
     'axxEdgeDcnIpOverDccMapDccChannel' =>
                                        '1.3.6.1.4.1.7546.1.4.1.2.3.1.2.1.4',
     'axxEdgeWanPortMapTable'      => '1.3.6.1.4.1.7546.1.4.1.2.5.1.2',
     'axxEdgeWanPortMapSlotNumber' => '1.3.6.1.4.1.7546.1.4.1.2.5.1.2.1.1',
     'axxEdgeWanPortMapPortNumber' => '1.3.6.1.4.1.7546.1.4.1.2.5.1.2.1.2'
     );

# Not all interfaces are normally needed to monitor.
# You may override the interface filtering in devdiscover-siteconfig.pl:
# redefine $Torrus::DevDiscover::AxxessIT::interfaceFilter
# or define $Torrus::DevDiscover::AxxessIT::interfaceFilterOverlay

our $interfaceFilter;
our $interfaceFilterOverlay;
my %axxInterfaceFilter;

if( not defined( $interfaceFilter ) )
{
    $interfaceFilter = \%axxInterfaceFilter;
}


# Key is some unique symbolic name, does not mean anything
# ifType is the number to match the interface type
# ifDescr is the regexp to match the interface description
%axxInterfaceFilter =
    (
     );

sub checkdevtype
{
    my $dd = shift;
    my $devdetails = shift;

    if( index( $devdetails->snmpVar( $dd->oiddef('sysObjectID') ),
               $dd->oiddef('axxEdgeTypes') ) != 0 )
    {
        return 0;
    }

    # Leave room for AXX155 devices, maybe someone needs them in the future
    $devdetails->setCap('axxEdge');
        
    &Torrus::DevDiscover::RFC2863_IF_MIB::addInterfaceFilter
        ($devdetails, $interfaceFilter);

    if( defined( $interfaceFilterOverlay ) )
    {
        &Torrus::DevDiscover::RFC2863_IF_MIB::addInterfaceFilter
            ($devdetails, $interfaceFilterOverlay);
    }

    my $data = $devdetails->data();

    $data->{'param'}{'ifindex-map'} = '$IFIDX_IFINDEX';

    $data->{'nameref'}{'ifNick'}        = 'axxInterfaceNick';
    $data->{'nameref'}{'ifSubtreeName'} = 'axxInterfaceNick';
    $data->{'nameref'}{'ifComment'}     = 'axxInterfaceComment';
    $data->{'nameref'}{'ifHumanName'}   = 'axxInterfaceHumanName';

    return 1;
}


sub discover
{
    my $dd = shift;
    my $devdetails = shift;

    my $data = $devdetails->data();
    my $session = $dd->session();

    if( $devdetails->hasCap('axxEdge') )
    {
        my $dccTable =
            $session->get_table( -baseoid =>
                                 $dd->oiddef('axxEdgeDcnIpOverDccMapTable') );
        $devdetails->storeSnmpVars( $dccTable );

        my $wanTable =
            $session->get_table( -baseoid =>
                                 $dd->oiddef('axxEdgeWanPortMapTable') );
        $devdetails->storeSnmpVars( $wanTable );

        foreach my $ifIndex
            ( $devdetails->
              getSnmpIndices($dd->oiddef('axxEdgeDcnIpOverDccMapSlot')) )
        {
            my $interface = $data->{'interfaces'}{$ifIndex};
            next if not defined( $interface );
            
            my $slot =
                $devdetails->snmpVar
                ($dd->oiddef('axxEdgeDcnIpOverDccMapSlot') .'.'. $ifIndex);
            my $port =
                $devdetails->snmpVar
                ($dd->oiddef('axxEdgeDcnIpOverDccMapSdhPort') .'.'. $ifIndex);
            my $channel =
                $devdetails->snmpVar
                ($dd->oiddef('axxEdgeDcnIpOverDccMapDccChannel') .'.'.
                 $ifIndex);
            
            my $channel_nick = 'dcc' . ($channel == 1 ? 'R':'M');
            my $channel_name = 'DCC-' . ($channel == 1 ? 'R':'M');
            
            $interface->{'param'}{'interface-index'} = $ifIndex;

            $interface->{'axxInterfaceNick'} =
                sprintf( 'Dcn_%d_%d_%s', $slot, $port, $channel_nick );

            $interface->{'axxInterfaceHumanName'} =
                sprintf( 'DCN %d/%d %s', $slot, $port, $channel_name );

            $interface->{'axxInterfaceComment'} =
                sprintf( 'DCN slot %d, port %d, channel %s',
                         $slot, $port, $channel_name );
        }

        
        foreach my $ifIndex
            ( $devdetails->
              getSnmpIndices($dd->oiddef('axxEdgeWanPortMapSlotNumber')) )
        {
            my $interface = $data->{'interfaces'}{$ifIndex};
            next if not defined( $interface );

            my $slot =
                $devdetails->snmpVar
                ($dd->oiddef('axxEdgeWanPortMapSlotNumber') .'.'. $ifIndex);
            my $port =
                $devdetails->snmpVar
                ($dd->oiddef('axxEdgeWanPortMapPortNumber') .'.'. $ifIndex);
            
            
            $interface->{'param'}{'interface-index'} = $ifIndex;

            $interface->{'axxInterfaceNick'} =
                sprintf( 'Wan_%d_%d', $slot, $port );

            $interface->{'axxInterfaceHumanName'} =
                sprintf( 'WAN %d/%d', $slot, $port );

            $interface->{'axxInterfaceComment'} =
                sprintf( 'WAN slot %d, port %d', $slot, $port );
        }

        # Management interface
        {
            my $interface = $data->{'interfaces'}{1000};
            
            $interface->{'param'}{'interface-index'} = 1000;

            $interface->{'axxInterfaceNick'} = 'Mgmt';

            $interface->{'axxInterfaceHumanName'} = 'Management';

            $interface->{'axxInterfaceComment'} = 'Management port';
        }
        
        foreach my $ifIndex ( keys %{$data->{'interfaces'}} )
        {
            if( not defined( $data->{'interfaces'}{$ifIndex}->
                             {'param'}{'interface-index'} ) )
            {
                delete $data->{'interfaces'}{$ifIndex};
            }
        }
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
