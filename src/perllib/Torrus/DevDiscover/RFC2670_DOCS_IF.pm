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

# DOCSIS interface statistics

package Torrus::DevDiscover::RFC2670_DOCS_IF;

use strict;
use Torrus::Log;


$Torrus::DevDiscover::registry{'RFC2670_DOCS_IF'} = {
    'sequence'     => 100,
    'checkdevtype' => \&checkdevtype,
    'discover'     => \&discover,
    'buildConfig'  => \&buildConfig
    };


our %oiddef =
    (
     # DOCS-IF-MIB::docsIfDownstreamChannelTable
     'docsIfDownstreamChannelTable' => '1.3.6.1.2.1.10.127.1.1.1',
     );



sub checkdevtype
{
    my $dd = shift;
    my $devdetails = shift;

    my $session = $dd->session();
    my $data = $devdetails->data();

    if( $dd->checkSnmpTable( 'docsIfDownstreamChannelTable' ) )
    {
        return 1;
    }

    return 0;
}


sub discover
{
    my $dd = shift;
    my $devdetails = shift;

    my $data = $devdetails->data();

    $data->{'docsCableMaclayer'} = [];
    $data->{'docsCableDownstream'} = [];
    $data->{'docsCableUpstream'} = [];

    foreach my $ifIndex ( sort {$a<=>$b} keys %{$data->{'interfaces'}} )
    {
        my $ifType = $interface->{'ifType'};
        if( $ifType == 127 )
        {
            push( @{$data->{'docsCableMaclayer'}}, $ifIndex );
        }
        elsif(  $ifType == 128 )
        {
            push( @{$data->{'docsCableDownstream'}}, $ifIndex );
        }
        elsif(  $ifType == 129 )
        {
            push( @{$data->{'docsCableUpstream'}}, $ifIndex );
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

    # Build Docsis_Signal_Quality subtree

    my $subtreeNode =
        $cb->addSubtree( $devNode, 'Docsis_Signal_Quality', {},
                         ['RFC2670_DOCS_IF::docsis-signal-quality-subtree'] );

    foreach my $ifIndex ( @{$data->{'docsCableUpstream'}} )
    {
        my $interface = $data->{'interfaces'}{$ifIndex};

        my $param = {
            'interface-name' => $interface->{'param'}{'interface-name'},
            'interface-nick' => $interface->{'param'}{'interface-nick'},
            'comment'        => $interface->{'param'}{'comment'}
        };

        $cb->addSubtree
            ( $subtreeNode, $interface->{$data->{'nameref'}{'ifSubtreeName'}},
              $param, ['RFC2670_DOCS_IF::docsis-interface-signal-quality'] );
    }
}


1;


# Local Variables:
# mode: perl
# indent-tabs-mode: nil
# perl-indent-level: 4
# End:
