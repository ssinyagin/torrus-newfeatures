#
#  Discovery module for Liebert HVAC systems
#
#  Copyright (C) 2008-2018 Jon Nistor
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
#
# Jon Nistor <nistor at snickers.org>
#
# NOTE: Options for this module
#       Liebert::use-fahrenheit
#       Liebert::disable-temperature
#       Liebert::disable-humidity
#       Liebert::disable-state
#       Liebert::disable-statistics
#
# NOTE: This module supports both Fahrenheit and Celcius, but for ease of
#       module and cleanliness we will convert Celcius into Fahrenheit
#       instead of polling for Fahrenheit directly.
#
# NOTE: Systems can be configured with many options and modules.  As such the
#       Torrus discovery module has been modified to be extremely dynamic and
#       will attempt to do a more thorough check of supported values.
#
#

# Liebert discovery module
package Torrus::DevDiscover::Liebert;

use strict;
use warnings;

use Torrus::Log;

$Torrus::DevDiscover::registry{'Liebert'} = {
    'sequence'     => 500,
    'checkdevtype' => \&checkdevtype,
    'discover'     => \&discover,
    'buildConfig'  => \&buildConfig
    };

our %oiddef =
    (
     # LIEBERT-GP-REGISTRATION-MIB
     'GlobalProducts'     => '1.3.6.1.4.1.476.1.42',

     # LIEBERT-GP-AGENT-MIB
     'Manufacturer'       => '1.3.6.1.4.1.476.1.42.2.1.1.0',
     'Model'              => '1.3.6.1.4.1.476.1.42.2.1.2.0',
     'FirmwareVer'        => '1.3.6.1.4.1.476.1.42.2.1.3.0',
     'SerialNum'          => '1.3.6.1.4.1.476.1.42.2.1.4.0',
     'PartNum'            => '1.3.6.1.4.1.476.1.42.2.1.5.0',

     # LIEBERT-GP-ENVIRONMENTAL-MIB - main entries/tables to look at
     #
     # Temp only seems to work with info on DegF and DegC results.
     'lgpEnvTemperature'                        => '1.3.6.1.4.1.476.1.42.3.4.1',
     'lgpEnvHumidity'                           => '1.3.6.1.4.1.476.1.42.3.4.2',
     'lgpEnvState'                              => '1.3.6.1.4.1.476.1.42.3.4.3',
     'lgpEnvStatistics'                         => '1.3.6.1.4.1.476.1.42.3.4.6',


     # -> lgpEnvTemperatureTableDegC table
     'lgpEnvTemperatureEntryDegC'               => '1.3.6.1.4.1.476.1.42.3.4.1.3.3.1',
     'TemperatureIdDegC'                        => '1.3.6.1.4.1.476.1.42.3.4.1.3.3.1.1',
     'TemperatureDescrDegC'                     => '1.3.6.1.4.1.476.1.42.3.4.1.3.3.1.2',
     # - Sensors below
     'lgpEnvTemperatureMeasurementDegC'         => '1.3.6.1.4.1.476.1.42.3.4.1.3.3.1.3',
     'lgpEnvTemperatureHighThresholdDegC'       => '1.3.6.1.4.1.476.1.42.3.4.1.3.3.1.4',
     'lgpEnvTemperatureLowThresholdDegC'        => '1.3.6.1.4.1.476.1.42.3.4.1.3.3.1.5',
     'lgpEnvTemperatureSetPointDegC'            => '1.3.6.1.4.1.476.1.42.3.4.1.3.3.1.6',
     'lgpEnvTemperatureDailyHighDegC'           => '1.3.6.1.4.1.476.1.42.3.4.1.3.3.1.7',
     'lgpEnvTemperatureDailyLowDegC'            => '1.3.6.1.4.1.476.1.42.3.4.1.3.3.1.8',
     'lgpEnvTempDailyHighTimeHourDegC'          => '1.3.6.1.4.1.476.1.42.3.4.1.3.3.1.9',
     'lgpEnvTempDailyHighTimeMinuteDegC'        => '1.3.6.1.4.1.476.1.42.3.4.1.3.3.1.10',
     'lgpEnvTempDailyHighTimeSecondDegC'        => '1.3.6.1.4.1.476.1.42.3.4.1.3.3.1.11',
     'lgpEnvTempDailyLowTimeHourDegC'           => '1.3.6.1.4.1.476.1.42.3.4.1.3.3.1.12',
     'lgpEnvTempDailyLowTimeMinuteDegC'         => '1.3.6.1.4.1.476.1.42.3.4.1.3.3.1.13',
     'lgpEnvTempDailyLowTimeSecondDegC'         => '1.3.6.1.4.1.476.1.42.3.4.1.3.3.1.14',
     'lgpEnvTemperatureMeasurementTenthsDegC'   => '1.3.6.1.4.1.476.1.42.3.4.1.3.3.1.50',
     'lgpEnvTemperatureHighThresholdTenthsDegC' => '1.3.6.1.4.1.476.1.42.3.4.1.3.3.1.51',
     'lgpEnvTemperatureLowThresholdTenthsDegC'  => '1.3.6.1.4.1.476.1.42.3.4.1.3.3.1.52.0',
     'lgpEnvTemperatureSetPointTenthsDegC'      => '1.3.6.1.4.1.476.1.42.3.4.1.3.3.1.53.0',
     'lgpEnvTemperatureDeadBandTenthsDegC'      => '1.3.6.1.4.1.476.1.42.3.4.1.3.3.1.60.0',
     'lgpEnvTempHeatingPropBandTenthsDegC'      => '1.3.6.1.4.1.476.1.42.3.4.1.3.3.1.61.0',
     'lgpEnvTempCoolingPropBandTenthsDegC'      => '1.3.6.1.4.1.476.1.42.3.4.1.3.3.1.62.0',

     # --
     # Humidity 
     'lgpEnvHumidity'                           => '1.3.6.1.4.1.476.1.42.3.4.2',
     'lgpEnvHumidityRelative'                   => '1.3.6.1.4.1.476.1.42.3.4.2.2',
     'lgpEnvHumiditySettingRel'                 => '1.3.6.1.4.1.476.1.42.3.4.2.2.1.0',
     'lgpEnvHumidityToleranceRel'               => '1.3.6.1.4.1.476.1.42.3.4.2.2.2.0',
     #
     'lgpEnvHumidityTableRel'                   => '1.3.6.1.4.1.476.1.42.3.4.2.2.3',
     'lgpEnvHumidityEntryRel'                   => '1.3.6.1.4.1.476.1.42.3.4.2.2.3.1',
     'lgpHumidityIdRel'                         => '1.3.6.1.4.1.476.1.42.3.4.2.2.3.1.1', # not on all
     # -- Sensors below
     'lgpEnvHumidityDescrRel'                   => '1.3.6.1.4.1.476.1.42.3.4.2.2.3.1.2',
     'lgpEnvHumidityMeasurementRel'             => '1.3.6.1.4.1.476.1.42.3.4.2.2.3.1.3',
     'lgpEnvHumidityHighThresholdRel'           => '1.3.6.1.4.1.476.1.42.3.4.2.2.3.1.4',
     'lgpEnvHumidityLowThresholdRel'            => '1.3.6.1.4.1.476.1.42.3.4.2.2.3.1.5',
     'lgpEnvHumiditySetPoint'                   => '1.3.6.1.4.1.476.1.42.3.4.2.2.3.1.6',
     'lgpEnvHumidityDailyHigh'                  => '1.3.6.1.4.1.476.1.42.3.4.2.2.3.1.7',
     'lgpEnvHumidityDailyLow'                   => '1.3.6.1.4.1.476.1.42.3.4.2.2.3.1.8',
     'lgpEnvHumidityDailyHighTimeHour'          => '1.3.6.1.4.1.476.1.42.3.4.2.2.3.1.9',
     'lgpEnvHumidityDailyHighTimeMinute'        => '1.3.6.1.4.1.476.1.42.3.4.2.2.3.1.10',
     'lgpEnvHumidityDailyHighTimeSecond'        => '1.3.6.1.4.1.476.1.42.3.4.2.2.3.1.11',
     'lgpEnvHumidityDailyLowTimeHour'           => '1.3.6.1.4.1.476.1.42.3.4.2.2.3.1.12',
     'lgpEnvHumidityDailyLowTimeMinute'         => '1.3.6.1.4.1.476.1.42.3.4.2.2.3.1.13',
     'lgpEnvHumidityDailyLowTimeSecond'         => '1.3.6.1.4.1.476.1.42.3.4.2.2.3.1.14',
     'lgpEnvHumidityDeadBand'                   => '1.3.6.1.4.1.476.1.42.3.4.2.2.3.1.15',
     'lgpEnvHumidifyPropBand'                   => '1.3.6.1.4.1.476.1.42.3.4.2.2.3.1.16',
     'lgpEnvDehumidifyPropBand'                 => '1.3.6.1.4.1.476.1.42.3.4.2.2.3.1.17',
     'lgpEnvHumidityMeasurementRelTenths'       => '1.3.6.1.4.1.476.1.42.3.4.2.2.3.1.50',
     'lgpEnvHumidityHighThresholdRelTenths'     => '1.3.6.1.4.1.476.1.42.3.4.2.2.3.1.51',
     'lgpEnvHumidityLowThresholdRelTenths'      => '1.3.6.1.4.1.476.1.42.3.4.2.2.3.1.52',


     # Not all units support each of these values so we need to check
     # -> lgpEnvState table
     'lgpEnvStateSystem'             => '1.3.6.1.4.1.476.1.42.3.4.3.1.0',
     'lgpEnvStateCooling'            => '1.3.6.1.4.1.476.1.42.3.4.3.2.0',
     'lgpEnvStateHeating'            => '1.3.6.1.4.1.476.1.42.3.4.3.3.0',
     'lgpEnvStateHumidifying'        => '1.3.6.1.4.1.476.1.42.3.4.3.4.0',
     'lgpEnvStateDehumidifying'      => '1.3.6.1.4.1.476.1.42.3.4.3.5.0',
     'lgpEnvStateEconoCycle'         => '1.3.6.1.4.1.476.1.42.3.4.3.6.0',
     'lgpEnvStateFan'                => '1.3.6.1.4.1.476.1.42.3.4.3.7.0',
     'lgpEnvStateGeneralAlarmOutput' => '1.3.6.1.4.1.476.1.42.3.4.3.8.0',
     'lgpEnvStateCoolingCapacity'    => '1.3.6.1.4.1.476.1.42.3.4.3.9.0',
     'lgpEnvStateHeatingCapacity'    => '1.3.6.1.4.1.476.1.42.3.4.3.10.0',
     'lgpEnvStateAudibleAlarm'       => '1.3.6.1.4.1.476.1.42.3.4.3.11.0',

     'lgpEnvStateCoolingUnits'       => '1.3.6.1.4.1.476.1.42.3.4.3.12', # sub-values
     'lgpEnvStateHeatingUnits'       => '1.3.6.1.4.1.476.1.42.3.4.3.13', # sub-values

     'lgpEnvStateOperatingReason'    => '1.3.6.1.4.1.476.1.42.3.4.3.14.0',
     'lgpEnvStateOperatingMode'      => '1.3.6.1.4.1.476.1.42.3.4.3.15.0',
     'lgpEnvStateFanCapacity'        => '1.3.6.1.4.1.476.1.42.3.4.3.16.0',
     'lgpEnvStateFreeCoolingCapacity' => '1.3.6.1.4.1.476.1.42.3.4.3.17.0',
     'lgpEnvStateDehumidifyingCapacity' => '1.3.6.1.4.1.476.1.42.3.4.3.18.0',
     'lgpEnvStateHumidifyingCapacity'   => '1.3.6.1.4.1.476.1.42.3.4.3.19.0',
     'lgpEnvStateFreeCooling'           => '1.3.6.1.4.1.476.1.42.3.4.3.20.0',
     'lgpEnvStateElectricHeater'        => '1.3.6.1.4.1.476.1.42.3.4.3.21.0',
     'lgpEnvStateHotWater'              => '1.3.6.1.4.1.476.1.42.3.4.3.22.0',
     'lgpEnvStateOperatingEfficiency'   => '1.3.6.1.4.1.476.1.42.3.4.3.23.0',

     # -> lgpEnvStatistics table
     'lgpEnvStatisticsComp1RunHr'        => '1.3.6.1.4.1.476.1.42.3.4.6.1.0',
     'lgpEnvStatisticsComp2RunHr'        => '1.3.6.1.4.1.476.1.42.3.4.6.2.0',
     'lgpEnvStatisticsFanRunHr'          => '1.3.6.1.4.1.476.1.42.3.4.6.3.0',
     'lgpEnvStatisticsHumRunHr'          => '1.3.6.1.4.1.476.1.42.3.4.6.4.0',
     'lgpEnvStatisticsReheat1RunHr'      => '1.3.6.1.4.1.476.1.42.3.4.6.7.0',
     'lgpEnvStatisticsReheat2RunHr'      => '1.3.6.1.4.1.476.1.42.3.4.6.8.0',
     'lgpEnvStatisticsReheat3RunHr'      => '1.3.6.1.4.1.476.1.42.3.4.6.9.0',
     'lgpEnvStatisticsCoolingModeHrs'    => '1.3.6.1.4.1.476.1.42.3.4.6.10.0',
     'lgpEnvStatisticsHeatingModeHrs'    => '1.3.6.1.4.1.476.1.42.3.4.6.11.0',
     'lgpEnvStatisticsHumidifyModeHrs'   => '1.3.6.1.4.1.476.1.42.3.4.6.12.0',
     'lgpEnvStatisticsDehumidifyModeHrs' => '1.3.6.1.4.1.476.1.42.3.4.6.13.0',
     'lgpEnvStatisticsHotGasRunHr'       => '1.3.6.1.4.1.476.1.42.3.4.6.14.0',
     'lgpEnvStatisticsHotWaterRunHr'     => '1.3.6.1.4.1.476.1.42.3.4.6.15.0',
     'lgpEnvStatisticsFreeCoolRunHr'     => '1.3.6.1.4.1.476.1.42.3.4.6.16.0',
     'lgpEnvStatisticsComp3RunHr'        => '1.3.6.1.4.1.476.1.42.3.4.6.17.0',
     'lgpEnvStatisticsComp4RunHr'        => '1.3.6.1.4.1.476.1.42.3.4.6.18.0',


     # Flexible Registrations
     'lgpFlexible'                          => '1.3.6.1.4.1.476.1.42.3.9',
     'lgpFlexibleEntryDataLabel'            => '1.3.6.1.4.1.476.1.42.3.9.20.1.10',
     'lgpFlexibleEntryValue'                => '1.3.6.1.4.1.476.1.42.3.9.20.1.20',
     'lgpFlexibleEntryUnsignedIntegerValue' => '1.3.6.1.4.1.476.1.42.3.9.30.1.20',
     'lgpFlexibleEntryDataType'             => '1.3.6.1.4.1.476.1.42.3.9.30.1.40',
     'lgpFlexibleEntryAccessibility'        => '1.3.6.1.4.1.476.1.42.3.9.30.1.50',
     'lgpFlexibleEntryDataDescription'      => '1.3.6.1.4.1.476.1.42.3.9.30.1.70',

     );

our %oid_Temperature =
    (

    # -> lgpEnvTemperatureWellKnown ref for tempDescr
    'Control_Temperature'                  => '1.3.6.1.4.1.476.1.42.3.4.1.1.1',
    'ReturnAir_Temperature'                => '1.3.6.1.4.1.476.1.42.3.4.1.1.2',
    'SupplyAir_Temperature'                => '1.3.6.1.4.1.476.1.42.3.4.1.1.3',
    'Ambient_Temperature'                  => '1.3.6.1.4.1.476.1.42.3.4.1.1.4',
    'Inverter_Temperature'                 => '1.3.6.1.4.1.476.1.42.3.4.1.1.5',
    'Battery_Tempterature'                 => '1.3.6.1.4.1.476.1.42.3.4.1.1.6',
    'AcDcConverter_Temperature'            => '1.3.6.1.4.1.476.1.42.3.4.1.1.7',
    'Pfc_Temperature'                      => '1.3.6.1.4.1.476.1.42.3.4.1.1.8',
    'Transformer_Temperature'              => '1.3.6.1.4.1.476.1.42.3.4.1.1.9',
    'Local_Temperature'                    => '1.3.6.1.4.1.476.1.42.3.4.1.1.10',
    'Local1_Temperature'                   => '1.3.6.1.4.1.476.1.42.3.4.1.1.10.1',
    'Local2_Temperature'                   => '1.3.6.1.4.1.476.1.42.3.4.1.1.10.2',
    'Local3_Temperature'                   => '1.3.6.1.4.1.476.1.42.3.4.1.1.10.3',
    'DigitalScrollCompressor_Temperature'  => '1.3.6.1.4.1.476.1.42.3.4.1.1.11',
    'DigitalScrollCompressor1_Temperature' => '1.3.6.1.4.1.476.1.42.3.4.1.1.11.1',
    'DigitalScrollCompressor2_Temperature' => '1.3.6.1.4.1.476.1.42.3.4.1.1.11.2',
    'ChillWater_Temperature'               => '1.3.6.1.4.1.476.1.42.3.4.1.1.12',
    'Coolant_Temperature'                  => '1.3.6.1.4.1.476.1.42.3.4.1.1.13',
    'Enclosure_TemperatureSensors'         => '1.3.6.1.4.1.476.1.42.3.4.1.1.14',
    'Enclosure1_TemperatureSensors'        => '1.3.6.1.4.1.476.1.42.3.4.1.1.14.1',
    'Enclosure2_TemperatureSensors'        => '1.3.6.1.4.1.476.1.42.3.4.1.1.14.2',
    'Enclosure3_TemperatureSensors'        => '1.3.6.1.4.1.476.1.42.3.4.1.1.14.3',
    'Enclosure4_TemperatureSensors'        => '1.3.6.1.4.1.476.1.42.3.4.1.1.14.4',
    'ValueAmbientRoom_Temperature'         => '1.3.6.1.4.1.476.1.42.3.4.1.1.15',
    'DewPoint_Temperature'                 => '1.3.6.1.4.1.476.1.42.3.4.1.1.16',
    'Enclosure_Temperature'                => '1.3.6.1.4.1.476.1.42.3.4.1.1.17',
    'Adjusted_Temperature'                 => '1.3.6.1.4.1.476.1.42.3.4.1.1.18',
    'ExternalSensors'                      => '1.3.6.1.4.1.476.1.42.3.4.1.1.19',
    'ExternalAirSensorA'                   => '1.3.6.1.4.1.476.1.42.3.4.1.1.19.1',
    'ExternalAirSensorADewPoint'           => '1.3.6.1.4.1.476.1.42.3.4.1.1.19.2',
    'ExternalAirSensorB'                   => '1.3.6.1.4.1.476.1.42.3.4.1.1.19.3',
    'ExternalAirSensorBDewPoint'           => '1.3.6.1.4.1.476.1.42.3.4.1.1.19.4',
    'SupplyFluid_Temperature'              => '1.3.6.1.4.1.476.1.42.3.4.1.1.20',
    'SupplyRefrigerant_Temperature'        => '1.3.6.1.4.1.476.1.42.3.4.1.1.21',
    'MinDesiredRoomAir_Temperature'        => '1.3.6.1.4.1.476.1.42.3.4.1.1.22',
    'DewPoint_Temperature'                 => '1.3.6.1.4.1.476.1.42.3.4.1.1.23',
    'InletDewPoint_Temperature'            => '1.3.6.1.4.1.476.1.42.3.4.1.1.23.1',
);

our %oid_Humidity = (
    'Control_Humidity'                     => '1.3.6.1.4.1.476.1.42.3.4.2.1.1',
    'Return_Air_Humidity'                  => '1.3.6.1.4.1.476.1.42.3.4.2.1.2',
    'Supply_Air_Humidity'                  => '1.3.6.1.4.1.476.1.42.3.4.2.1.3',
    'Value_Ambient_Humidity'               => '1.3.6.1.4.1.476.1.42.3.4.2.1.4',


);

our @cap_EnvState;
our @cap_EnvStatistics;
our %sensorTempHash;


sub checkdevtype
{
    my $dd = shift;
    my $devdetails = shift;

    if( not $dd->oidBaseMatch ( 'GlobalProducts',
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

    my $session = $dd->session();
    my $data = $devdetails->data();

    # PROG: Grab versions, serials and type of chassis.
    my $Info = $dd->retrieveSnmpOIDs ( 'Manufacturer', 'Model',
                        'FirmwareVer', 'SerialNum', 'PartNum' );

    # SNMP: System comment
    $data->{'param'}{'comment'} =
            $Info->{'Manufacturer'} . " " . $Info->{'Model'} . ", Version: " .
            $Info->{'FirmwareVer'} . ", Serial: " . $Info->{'SerialNum'};

    # The Liebert HVAC snmp implementation requires a lower number
    # of pdu's to be sent to it.
    $data->{'param'}{'snmp-oids-per-pdu'} = 10;

    # -------------------------------------------------------------------------
    # Temperature
    #

    if( $devdetails->paramDisabled('Liebert::disable-temperature') ) 
    {
        # ENV: Degrees Celcius - Description Table (SupplyAir, Control, Return, etc)
        #      Result is an OID reference, need to look that up afterwards for proper
        #      sensor name.

        my $idTable = $dd->walkSnmpTable('TemperatureDescrDegC');

        if( defined( $idTable ) )
        {
            # - Grab the Celcius table by default and do the math for fahrenheit
            if( $devdetails->paramEnabled('Liebert::use-fahrenheit') )
            {
                $devdetails->setCap('env-temperature');
                $devdetails->setCap('env-temperature-fahrenheit');
            } else {
                $devdetails->setCap('env-temperature');
            }

            # - Cycle through Description Table and lookup resulting OID for name
            foreach my $idxDesc ( sort { $a <=> $b } keys %{$idTable} )
            {
                my $oid_tmp = $idTable->{$idxDesc};

                # FIND: Check if the OID exists in oid_Temperature and return sensor name
                #       oid_Temperature built only for description references.
                while( my( $oid_name, $oid_num ) = each %oid_Temperature )
                {
                    if( $oid_tmp eq $oid_num )
                    {
                        Verbose("Liebert: Description Index: $idxDesc, name: $oid_name");
                        $data->{'liebert'}{'temp-IdxDesc'}{$idxDesc} = $oid_name;
                    }
                }
            }

            # Parse lgpEnvTemperatureEntryDegC Table, split Sensor Index and Type
            #
            # -> Table output has numerous options, indices are double value.
            # eg: 1.3.6.1.4.1.476.1.42.3.4.1.3.3.1.X.Y (OID)
            #     lgpEnvTemperatureEntryDegC.X.Y
            #                                | +-- Index of Sensor
            #                                +---- Index of SensorType
            #                                        eg: TemperatureMeasurementDegC
            #                                        eg: emperatureMeasurementTenthsDegC

            my $tblEntrySensor = $session->get_table(
                                   -baseoid => $dd->oiddef('lgpEnvTemperatureEntryDegC')
                                 );
            $devdetails->storeSnmpVars($tblEntrySensor);

            # LOOP: Cycle through each index, split results.
            #       Group the SensorType into the SensorIndex buckets.
            foreach my $idxDualOID ( $devdetails->getSnmpIndices(
                                  $dd->oiddef('lgpEnvTemperatureEntryDegC')) )
            {
                my( $s_oidIdxType, $s_oidIdx ) = split( /\./, $idxDualOID );

                # SKIP: Don't need to check specific ID reference or Description entries
                #       type1 = lgpEnvTemperatureIdDegC
                #       type2 = lgpEnvTemperatureDescrDegC
                next if( $s_oidIdxType == 1 || $s_oidIdxType == 2 );

                push( @{$data->{'liebert'}{'tempIdx'}{$s_oidIdx}}, $s_oidIdxType);

                # LOOP: Check if the OID exists in oiddef and return sensor name
                my $oid_chk  = $dd->oiddef('lgpEnvTemperatureEntryDegC') . "." . $s_oidIdxType;
                my $oid_snmp = $dd->oiddef('lgpEnvTemperatureEntryDegC') . "." . $idxDualOID;

                while( my( $oid_name, $oid_num ) = each %oiddef )
                {
                    if( $oid_chk eq $oid_num )
                    {
                        # - Grab temperature main index desription
                        my $s_oidIdxName = $data->{'liebert'}{'temp-IdxDesc'}{$s_oidIdx};

                        Verbose("Liebert: Sensor type $s_oidIdxType ($oid_name) " .
                                "supported by Index $s_oidIdx ($s_oidIdxName)");

                        $data->{'liebert'}{'temp-IdxSensor'}{$s_oidIdx}{$s_oidIdxType}{'name'} = $oid_name;
                        $data->{'liebert'}{'temp-IdxSensor'}{$s_oidIdx}{$s_oidIdxType}{'oid'}  = $oid_snmp;
                    }
                } # END: while
            } # END: foreach index of getSnmpIndices
        } # END: if idTable
    } # END: Temperature


    # -------------------------------------------------------------------------
    # ENV: Humidity
    #

    if( $devdetails->paramDisabled('Liebert::disable-humidity') )
    {
        my $idTable = $session->get_table(
                                   -baseoid => $dd->oiddef('lgpEnvHumidityEntryRel')
                                 );
        $devdetails->storeSnmpVars( $idTable );

        if( defined( $idTable ) )
        {
            $devdetails->setCap('env-humidity');

            # - Check for Global lgpEnvHumidity -> SettingRel and ToleranceRel
            my @global_humidity_mib = ('lgpEnvHumiditySettingRel',
                                       'lgpEnvHumidityToleranceRel');

            foreach my $global_humidity_oid ( @global_humidity_mib )
            {
                if( $dd->checkSnmpOID($global_humidity_oid) )
                {
                    $devdetails->setCap('env-humidity-global-' . $global_humidity_oid);
                }
            }

            # - Cycle through Description Table and lookup resulting OID for name
            #
            foreach my $idxDesc ( $devdetails->getSnmpIndices(
                                $dd->oiddef('lgpEnvHumidityDescrRel') ) )
            {
                my $oid_snmp = $dd->oiddef('lgpEnvHumidityDescrRel') . "." . $idxDesc;
                my $oid_tmp  = $idTable->{$oid_snmp};;

                # FIND: Check if the OID exists in oid_Temperature and return sensor name
                #       oid_Temperature built only for description references.
                while( my( $oid_name, $oid_num ) = each %oid_Humidity )
                {
                    if( $oid_tmp eq $oid_num )
                    {
                        Verbose("Liebert: Humidity Index: $idxDesc, name: $oid_name");
                        $data->{'liebert'}{'humid-IdxDesc'}{$idxDesc} = $oid_name;
                    }
                }
            } # END: foreach index <-> descr match

            # LOOP: Cycle through each index, split results.
            #       Group the SensorType into the SensorIndex buckets.
            foreach my $idxDualOID ( $devdetails->getSnmpIndices(
                                  $dd->oiddef('lgpEnvHumidityEntryRel')) )
            {
                my( $s_oidIdxType, $s_oidIdx ) = split( /\./, $idxDualOID );

                # SKIP: Don't need to check specific ID reference or Description entries
                #       type1 = lgpEnvHumidityIdRel
                #       type2 = lgpEnvHumidityDescrRel
                next if( $s_oidIdxType == 1 || $s_oidIdxType == 2 );

                push( @{$data->{'liebert'}{'humid-Idx'}{$s_oidIdx}}, $s_oidIdxType);

                # LOOP: Check if the OID exists in oiddef and return sensor name
                my $oid_chk = $dd->oiddef('lgpEnvHumidityEntryRel') . "." . $s_oidIdxType;

                while( my( $oid_name, $oid_num ) = each %oiddef )
                {
                    if( $oid_chk eq $oid_num )
                    {
                        # - Grab temperature main index desription
                        my $s_oidIdxName = $data->{'liebert'}{'humid-IdxDesc'}{$s_oidIdx};

                        Verbose("Liebert: Sensor type $s_oidIdxType ($oid_name) " .
                                "supported by Index $s_oidIdx ($s_oidIdxName)");

                        $data->{'liebert'}{'humid-IdxSensor'}{$s_oidIdx}{$s_oidIdxType}{'name'} = $oid_name;
                        $data->{'liebert'}{'humid-IdxSensor'}{$s_oidIdx}{$s_oidIdxType}{'oid'}  = $oid_chk;
                    }
                } # END: while
            } # END: foreach index of getSnmpIndices
        } # END: if idTable
    }


    # -------------------------------------------------------------------------
    # ENV: State
    if( $devdetails->paramDisabled('Liebert::disable-state') )
    {
        my $stateTable = $session->get_table(
                 -baseoid => $dd->oiddef('lgpEnvState') );
        $devdetails->storeSnmpVars( $stateTable );

        if( defined( $stateTable ) )
        {
            $devdetails->setCap('env-state');

            # PROG: Check to see if Firmware is new enough for Capacity
            foreach my $entry ( keys %{ $stateTable } )
            {
                # LOOP: Check if the OID exists in oiddef and set capability
                while( my( $oid_name, $oid_num ) = each %oiddef )
                {
                    if( $entry eq $oid_num )
                    {
                        $devdetails->setCap("env-state-$oid_name");
                        push(@cap_EnvState, "env-state-$oid_name");
                    }
                }
            } # END: foreach
        } # END: if $stateTable
    }

    # -------------------------------------------------------------------------
    # Statistics
    if( $devdetails->paramDisabled('Liebert::disable-statistics') )
    {
        my $tblStatistics = $dd->walkSnmpTable('lgpEnvStatistics');

        if( defined( $tblStatistics ) )
        {
            $devdetails->setCap('env-statistics');

            foreach my $entry ( keys %{ $tblStatistics } )
            {
                # LOOP: Check if the OID exists in oiddef and set capability
                my $oid_tmp = $dd->oiddef('lgpEnvStatistics') . "." . $entry;

                while( my( $oid_name, $oid_num ) = each %oiddef )
                {
                    if( $oid_tmp eq $oid_num )
                    {
                        $devdetails->setCap("env-statistics-$oid_name");
                        push(@cap_EnvStatistics, "env-statistics-$oid_name");
                    }
                }
            } # END: foreach
        } # END: if $tblStatistics
    }


    # WORK IN PROGRESS --- WORK IN PROGRESS --- WORK IN PROGRESS
    # DD: Flexible Registrations
    #
    #  LgpFlexibleBasicEntry ::= SEQUENCE
    #       lgpFlexibleEntryIndex               OBJECT IDENTIFIER,
    #       lgpFlexibleEntryDataLabel           DisplayString,
    #       lgpFlexibleEntryValue               DisplayString,
    #       lgpFlexibleEntryUnitsOfMeasure      DisplayString

    #if( $devdetails->paramDisabled('Liebert::disable-flexible') )
    #{
    #
    #}

    return 1;
}


sub buildConfig
{
    my $devdetails = shift;
    my $cb = shift;
    my $devNode = shift;
    my $data = $devdetails->data();

    # -------------------------------------------------------------------------
    # XML: Temperature
    #
    if( $devdetails->hasCap('env-temperature') )
    {
        # All place-setting variables default to Celcius
        my @template;
        my $dataFile   = "%system-id%_temperature.rrd";
        my $fahrenheit = 0;
        my $tempUnit   = "C";
        my $tempScale  = "Celcius";
        my $tempLowLim = 15;
        my $tempUppLim = 70;

        if( $devdetails->hasCap('env-temperature-fahrenheit') )
        {
            $dataFile   = "%system-id%_temperature_f.rrd";
            $fahrenheit = 1;
            $tempUnit   = "F";
            $tempScale  = "Fahrenheit";
            $tempLowLim = (( $tempLowLim * 1.8 ) + 32);
            $tempUppLim = (( $tempUppLim * 1.8 ) + 32);
        }

        my $paramSubTree = {
            'temp-lower'     => $tempLowLim,
            'temp-scale'     => $tempUnit,
            'temp-upper'     => $tempUppLim,
            'vertical-label' => "degrees $tempScale"
        };
        my $nodeTemp = $cb->addSubtree( $devNode, 'Temperature', $paramSubTree,
                                      [ 'Liebert::envtemp-sensor-subtree' ] );

        # ------------------------------------------------------------------
        # SENSOR: Cycle through temperature sensor indexes, add accordingly.
        foreach my $index ( sort { $a <=> $b } keys %{$data->{'liebert'}{'temp-IdxDesc'}} )
        {
            my $sensorName = $data->{'liebert'}{'temp-IdxDesc'}{$index};
	    (my $sensorNameShort = $sensorName) =~ s/_Temperature//g;

            Verbose("Liebert: XML Temperature idx: $index : $tempScale : $sensorName");
            my $param = {
                'comment'          => "Sensor: $sensorName",
                'precedence'       => 999 - $index,
                'sensor-idx'       => $index,
                'sensor-name'      => $sensorName,
                'sensor-nameShort' => $sensorNameShort
            };

            my $nodeTempSub = $cb->addSubtree( $nodeTemp, 'sensor_' . $sensorNameShort, $param,
                                             [ @template ] );

            # -> Cycle through each top level sensor index we found
            # eg: LIEBERT-GP-ENVIRONMENTAL-MIB::lgpEnvTemperatureMeasurementDegC.${X} references
            foreach my $indexLeaf ( sort { $a <=> $b } keys %{$data->{'liebert'}{'temp-IdxSensor'}{$index}} )
            {
                # -> Cycle through each specific sensor available per MIB sensor option, add leaf
                # eg: lgpEnvTemperatureMeasurementDegC.Y
                #     lgpEnvTemperatureMeasurementTenthsDegC.Y
                #     lgpEnvTemperatureHighThresholdTenthsDegC.Y

                my $leaf_sensorName = $data->{'liebert'}{'temp-IdxSensor'}{$index}{$indexLeaf}{'name'};
                my $leaf_sensorOID  = $data->{'liebert'}{'temp-IdxSensor'}{$index}{$indexLeaf}{'oid'};
 
                my $sensorRRDDS   = $leaf_sensorName; # rrd DS max length is 19, validate

                if( length($sensorRRDDS) > 19 )
                {
                   $sensorRRDDS = substr($sensorRRDDS, 0, 19);
                   Debug("Liebert: XML RRD-DS fix $leaf_sensorName -> $sensorRRDDS");
                }

                my $param = {
                    'comment'            => $leaf_sensorName,
                    'precedence'         => 999 - $index - $indexLeaf - $indexLeaf,
                    'idx-tempsensor'     => $index,
                    'idx-tempsensorType' => $indexLeaf,
                    'sensor-name'        => $leaf_sensorName,
                    'sensor-rrdfile'     => $index . "_" . $indexLeaf,
                    'sensor-rrdds'       => $sensorRRDDS,
                    'sensor-snmp'        => "$leaf_sensorOID"
                };

                $param->{'data-file'} =
                    '%system-id%_envtemp_sensor_' . lc($sensorNameShort) . "_%sensor-rrdfile%" . 
                    ($fahrenheit ? '_fahrenheit':'') . '.rrd';

                # FIX: Time to do a little whizardry on the entries in the same table.
                if( ( $leaf_sensorName =~ /^lgpEnvTemperature/ ) &&
                    ( $devdetails->hasCap('env-temperature-fahrenheit') ) )
                {
                    $param->{'collector-scale'} = "1.8,*,32,+";
                }

                if( $leaf_sensorName =~ /^lgpEnvTempDaily/ )
                {
                    $param->{'vertical-label'} = "Time";
                    $param->{'graph-legend'}   = $leaf_sensorName;
                }

                if( $leaf_sensorName =~ /TenthsDegC$/ )
                {
                    $param->{'collector-scale'} = "0.1,*";
                }

                $cb->addLeaf( $nodeTempSub, $leaf_sensorName, $param,
                            [ 'Liebert::envtemp-sensor-leaf' ] );
 
            } # END: foreach indexLeaf
        } # END: foreach my $index
    } # END: env-temperature


    # -------------------------------------------------------------------------
    # XML: Humidity
    #
    if( $devdetails->hasCap('env-humidity') )
    {
        my $nodeHumidity = $cb->addSubtree( $devNode, "Humidity", undef,
                                          [ 'Liebert::envhumidity-subtree' ] );

        # PROG: Check a couple global entries first
        #
        if( $devdetails->hasCap('env-humidity-global-lgpEnvHumiditySettingRel') )
        {
            my $param_humiditySet = {
                'comment'        => "Current Realitive Humidity setting",
                'data-file'      => "%system-id%_humidity_setting.rrd",
                'graph-legend'   => "Setting",
                'graph-title'    => "%system-id%",
                'vertical-label' => "Percent",
                'rrd-ds'         => "humidSetting",
                'snmp-object'    => "\$HumiditySettingRel"
            };
            $cb->addLeaf( $nodeHumidity, "Setting", $param_humiditySet, undef );
        }

        if( $devdetails->hasCap('env-humidity-global-lgpEnvHumidityToleranceRel') )
        {
            my $param_humiditySet = {
                'comment'        => "Acceptable variance from setting",
                'graph-legend'   => "Tolerance",
                'data-file'      => "%system-id%_humidity_tolerance.rrd",
                'graph-title'    => "%system-id%",
                'vertical-label' => "Percent",
                'rrd-ds'         => "humidTolerance",
                'snmp-object'    => "\$HumidityToleranceRel"
            };
            $cb->addLeaf( $nodeHumidity, "Tolerance", $param_humiditySet, undef );
        }

        # PROG: Extract the sensors and build the appropriate structure.
        #
        foreach my $index ( sort { $a <=> $b } keys %{$data->{'liebert'}{'humid-IdxDesc'}} )
        {
            my $sensorName = $data->{'liebert'}{'humid-IdxDesc'}{$index};
	    (my $sensorNameShort = $sensorName) =~ s/_Humidity//g;

            Verbose("Liebert: XML Humidity idx: $index : $sensorName");
            my $param = {
                'comment'          => "Sensor: $sensorName",
                'precedence'       => 999 - $index,
                'sensor-idx'       => $index,
                'sensor-name'      => $sensorName,
                'sensor-nameShort' => $sensorNameShort
            };

            my @template = ();
            my $nodeHumiditySub = $cb->addSubtree( $nodeHumidity,  'sensor_' .
                                  $sensorNameShort, $param, [ @template ] );

            # -> Double check Relative Humidity global sensor works.

            # -> Cycle through each top level sensor index we found
            # eg: LIEBERT-GP-ENVIRONMENTAL-MIB::lgpEnvHumidityEntryRel.${X} references
            foreach my $indexLeaf ( sort { $a <=> $b }
                                    keys %{$data->{'liebert'}{'humid-IdxSensor'}{$index}} )
            {
                # -> Cycle through each entry/index and find which entries are supported.
                # eg: lgpEnvHumidityMeasurementRel.Y
                #     lgpEnvHumidityHighThresholdRel.Y
                #     lgpEnvHumidityLowThresholdRel.Y

                my $leaf_sensorName = $data->{'liebert'}{'humid-IdxSensor'}{$index}{$indexLeaf}{'name'};
                my $leaf_sensorOID  = $data->{'liebert'}{'humid-IdxSensor'}{$index}{$indexLeaf}{'oid'};

               ( $leaf_sensorName  = $leaf_sensorName ) =~ s/lgpEnv//g;
 
                my $sensorRRDDS   = $leaf_sensorName; # rrd DS max length is 19, validate
                if( length($sensorRRDDS) > 19 )
                {
                   $sensorRRDDS = substr($sensorRRDDS, 0, 19);
                   Debug("Liebert: XML RRD-DS fix $leaf_sensorName -> $sensorRRDDS");
                }

                my $param = {
                    'precedence'         => 999 - $index - $indexLeaf - $indexLeaf,
                    'rrd-ds'             => $sensorRRDDS,
                    'snmp-object'        => "\$$leaf_sensorName",
                    #
                    'sensor-name'        => $leaf_sensorName,
                    'sensor-rrdfile'     => $index . "_" . $indexLeaf,
                    'humid-idx'          => $index,
                    'humid-idxType'      => $indexLeaf,
                };

                $param->{'data-file'} =
                    '%system-id%_humidity_sensor_' . lc($sensorNameShort) .
                    "_%sensor-rrdfile%" . '.rrd';

                # FIX: Time to do a little whizardry on the entries in the same table.
                if( $leaf_sensorName =~ /Time/ )
                {
                    $param->{'vertical-label'} = "Time";
                    $param->{'graph-legend'}   = $leaf_sensorName;
                }

                if( $leaf_sensorName =~ /Tenths$/ )
                {
                    $param->{'collector-scale'} = "0.1,*";
                }

                $cb->addLeaf( $nodeHumiditySub, $leaf_sensorName, $param,
                            [ 'Liebert::envhumidity-sensor-leaf' ] );

            } # END: foreach indexLeaf
        } # END: foreach index
    } # END of hasCap



    # ENVIRONMENT: State of the system
    if( $devdetails->hasCap('env-state') )
    {
        my $nodeState = $cb->addSubtree( $devNode, 'State', undef,
                                       [ 'Liebert::envstate-subtree' ] );

        foreach my $cap_arr ( @cap_EnvState )
        {
           if( $devdetails->hasCap($cap_arr) )
           {
               ( my $sensorName  = $cap_arr) =~ s/env-state-//g;
               ( my $sensorLabel = $cap_arr) =~ s/env-state-lgpEnvState//g;

               my $sensorRRDDS   = $sensorLabel; # rrd DS max length is 19
               if( length($sensorRRDDS) > 19 )
               {
                   $sensorRRDDS = substr($sensorRRDDS, 0, 19);
                   Debug("Liebert: XML RRD-DS fix $sensorLabel -> $sensorRRDDS");
               }

               my $sensorOID    = $oiddef{$sensorName};

               my $param = {
                   'comment'        => $sensorLabel,
                   'sensor-rrdds'   => $sensorRRDDS,
                   'sensor-name'    => $sensorName,
                   'sensor-desc'    => 'sensor desc here',
                   'sensor-snmp'    => $sensorOID,
                   'graph-legend'   => $sensorLabel,
                   'vertical-label' => "on(1), off(2)"
               };
               # -- Vertical Label fix for a few entries
               if( $sensorName eq "lgpEnvStateSystem" )
               {
                   $param->{'vertical-label'} = "on(1), off(2), standby(3)";
               }

               if( $sensorName =~ /^lgp.*Capacity.*/ )
               {
                   $param->{'vertical-label'} = "Percentage capacity";
               }

               # -- Add the leaf with the variables from $param
               $cb->addLeaf( $nodeState, $sensorLabel, $param,
                         [ 'Liebert::envstate-leaf' ]  );
           } # END: if hasCap
        } # END: foreach
    }

    # ENVIRONMENT: Statistics of the system
    if( $devdetails->hasCap('env-statistics') )
    {
        my $nodeStatistics = $cb->addSubtree( $devNode, 'Statistics', undef,
                                       [ 'Liebert::envstatistics-subtree' ] );

        foreach my $cap_arr ( @cap_EnvStatistics )
        {
           if( $devdetails->hasCap($cap_arr) )
           {
               ( my $sensorName  = $cap_arr) =~ s/env-statistics-//g;
               ( my $sensorLabel = $cap_arr) =~ s/env-statistics-lgpEnvStatistics//g;

               my $sensorRRDDS   = $sensorLabel; # rrd DS max length is 19, validate
               if( length($sensorRRDDS) > 19 )
               {
                   $sensorRRDDS = substr($sensorRRDDS, 0, 19);
                   Debug("Liebert: XML RRD-DS fix $sensorLabel -> $sensorRRDDS");
               }

               my $sensorOID    = $oiddef{$sensorName};

               # -- Vertical Label fix for a few entries
               my $sensorVLabel = "Accumulated run hours";

               my $param = {
                   'comment'        => $sensorLabel,
                   'sensor-rrdds'   => $sensorRRDDS,
                   'sensor-name'    => $sensorName,
                   'sensor-desc'    => 'sensor desc here',
                   'sensor-snmp'    => $sensorOID,
                   'sensor-legend'  => $sensorLabel,
                   'vertical-label' => $sensorVLabel
               };

               # -- Add the leaf with the variables
               $cb->addLeaf( $nodeStatistics, $sensorLabel, $param,
                         [ 'Liebert::envstatistics-leaf' ]  );
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
