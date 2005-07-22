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

# Cisco IOS MAC accounting

package Torrus::DevDiscover::CiscoIOS_MacAccounting;

use strict;
use Torrus::Log;


$Torrus::DevDiscover::registry{'CiscoIOS_MacAccounting'} = {
    'sequence'     => 510,
    'checkdevtype' => \&checkdevtype,
    'discover'     => \&discover,
    'buildConfig'  => \&buildConfig
    };


our %oiddef =
    (
     # CISCO-IP-STAT-MIB
     'cipMacHCSwitchedBytes'        => '1.3.6.1.4.1.9.9.84.1.2.3.1.2',
     
     );


sub checkdevtype
{
    my $dd = shift;
    my $devdetails = shift;

    my $session = $dd->session();

    if( $devdetails->isDevType('CiscoIOS') and
        $dd->checkSnmpTable('cipMacHCSwitchedBytes') )
    {
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

    my $table = $session->get_table( -baseoid =>
                                     $dd->oiddef('cipMacHCSwitchedBytes'));
    
    if( not defined( $table ) or scalar( %{$table} ) == 0 )
    {
        return 0;
    }
    $devdetails->storeSnmpVars( $table );

    Torrus::DevDiscover::RFC2011_IP_MIB::discover($dd, $devdetails);
    Torrus::DevDiscover::RFC1657_BGP4_MIB::discover($dd, $devdetails);
    
    foreach my $INDEX
        ( $devdetails->
          getSnmpIndices( $dd->oiddef('cipMacHCSwitchedBytes') ) )
    {
        my( $ifIndex, $direction, @phyAddrOctets ) = split( '\.', $INDEX );

        my $interface = $data->{'interfaces'}{$ifIndex};
        next if not defined( $interface );

        my $phyAddr = '0x';
        my $macAddrString = '';
        foreach my $byte ( @phyAddrOctets )
        {
            $phyAddr .= sprintf('%.2x', $byte);
            if( length( $macAddrString ) > 0 )
            {
                $macAddrString .= ':';
            }
            $macAddrString .= sprintf('%.2x', $byte);
        }

        next if ( $phyAddr eq '0xffffffffffff' );
        
        my $peerIP = $interface->{'mediaToIpNet'}{$phyAddr};
        if( not defined( $peerIP ) )
        {
            # high logging level, because who cares about staled entries?
            Debug('Cannot determine IP address for MAC accounting ' .
                  'entry: ' . $macAddrString);            
            next;
        }

        # There should be two entries per IP: in and out.
        if( defined( $data->{'cipMac'}{$ifIndex . ':' . $phyAddr} ) )
        {
            $data->{'cipMac'}{$ifIndex . ':' . $phyAddr}{'nEntries'}++;
            next;
        }
        
        my $peer = {
            'peerIP' => $peerIP,
            'phyAddr' => $phyAddr,
            'macAddrString' => $macAddrString,
            'ifIndex' => $ifIndex,
            'nEntries' => 1
        };

        $peer->{'macAddrOID'} = join('.', @phyAddrOctets);

        $peer->{'ifReferenceName'} =
            $interface->{$data->{'nameref'}{'ifReferenceName'}};
        $peer->{'ifNick'} =
            $interface->{$data->{'nameref'}{'ifNick'}};
        
        my $desc =
            $devdetails->param('peer-ipaddr-description-' .
                               join('_', split('\.', $peerIP)));
        if( length( $desc ) > 0 )
        {
            $peer->{'description'} = $desc;
        }        
        
        if( $devdetails->hasCap('bgpPeerTable') )
        {
            my $peerAS = $data->{'bgpPeerAS'}{$peerIP};
            if( defined( $peerAS ) )
            {
                $peer->{'peerAS'} = $data->{'bgpPeerAS'}{$peerIP};
                
                my $desc =
                    $devdetails->param('bgp-as-description-' . $peerAS);
                if( length( $desc ) > 0 )
                {
                    if( defined( $peer->{'description'} ) )
                    {
                        Warn('Conflicting descriptions for peer ' .
                             $peerIP);
                    }
                    $peer->{'description'} = $desc;
                }
            }
            elsif( $devdetails->
                    param('CiscoIOS_MacAccounting::bgponly') eq 'yes' )
            {
                next;
            }
        }

        $data->{'cipMac'}{$ifIndex . ':' . $phyAddr} = $peer;
    }

    my %asNumbers;    
    foreach my $INDEX ( keys %{$data->{'cipMac'}} )
    {        
        my $peer = $data->{'cipMac'}{$INDEX};

        if( $peer->{'nEntries'} != 2 )
        {
            delete $data->{'cipMac'}{$INDEX};
        }
        else
        {
            if( defined( $peer->{'peerAS'} ) )
            {
                $asNumbers{$peer->{'peerAS'}}++;
            }
        }
    }
    
    foreach my $INDEX ( keys %{$data->{'cipMac'}} )
    {
        my $peer = $data->{'cipMac'}{$INDEX};
        
        my $subtreeName = $peer->{'peerIP'};
        my $asNum = $peer->{'peerAS'};
        if( defined( $asNum ) )
        {
            $subtreeName = 'AS' . $asNum; 
            if( $asNumbers{$asNum} > 1 )
            {
                $subtreeName .= '_' . $peer->{'peerIP'};
            }
        }
        $peer->{'subtreeName'} = $subtreeName;
    }
    
    return 1;
}


sub buildConfig
{
    my $devdetails = shift;
    my $cb = shift;
    my $devNode = shift;

    my $data = $devdetails->data();

    my $countersNode =
        $cb->addSubtree( $devNode, 'MAC_Accounting',
                         { 'comment' => 'MAC accounting statistics'},
                         ['CiscoIOS_MacAccounting::cisco-macacc-subtree']);
    
    foreach my $INDEX ( sort { $data->{'cipMac'}{$a}{'subtreeName'} <=>
                                   $data->{'cipMac'}{$b}{'subtreeName'} }
                        keys %{$data->{'cipMac'}} )
    {
        my $peer = $data->{'cipMac'}{$INDEX};
    
        my $param = {
            'peer-macaddr'         => $peer->{'phyAddr'},
            'peer-macoid'          => $peer->{'macAddrOID'},
            'interface-name'       => $peer->{'ifReferenceName'},
            'interface-nick'       => $peer->{'ifNick'},
            'comment'              => $peer->{'description'},
            'descriptive-nickname' => $peer->{'subtreeName'}
            };

        $cb->addSubtree( $countersNode, $peer->{'subtreeName'}, $param,
                         ['CiscoIOS_MacAccounting::cisco-macacc'] );
    }
}



1;


# Local Variables:
# mode: perl
# indent-tabs-mode: nil
# perl-indent-level: 4
# End:
