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

# C-COM CAPSPAN devices
# We only set the fixed ifIndex mapping

package Torrus::DevDiscover::CCOM;

use strict;
use Torrus::Log;


$Torrus::DevDiscover::registry{'CCOM'} = {
    'sequence'     => 500,
    'checkdevtype' => \&checkdevtype,
    'discover'     => \&discover,
    'buildConfig'  => \&buildConfig
    };


our %oiddef =
    (
     'ccomProducts'     => '1.3.6.1.4.1.3278.1',
     );


sub checkdevtype
{
    my $dd = shift;
    my $devdetails = shift;

    if( not $dd->oidBaseMatch
        ( 'ccomProducts',
          $devdetails->snmpVar( $dd->oiddef('sysObjectID') ) ) )
    {
        return 0;
    }
    
    $devdetails->setCap('interfaceIndexingPersistent');
    $devdetails->setCap('disable_ifXTable');
    
    return 1;
}


sub discover
{
    my $dd = shift;
    my $devdetails = shift;

    my $data = $devdetails->data();
    my $session = $dd->session();

    # for some devices, ifDescr is poisoned with non-ASSCII characters.
    # clean that up to get some meaningful names
    
    foreach my $ifIndex ( keys %{$data->{'interfaces'}} )
    {
        my $interface = $data->{'interfaces'}{$ifIndex};
        
        next if $interface->{'excluded'};

        my $descr = $interface->{'ifDescr'};
        if( $descr =~ /^0x/ )
        {
            $descr =~ s/^0x//;
            $descr = pack('H*', $descr);
            $descr =~ /^([0-9a-zA-Z \/]+)/ and $descr = $1;
        }

        $interface->{'CCOM-ifDescr'} = $descr;
        $descr =~ s/\W/_/g;
        $interface->{'CCOM-ifDescrT'} = $descr;
    }
            
    $data->{'nameref'}{'ifSubtreeName'} = 'CCOM-ifDescrT';
    $data->{'nameref'}{'ifReferenceName'} = 'CCOM-ifDescr';
    $data->{'nameref'}{'ifNick'} = 'ifIndex';
    $data->{'nameref'}{'ifNodeid'} = 'ifIndex';

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
