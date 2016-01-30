#  Copyright (C) 2005  Stanislav Sinyagin
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

# Stanislav Sinyagin <ssinyagin@k-open.com>

# Discovery module for IP-MIB (RFC 2011) This module does not generate
# any XML, but provides information for other discovery modules. For the
# sake of discovery time and traffic, it is not implicitly executed
# during the normal discovery process. The module queries
# ipNetToMediaTable which is deprecated, but still supported in newer
# RFC4293. Some Cisco routers still use the old table anyway.

package Torrus::DevDiscover::RFC2011_IP_MIB;

use strict;
use warnings;

use Torrus::Log;


our %oiddef =
    (
     # IP-MIB
     'ipNetToMediaTable'       => '1.3.6.1.2.1.4.22',
     'ipNetToMediaPhysAddress' => '1.3.6.1.2.1.4.22.1.2',
     );




sub discover
{
    my $dd = shift;
    my $devdetails = shift;

    my $data = $devdetails->data();
    my $session = $dd->session();

    my $map = $dd->walkSnmpTable('ipNetToMediaPhysAddress');
        
    if( not defined($map) or scalar(keys %{$map}) == 0 )
    {
        return 0;
    }
    
    foreach my $INDEX (keys %{$map})
    {
        my( $ifIndex, @ipAddrOctets ) = split( '\.', $INDEX );
        my $ipAddr = join('.', @ipAddrOctets);

        my $interface = $data->{'interfaces'}{$ifIndex};
        next if not defined( $interface );

        my $phyAddr = $map->{$INDEX};

        $interface->{'ipNetToMedia'}{$ipAddr} = $phyAddr;
        $interface->{'mediaToIpNet'}{$phyAddr} = $ipAddr;

        # Cisco routers assign ARP to subinterfaces, but MAC accounting
        # to main interfaces. Let them search in a global table
        $data->{'ipNetToMedia'}{$ipAddr} = $phyAddr;
        $data->{'mediaToIpNet'}{$phyAddr} = $ipAddr;
    }
                            
    return 1;
}



1;


# Local Variables:
# mode: perl
# indent-tabs-mode: nil
# perl-indent-level: 4
# End:
