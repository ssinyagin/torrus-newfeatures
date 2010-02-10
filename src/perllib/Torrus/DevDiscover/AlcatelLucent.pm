#
#  Discovery module for Alcatel-Lucent devices
#
#  Copyright (C) 2009 Stanislav Sinyagin
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
#

# Currently tested with following Alcatel-Lucent devices:
#  * ESS 7450


package Torrus::DevDiscover::AlcatelLucent;

use strict;
use Torrus::Log;


$Torrus::DevDiscover::registry{'AlcatelLucent'} = {
    'sequence'     => 500,
    'checkdevtype' => \&checkdevtype,
    'discover'     => \&discover,
    'buildConfig'  => \&buildConfig
    };



our %oiddef =
    (
     'pantheranetworks'          => '1.3.6.1.4.1.6527',
     'alcatellucent'             => '1.3.6.1.4.1.637',
     'ess7450'                   => '1.3.6.1.4.1.6527.1.6.1',
     );


my %essInterfaceFilter =
    (
     'system'  => {
         'ifType'  => 24,                     # softwareLoopback
         'ifName' => '^system'
         },
     );



sub checkdevtype
{
    my $dd = shift;
    my $devdetails = shift;

    my $objectID = $devdetails->snmpVar( $dd->oiddef('sysObjectID') );
    
    if( $dd->oidBaseMatch( 'pantheranetworks', $objectID ) )
    {
        if( $dd->oidBaseMatch( 'ess7450', $objectID ) )
        {
            $devdetails->setCap('AlcatelLucent_ESS7450');

            $devdetails->setCap('interfaceIndexingManaged');
            $devdetails->setCap('interfaceIndexingPersistent');
            
            &Torrus::DevDiscover::RFC2863_IF_MIB::addInterfaceFilter
                ($devdetails, \%essInterfaceFilter);
        }
        return 1;
    }
    elsif( $dd->oidBaseMatch( 'alcatellucent', $objectID ) )
    {
        # placeholder for future developments
        Warn('This model of Alcatel-Lucent equipment is not yet supported');
        return 1;
    }
    
    return 0;
}




sub discover
{
    my $dd = shift;
    my $devdetails = shift;

    my $session = $dd->session();
    my $data = $devdetails->data();

    if( $devdetails->hasCap('AlcatelLucent_ESS7450') )
    {
        # Amend RFC2863_IF_MIB references
        $data->{'nameref'}{'ifSubtreeName'}    = 'ifNameT';
        $data->{'nameref'}{'ifReferenceName'}  = 'ifName';
        $data->{'nameref'}{'ifNick'} = 'ifNameT';
        $data->{'nameref'}{'ifComment'} = 'ifDescr';

        if( $devdetails->param('AlcatelLucent::full-ifdescr') ne 'yes' )
        { 
            $data->{'nameref'}{'ifComment'} = 'ifStrippedDescr';

            foreach my $ifIndex ( keys %{$data->{'interfaces'}} )
            {
                my $interface = $data->{'interfaces'}{$ifIndex};
                my $descr = $interface->{'ifDescr'};

                # in 7450, ifdescr is 3 comma-separated values:
                # STRING: 1/1/1, 10/100/Gig Ethernet SFP, "COMMENT"
                # Strip everything except the actual comment.
                
                if( $descr =~ /\"(.+)\"/ )
                {
                    $descr = $1;
                }

                $interface->{'ifStrippedDescr'} = $descr;
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
    my $data = $devdetails->data();

}

1;

# Local Variables:
# mode: perl
# indent-tabs-mode: nil
# perl-indent-level: 4
# End:
