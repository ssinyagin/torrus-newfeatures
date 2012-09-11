#  Copyright (C) 2011 Stanislav Sinyagin
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


# APC PowerNet SNMP-managed power distribution products
# MIB location:
#  ftp://ftp.apc.com/apc/public/software/pnetmib/mib/404/powernet404.mib
#
# Currently supported:
#   PDU firmware 5.x (tested with: AP8853 firmware v5.1.1)
#   NB200 environment sensors (tested with NBRK0200)


package Torrus::DevDiscover::APC_PowerNet;

use strict;
use warnings;

use Torrus::Log;


$Torrus::DevDiscover::registry{'APC_PowerNet'} = {
    'sequence'     => 500,
    'checkdevtype' => \&checkdevtype,
    'discover'     => \&discover,
    'buildConfig'  => \&buildConfig
    };


our %oiddef =
    (
     # PowerNet-MIB
     'apc_products' => '1.3.6.1.4.1.318.1',
     
     # rPDU2, the newer hardware and firmware
     'rPDU2IdentFirmwareRev' => '1.3.6.1.4.1.318.1.1.26.2.1.6',
     'rPDU2IdentModelNumber' => '1.3.6.1.4.1.318.1.1.26.2.1.8',
     'rPDU2IdentSerialNumber' => '1.3.6.1.4.1.318.1.1.26.2.1.9',

     'rPDU2DeviceConfigNearOverloadPowerThreshold' =>
     '1.3.6.1.4.1.318.1.1.26.4.1.1.8',

     'rPDU2DeviceConfigOverloadPowerThreshold' =>
     '1.3.6.1.4.1.318.1.1.26.4.1.1.9',

     'rPDU2DevicePropertiesNumOutlets' =>
     '1.3.6.1.4.1.318.1.1.26.4.2.1.4',

     'rPDU2DevicePropertiesNumPhases' =>
     '1.3.6.1.4.1.318.1.1.26.4.2.1.7',

     'rPDU2DevicePropertiesNumMeteredBanks' =>
     '1.3.6.1.4.1.318.1.1.26.4.2.1.8',

     'rPDU2DevicePropertiesMaxCurrentRating' =>
     '1.3.6.1.4.1.318.1.1.26.4.2.1.9',

     'rPDU2PhaseConfigNumber' => '1.3.6.1.4.1.318.1.1.26.6.1.1.3',

     'rPDU2PhaseConfigNearOverloadCurrentThreshold' =>
     '1.3.6.1.4.1.318.1.1.26.6.1.1.6',

     'rPDU2PhaseConfigOverloadCurrentThreshold' =>
     '1.3.6.1.4.1.318.1.1.26.6.1.1.7',

     'rPDU2BankConfigNumber' =>
     '1.3.6.1.4.1.318.1.1.26.8.1.1.3',

     'rPDU2BankConfigNearOverloadCurrentThreshold' =>
     '1.3.6.1.4.1.318.1.1.26.8.1.1.6',

     'rPDU2BankConfigOverloadCurrentThreshold' =>
     '1.3.6.1.4.1.318.1.1.26.8.1.1.7',


     # rPDU, the older hardware and firmware
     'sPDUIdentFirmwareRev'   => '1.3.6.1.4.1.318.1.1.4.1.2.0',
     'sPDUIdentModelNumber'   => '1.3.6.1.4.1.318.1.1.4.1.4.0',
     'sPDUIdentSerialNumber'  => '1.3.6.1.4.1.318.1.1.4.1.5.0',
     'rPDUIdentDeviceRating'  => '1.3.6.1.4.1.318.1.1.12.1.7.0',
     'rPDUIdentDeviceNumOutlets' => '1.3.6.1.4.1.318.1.1.12.1.8.0',
     'rPDUIdentDeviceNumPhases' => '1.3.6.1.4.1.318.1.1.12.1.9.0',

     'rPDULoadStatusPhaseNumber' => '1.3.6.1.4.1.318.1.1.12.2.3.1.1.4',
     'rPDULoadStatusBankNumber'  => '1.3.6.1.4.1.318.1.1.12.2.3.1.1.5',
     
     'rPDULoadPhaseConfigNearOverloadThreshold' =>
     '1.3.6.1.4.1.318.1.1.12.2.2.1.1.3',
     'rPDULoadPhaseConfigOverloadThreshold' =>
     '1.3.6.1.4.1.318.1.1.12.2.2.1.1.4',

     'rPDULoadBankConfigNearOverloadThreshold' =>
     '1.3.6.1.4.1.318.1.1.12.2.4.1.1.3',
     
     'rPDULoadBankConfigOverloadThreshold' =>
     '1.3.6.1.4.1.318.1.1.12.2.4.1.1.4',

     # Modular Environmental Manager (MEM)
     'memModulesStatusModuleName'     => '1.3.6.1.4.1.318.1.1.10.4.1.2.1.2',
     'memModulesStatusModuleLocation' => '1.3.6.1.4.1.318.1.1.10.4.1.2.1.3',
     'memModulesStatusModelNumber'    => '1.3.6.1.4.1.318.1.1.10.4.1.2.1.4',
     'memModulesStatusSerialNumber'   => '1.3.6.1.4.1.318.1.1.10.4.1.2.1.5',
     'memModulesStatusFirmwareRev'    => '1.3.6.1.4.1.318.1.1.10.4.1.2.1.6',
     'memSensorsStatusSysTempUnits'   => '1.3.6.1.4.1.318.1.1.10.4.2.1.0',
     'memSensorsStatusSensorName'     => '1.3.6.1.4.1.318.1.1.10.4.2.3.1.3',
     'memSensorsStatusSensorLocation' => '1.3.6.1.4.1.318.1.1.10.4.2.3.1.4',
     'memSensorsTempHighThresh'       => '1.3.6.1.4.1.318.1.1.10.4.2.5.1.7',
     'memSensorsTempLowThresh'        => '1.3.6.1.4.1.318.1.1.10.4.2.5.1.8',
     'memSensorsHumidityHighThresh'   => '1.3.6.1.4.1.318.1.1.10.4.2.5.1.20',
     'memSensorsHumidityLowThresh'    => '1.3.6.1.4.1.318.1.1.10.4.2.5.1.21',
     
     );



my %rpdu2_system_oid;
foreach my $name
    ('rPDU2IdentFirmwareRev',
     'rPDU2IdentModelNumber',
     'rPDU2IdentSerialNumber',
     'rPDU2DeviceConfigNearOverloadPowerThreshold',
     'rPDU2DeviceConfigOverloadPowerThreshold',
     'rPDU2DevicePropertiesNumOutlets',
     'rPDU2DevicePropertiesNumPhases',
     'rPDU2DevicePropertiesNumMeteredBanks',
     'rPDU2DevicePropertiesMaxCurrentRating',
     )
{
    $rpdu2_system_oid{$name} = $oiddef{$name} . '.1';
}


my @rpdu_system_oid =
    ('sPDUIdentFirmwareRev', 'sPDUIdentModelNumber',
     'sPDUIdentSerialNumber', 'rPDUIdentDeviceRating',
     'rPDUIdentDeviceNumOutlets', 'rPDUIdentDeviceNumPhases');

    
my $apcInterfaceFilter = {
    'LOOPBACK' => {
        'ifType'  => 24,                     # softwareLoopback
    },
};



sub checkdevtype
{
    my $dd = shift;
    my $devdetails = shift;

    if( not $dd->oidBaseMatch
        ( 'apc_products',
          $devdetails->snmpVar( $dd->oiddef('sysObjectID') ) ) )
    {
        return 0;
    }

    $devdetails->setCap('interfaceIndexingPersistent');

    &Torrus::DevDiscover::RFC2863_IF_MIB::addInterfaceFilter
        ($devdetails, $apcInterfaceFilter);

    return 1;
}


sub discover
{
    my $dd = shift;
    my $devdetails = shift;

    my $data = $devdetails->data();
    my $session = $dd->session();

    # check if rPDU2 is supported and retrieve system information
    {
        my $result = $session->get_request
            ( -varbindlist => [values %rpdu2_system_oid] );

        my $oid = $rpdu2_system_oid{'rPDU2IdentFirmwareRev'};
    
        if( defined($result) and
            defined($result->{$oid}) and length($result->{$oid}) > 0 )
        {
            $devdetails->setCap('apc_rPDU2');

            my $sysref = {};
            while( my($name, $oid) = each %rpdu2_system_oid )
            {
                $sysref->{$name} = $result->{$oid};
            }

            $data->{'param'}{'comment'} =
                'APC PDU ' .
                $sysref->{'rPDU2IdentModelNumber'} .
                ', Firmware ' .
                $sysref->{'rPDU2IdentFirmwareRev'} .
                ', S/N ' .
                $sysref->{'rPDU2IdentSerialNumber'};
            
            $data->{'param'}{'rpdu2-warn-pwr'} =
                $sysref->{'rPDU2DeviceConfigNearOverloadPowerThreshold'};
            
            $data->{'param'}{'rpdu2-crit-pwr'} =
                $sysref->{'rPDU2DeviceConfigOverloadPowerThreshold'};
            
            if( $devdetails->paramDisabled('suppress-legend') )
            {
                my $legend = $data->{'param'}{'legend'};
                $legend = '' unless defined($legend);

                $legend .= 'Phases:' .
                    $sysref->{'rPDU2DevicePropertiesNumPhases'} . ';';

                $legend .= 'Banks:' .
                    $sysref->{'rPDU2DevicePropertiesNumMeteredBanks'} . ';';

                $legend .= 'Outlets:' .
                    $sysref->{'rPDU2DevicePropertiesNumOutlets'} . ';';

                $legend .= 'Max current:' .
                    $sysref->{'rPDU2DevicePropertiesMaxCurrentRating'} . 'A;';
                
                $data->{'param'}{'legend'} = $legend;
            }
        }
    }

    if( $devdetails->hasCap('apc_rPDU2') )
    {
        # Discover PDU phases
        {
            my $cfnum = $dd->walkSnmpTable('rPDU2PhaseConfigNumber');
            my $warn_thr = $dd->walkSnmpTable
                ('rPDU2PhaseConfigNearOverloadCurrentThreshold');
            my $crit_thr = $dd->walkSnmpTable
                ('rPDU2PhaseConfigOverloadCurrentThreshold');

            while( my( $INDEX, $val ) = each %{$cfnum} )
            {
                $data->{'apc_rPDU2'}{'phases'}{$INDEX} = {
                    'rpdu2-phasenum' => $val,
                    'rpdu2-warn-currnt' => $warn_thr->{$INDEX},
                    'rpdu2-crit-currnt' => $crit_thr->{$INDEX},
                };
            }
        }

        # Discover PDU banks
        {
            my $cfnum = $dd->walkSnmpTable('rPDU2BankConfigNumber');
            my $warn_thr = $dd->walkSnmpTable
                ('rPDU2BankConfigNearOverloadCurrentThreshold');
            my $crit_thr = $dd->walkSnmpTable
                ('rPDU2BankConfigOverloadCurrentThreshold');

            while( my( $INDEX, $val ) = each %{$cfnum} )
            {
                $data->{'apc_rPDU2'}{'banks'}{$INDEX} = {
                    'rpdu2-banknum' => $val,
                    'rpdu2-warn-currnt' => $warn_thr->{$INDEX},
                    'rpdu2-crit-currnt' => $crit_thr->{$INDEX},
                };
            }
        }
    }
    else
    {
        # This is an old firmware, fall back to rPDU MIB
        my @oids;
        foreach my $oidname ( @rpdu_system_oid )
            
        {
            push( @oids, $dd->oiddef($oidname) );
        }
        
        my $result = $session->get_request( -varbindlist => \@oids );

        my $model_oid = $dd->oiddef('sPDUIdentModelNumber');
        
        if( defined($result) and
            defined($result->{$model_oid}) and
            length($result->{$model_oid}) > 0 )
        {
            $devdetails->setCap('apc_rPDU');

            my $sysref = {};
            foreach my $oidname ( @rpdu_system_oid )
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
                'APC PDU ' .
                $sysref->{'sPDUIdentModelNumber'} .
                ', Firmware ' .
                $sysref->{'sPDUIdentFirmwareRev'} .
                ', S/N ' .
                $sysref->{'sPDUIdentSerialNumber'};

            if( $devdetails->paramDisabled('suppress-legend') )
            {
                my $legend = $data->{'param'}{'legend'};
                $legend = '' unless defined($legend);

                $legend .= 'Phases:' .
                    $sysref->{'rPDUIdentDeviceNumPhases'} . ';';

                $legend .= 'Outlets:' .
                    $sysref->{'rPDUIdentDeviceNumOutlets'} . ';';

                $legend .= 'Max current:' .
                    $sysref->{'rPDUIdentDeviceRating'} . 'A;';
                
                $data->{'param'}{'legend'} = $legend;
            }
        

            # Discover PDU phases
        
            my $phases = $dd->walkSnmpTable('rPDULoadStatusPhaseNumber');
            my $banks = $dd->walkSnmpTable('rPDULoadStatusBankNumber');
            
            my $phase_warn_thr = $dd->walkSnmpTable
                ('rPDULoadPhaseConfigNearOverloadThreshold');
            my $phase_crit_thr = $dd->walkSnmpTable
                ('rPDULoadPhaseConfigOverloadThreshold');
            
            my $bank_warn_thr = $dd->walkSnmpTable
                ('rPDULoadBankConfigNearOverloadThreshold');
            my $bank_crit_thr = $dd->walkSnmpTable
                ('rPDULoadBankConfigOverloadThreshold');

            $data->{'apc_rPDU'} = [];
            
            foreach my $INDEX ( keys %{$phases} )
            {
                my $phasenum = $phases->{$INDEX};
                my $banknum = $banks->{$INDEX};

                my $param = {'rpdu-statusidx' => $INDEX};
                my $name;
                
                if( $banknum > 0 )
                {
                    $name = 'Bank ' . $banknum;
                    $param->{'nodeid-rpdu-ref'} = 'bank' . $banknum;
                    
                    if( defined($bank_warn_thr->{$banknum}) and
                        $bank_warn_thr->{$banknum} > 0 )
                    {
                        $param->{'rpdu-warn-currnt'} =
                            $bank_warn_thr->{$banknum};
                        $param->{'rpdu-crit-currnt'} =
                            $bank_crit_thr->{$banknum};
                    }
                }
                else                  
                {
                    $name = 'Phase ' . $phasenum;
                    $param->{'nodeid-rpdu-ref'} = 'phase' . $phasenum;
                    if( defined($phase_warn_thr->{$phasenum}) and
                        $phase_warn_thr->{$phasenum} > 0 )
                    {
                        $param->{'rpdu-warn-currnt'} =
                            $phase_warn_thr->{$phasenum};
                        $param->{'rpdu-crit-currnt'} =
                            $phase_crit_thr->{$phasenum};
                    }
                }

                push( @{$data->{'apc_rPDU'}},
                      {'param' => $param, 'name' => $name} );
            }
        }
    }

    # Modular Environmental Manager (MEM)
    
    my $mod_names = $dd->walkSnmpTable('memModulesStatusModuleName');
    if( scalar(keys %{$mod_names}) > 0 )
    {
        $devdetails->setCap('apc_MEM');

        my $temp_units;
        {
            my $oid = $dd->oiddef('memSensorsStatusSysTempUnits');
            my $result = $session->get_request( -varbindlist => [$oid] );
            $temp_units =
                (defined($result->{$oid}) and $result->{$oid} == 2) ?
                'Fahrenheit':'Celsius';
        }
        
        my $mod_locations =
            $dd->walkSnmpTable('memModulesStatusModuleLocation');

        my $mod_models = $dd->walkSnmpTable('memModulesStatusModelNumber');
        my $mod_serials = $dd->walkSnmpTable('memModulesStatusSerialNumber');
        my $mod_firmware = $dd->walkSnmpTable('memModulesStatusFirmwareRev');

        my $modules = {};
        foreach my $INDEX (keys %{$mod_names})
        {
            my $ref = {};
            $ref->{'name'} = $mod_names->{$INDEX};
            $ref->{'location'} = $mod_locations->{$INDEX};            
            $ref->{'model'} = $mod_models->{$INDEX};
            $ref->{'serial'} = $mod_serials->{$INDEX};
            $ref->{'firmware'} = $mod_firmware->{$INDEX};
            $ref->{'temp-units'} = $temp_units;
            
            $modules->{$INDEX}{'sys'} = $ref;           
        }

        my $s_names = $dd->walkSnmpTable('memSensorsStatusSensorName');
        my $s_locations = $dd->walkSnmpTable('memSensorsStatusSensorLocation');
        my $s_temp_hi = $dd->walkSnmpTable('memSensorsTempHighThresh');
        my $s_temp_lo = $dd->walkSnmpTable('memSensorsTempLowThresh');
        my $s_hum_hi = $dd->walkSnmpTable('memSensorsHumidityHighThresh');
        my $s_hum_lo = $dd->walkSnmpTable('memSensorsHumidityLowThresh');

        foreach my $INDEX (keys %{$s_names})
        {
            my ($mod_idx, $sens_idx) = split(/\./o, $INDEX);
            my $ref = {};
            $ref->{'sensor-name'} = $s_names->{$INDEX};
            $ref->{'sensor-location'} = $s_locations->{$INDEX};
            $ref->{'sensor-temp-hi'} = $s_temp_hi->{$INDEX};
            $ref->{'sensor-temp-lo'} = $s_temp_lo->{$INDEX};
            $ref->{'sensor-hum-hi'} = $s_hum_hi->{$INDEX};
            $ref->{'sensor-hum-lo'} = $s_hum_lo->{$INDEX};
            $ref->{'sensor-num'} = $sens_idx;

            $modules->{$mod_idx}{'sensors'}{$INDEX} = $ref;
        }

        $data->{'apc_MEM'} = $modules;
        $data->{'param'}{'comment'} = 'APC ' . $mod_models->{0};
    }    
    
    return 1;
}


sub buildConfig
{
    my $devdetails = shift;
    my $cb = shift;
    my $devNode = shift;

    my $data = $devdetails->data();
        
    if( $devdetails->hasCap('apc_rPDU2') )
    {
        my $pduParam = {
            'node-display-name' => 'PDU Statistics',
            'comment' => 'PDU current and power load',
            'precedence' => 10000,
        };
        
        my $pduSubtree =
            $cb->addSubtree( $devNode, 'PDU_Stats', $pduParam,
                             ['APC_PowerNet::apc-pdu2-subtree'] );
        
        my $precedence = 1000;

        # phases

        foreach my $INDEX ( sort {$a <=> $b}
                            keys %{$data->{'apc_rPDU2'}{'phases'}} )
        {
            my $ref = $data->{'apc_rPDU2'}{'phases'}{$INDEX};

            my $param = {
                'rpdu2-phase-index' => $INDEX,
                'node-display-name' => 'Phase ' . $ref->{'rpdu2-phasenum'},
                'precedence' => $precedence,
            };

            while (my($key, $val) = each %{$ref})
            {
                $param->{$key} = $val;
            }

            $cb->addSubtree
                ( $pduSubtree, 'Phase_' . $ref->{'rpdu2-phasenum'}, $param,
                  ['APC_PowerNet::apc-pdu2-phase'] );

            $precedence--;
        }

        # banks

        foreach my $INDEX ( sort {$a <=> $b}
                            keys %{$data->{'apc_rPDU2'}{'banks'}} )
        {
            my $ref = $data->{'apc_rPDU2'}{'banks'}{$INDEX};

            my $param = {
                'rpdu2-bank-index' => $INDEX,
                'node-display-name' => 'Bank ' . $ref->{'rpdu2-banknum'},
                'precedence' => $precedence,
            };

            while (my($key, $val) = each %{$ref})
            {
                $param->{$key} = $val;
            }

            $cb->addSubtree
                ( $pduSubtree, 'Bank_' . $ref->{'rpdu2-banknum'}, $param,
                  ['APC_PowerNet::apc-pdu2-bank'] );

            $precedence--;
        }
    }
    elsif( $devdetails->hasCap('apc_rPDU') )
    {
        # Old rPDU MIB
        
        my $pduParam = {
            'node-display-name' => 'PDU Statistics',
            'comment' => 'PDU current and power load',
            'precedence' => 10000,
        };
        
        my $pduSubtree =
            $cb->addSubtree( $devNode, 'PDU_Stats', $pduParam,
                             ['APC_PowerNet::apc-pdu-subtree'] );
        
        foreach my $ref (@{$data->{'apc_rPDU'}})
        {
            my $param = {};

            while (my($key, $val) = each %{$ref->{'param'}})
            {
                $param->{$key} = $val;
            }

            $param->{'precedence'} = 1000 - $param->{'rpdu-statusidx'};
            $param->{'node-display-name'} = $ref->{'name'};
            $param->{'graph-title'} = '%system-id% ' . $ref->{'name'};

            if( defined($param->{'rpdu-crit-currnt'}) )
            {
                $param->{'upper-limit'} = $param->{'rpdu-crit-currnt'};
                $param->{'graph-upper-limit'} = $param->{'rpdu-crit-currnt'};
            }

            if( defined($param->{'rpdu-warn-currnt'}) )
            {
                $param->{'normal-level'} = $param->{'rpdu-warn-currnt'};
            }

            my $subtreeName = $ref->{'name'};
            $subtreeName =~ s/\W/_/go;
                
            $cb->addSubtree
                ( $pduSubtree, $subtreeName, $param,
                  ['APC_PowerNet::apc-pdu-stat'] );
        }        
    }


    if( $devdetails->hasCap('apc_MEM') )
    {
        # Modular Environmental Manager (MEM)

        my $mod_precedence = 5000;
        
        foreach my $mod_idx (sort {$a <=>$b} keys %{$data->{'apc_MEM'}})
        {
            my $mod_data = $data->{'apc_MEM'}{$mod_idx};
            $mod_precedence--;

            my $modSubtreeName = $mod_data->{'sys'}{'name'};
            $modSubtreeName =~ s/\W/_/go;
            
            my $modParam = {
                'node-display-name' => $mod_data->{'sys'}{'name'},
                'precedence' => $mod_precedence,
                'sensor-temp-units' => $mod_data->{'sys'}{'temp-units'},
            };
            
            $modParam->{'comment'} = 'Environment sensors, Location: ' .
                $mod_data->{'sys'}{'location'} . ', Model: ' .
                $mod_data->{'sys'}{'model'} . ', Serial: ' .
                $mod_data->{'sys'}{'serial'} . ', Firmware: ' .
                $mod_data->{'sys'}{'firmware'};

            my $modSubtree =
                $cb->addSubtree( $devNode, $modSubtreeName, $modParam,
                                 ['APC_PowerNet::apc-mem-subtree'] );
            
            foreach my $INDEX (sort keys %{$mod_data->{'sensors'}})
            {
                my $sens_data = $mod_data->{'sensors'}{$INDEX};

                my $senSubtreeName = $sens_data->{'sensor-name'};
                $senSubtreeName =~ s/\W/_/go;

                my $sensParam = {};
                foreach my $p ('sensor-temp-hi', 'sensor-temp-lo',
                               'sensor-hum-hi', 'sensor-hum-lo',
                               'sensor-name')
                {
                    $sensParam->{$p} = $sens_data->{$p};
                }

                $sensParam->{'node-display-name'} =
                    $sens_data->{'sensor-name'};
                $sensParam->{'comment'} =
                    'Location: ' . $sens_data->{'sensor-location'};
                $sensParam->{'precedence'} =
                    1000 - $sens_data->{'sensor-num'};
                $sensParam->{'sensor-index'} = $INDEX;
                
                $cb->addSubtree( $modSubtree, $senSubtreeName, $sensParam,
                                 ['APC_PowerNet::apc-mem-sensor'] );
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
