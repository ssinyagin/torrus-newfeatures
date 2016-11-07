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

# Discovery module for BGP4-MIB (RFC 1657)
# This module does not generate any XML, but provides information
# for other discovery modules. For the sake of discovery time and traffic,
# it is not implicitly executed during the normal discovery process.

package Torrus::DevDiscover::RFC1657_BGP4_MIB;

use strict;
use warnings;

use Torrus::Log;


our %oiddef =
    (
     # BGP4-MIB
     'bgpPeerRemoteAs'       => '1.3.6.1.2.1.15.3.1.9',
     );




sub discover
{
    my $dd = shift;
    my $devdetails = shift;

    my $data = $devdetails->data();
    my $session = $dd->session();

    my $table = $dd->walkSnmpTable('bgpPeerRemoteAs');
    
    if( scalar(keys %{$table}) > 0 )
    {
        $devdetails->setCap('bgpPeerTable');

        while( my ($ipAddr, $asNum) = each %{$table} )
        {
            $data->{'bgpPeerAS'}{$ipAddr} = $asNum;
        }
    }
                            
    return 1;
}



1;


# Local Variables:
# mode: perl
# indent-tabs-mode: nil
# perl-indent-level: 4
# End:
