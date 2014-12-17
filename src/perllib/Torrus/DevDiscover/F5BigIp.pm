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
use Digest::MD5 qw(md5_hex);

use Torrus::Log;


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
     'f5_sysGlobalHostMemTotal'        => '1.3.6.1.4.1.3375.2.1.1.2.20.2.0',
     'f5_sysMultiHostHostId'           => '1.3.6.1.4.1.3375.2.1.7.4.2.1.1',
     'f5_sysMultiHostTotal'            => '1.3.6.1.4.1.3375.2.1.7.4.2.1.2',
     'f5_sysMultiHostCpuId'            => '1.3.6.1.4.1.3375.2.1.7.5.2.1.3',

     # F5-BIGIP-LOCAL-MIB -- LTM stats
     'ltmNodeAddrNumber'         => '1.3.6.1.4.1.3375.2.2.4.1.1.0',
     'ltmNodeAddrStatNodeName'   => '1.3.6.1.4.1.3375.2.2.4.2.3.1.20',
     'ltmPoolNumber'             => '1.3.6.1.4.1.3375.2.2.5.1.1.0',
     'ltmPoolStatName'           => '1.3.6.1.4.1.3375.2.2.5.2.3.1.1',
     'ltmPoolMemberStatPoolName' => '1.3.6.1.4.1.3375.2.2.5.4.3.1.1',
     'ltmPoolMemberStatNodeName' => '1.3.6.1.4.1.3375.2.2.5.4.3.1.28',
     'ltmPoolMemberStatPort'     => '1.3.6.1.4.1.3375.2.2.5.4.3.1.4',
     'ltmVirtualServNumber'      => '1.3.6.1.4.1.3375.2.2.10.1.1.0',
     'ltmVirtualServStatName'    => '1.3.6.1.4.1.3375.2.2.10.2.3.1.1',
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


my %ltm_category_templates =
    (
     'Nodes' => ['F5BigIp::ltm-node-statistics',
                 'F5BigIp::f5-object-statistics'],
     'Pools' => ['F5BigIp::ltm-pool-statistics',
                 'F5BigIp::f5-object-statistics'],
     'VServers' => ['F5BigIp::ltm-vserver-statistics',
                    'F5BigIp::f5-object-statistics'],
    );

my %ltm_category_comment =
    (
     'Nodes' => 'Per-node statistics',
     'Pools' => 'Pool statistics',
     'VServers' => 'Virtual server statistics',
    );

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

    my $old_maxrepetitions = $dd->{'maxrepetitions'};
    $dd->{'maxrepetitions'} = 3;
    
    # Common system information
    {
        my $result = $dd->retrieveSnmpOIDs(@f5_sys_oidlist);
        if( defined($result) )
        {
        
            my $sysref = {};
            foreach my $oidname ( @f5_sys_oidlist )
            {
                my $val = $result->{$oidname};
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

        $result = $dd->retrieveSnmpOIDs('f5_sysGlobalHostMemTotal');
        if( defined($result) and $result->{'f5_sysGlobalHostMemTotal'} > 0 )
        {
            $data->{'param'}{'f5-global-host-memtotal'} =
                $result->{'f5_sysGlobalHostMemTotal'};
            push( @{$data->{'templates'}}, 'F5BigIp::f5-global-host' );
        }

        if( $devdetails->paramEnabled('F5BigIp::multi-host-stats') )
        {
            my $hostID = $dd->walkSnmpTable('f5_sysMultiHostHostId');
            my $hostMem = $dd->walkSnmpTable('f5_sysMultiHostTotal');
            while( my( $hINDEX, $memsize ) = each %{$hostMem} )
            {
                $data->{'f5_host'}{$hINDEX}{'memtotal'} = $memsize;
                $data->{'f5_host'}{$hINDEX}{'hostid'} = $hostID->{$hINDEX};
            }
            
            foreach my $hINDEX (keys %{$data->{'f5_host'}})
            {
                my $cpus = $dd->walkSnmpTable('f5_sysMultiHostCpuId');
                while( my( $cINDEX, $id ) = each %{$cpus} )
                {
                    $cINDEX = substr($cINDEX, length($hINDEX)+1);
                    $data->{'f5_host'}{$hINDEX}{'cpu'}{$cINDEX} = $id;
                }
            }
        }
    }

    # Check LTM capabilities
    {
        my $result = $dd->retrieveSnmpOIDs(
            'ltmNodeAddrNumber', 'ltmPoolNumber', 'ltmVirtualServNumber');
                
        if( defined($result->{'ltmNodeAddrNumber'}) and
            $result->{'ltmNodeAddrNumber'} > 0 )
        {
            $devdetails->setCap('F5_LTM_Nodes');
        }
        
        if( defined($result->{'ltmPoolNumber'}) and
            $result->{'ltmPoolNumber'} > 0 )
        {
            $devdetails->setCap('F5_LTM_Pools');
        }
        
        if( defined($result->{'ltmVirtualServNumber'}) and
            $result->{'ltmVirtualServNumber'} > 0 )
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
                    'f5-object-fullname' => $fullname,
                    'f5-object-nameidx' => $INDEX,
                    'f5-object-shortname' => $node,
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
                # the full name may consist of 3 parts if it's generated
                # by application template. We drop the middle part
                # (template name)
                my $pool = $2;
                if( $pool =~ /^[^\/]+\/(.+)$/ )
                {
                    $pool = $1;
                }
                
                $data->{'ltm'}{$partition}{'Pools'}{$pool} = {
                    'f5-object-fullname' => $fullname,
                    'f5-object-nameidx' => $INDEX,
                    'f5-object-shortname' => $pool,
                };
            }
        }

        # Get the pool members
        my $poolnames = $dd->walkSnmpTable('ltmPoolMemberStatPoolName');
        my $nodenames = $dd->walkSnmpTable('ltmPoolMemberStatNodeName');
        my $ports = $dd->walkSnmpTable('ltmPoolMemberStatPort');
        
        while( my( $INDEX, $poolname ) = each %{$poolnames} )
        {
            if( $poolname !~ /^\/([^\/]+)\/(.+)$/o )
            {
                next;
            }            
            my $partition = $1;
            # the full name may consist of 3 parts if it's generated
            # by application template. We drop the middle part
            # (template name)
            my $pool = $2;
            if( $pool =~ /^[^\/]+\/(.+)$/ )
            {
                $pool = $1;
            }

            my $nodename = $nodenames->{$INDEX};
            # Node name consists of /Partition/Name
            if( $nodename !~ /^\/([^\/]+)\/(.+)$/o )
            {
                next;
            }
            my $node = $2;

            my $port = $ports->{$INDEX};
            next unless (defined($port) and $port > 0 );

            $data->{'ltm_poolmembers'}{$partition}{$pool}{$node}{$port} = {
                'f5-object-fullname' => join(':', $partition,
                                             $pool,$node,$port),
                'f5-object-nameidx' => $INDEX,
                'f5-object-shortname' => $node . ':' . $port,
            };
            
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
                # the full name may consist of 3 parts if it's generated
                # by application template. We drop the middle part
                # (template name)
                my $srv = $2;
                if( $srv =~ /^[^\/]+\/(.+)$/ )
                {
                    $srv = $1;
                }
                
                $data->{'ltm'}{$partition}{'VServers'}{$srv} = {
                    'f5-object-fullname' => $fullname,
                    'f5-object-nameidx' => $INDEX,
                    'f5-object-shortname' => $srv,
                };
            }
        }
    }

    $dd->{'maxrepetitions'} = $old_maxrepetitions;
    
    return 1;
}


sub buildConfig
{
    my $devdetails = shift;
    my $cb = shift;
    my $devNode = shift;

    my $data = $devdetails->data();

    if( defined($data->{'f5_host'}) )
    {
        foreach my $hINDEX (keys %{$data->{'f5_host'}})
        {
            my $hostSubtree = 'Host ' . $data->{'f5_host'}{$hINDEX}{'hostid'};
            
            my $params = {
                'node-display-name' =>$hostSubtree,
                'comment' => 'BigIP host',
                'f5-host-index' => $hINDEX,
                'f5-host-memtotal' => $data->{'f5_host'}{$hINDEX}{'memtotal'},
            };
                
            $hostSubtree =~ s/\W/_/g;
            my $hostNode = $cb->addSubtree
                ( $devNode, $hostSubtree, $params,
                  ['F5BigIp::f5-multihost-host']);
            
            my $cpusNode = $cb->addSubtree
                ( $hostNode, 'CPU', {}, ['F5BigIp::f5-multihost-cpu-subtree']);

            foreach my $cINDEX (sort {$a<=>$b} keys
                                %{$data->{'f5_host'}{$hINDEX}{'cpu'}})
            {
                my $id = $data->{'f5_host'}{$hINDEX}{'cpu'}{$cINDEX};
                my $params = {
                    'f5-cpu-index' => $cINDEX,
                    'f5-cpu-id' => $id,
                };

                $cb->addSubtree
                    ( $cpusNode, $id, $params, ['F5BigIp::f5-multihost-cpu']);
                
            }
        }
    }
    
    my $p_precedence = 10000;
    
    foreach my $partition (sort keys %{$data->{'ltm'}})
    {
        $p_precedence--;
        
        my $partParams = {
            'node-display-name' => $partition,
            'precedence' => $p_precedence,
            'comment' => 'BigIP partition',
        };

        my $partSubtree = $partition;
        $partSubtree =~ s/\W+/_/g;
        
        my $partitionNode =
            $cb->addSubtree( $devNode, $partSubtree, $partParams );

        foreach my $category (sort keys %{$data->{'ltm'}{$partition}})
        {
            my $catParams = {
                'comment' => $ltm_category_comment{$category},
            };
            
            my $categoryNode =
                $cb->addSubtree( $partitionNode, $category, $catParams,
                                 ['F5BigIp::f5-category-subtree'] );
            
            foreach my $object
                (sort keys %{$data->{'ltm'}{$partition}{$category}})
            {
                my $objParam = {
                    'node-display-name' => $object,
                };

                my $ref = $data->{'ltm'}{$partition}{$category}{$object};
                while( my($p, $v) = each %{$ref} )
                {
                    $objParam->{$p} = $v;
                }

                $objParam->{'f5-object-md5'} =
                    md5_hex($objParam->{'f5-object-fullname'});
                
                my $objSubtree = $object;
                $objSubtree =~ s/\W/_/g;
                $cb->addSubtree( $categoryNode, $objSubtree, $objParam,
                                 $ltm_category_templates{$category});
            }
        }

        # Pool members
        if( defined($data->{'ltm_poolmembers'}{$partition}) and
            scalar(keys %{$data->{'ltm_poolmembers'}{$partition}}) > 0 )
        {
            my $m_precedence = 1000;
            
            my $membersNode =
                $cb->addSubtree( $partitionNode, 'Pool_Members',
                                 {
                                     'node-display-name' => 'Pool Members',
                                     'comment' => 'Pool member statistics',
                                 } );
            foreach my $pool
                (sort keys %{$data->{'ltm_poolmembers'}{$partition}})
            {
                my $ref1 = $data->{'ltm_poolmembers'}{$partition}{$pool};

                my $poolSubtree = $pool;
                $poolSubtree =~ s/\W/_/g;

                my $poolNode =
                    $cb->addSubtree( $membersNode, $poolSubtree,
                                     {
                                         'node-display-name' => $pool,
                                     },
                                     ['F5BigIp::f5-category-subtree'] );
                
                foreach my $node (sort keys %{$ref1})
                {
                    foreach my $port (sort {$a <=> $b} keys %{$ref1->{$node}})
                    {
                        $m_precedence--;
                        my $objParam = {
                            'node-display-name' => $node . ':' . $port,
                            'precedence' => $m_precedence,
                        };
                        
                        my $ref = $ref1->{$node}{$port};
                        while( my($p, $v) = each %{$ref} )
                        {
                            $objParam->{$p} = $v;
                        }

                        $objParam->{'f5-object-md5'} =
                            md5_hex($objParam->{'f5-object-fullname'});
                
                        my $objSubtree = $node . ':' . $port;
                        $objSubtree =~ s/\W/_/g;
                        $cb->addSubtree( $poolNode, $objSubtree, $objParam,
                                         ['F5BigIp::ltm-poolmember-statistics',
                                          'F5BigIp::f5-object-statistics']);
                    }
                }
            }
        }            
    }
    
    return;
}



1;


# Local Variables:
# mode: perl
# indent-tabs-mode: nil
# perl-indent-level: 4
# End:
