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

# Cisco IOS devices discovery
# To do:
#   SA Agent MIB
#   DiffServ MIB

package Torrus::DevDiscover::CiscoIOS;

use strict;
use Torrus::Log;


$Torrus::DevDiscover::registry{'CiscoIOS'} = {
    'sequence'     => 500,
    'checkdevtype' => \&checkdevtype,
    'discover'     => \&discover,
    'buildConfig'  => \&buildConfig
    };


our %oiddef =
    (
     # CISCO-SMI
     'ciscoProducts'                     => '1.3.6.1.4.1.9.1',
     # CISCO-PRODUCTS-MIB
     'ciscoLS1010'                       => '1.3.6.1.4.1.9.1.107',
     # CISCO-IMAGE-MIB
     'ciscoImageTable'                   => '1.3.6.1.4.1.9.9.25.1.1',
     # OLD-CISCO-MEMORY-MIB
     'bufferElFree'                      => '1.3.6.1.4.1.9.2.1.9.0',
     # CISCO-IPSEC-FLOW-MONITOR-MIB
     'cipSecGlobalHcInOctets'            => '1.3.6.1.4.1.9.9.171.1.3.1.4.0'
     );


# Not all interfaces are normally needed to monitor.
# You may override the interface filtering in devdiscover-siteconfig.pl:
# redefine $Torrus::DevDiscover::CiscoIOS::interfaceFilter
# or define $Torrus::DevDiscover::CiscoIOS::interfaceFilterOverlay

our $interfaceFilter;
our $interfaceFilterOverlay;
my %ciscoInterfaceFilter;

if( not defined( $interfaceFilter ) )
{
    $interfaceFilter = \%ciscoInterfaceFilter;
}


# Key is some unique symbolic name, does not mean anything
# ifType is the number to match the interface type
# ifDescr is the regexp to match the interface description
%ciscoInterfaceFilter =
    (
     'Null0' => {
         'ifType'  => 1,                      # other
         'ifDescr' => '^Null'
         },

     'E1 N/N/N' => {
         'ifType'  => 18,                     # ds1
         'ifDescr' => '^E1'
         },

     'Virtual-AccessN' => {
         'ifType'  => 23,                     # ppp
         'ifDescr' => '^Virtual-Access'
         },
     
     'DialerN' => {
         'ifType'  => 23,                     # ppp
         'ifDescr' => '^Dialer'
         },

     'LoopbackN'  => {
         'ifType'  => 24,                     # softwareLoopback
         'ifDescr' => '^Loopback'
         },

     'VlanN' => {
         'ifType'  => 53,                     # propVirtual
         'ifDescr' => '^Vlan\d+'
         },

     'unrouted VLAN N' => {
         'ifType'  => 53,                     # propVirtual
         'ifDescr' => '^unrouted\s+VLAN\s+\d+'
         },

     'SerialN:N-Bearer Channel' => {
         'ifType'  => 81,                     #  ds0, Digital Signal Level 0
         'ifDescr' => '^Serial.*Bearer\s+Channel'
         },

     'Voice Encapsulation (POTS) Peer: N' => {
         'ifType'  => 103                     # voiceEncap
         },

     'Voice Over IP Peer: N' => {
         'ifType'  => 104                     # voiceOverIp
         },

     'ATMN/N/N.N-atm subif' => {
         'ifType'  => 134,                    # atmSubInterface
         'ifDescr' => '^ATM[0-9\/]+\.[0-9]+\s+subif'
         },
     );




sub checkdevtype
{
    my $dd = shift;
    my $devdetails = shift;

    if( not $dd->oidBaseMatch
        ( 'ciscoProducts',
          $devdetails->snmpVar( $dd->oiddef('sysObjectID') ) ) )
    {
        return 0;
    }

    my $session = $dd->session();
    if( not defined( $session->get_table
                     ( -baseoid => $dd->oiddef('ciscoImageTable') ) ) )
    {
        return 0;
    }

    &Torrus::DevDiscover::RFC2863_IF_MIB::addInterfaceFilter
        ($devdetails, $interfaceFilter);

    if( defined( $interfaceFilterOverlay ) )
    {
        &Torrus::DevDiscover::RFC2863_IF_MIB::addInterfaceFilter
            ($devdetails, $interfaceFilterOverlay);
    }

    return 1;
}


sub discover
{
    my $dd = shift;
    my $devdetails = shift;

    my $session = $dd->session();
    my $data = $devdetails->data();

    # Old mkroutercfg used cisco-interface-counters
    if( $Torrus::DevDiscover::CiscoIOS::useCiscoInterfaceCounters )
    {
        foreach my $interface ( values %{$data->{'interfaces'}} )
        {
            $interface->{'hasHCOctets'} = 0;
            $interface->{'hasOctets'} = 0;
            push( @{$interface->{'templates'}},
                  'CiscoIOS::cisco-interface-counters' );
        }
    }
    else
    {
        # This is a well-known bug in IOS: HC counters are implemented,
        # but always zero. We can catch this only for active interfaces.

        foreach my $ifIndex ( sort {$a<=>$b} keys %{$data->{'interfaces'}} )
        {
            my $interface = $data->{'interfaces'}{$ifIndex};

            if( $interface->{'hasHCOctets'} and
                ( (
                   $devdetails->snmpVar( $dd->oiddef('ifHCInOctets')
                                         . '.' . $ifIndex ) == 0 and
                   $devdetails->snmpVar( $dd->oiddef('ifInOctets')
                                         . '.' . $ifIndex ) > 0
                   )
                  or
                  (
                   $devdetails->snmpVar( $dd->oiddef('ifHCOutOctets')
                                         . '.' . $ifIndex ) == 0 and
                   $devdetails->snmpVar( $dd->oiddef('ifOutOctets')
                                         . '.' . $ifIndex ) > 0
                   ) ) )
            {
                Debug('Disabling HC octets for ' . $ifIndex . ': ' .
                      $interface->{'ifDescr'});

                $interface->{'hasHCOctets'} = 0;
                $interface->{'hasHCUcastPkts'} = 0;
            }
        }
    }

    if( $devdetails->param('CiscoIOS::disable-membuf-stats') ne 'yes' )
    {
        # Old Memory Buffers, if we have bufferElFree we assume
        # the rest as they are "required"

        $session->get_request( -varbindlist =>
                               [ $dd->oiddef('bufferElFree') ] );
        if( $session->error_status() == 0 )
        {
            $devdetails->setCap('old-ciscoMemoryBuffers');
            push( @{$data->{'templates'}},
                  'CiscoIOS::old-cisco-memory-buffers' );
        }
    }

    if( $devdetails->param('CiscoIOS::disable-ipsec-stats') ne 'yes' )
    {
        $session->get_request( -varbindlist =>
                               [ $dd->oiddef('cipSecGlobalHcInOctets') ] );
        if( $session->error_status() == 0 )
        {
            $devdetails->setCap('ciscoIPSecGlobalStats');
            push( @{$data->{'templates'}},
                  'CiscoIOS::cisco-ipsec-flow-globals' );
        }
        
        if( $dd->oidBaseMatch
            ( 'ciscoLS1010',
              $devdetails->snmpVar( $dd->oiddef('sysObjectID') ) ) )
        {
            $data->{'param'}{'snmp-oids-per-pdu'} = 10;
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
