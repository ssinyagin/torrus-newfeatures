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

# Common Cisco MIBs, supported by many IOS and CatOS devices

package Torrus::DevDiscover::CiscoGeneric;

use strict;
use Torrus::Log;


$Torrus::DevDiscover::registry{'CiscoGeneric'} = {
    'sequence'     => 500,
    'checkdevtype' => \&checkdevtype,
    'discover'     => \&discover,
    'buildConfig'  => \&buildConfig
    };


our %oiddef =
    (
     # CISCO-SMI
     'cisco'                             => '1.3.6.1.4.1.9',

     # CISCO-ENVMON-MIB
     'ciscoEnvMonTemperatureStatusDescr' => '1.3.6.1.4.1.9.9.13.1.3.1.2',
     'ciscoEnvMonTemperatureStatusValue' => '1.3.6.1.4.1.9.9.13.1.3.1.3',
     'ciscoEnvMonTemperatureThreshold'   => '1.3.6.1.4.1.9.9.13.1.3.1.4',
     'ciscoEnvMonTemperatureStatusState' => '1.3.6.1.4.1.9.9.13.1.3.1.6',

     # CISCO-MEMORY-POOL-MIB
     'ciscoMemoryPoolTable'              => '1.3.6.1.4.1.9.9.48.1.1.1',
     'ciscoMemoryPoolName'               => '1.3.6.1.4.1.9.9.48.1.1.1.2',

     # CISCO-PROCESS-MIB
     'cpmCPUTotalTable'                  => '1.3.6.1.4.1.9.9.109.1.1.1.1',
     'cpmCPUTotalPhysicalIndex'          => '1.3.6.1.4.1.9.9.109.1.1.1.1.2',
     'cpmCPUTotal1minRev'                => '1.3.6.1.4.1.9.9.109.1.1.1.1.7',
     'cpmCPUTotal1min'                   => '1.3.6.1.4.1.9.9.109.1.1.1.1.4',

     # OLD-CISCO-CPU-MIB
     'avgBusy1'                          => '1.3.6.1.4.1.9.2.1.57.0'
     );

sub checkdevtype
{
    my $dd = shift;
    my $devdetails = shift;

    if( not $dd->oidBaseMatch
        ( 'cisco', $devdetails->snmpVar( $dd->oiddef('sysObjectID') ) ) )
    {
        return 0;
    }
    
    return 1;
}


sub discover
{
    my $dd = shift;
    my $devdetails = shift;

    my $session = $dd->session();
    my $data = $devdetails->data();

    if( $devdetails->param('CiscoGeneric::disable-sensors') ne 'yes' )
    {
        # Check if temperature sensors are supported

        my $oidTempDescr = $dd->oiddef('ciscoEnvMonTemperatureStatusDescr');
        my $oidTempValue = $dd->oiddef('ciscoEnvMonTemperatureStatusValue');
        my $oidTempThrsh = $dd->oiddef('ciscoEnvMonTemperatureThreshold');
        my $oidTempState = $dd->oiddef('ciscoEnvMonTemperatureStatusState');

        if( defined $session->get_table( -baseoid => $oidTempValue ) )
        {
            $devdetails->setCap('ciscoTemperatureSensors');
            $data->{'ciscoTemperatureSensors'} = {};

            my $tempDescr = $session->get_table( -baseoid => $oidTempDescr );
            my $tempThrsh = $session->get_table( -baseoid => $oidTempThrsh );

            # Get the sensor states and ignore those notPresent(5)

            my $tempState = $session->get_table( -baseoid => $oidTempState );

            my $prefixLen = length( $oidTempDescr ) + 1;
            while( my( $oid, $descr ) = each %{$tempDescr} )
            {
                # Extract the sensor index from OID
                my $sIndex = substr( $oid, $prefixLen );

                if( $tempState->{$oidTempState.'.'.$sIndex} != 5 )
                {
                    $data->{'ciscoTemperatureSensors'}{$sIndex}{
                        'description'} = $descr;
                    $data->{'ciscoTemperatureSensors'}{$sIndex}{
                        'threshold'} = $tempThrsh->{$oidTempThrsh.'.'.$sIndex};
                }
            }
        }
    }

    if( $devdetails->param('CiscoGeneric::disable-memory-pools') ne 'yes' )
    {
        my $MemoryPool =
            $session->get_table( -baseoid =>
                                 $dd->oiddef('ciscoMemoryPoolTable') );

        if( defined $MemoryPool )
        {
            $devdetails->storeSnmpVars( $MemoryPool );
            $devdetails->setCap('ciscoMemoryPool');

            $data->{'ciscoMemoryPool'} = {};

            foreach my $memType
                ( $devdetails->getSnmpIndices($dd->
                                              oiddef('ciscoMemoryPoolName')) )
            {
                # According to CISCO-MEMORY-POOL-MIB, only types 1 to 5
                # are static, and the rest are dynamic
                # (of which none ever seen)
                if( $memType <= 5 )
                {
                    my $name =
                        $devdetails->snmpVar($dd->
                                             oiddef('ciscoMemoryPoolName') .
                                             '.' . $memType );

                    $data->{'ciscoMemoryPool'}{$memType} = $name;
                }
            }
        }
    }

    if( $devdetails->param('CiscoGeneric::disable-cpu-stats') ne 'yes' )
    {
        my $ciscoCpuStats =
            $session->get_table( -baseoid => $dd->oiddef('cpmCPUTotalTable') );

        if( defined $ciscoCpuStats )
        {
            $devdetails->setCap('ciscoCpuStats');
            $devdetails->storeSnmpVars( $ciscoCpuStats );

            $data->{'ciscoCpuStats'} = {};

            foreach my $INDEX
                ( $devdetails->
                  getSnmpIndices($dd->oiddef('cpmCPUTotalPhysicalIndex') ) )
            {
                $data->{'ciscoCpuStats'}{$INDEX} = {};

                $data->{'ciscoCpuStats'}{$INDEX}{'phy-index'} =
                    $devdetails->
                    snmpVar($dd->oiddef('cpmCPUTotalPhysicalIndex') .
                            '.' . $INDEX );

                if( $devdetails->hasOID( $dd->oiddef('cpmCPUTotal1minRev') .
                                         '.' .  $INDEX ) )
                {
                    $data->{'ciscoCpuStats'}{$INDEX}{'stats-type'} = 'revised';
                }
            }
        }
        else
        {
            # Although OLD-CISCO-CPU-MIB is implemented in IOS only,
            # it is easier to leave it here in Generic

            $session->get_request( -varbindlist =>
                                   [ $dd->oiddef('avgBusy1') ] );
            if( $session->error_status() == 0 )
            {
                $devdetails->setCap('old-ciscoCpuStats');
                push( @{$data->{'templates'}}, 'CiscoGeneric::old-cisco-cpu' );
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


    # Temperature Sensors

    if( $devdetails->hasCap('ciscoTemperatureSensors') )
    {
        # Create a subtree for the sensors
        my $subtreeName = 'Temperature_Sensors';

        my $fahrenheit =
            $devdetails->param('CiscoGeneric::use-fahrenheit') eq 'yes';

        my $param = {};
        my $templates = [ 'CiscoGeneric::cisco-temperature-subtree' ];
        
        my $filePerSensor =
            $devdetails->param('CiscoGeneric::file-per-sensor') eq 'yes';
        
        $param->{'data-file'} = '%snmp-host%_sensors' .
            ($filePerSensor ? '_%sensor-index%':'') .
            ($fahrenheit ? '_fahrenheit':'') . '.rrd';

        my $subtreeNode = $cb->addSubtree( $devNode, $subtreeName,
                                           $param, $templates );

        foreach my $sIndex ( sort {$a<=>$b} keys
                             %{$data->{'ciscoTemperatureSensors'}} )
        {
            my $leafName = sprintf( 'sensor_%.2d', $sIndex );

            my $desc =
                $data->{'ciscoTemperatureSensors'}{$sIndex}{'description'};
            my $threshold =
                $data->{'ciscoTemperatureSensors'}{$sIndex}{'threshold'};

            if( $fahrenheit )
            {
                $threshold = $threshold * 1.8 + 32;
            }

            my $param = {
                'sensor-index'       => $sIndex,
                'sensor-description' => $desc,
                'upper-limit'        => $threshold
                };

            my $templates = ['CiscoGeneric::cisco-temperature-sensor' .
                             ($fahrenheit ? '-fahrenheit':'')];

            $cb->addLeaf( $subtreeNode, $leafName, $param, $templates );
        }
    }

    # Memory Pools

    if( $devdetails->hasCap('ciscoMemoryPool') )
    {
        my $subtreeName = 'Memory_Usage';

        my $param = {
            'precedence'        => '-100',
            'comment'           => 'Memory usage statistics'
            };

        my $subtreeNode =
            $cb->addSubtree( $devNode, $subtreeName, $param,
                             ['CiscoGeneric::cisco-memusage-subtree']);

        foreach my $memType
            ( sort {$a<=>$b} keys %{$data->{'ciscoMemoryPool'}} )
        {
            my $poolName = $data->{'ciscoMemoryPool'}{$memType};

            my $poolSubtreeName = $poolName;
            $poolSubtreeName =~ s/^\///;
            $poolSubtreeName =~ s/\W/_/g;
            $poolSubtreeName =~ s/_+/_/g;

            my $param = {
                'comment'      => 'Memory Pool: ' . $poolName,
                'mempool-type' => $memType,
                'mempool-name' => $poolName,
                'precedence'   => sprintf("%d", 1000 - $memType)
            };

            $cb->addSubtree( $subtreeNode, $poolSubtreeName,
                             $param, [ 'CiscoGeneric::cisco-mempool' ]);
        }
    }

    if( $devdetails->hasCap('ciscoCpuStats') )
    {
        my $subtreeName = 'CPU_Usage';
        my $param = {
            'precedence'         => '-500',
            'comment'            => 'Overall CPU busy percentage'
            };

        my $subtreeNode =
            $cb->addSubtree( $devNode, $subtreeName, $param,
                             ['CiscoGeneric::cisco-cpu-usage-subtree']);

        foreach my $INDEX ( sort {$a<=>$b} keys %{$data->{'ciscoCpuStats'}} )
        {
            my $phyIndex = $data->{'ciscoCpuStats'}{$INDEX}{'phy-index'};
            my $phyDescr;
            my $phyName;

            if( $phyIndex > 0 and
                $devdetails->isDevType('RFC2737_ENTITY_MIB') )
            {
                $phyDescr = $data->{'entityPhysical'}{$phyIndex}{'descr'};
                $phyName = $data->{'entityPhysical'}{$phyIndex}{'name'};
            }

            $phyDescr = 'Central Processor' unless $phyDescr;
            $phyName = ('Chassis #' . $phyIndex) unless $phyName;

            my $param = {
                'entity-phy-index' => $phyIndex,
                'comment' => $phyDescr . ' in ' . $phyName
                };

            my @templates;

            if( $data->{'ciscoCpuStats'}{$INDEX}{'stats-type'} eq 'revised' )
            {
                push( @templates, 'CiscoGeneric::cisco-cpu-revised' );
            }
            else
            {
                push( @templates, 'CiscoGeneric::cisco-cpu' );
            }

            my $cpuSubtreeName = $phyName;
            $cpuSubtreeName =~ s/^\///;
            $cpuSubtreeName =~ s/\W/_/g;
            $cpuSubtreeName =~ s/_+/_/g;

            $cb->addSubtree( $subtreeNode, $cpuSubtreeName,
                             $param, \@templates );
        }
    }
}


1;


# Local Variables:
# mode: perl
# indent-tabs-mode: nil
# perl-indent-level: 4
# End:
