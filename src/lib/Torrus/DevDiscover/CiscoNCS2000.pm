#  Copyright (C) 2020 Stanislav Sinyagin
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

# Cisco NCS 2000 platform (ex-Cerent)

package Torrus::DevDiscover::CiscoNCS2000;

use strict;
use warnings;

use Torrus::Log;


$Torrus::DevDiscover::registry{'CiscoNCS2000'} = {
    'sequence'     => 500,
    'checkdevtype' => \&checkdevtype,
    'discover'     => \&discover,
    'buildConfig'  => \&buildConfig
    };


our %oiddef =
    (
     'cerent'     => '1.3.6.1.4.1.3607',
     );


sub checkdevtype
{
    my $dd = shift;
    my $devdetails = shift;

    if( not $dd->oidBaseMatch
        ( 'cerent',
          $devdetails->snmpVar( $dd->oiddef('sysObjectID') ) ) )
    {
        return 0;
    }
    
    $devdetails->setCap('interfaceIndexingPersistent');
        
    return 1;
}


sub discover
{
    my $dd = shift;
    my $devdetails = shift;

    my $data = $devdetails->data();
    my $session = $dd->session();
            
    $data->{'param'}{'snmp-oids-per-pdu'} = 10;
    $data->{'nameref'}{'ifSubtreeName'} = 'ifDescrT';
    $data->{'nameref'}{'ifReferenceName'} = 'ifName';
    $data->{'nameref'}{'ifNick'} = 'ifName';
    $data->{'nameref'}{'ifNodeid'} = 'ifName';
    $data->{'nameref'}{'ifComment'} = 'ifDescr';
    
    foreach my $ifIndex ( keys %{$data->{'interfaces'}})
    {
        my $interface = $data->{'interfaces'}{$ifIndex};
        next if $interface->{'excluded'};

        # Only xGigabitEthernet interafces are of interest
        
        if( $interface->{'ifDescr'} !~ /GigabitEthernet/ )
        {
            $interface->{'excluded'} = 1;
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
