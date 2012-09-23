#  Copyright (C) 2012 Stanislav Sinyagin
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

# F5 BIG-IP versions 10.x and higher
# Tested with LTM version 11.0

package Torrus::DevDiscover::F5BigIp;

use strict;
use warnings;

use Torrus::Log;

use Data::Dumper;

$Torrus::DevDiscover::registry{'F5BigIp'} = {
    'sequence'     => 500,
    'checkdevtype' => \&checkdevtype,
    'discover'     => \&discover,
    'buildConfig'  => \&buildConfig
    };


our %oiddef =
    (
     # F5-BIGIP-COMMON-MIB
     'f5_bigipTrafficMgmt'             => '1.3.6.1.4.1.3375.2',
     
     # F5-BIGIP-SYSTEM-MIB
     'f5_sysPlatformInfoMarketingName' => '1.3.6.1.4.1.3375.2.1.3.5.2.0',
     'f5_sysProductVersion'            => '1.3.6.1.4.1.3375.2.1.4.2.0',
     'f5_sysProductBuild'              => '1.3.6.1.4.1.3375.2.1.4.3.0',

     # F5-BIGIP-LOCAL-MIB -- LTM stats
     'ltmNodeAddrNumber'        => '1.3.6.1.4.1.3375.2.2.4.1.1.0',
     'ltmNodeAddrStatNodeName'  => '1.3.6.1.4.1.3375.2.2.4.2.3.1.20',
     'ltmPoolNumber'            => '1.3.6.1.4.1.3375.2.2.5.1.1.0',
     'ltmPoolStatName'          => '1.3.6.1.4.1.3375.2.2.5.2.3.1.1',
     'ltmVirtualServNumber'     => '1.3.6.1.4.1.3375.2.2.10.1.1.0',
     'ltmVirtualServStatName'   => '1.3.6.1.4.1.3375.2.2.10.2.3.1.1',
     );


my @f5_sys_oidlist = (
    'f5_sysPlatformInfoMarketingName',
    'f5_sysProductVersion',
    'f5_sysProductBuild',
    );


my $f5InterfaceFilter = {
    'LOOPBACK' => {
        'ifType'  => 24,                     # softwareLoopback
    },
};


sub checkdevtype
{
    my $dd = shift;
    my $devdetails = shift;

    if( not $dd->oidBaseMatch
        ( 'f5_bigipTrafficMgmt',
          $devdetails->snmpVar( $dd->oiddef('sysObjectID') ) ) )
    {
        return 0;
    }
    
    $devdetails->setCap('interfaceIndexingPersistent');

    &Torrus::DevDiscover::RFC2863_IF_MIB::addInterfaceFilter
        ($devdetails, $f5InterfaceFilter);
    
    return 1;
}


sub discover
{
    my $dd = shift;
    my $devdetails = shift;

    my $data = $devdetails->data();
    my $session = $dd->session();

    $data->{'param'}{'snmp-oids-per-pdu'} = 10;
    
    # Common system information
    {
        my @oids;
        foreach my $oidname ( @f5_sys_oidlist )
        {
            push( @oids, $dd->oiddef($oidname) );
        }
        
        my $result = $session->get_request( -varbindlist => \@oids );
        
        my $sysref = {};
        foreach my $oidname ( @f5_sys_oidlist )
        {
            my $oid = $dd->oiddef($oidname);
            my $val = $result->{$oid};
            if( defined($val) and length($val) > 0 )
            {
                $sysref->{$oidname} = $val;
            }
            else
            {
                $sysref->{$oidname} = 'N/A';
            }
        }
        
        $data->{'param'}{'comment'} =
            $sysref->{'f5_sysPlatformInfoMarketingName'} .
            ', Version ' .
            $sysref->{'f5_sysProductVersion'} .
            ', Build ' .
            $sysref->{'f5_sysProductBuild'};
    }

    # Check LTM capabilities
    {
        my $oid_nodes = $dd->oiddef('ltmNodeAddrNumber');
        my $oid_pools = $dd->oiddef('ltmPoolNumber');
        my $oid_vservers = $dd->oiddef('ltmVirtualServNumber');
        
        my $result = $session->get_request
            ( -varbindlist => [$oid_nodes, $oid_pools, $oid_vservers] );
        
        if( defined($result->{$oid_nodes}) and $result->{$oid_nodes} > 0 )
        {
            $devdetails->setCap('F5_LTM_Nodes');
        }
        
        if( defined($result->{$oid_pools}) and $result->{$oid_pools} > 0 )
        {
            $devdetails->setCap('F5_LTM_Pools');
        }
        
        if( defined($result->{$oid_vservers}) and $result->{$oid_vservers} > 0 )
        {
            $devdetails->setCap('F5_LTM_VServers');
        }
    }

    $data->{'ltm'} = {};
    
    if( $devdetails->hasCap('F5_LTM_Nodes') )
    {
        my $names = $dd->walkSnmpTable('ltmNodeAddrStatNodeName');
        while( my( $INDEX, $fullname ) = each %{$names} )
        {
            if( $fullname =~ /^\/([^\/]+)\/(.+)$/o )
            {
                my $partition = $1;
                my $node = $2;
                
                $data->{'ltm'}{$partition}{'Nodes'}{$node} = {
                    'fullname' => $fullname,
                    'nameidx' => $INDEX,
                };
            }
        }
    }
        
    if( $devdetails->hasCap('F5_LTM_Pools') )
    {
        my $names = $dd->walkSnmpTable('ltmPoolStatName');
        while( my( $INDEX, $fullname ) = each %{$names} )
        {
            if( $fullname =~ /^\/([^\/]+)\/(.+)$/o )
            {
                my $partition = $1;
                my $pool = $2;
                
                $data->{'ltm'}{$partition}{'Pools'}{$pool} = {
                    'fullname' => $fullname,
                    'nameidx' => $INDEX,
                };
            }
        }
    }

    if( $devdetails->hasCap('F5_LTM_VServers') )
    {
        my $names = $dd->walkSnmpTable('ltmVirtualServStatName');
        while( my( $INDEX, $fullname ) = each %{$names} )
        {
            if( $fullname =~ /^\/([^\/]+)\/(.+)$/o )
            {
                my $partition = $1;
                my $srv = $2;
                
                $data->{'ltm'}{$partition}{'Servers'}{$srv} = {
                    'fullname' => $fullname,
                    'nameidx' => $INDEX,
                };
            }
        }
    }

    print STDERR Dumper($data->{'ltm'});
    
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
