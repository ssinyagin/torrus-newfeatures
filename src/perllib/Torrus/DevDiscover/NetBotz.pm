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
#  Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.


# NetBotz modular sensors

package Torrus::DevDiscover::NetBotz;

use strict;
use warnings;

use Torrus::Log;


$Torrus::DevDiscover::registry{'NetBotz'} = {
    'sequence'     => 500,
    'checkdevtype' => \&checkdevtype,
    'discover'     => \&discover,
    'buildConfig'  => \&buildConfig
    };


our %oiddef =
    (
     # NETBOTZV2-MIB
     'netBotzV2Products'           => '1.3.6.1.4.1.5528.100.20',
     'nb_enclosureId'              => '1.3.6.1.4.1.5528.100.2.1.1.1',
     'nb_enclosureLabel'           => '1.3.6.1.4.1.5528.100.2.1.1.4',
     'nb_tempSensorLabel'          => '1.3.6.1.4.1.5528.100.4.1.1.1.4',
     'nb_tempSensorEncId'          => '1.3.6.1.4.1.5528.100.4.1.1.1.5',
     'nb_humiSensorLabel'          => '1.3.6.1.4.1.5528.100.4.1.2.1.4',
     'nb_humiSensorEncId'          => '1.3.6.1.4.1.5528.100.4.1.2.1.5',
     'nb_dewPointSensorLabel'      => '1.3.6.1.4.1.5528.100.4.1.3.1.4',
     'nb_dewPointSensorEncId'      => '1.3.6.1.4.1.5528.100.4.1.3.1.5',
     'nb_audioSensorLabel'         => '1.3.6.1.4.1.5528.100.4.1.4.1.4',
     'nb_audioSensorEncId'         => '1.3.6.1.4.1.5528.100.4.1.4.1.5',
     'nb_airFlowSensorLabel'       => '1.3.6.1.4.1.5528.100.4.1.5.1.4',
     'nb_airFlowSensorEncId'       => '1.3.6.1.4.1.5528.100.4.1.5.1.5',
     'nb_ampDetectSensorLabel'     => '1.3.6.1.4.1.5528.100.4.1.6.1.4',
     'nb_ampDetectSensorEncId'     => '1.3.6.1.4.1.5528.100.4.1.6.1.5',
     'nb_otherNumericSensorLabel'  => '1.3.6.1.4.1.5528.100.4.1.10.1.4',
     'nb_otherNumericSensorEncId'  => '1.3.6.1.4.1.5528.100.4.1.10.1.5',
     'nb_dryContactSensorLabel'    => '1.3.6.1.4.1.5528.100.4.2.1.1.4',
     'nb_dryContactSensorEncId'    => '1.3.6.1.4.1.5528.100.4.2.1.1.5',
     'nb_doorSwitchSensorLabel'    => '1.3.6.1.4.1.5528.100.4.2.2.1.4',
     'nb_doorSwitchSensorEncId'    => '1.3.6.1.4.1.5528.100.4.2.2.1.5',
     'nb_cameraMotionSensorLabel'  => '1.3.6.1.4.1.5528.100.4.2.3.1.4',
     'nb_cameraMotionSensorEncId'  => '1.3.6.1.4.1.5528.100.4.2.3.1.5',
     'nb_otherStateSensorLabel'    => '1.3.6.1.4.1.5528.100.4.2.10.1.4',
     'nb_otherStateSensorEncId'    => '1.3.6.1.4.1.5528.100.4.2.10.1.5',     
     );


our %sensor_types =
    ('temp'   => {
        'oidname' => 'temp',
        'template' => 'NetBotz::netbotz-temp-sensor',
        'max' => 'NetBotz::temp-max',
        },
     'humi'   => {
         'oidname' => 'humi',
         'template' => 'NetBotz::netbotz-humi-sensor',
         'max' => 'NetBotz::humi-max',
         },
     'dew'    => {
         'oidname' => 'dewPoint',
         'template' => 'NetBotz::netbotz-dew-sensor',
         'max' => 'NetBotz::dew-max',
         },
     'audio'  => {
         'oidname' => 'audio',
         'template' => 'NetBotz::netbotz-audio-sensor'
         },
     'air' => {
         'oidname' => 'airFlow',
         'template' => 'NetBotz::netbotz-air-sensor'
         },
     'door' => {
         'oidname' => 'doorSwitch',
         'template' => 'NetBotz::netbotz-door-sensor'
         },
     );
     
     

sub checkdevtype
{
    my $dd = shift;
    my $devdetails = shift;

    if( not $dd->oidBaseMatch
        ( 'netBotzV2Products',
          $devdetails->snmpVar( $dd->oiddef('sysObjectID') ) ) )
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

    my $data = $devdetails->data();
    my $session = $dd->session();

    # retrieve enclosure IDs and names;
    $data->{'NetBotz'} = {};

    {
        my $id_table = $dd->walkSnmpTable('nb_enclosureId');
        my $label_table = $dd->walkSnmpTable('nb_enclosureLabel');

        while( my($INDEX, $id) = each %{$id_table} )
        {
            my $label = $label_table->{$INDEX};
            if( defined($label) )
            {
                $data->{'NetBotz'}{$id} = {
                    'encl_label' => $label,
                    'sensors' => {}};
            }
            else
            {
                Error('Cannot retrieve NetBotz enclosure label for id=' . $id);
            }
        }
    }
    
    # store the sensor names to guarantee uniqueness
    my %sensorNames;
    
    foreach my $stype (sort keys %sensor_types)
    {
        my $oid_name_base = 'nb_' . $sensor_types{$stype}{'oidname'};

        my $encl_table = $dd->walkSnmpTable($oid_name_base . 'SensorEncId');
        my $label_table = $dd->walkSnmpTable($oid_name_base . 'SensorLabel');
        

        foreach my $INDEX (sort {$a <=> $b} keys %{$encl_table})
        {
            my $enclId = $encl_table->{$INDEX};
            my $label = $label_table->{$INDEX};
            
            next unless (defined($enclId) and defined($label));

            if( not defined($data->{'NetBotz'}{$enclId}) )
            {
                Error('Cannot associate sensor ' . $label .
                      ' with enclosure ID');
                next;
            }
            
            if( $sensorNames{$label} )
            {
                Warn('Duplicate sensor names: ' . $label);
                $sensorNames{$label}++;
            }
            else
            {
                $sensorNames{$label} = 1;
            }
            
            if( $sensorNames{$label} > 1 )
            {
                $label .= sprintf(' %d', $sensorNames{$label});
            }
            
            my $leafName = $label;
            $leafName =~ s/\W/_/g;
            $leafName =~ s/_+$//g;
            
            my $param = {
                'netbotz-sensor-index' => $INDEX,
                'node-display-name' => $label,
                'graph-title' => $label,
                'precedence' => sprintf('%d', 0 - $INDEX)
                };

            if( defined( $sensor_types{$stype}{'max'} ) )
            {
                my $max =
                    $devdetails->param($sensor_types{$stype}{'max'});
                
                if( defined($max) and $max > 0 )
                {
                    $param->{'upper-limit'} = $max;
                }
            }
            
            
            $data->{'NetBotz'}{$enclId}{'sensors'}{$INDEX} = {
                'param'    => $param,
                'leafName' => $leafName,
                'template' => $sensor_types{$stype}{'template'}};
        }        
    }
    
    if( not defined($data->{'param'}{'comment'}) or
        $data->{'param'}{'comment'} eq '')
    {
        $data->{'param'}{'comment'} = 'NetBotz environment sensors';
    }

    return 1;
}


sub buildConfig
{
    my $devdetails = shift;
    my $cb = shift;
    my $devNode = shift;

    my $data = $devdetails->data();

    my $enclSubtree = $cb->addSubtree
        ( $devNode, 'Sensor_Enclosures',
          {'node-display-name' => 'Sensor Enclosures',
           'comment' => 'NetBotz sensors arranged in enclosures',
           'precedence' => 10000});

    my $precedence = 1000;
    
    foreach my $enclId (sort keys %{$data->{'NetBotz'}} )
    {
        my $ref = $data->{'NetBotz'}{$enclId};

        next if scalar(keys %{$ref->{'sensors'}}) == 0;
                       
        my $enclLabel = $ref->{'encl_label'};
        my $subtreeName = $enclLabel;
        $subtreeName =~ s/\W+/_/g;
        $subtreeName =~ s/_+$//;
        
        my $enclNode =
            $cb->addSubtree( $enclSubtree, $subtreeName,
                             {'node-display-name' => $enclLabel,
                              'precedence' => $precedence});
        $precedence--;
        
        foreach my $INDEX ( sort {$a<=>$b} keys %{$ref->{'sensors'}} )
        {
            my $sensor = $ref->{'sensors'}{$INDEX};
            
            $cb->addLeaf( $enclNode, $sensor->{'leafName'}, $sensor->{'param'},
                          [$sensor->{'template'}] );
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
