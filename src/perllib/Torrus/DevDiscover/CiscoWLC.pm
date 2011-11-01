#
#  Copyright (C) 2010  Stanislav Sinyagin
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
# 

# Cisco wireless controller

package Torrus::DevDiscover::CiscoWLC;

use strict;
use warnings;

use Torrus::Log;


$Torrus::DevDiscover::registry{'CiscoWLC'} = {
    'sequence'     => 510,
    'checkdevtype' => \&checkdevtype,
    'discover'     => \&discover,
    'buildConfig'  => \&buildConfig
};


our %oiddef =
    (
     # AIRESPACE-WIRELESS-MIB
     'bsnDot11EssTable'           => '1.3.6.1.4.1.14179.2.1.1',
     'bsnDot11EssSsid'            => '1.3.6.1.4.1.14179.2.1.1.1.2',
     'bsnDot11EssInterfaceName'   => '1.3.6.1.4.1.14179.2.1.1.1.42',
    );


sub checkdevtype
{
    my $dd = shift;
    my $devdetails = shift;

    if( not $devdetails->isDevType('CiscoGeneric') or
        not $dd->checkSnmpTable('bsnDot11EssTable') )
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

    my $session = $dd->session();
    my $data = $devdetails->data();

    $data->{'nameref'}{'ifReferenceName'} = 'ifName';
    $data->{'nameref'}{'ifSubtreeName'} = 'ifNameT';

    my $ssid_oid = $dd->oiddef('bsnDot11EssSsid');
    my $prefixLen = length( $ssid_oid ) + 1;
    
    my $ssidTable = $session->get_table( -baseoid => $ssid_oid );
    if( not defined( $ssidTable ) )
    {
        return 1;
    }

    my $name_oid = $dd->oiddef('bsnDot11EssInterfaceName');
    my $namesTable = $session->get_table( -baseoid => $name_oid );
    if( not defined( $namesTable ) )
    {
        return 1;
    }

    my $filter_ssid = 0;
    my %only_ssid;
    my $only_ssid_list = $devdetails->paramString('CiscoWLC::only-ssid');
    if( $only_ssid_list ne '' )
    {
        $filter_ssid = 1;
        
        foreach my $ssid
            (split(/\s*,\s*/, $only_ssid_list))
        {
            $only_ssid{$ssid} = 1;
        }
    }
             

    while( my( $oid, $ssid ) = each %{$ssidTable} )
    {
        if( $filter_ssid and not $only_ssid{$ssid} )
        {
            next;
        }
        
        my $INDEX = substr( $oid, $prefixLen );
        my $name = $namesTable->{$name_oid . '.' . $INDEX};

        $data->{'CiscoWLC'}{$INDEX} = {'ssid' => $ssid,
                                       'name' => $name};
    }
    
    return 1;
}


sub buildConfig
{
    my $devdetails = shift;
    my $cb = shift;
    my $devNode = shift;
    my $data = $devdetails->data();


    if( defined($data->{'CiscoWLC'}) and
        scalar(keys %{$data->{'CiscoWLC'}}) > 0 )
    {
        my $nodeTop =
            $cb->addSubtree( $devNode, 'Wireless_Clients', undef,
                             [ 'CiscoWLC::ciscowlc-clients-subtree'] );
        
        foreach my $INDEX ( sort {$a <=> $b} keys %{$data->{'CiscoWLC'}} )
        {
            my $ssid = $data->{'CiscoWLC'}{$INDEX}{'ssid'};
            my $name = $data->{'CiscoWLC'}{$INDEX}{'name'};
            my $leafName = $ssid;
            $leafName =~ s/\W/_/go;
            $leafName =~ s/_+/_/go;
            
            $cb->addLeaf( $nodeTop, $leafName,
                          { 'node-display-name'  => $ssid,
                            'ciscowlc-ssid'      => $ssid,
                            'comment'            => $name,
                            'ciscowlc-essindex'  => $INDEX,
                            'precedence'         => 200-$INDEX,
                          },
                          [ 'CiscoWLC::ciscowlc-ess-leaf' ] );
        }
    }
}


1;

# Local Variables:
# mode: perl
# indent-tabs-mode: nil
# perl-indent-level: 4
# End:
