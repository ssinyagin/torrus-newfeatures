#  Copyright (C) 2014 Stanislav Sinyagin
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

# Fortinet products

package Torrus::DevDiscover::Fortinet;

use strict;
use warnings;

use Torrus::Log;


$Torrus::DevDiscover::registry{'Fortinet'} = {
    'sequence'     => 500,
    'checkdevtype' => \&checkdevtype,
    'discover'     => \&discover,
    'buildConfig'  => \&buildConfig
    };


our %oiddef =
    (
     # FORTINET-FORTIGATE-MIB
     'fgModel'     => '1.3.6.1.4.1.12356.101.1',

     # FORTINET-FORTIMANAGER-FORTIANALYZER-MIB
     'fmModel'     => '1.3.6.1.4.1.12356.103.1',
     'faModel'     => '1.3.6.1.4.1.12356.103.3',

     # FORTINET-FORTIGATE-MIB
     'fgSysDiskCapacity' => '1.3.6.1.4.1.12356.101.4.1.7.0',
     'fgProcessorCount'  => '1.3.6.1.4.1.12356.101.4.4.1.0',

     # FORTINET-FORTIMANAGER-FORTIANALYZER-MIB
     'fmSysMemCapacity' => '1.3.6.1.4.1.12356.103.2.1.3.0',
     'fmSysDiskCapacity' => '1.3.6.1.4.1.12356.103.2.1.5.0',
    );


sub checkdevtype
{
    my $dd = shift;
    my $devdetails = shift;

    my $objID = $devdetails->snmpVar($dd->oiddef('sysObjectID'));
    
    if( $dd->oidBaseMatch('fgModel', $objID) )
    {
        $devdetails->setCap('Fortinet_FG');
        return 1;
    }
    elsif( $dd->oidBaseMatch('fmModel', $objID) )
    {
        $devdetails->setCap('Fortinet_FM');
        $devdetails->setCap('interfaceIndexingPersistent');
        return 1;
    }
    elsif( $dd->oidBaseMatch('faModel', $objID) )
    {
        $devdetails->setCap('Fortinet_FA');
        $devdetails->setCap('interfaceIndexingPersistent');
        return 1;
    }
    
    return 0;
}


sub discover
{
    my $dd = shift;
    my $devdetails = shift;

    my $data = $devdetails->data();
    my $session = $dd->session();

    if( $devdetails->hasCap('Fortinet_FG') )
    {
        my $result =
            $dd->retrieveSnmpOIDs('fgSysDiskCapacity', 'fgProcessorCount');
        
        if( defined $result )
        {
            $data->{'Fortigate'}{'disk'} = $result->{'fgSysDiskCapacity'};
            if( $result->{'fgProcessorCount'} > 1 )
            {
                $data->{'Fortigate'}{'cpucount'} =
                    $result->{'fgProcessorCount'};
            }
        }
    }
    elsif( $devdetails->hasCap('Fortinet_FM') )
    {
        my $result =
            $dd->retrieveSnmpOIDs('fmSysMemCapacity', 'fmSysDiskCapacity');
        if( defined $result )
        {            
            $data->{'Fortimanager'}{'mem'} = $result->{'fmSysMemCapacity'};
            $data->{'Fortimanager'}{'disk'} = $result->{'fmSysDiskCapacity'};
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

    if( $devdetails->hasCap('Fortinet_FG') )
    {
        my $param = {
            'fortigate-disk-capacity' => 0+$data->{'Fortigate'}{'disk'},
        };
        
        $cb->addSubtree( $devNode, 'System', $param,
                         [ 'Fortinet::fortigate-system-stats' ] );
        
        if( $devdetails->paramEnabled('Fortinet::per-cpu-stats') and
            $data->{'Fortigate'}{'cpucount'} )
        {
            my $node =
                $cb->addSubtree( $devNode, 'Per_CPU_Stats',
                                 {'node-display-name' => 'Per-CPU Stats'});

            my $count = $data->{'Fortigate'}{'cpucount'};
            for( my $i=1; $i <= $count; $i++ )
            {
                my $param = {
                    'fortigate-cpu-index' => $i,
                    'node-display-name' => 'CPU ' . $i,
                    'graph-legend' => 'CPU ' . $i . ' usage',
                    'precedence' => sprintf('%d', 1000 - $i),
                };
                
                $cb->addLeaf( $node, 'CPU_' . $i, $param,
                              [ 'Fortinet::fortigate-cpu' ] );
            }
        }
    }
    elsif( $devdetails->hasCap('Fortinet_FM') )
    {
        my $param = {
            'fortimanager-mem-capacity' => 0+$data->{'Fortimanager'}{'mem'},
            'fortimanager-disk-capacity' => 0+$data->{'Fortimanager'}{'disk'},
        };

        $cb->addSubtree( $devNode, 'System', $param,
                         [ 'Fortinet::fortimanager-system-stats' ] );
        
    }

    return;
}



1;


# Local Variables:
# mode: perl
# indent-tabs-mode: nil
# perl-indent-level: 4
# End:
