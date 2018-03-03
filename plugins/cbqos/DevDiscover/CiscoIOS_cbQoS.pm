#  Copyright (C) 2003  Stanislav Sinyagin
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

# Stanislav Sinyagin <ssinyagin@k-open.com>

# Cisco IOS Class-based QoS discovery

## no critic (Modules::RequireFilenameMatchesPackage)

# TODO:
#  Is cbQosQueueingMaxQDepth constant or variable?
#  RED statistics

package Torrus::DevDiscover::CiscoIOS_cbQoS;

use strict;
use warnings;

use Torrus::Log;


$Torrus::DevDiscover::registry{'CiscoIOS_cbQoS'} = {
    'sequence'     => 520,
    'checkdevtype' => \&checkdevtype,
    'discover'     => \&discover,
    'buildConfig'  => \&buildConfig
    };


our %oiddef =
    (
     # CISCO-CLASS-BASED-QOS-MIB
     'cbQosServicePolicyTable'         => '1.3.6.1.4.1.9.9.166.1.1.1',
     'cbQosPolicyIndex'                => '1.3.6.1.4.1.9.9.166.1.1.1.1.1',
     'cbQosIfType'                     => '1.3.6.1.4.1.9.9.166.1.1.1.1.2',
     'cbQosPolicyDirection'            => '1.3.6.1.4.1.9.9.166.1.1.1.1.3',
     'cbQosIfIndex'                    => '1.3.6.1.4.1.9.9.166.1.1.1.1.4',
     'cbQosFrDLCI'                     => '1.3.6.1.4.1.9.9.166.1.1.1.1.5',
     'cbQosAtmVPI'                     => '1.3.6.1.4.1.9.9.166.1.1.1.1.6',
     'cbQosAtmVCI'                     => '1.3.6.1.4.1.9.9.166.1.1.1.1.7',
     'cbQosEntityIndex'                => '1.3.6.1.4.1.9.9.166.1.1.1.1.8',
     'cbQosVlanIndex'                  => '1.3.6.1.4.1.9.9.166.1.1.1.1.9',
     'cbQosEVC'                        => '1.3.6.1.4.1.9.9.166.1.1.1.1.10',

     'cbQosObjectsTable'               => '1.3.6.1.4.1.9.9.166.1.5.1',
     'cbQosObjectsIndex'               => '1.3.6.1.4.1.9.9.166.1.5.1.1.1',
     'cbQosConfigIndex'                => '1.3.6.1.4.1.9.9.166.1.5.1.1.2',
     'cbQosObjectsType'                => '1.3.6.1.4.1.9.9.166.1.5.1.1.3',
     'cbQosParentObjectsIndex'         => '1.3.6.1.4.1.9.9.166.1.5.1.1.4',

     'cbQosPolicyMapCfgTable'          => '1.3.6.1.4.1.9.9.166.1.6.1',
     'cbQosPolicyMapName'              => '1.3.6.1.4.1.9.9.166.1.6.1.1.1',
     'cbQosPolicyMapDesc'              => '1.3.6.1.4.1.9.9.166.1.6.1.1.2',

     'cbQosCMCfgTable'                 => '1.3.6.1.4.1.9.9.166.1.7.1',
     'cbQosCMName'                     => '1.3.6.1.4.1.9.9.166.1.7.1.1.1',
     'cbQosCMDesc'                     => '1.3.6.1.4.1.9.9.166.1.7.1.1.2',
     'cbQosCMInfo'                     => '1.3.6.1.4.1.9.9.166.1.7.1.1.3',

     'cbQosMatchStmtCfgTable'          => '1.3.6.1.4.1.9.9.166.1.8.1',
     'cbQosMatchStmtName'              => '1.3.6.1.4.1.9.9.166.1.8.1.1.1',

     'cbQosQueueingCfgTable'           => '1.3.6.1.4.1.9.9.166.1.9.1',
     'cbQosQueueingCfgBandwidth'       => '1.3.6.1.4.1.9.9.166.1.9.1.1.1',
     'cbQosQueueingCfgBandwidthUnits'  => '1.3.6.1.4.1.9.9.166.1.9.1.1.2',
     'cbQosQueueingCfgFlowEnabled'     => '1.3.6.1.4.1.9.9.166.1.9.1.1.3',
     'cbQosQueueingCfgPriorityEnabled' => '1.3.6.1.4.1.9.9.166.1.9.1.1.4',
     'cbQosQueueingCfgAggregateQSize'  => '1.3.6.1.4.1.9.9.166.1.9.1.1.5',
     'cbQosQueueingCfgIndividualQSize' => '1.3.6.1.4.1.9.9.166.1.9.1.1.6',
     'cbQosQueueingCfgDynamicQNumber'  => '1.3.6.1.4.1.9.9.166.1.9.1.1.7',
     'cbQosQueueingCfgPrioBurstSize'   => '1.3.6.1.4.1.9.9.166.1.9.1.1.8',
     'cbQosQueueingCfgQLimitUnits'     => '1.3.6.1.4.1.9.9.166.1.9.1.1.9',
     'cbQosQueueingCfgAggregateQLimit' => '1.3.6.1.4.1.9.9.166.1.9.1.1.10',
     'cbQosQueueingCfgBandwidth64'     => '1.3.6.1.4.1.9.9.166.1.9.1.1.13',

     'cbQosREDCfgTable'                => '1.3.6.1.4.1.9.9.166.1.10.1',
     'cbQosREDCfgExponWeight'          => '1.3.6.1.4.1.9.9.166.1.10.1.1.1',
     'cbQosREDCfgMeanQsize'            => '1.3.6.1.4.1.9.9.166.1.10.1.1.2',
     'cbQosREDCfgDscpPrec'             => '1.3.6.1.4.1.9.9.166.1.10.1.1.3',
     'cbQosREDCfgECNEnabled'           => '1.3.6.1.4.1.9.9.166.1.10.1.1.4',

     'cbQosREDClassCfgTable'           => '1.3.6.1.4.1.9.9.166.1.11.1',
     'cbQosREDCfgMinThreshold'         => '1.3.6.1.4.1.9.9.166.1.11.1.1.2',
     'cbQosREDCfgMaxThreshold'         => '1.3.6.1.4.1.9.9.166.1.11.1.1.3',
     'cbQosREDCfgPktDropProb'          => '1.3.6.1.4.1.9.9.166.1.11.1.1.4',
     'cbQosREDClassCfgThresholdUnit'   => '1.3.6.1.4.1.9.9.166.1.11.1.1.5',
     'cbQosREDClassCfgMinThreshold'    => '1.3.6.1.4.1.9.9.166.1.11.1.1.6',
     'cbQosREDClassCfgMaxThreshold'    => '1.3.6.1.4.1.9.9.166.1.11.1.1.7',

     'cbQosPoliceCfgTable'             => '1.3.6.1.4.1.9.9.166.1.12.1',
     'cbQosPoliceCfgRate'              => '1.3.6.1.4.1.9.9.166.1.12.1.1.1',
     'cbQosPoliceCfgBurstSize'         => '1.3.6.1.4.1.9.9.166.1.12.1.1.2',
     'cbQosPoliceCfgExtBurstSize'      => '1.3.6.1.4.1.9.9.166.1.12.1.1.3',
     'cbQosPoliceCfgConformAction'     => '1.3.6.1.4.1.9.9.166.1.12.1.1.4',
     'cbQosPoliceCfgConformSetValue'   => '1.3.6.1.4.1.9.9.166.1.12.1.1.5',
     'cbQosPoliceCfgExceedAction'      => '1.3.6.1.4.1.9.9.166.1.12.1.1.6',
     'cbQosPoliceCfgExceedSetValue'    => '1.3.6.1.4.1.9.9.166.1.12.1.1.7',
     'cbQosPoliceCfgViolateAction'     => '1.3.6.1.4.1.9.9.166.1.12.1.1.8',
     'cbQosPoliceCfgViolateSetValue'   => '1.3.6.1.4.1.9.9.166.1.12.1.1.9',
     'cbQosPoliceCfgRate64'            => '1.3.6.1.4.1.9.9.166.1.12.1.1.11',
     'cbQosPoliceCfgRateType'          => '1.3.6.1.4.1.9.9.166.1.12.1.1.12',
     'cbQosPoliceCfgPercentRateValue'  => '1.3.6.1.4.1.9.9.166.1.12.1.1.13',
     'cbQosPoliceCfgCellRate'          => '1.3.6.1.4.1.9.9.166.1.12.1.1.15',

     'cbQosTSCfgTable'                 => '1.3.6.1.4.1.9.9.166.1.13.1',
     'cbQosTSCfgRate'                  => '1.3.6.1.4.1.9.9.166.1.13.1.1.1',
     'cbQosTSCfgBurstSize'             => '1.3.6.1.4.1.9.9.166.1.13.1.1.2',
     'cbQosTSCfgExtBurstSize'          => '1.3.6.1.4.1.9.9.166.1.13.1.1.3',
     'cbQosTSCfgAdaptiveEnabled'       => '1.3.6.1.4.1.9.9.166.1.13.1.1.4',
     'cbQosTSCfgLimitType'             => '1.3.6.1.4.1.9.9.166.1.13.1.1.6',
     'cbQosTSCfgRateType'              => '1.3.6.1.4.1.9.9.166.1.13.1.1.7',
     'cbQosTSCfgPercentRateValue'      => '1.3.6.1.4.1.9.9.166.1.13.1.1.8',
     'cbQosTSCfgRate64'                => '1.3.6.1.4.1.9.9.166.1.13.1.1.11'
     );

# Object types "policymap", "set" are not used for statistics.

my %supportedObjectTypes =
    (
     'policymap'       => 1,
     'classmap'        => 1,
     'matchStatement'  => 1,
     'queueing'        => 1,
     'randomDetect'    => 1,
     'trafficShaping'  => 1,
     'police'          => 1
     );

my %cfgTablesForType =
    (
     'policymap'       => ['cbQosPolicyMapCfgTable'],
     'classmap'        => ['cbQosCMCfgTable'],
     'matchStatement'  => ['cbQosMatchStmtCfgTable'],
     'queueing'        => ['cbQosQueueingCfgTable'],
     'randomDetect'    => ['cbQosREDCfgTable', 'cbQosREDClassCfgTable'],
     'trafficShaping'  => ['cbQosTSCfgTable'],
     'police'          => ['cbQosPoliceCfgTable']
     );

my %cfgTablesOptional =
    ('cbQosREDClassCfgTable' => 1);

my %objTypeMap  =
    (
     'policymap'      => 1,
     'classmap'       => 2,
     'matchStatement' => 3,
     'queueing'       => 4,
     'randomDetect'   => 5,
     'trafficShaping' => 6,
     'police'         => 7,
     'set'            => 8 
     );



sub checkdevtype
{
    my $dd = shift;
    my $devdetails = shift;

    my $session = $dd->session();

    # cbQoS templates use 64-bit counters, so SNMPv1 is explicitly unsupported
    
    if( $devdetails->isDevType('CiscoIOS') and
        $devdetails->param('snmp-version') ne '1' and
        $dd->checkSnmpTable('cbQosServicePolicyTable') )
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

    $data->{'param'}{'snmp-oids-per-pdu'} = '20';

    if( $devdetails->paramEnabled('CiscoIOS_cbQoS::persistent-indexing') )
    {
        $data->{'param'}{'cbqos-persistent-indexing'} = 'yes';
        $data->{'cbqos_persistent_indexing'} = 1;
        $devdetails->setCap('cbQoS_PersistentIndexing');
    }
    else
    {
        $data->{'param'}{'cbqos-persistent-indexing'} = 'no';
    }

    $data->{'cbqos_default_skip'} =
        $devdetails->paramEnabled('CiscoIOS_cbQoS::default-skip-qos-stats');

    # Process cbQosServicePolicyTable
    
    $data->{'cbqos_policies'} = {};

    foreach my $entryName
        ('cbQosIfType', 'cbQosPolicyDirection', 'cbQosIfIndex',
         'cbQosFrDLCI', 'cbQosAtmVPI', 'cbQosAtmVCI',
         'cbQosEntityIndex', 'cbQosVlanIndex', 'cbQosEVC')
    {
        my $table = $dd->walkSnmpTable($entryName);
        while( my($policyIndex, $value) = each %{$table} )
        {
            $value = translateCbQoSValue( $value, $entryName );
            $data->{'cbqos_policies'}{$policyIndex}{$entryName} = $value;
        }
    }

    
    # Process cbQosObjectsTable
    
    $data->{'cbqos_objects'} = {};
    $data->{'cbqos_children'} = {};
    
    my $cbQosObjectsType = $dd->walkSnmpTable('cbQosObjectsType');

    if( scalar(keys %{$cbQosObjectsType}) == 0 )
    {
        return 1;
    }

    my $cbQosConfigIndex = $dd->walkSnmpTable('cbQosConfigIndex');
    my $cbQosParentObjectsIndex =
        $dd->walkSnmpTable('cbQosParentObjectsIndex');

    my $needTables = {};
    
    while( my($INDEX, $value) = each %{$cbQosObjectsType} )
    {
        my ($policyIndex, $objectIndex) = split(/\./o, $INDEX);

        if( not exists( $data->{'cbqos_policies'}{$policyIndex} ) )
        {
            next;
        }
        
        my $objType = translateCbQoSValue( $value, 'cbQosObjectsType' );

        # Store only objects of supported types
        if( not $supportedObjectTypes{$objType} )
        {
            next;
        }

        # Suppress unneeded objects
        if( $devdetails->paramEnabled('CiscoIOS_cbQoS::classmaps-only') and
            $objType ne 'policymap' and
            $objType ne 'classmap' )
        {
            next;
        }
        
        if( $objType eq 'matchStatement' and
            $devdetails->paramEnabled(
                'CiscoIOS_cbQoS::suppress-match-statements') )
        {
            next;
        }

        my $object = {};
        $object->{'cbQosObjectsType'} = $objType;
        $object->{'cbQosPolicyIndex'} = $policyIndex;
        $object->{'cbQosObjectsIndex'} = $objectIndex;
        $object->{'cbQosConfigIndex'} = $cbQosConfigIndex->{$INDEX};

        $data->{'cbqos_objects'}{$INDEX} = $object;
            
        # Store the hierarchy information
        my $parent = $cbQosParentObjectsIndex->{$INDEX};
        if( $parent ne '0' )
        {
            $parent = $policyIndex .'.'. $parent;
        }
                
        if( not exists( $data->{'cbqos_children'}{$parent} ) )
        {
            $data->{'cbqos_children'}{$parent} = [];
        }
        push( @{$data->{'cbqos_children'}{$parent}},
              $policyIndex .'.'. $objectIndex );

        foreach my $tableName
            ( @{$cfgTablesForType{$object->{'cbQosObjectsType'}}} )
        {
            $needTables->{$tableName} = 1;
        }
    }

    # Prepare the list of DSCP values for RED
    my @dscpValues =
        split(',',
              $devdetails->paramString('CiscoIOS_cbQoS::red-dscp-values'));
    
    if( scalar(@dscpValues) == 0 )
    {
        @dscpValues = @Torrus::DevDiscover::CiscoIOS_cbQoS::RedDscpValues;
    }

    my $maxrepetitions = $devdetails->param('snmp-maxrepetitions');
    my $cfgData = {};
    
    # Retrieve needed SNMP tables
    foreach my $tableName ( keys %{$needTables} )
    {
        my $table =
            $session->get_table( -baseoid => $dd->oiddef($tableName),
                                 -maxrepetitions => $maxrepetitions );
        if( defined( $table ) )
        {
            while( my($oid, $val) = each %{$table} )
            {
                $cfgData->{$oid} = $val;
            }
        }
        elsif( not $cfgTablesOptional{$tableName} )
        {
            Error('Error retrieving ' . $tableName);
            return 0;
        }
    }


    # Process cbQosxxxCfgTable
    $data->{'cbqos_objcfg'} = {};
    $data->{'cbqos_invalid_cfg'} = {};
    
    while( my( $policyObjectIndex, $objectRef ) =
           each %{$data->{'cbqos_objects'}} )
    {
        my $objConfIndex = $objectRef->{'cbQosConfigIndex'};

        next if exists( $data->{'cbqos_objcfg'}{$objConfIndex} );
        next if $data->{'cbqos_invalid_cfg'}{$objConfIndex};

        my $objType = $objectRef->{'cbQosObjectsType'};
        my $object = {};
        my @rows = ();

        # sometimes configuration changes leave garbage like objects
        # with empty configuration.        
        my %mandatory; 

        if( $objType eq 'policymap' )
        {
            push( @rows, 'cbQosPolicyMapName', 'cbQosPolicyMapDesc' );
            $mandatory{'cbQosPolicyMapName'} = 1;
        }
        elsif( $objType eq 'classmap' )
        {
            push( @rows, 'cbQosCMName', 'cbQosCMDesc', 'cbQosCMInfo' );
            $mandatory{'cbQosCMName'} = 1;
        }
        elsif( $objType eq 'matchStatement' )
        {
            push( @rows, 'cbQosMatchStmtName' );
            $mandatory{'cbQosMatchStmtName'} = 1;
        }
        elsif( $objType eq 'queueing' )
        {
            push( @rows,
                  'cbQosQueueingCfgBandwidth',
                  'cbQosQueueingCfgBandwidthUnits',
                  'cbQosQueueingCfgFlowEnabled',
                  'cbQosQueueingCfgPriorityEnabled',
                  'cbQosQueueingCfgAggregateQSize',
                  'cbQosQueueingCfgIndividualQSize',
                  'cbQosQueueingCfgDynamicQNumber',
                  'cbQosQueueingCfgPrioBurstSize',
                  'cbQosQueueingCfgQLimitUnits',
                  'cbQosQueueingCfgAggregateQLimit',
                  'cbQosQueueingCfgBandwidth64' );
            $mandatory{'cbQosQueueingCfgBandwidth'} = 1;
            $mandatory{'cbQosQueueingCfgBandwidthUnits'} = 1;
        }
        elsif( $objType eq 'randomDetect')
        {
            push( @rows,
                  'cbQosREDCfgExponWeight',
                  'cbQosREDCfgMeanQsize',
                  'cbQosREDCfgDscpPrec',
                  'cbQosREDCfgECNEnabled' );
            $mandatory{'cbQosREDCfgExponWeight'} = 1;
        }
        elsif( $objType eq 'trafficShaping' )
        {
            my $val = $cfgData->{$dd->oiddef('cbQosTSCfgRate') .'.'.
                                     $objConfIndex};
            if( not defined($val) and
                not $data->{'cbqos_persistent_indexing'} )
            {
                Warn('cbQosTSCfgRateType for ' . $objConfIndex .
                     ' has unsupported value. It is ' .
                     'recommended to use cbQoS MIB persistency if possible');
                $data->{'cbqos_invalid_cfg'}{$objConfIndex} = 1;
                next;
            }

            push( @rows,
                  'cbQosTSCfgRate',
                  'cbQosTSCfgBurstSize',
                  'cbQosTSCfgExtBurstSize',
                  'cbQosTSCfgAdaptiveEnabled',
                  'cbQosTSCfgLimitType',
                  'cbQosTSCfgRateType',
                  'cbQosTSCfgPercentRateValue',
                  'cbQosTSCfgRate64' );
            $mandatory{'cbQosTSCfgRate'} = 1;
        }
        elsif( $objType eq 'police' )
        {
            # if cbQosPoliceCfgRateType specifies other than bps, the
            # collector cannot use cbQosPoliceCfgRate as a name index
            my $val = $cfgData->{$dd->oiddef('cbQosPoliceCfgRate') .'.'.
                                     $objConfIndex};
            if( not defined($val) and
                not $data->{'cbqos_persistent_indexing'} )
            {
                Warn('cbQosPoliceCfgRateType for ' . $objConfIndex .
                     ' has unsupported value. It is ' .
                     'recommended to use cbQoS MIB persistency if possible');
                $data->{'cbqos_invalid_cfg'}{$objConfIndex} = 1;
                next;
            }
            
            push( @rows,
                  'cbQosPoliceCfgRate',
                  'cbQosPoliceCfgBurstSize',
                  'cbQosPoliceCfgExtBurstSize',
                  'cbQosPoliceCfgConformAction',
                  'cbQosPoliceCfgConformSetValue',
                  'cbQosPoliceCfgExceedAction',
                  'cbQosPoliceCfgExceedSetValue',
                  'cbQosPoliceCfgViolateAction',
                  'cbQosPoliceCfgViolateSetValue',
                  'cbQosPoliceCfgRate64',
                  'cbQosPoliceCfgRateType',
                  'cbQosPoliceCfgPercentRateValue',
                  'cbQosPoliceCfgCellRate' );
            $mandatory{'cbQosPoliceCfgRate'} = 1;
        }
        else
        {
            Error('Unsupported object type: ' . $objType);
        }

        foreach my $row ( @rows )
        {
            my $value = $cfgData->{$dd->oiddef($row) .'.'. $objConfIndex};
            if( defined($value) and $value ne '' )
            {
                $value = translateCbQoSValue( $value, $row );
                $data->{'cbqos_objcfg'}{$objConfIndex}{$row} = $value;
            }
            elsif( $mandatory{$row} )
            {
                Warn('Missing required configuration in: ' .
                     'cbQosConfigIndex=' . $objConfIndex . ', row=' . $row .
                     ' on ' . $devdetails->param('snmp-host') .
                     '. The statistics will be disabled for collection.');
                $data->{'cbqos_invalid_cfg'}{$objConfIndex} = 1;
                $objType = 'DELETED';
            }
        }

        # In addition, get per-DSCP RED configuration
        if( $objType eq 'randomDetect')
        {
            foreach my $dscp ( @dscpValues )
            {
                foreach my $row ( qw(cbQosREDCfgMinThreshold
                                     cbQosREDCfgMaxThreshold
                                     cbQosREDCfgPktDropProb
                                     cbQosREDClassCfgThresholdUnit
                                     cbQosREDClassCfgMinThreshold
                                     cbQosREDClassCfgMaxThreshold) )
                {
                    my $dscpN = translateDscpValue( $dscp );
                    my $value = $cfgData->{$dd->oiddef($row) .
                                               '.' . $objConfIndex .
                                               '.' . $dscpN};
                    if( defined($value) and $value ne '' )
                    {
                        $value = translateCbQoSValue( $value, $row );
                        $data->{'cbqos_redcfg'}{$objConfIndex}{$dscp}{$row} =
                            $value;
                    }
                }
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
    $data->{'cbqos_toplevel_policymaps_total'} = 0;
    
    my $topNode =
        $cb->addSubtree( $devNode, 'QoS_Stats', undef,
                         ['CiscoIOS_cbQoS::cisco-cbqos-subtree']);

    if( $devdetails->paramDisabled('CiscoIOS_cbQoS::suppress-dropnobuf') )
    {
        $cb->setVar( $topNode, 'CiscoIOS_cbQoS::CMNoBufDrop', 'true' );
    }
    
    # Recursively build a subtree for every policy
    buildChildrenConfigs( $data, $cb, $topNode, '0', '', '', '', '' );

    if( $data->{'cbqos_toplevel_policymaps_total'} == 0 )
    {
        $devNode->removeChild($topNode);
    }
    
    return;
}


sub buildChildrenConfigs
{
    my $data = shift;
    my $cb = shift;
    my $parentNode = shift;
    my $parentObjIndex = shift;
    my $parentObjType = shift;
    my $parentObjName = shift;
    my $parentObjNick = shift;
    my $parentFullName = shift;

    if( not defined( $data->{'cbqos_children'}{$parentObjIndex} ) )
    {
        return;
    }

    my $precedence = 10000;
    
    foreach my $policyObjectIndex
        ( sort { $a <=> $b } @{$data->{'cbqos_children'}{$parentObjIndex}} )
    {      
        my $objectRef     = $data->{'cbqos_objects'}{$policyObjectIndex};
        
        next if $objectRef->{'selectorActions'}{'SkipObect'};

        my $objConfIndex  = $objectRef->{'cbQosConfigIndex'};
        next unless defined($objConfIndex);

        next if $data->{'cbqos_invalid_cfg'}{$objConfIndex};
        
        my $objType       = $objectRef->{'cbQosObjectsType'};
        my $configRef     = $data->{'cbqos_objcfg'}{$objConfIndex};

        my $objectName = '';
        my $subtreeName = '';
        my $subtreeComment = '';
        my $objectNick = '';
        my $param = {
            'cbqos-object-type' => $objType,
            'precedence'        => $precedence--
            };        
        my @templates;

        $param->{'cbqos-parent-type'} = $parentObjType;
        $param->{'cbqos-parent-name'} = $parentObjName;

        if( $data->{'cbqos_persistent_indexing'} )
        {
            $param->{'cbqos-policy-index'} = $objectRef->{'cbQosPolicyIndex'};
            $param->{'cbqos-object-index'} = $objectRef->{'cbQosObjectsIndex'};
        }
        
        my $buildSubtree = 1;
        
        if( $objType eq 'policymap' )
        {
            $objectName = $configRef->{'cbQosPolicyMapName'};

            if( $parentObjIndex eq '0' )
            {
                my $policyIndex = substr($policyObjectIndex, 0,
                                         index($policyObjectIndex, '.'));
            
                my $policyRef = $data->{'cbqos_policies'}{$policyIndex};
                if( not ref( $policyRef ) )
                {
                    next;
                }
                
                my $ifIndex    = $policyRef->{'cbQosIfIndex'};
                if( not defined($ifIndex) )
                {
                    next;
                }
                
                my $interface  = $data->{'interfaces'}{$ifIndex};
                if( not defined( $interface ) or $interface->{'excluded'} )
                {
                    next;
                }

                if( $interface->{'selectorActions'}{'NoQoSStats'} or
                    $objectRef->{'selectorActions'}{'NoQoSStats'} )
                {
                    next;
                }                

                if( $data->{'cbqos_default_skip'} and
                    not $interface->{'selectorActions'}{'QoSStats'} and
                    not $objectRef->{'selectorActions'}{'QoSStats'} )
                {
                    next;
                }

                my $interfaceName = $interface->{'ifDescr'};
                $param->{'cbqos-interface-name'} = $interfaceName;
                $param->{'searchable'} = 'yes';
                
                my $policyNick =
                    $interface->{$data->{'nameref'}{'ifNick'}};

                $subtreeName =
                    $interface->{$data->{'nameref'}{'ifReferenceName'}};
                
                $subtreeComment = $interfaceName;
                
                my $ifType = $policyRef->{'cbQosIfType'};
                $param->{'cbqos-interface-type'} = $ifType;

                if( $ifType eq 'frDLCI' )
                {
                    my $dlci = $policyRef->{'cbQosFrDLCI'};
                    
                    $subtreeName .= ' ' . $dlci;
                    $subtreeComment .= ' DLCI ' . $dlci;
                    $policyNick .= '_' . $dlci;
                    
                    $param->{'cbqos-fr-dlci'} = $dlci;
                }
                elsif( $ifType eq 'atmPVC' )
                {
                    my $vpi = $policyRef->{'cbQosAtmVPI'};
                    my $vci = $policyRef->{'cbQosAtmVCI'};
                    
                    $subtreeName .= ' ' . $vpi . '/' . $vci;
                    $subtreeComment .= ' PVC ' . $vpi . '/' . $vci;
                    $policyNick .= '_' . $vpi . '_' . $vci;
                    
                    $param->{'cbqos-atm-vpi'} = $vpi;
                    $param->{'cbqos-atm-vci'} = $vci;
                }
                elsif( $ifType eq 'controlPlane' )
                {
                    my $ent = $policyRef->{'cbQosEntityIndex'};
                    $policyNick .= '_' . $ent;                        
                    $param->{'cbqos-phy-ent-idx'} = $ent;
                }
                elsif( $ifType eq 'vlanPort' )
                {
                    my $vlan = $policyRef->{'cbQosVlanIndex'};
                    
                    $subtreeName .= ' VLAN' . $vlan;
                    $subtreeComment .= ' VLAN ' . $vlan;
                    $policyNick .= '_' . $vlan;
                    
                    $param->{'cbqos-vlan-idx'} = $vlan;
                }
                elsif( $ifType eq 'evc' )
                {
                    my $evc = $policyRef->{'cbQosEVC'};
                    $policyNick .= '_' . $evc;
                    $param->{'cbqos-evc'} = $evc;
                }
                
                my $direction = $policyRef->{'cbQosPolicyDirection'};
                
                # input -> in, output -> out
                my $dir = $direction;
                $dir =~ s/put$//;
                
                $subtreeName .= ' ' . $dir;
                $subtreeComment .= ' ' . $direction . ' policy';
                $param->{'cbqos-direction'} = $direction;
                $policyNick .=  '_' . $dir;
                
                $param->{'cbqos-policy-nick'} = $policyNick;
                
                my $ifComment =
                    $interface->{$data->{'nameref'}{'ifComment'}};
                if( defined($ifComment) and $ifComment ne '' )
                {
                    $subtreeComment .= ' (' . $ifComment . ')';
                }

                $param->{'nodeid-cbqos-policy'} =
                    'qos//' .
                    $interface->{$data->{'nameref'}{'ifNodeidPrefix'}} .
                    $interface->{$data->{'nameref'}{'ifNodeid'}} .
                    '//' . $dir;

                $data->{'cbqos_toplevel_policymaps_total'}++;
            }
            else
            {
                # Nested policy map
                $subtreeName = $objectName;
                $subtreeComment = 'Policy map: ' . $objectName;
                $objectNick = 'pm_' . $objectName;
            }                

            $param->{'legend'} = 'Policy map:' . $objectName;
            if( defined( $configRef->{'cbQosPolicyMapDesc'} ) and
                $configRef->{'cbQosPolicyMapDesc'} =~ /\w/ )
            {
                $param->{'legend'} .=
                    ';Description:' . $configRef->{'cbQosPolicyMapDesc'};
            }

            push( @templates,
                  'CiscoIOS_cbQoS::cisco-cbqos-policymap-subtree' );
        }
        elsif( $objType eq 'classmap' )
        {
            $objectName = $configRef->{'cbQosCMName'};
            $subtreeName = $objectName;
            $subtreeComment = 'Class: ' . $objectName;
            if( $configRef->{'cbQosCMDesc'} )
            {
                $subtreeComment .= ' (' . $configRef->{'cbQosCMDesc'} . ')';
            }
            $objectNick = 'cm_' . $objectName;
            $param->{'cbqos-class-map-name'} = $objectName;
            push( @templates,
                  'CiscoIOS_cbQoS::cisco-cbqos-classmap-meters' );

            $param->{'legend'} =
                sprintf('Match: %s;', $configRef->{'cbQosCMInfo'});
            if( $configRef->{'cbQosCMDesc'} )
            {
                $param->{'legend'} .=
                    'Description:' . $configRef->{'cbQosCMDesc'} . ';';
            }                
        }
        elsif( $objType eq 'matchStatement' )
        {
            my $name = $configRef->{'cbQosMatchStmtName'};
            $objectName = $name;
            $subtreeName = $name;
            $subtreeComment = 'Match statement statistics';
            $objectNick = 'ms_' . $name;
            $param->{'cbqos-match-statement-name'} = $name;
            push( @templates,
                  'CiscoIOS_cbQoS::cisco-cbqos-match-stmt-meters' );
        }
        elsif( $objType eq 'queueing' )
        {
            my $val = $configRef->{'cbQosQueueingCfgPriorityEnabled'};
            my $priorityQ = (defined($val) and $val eq 'enabled');

            $val = $configRef->{'cbQosQueueingCfgFlowEnabled'};
            my $flowQ = (defined($val) and $val eq 'enabled');

            my $bandwidth = $configRef->{'cbQosQueueingCfgBandwidth'};
            if( not defined($bandwidth) )
            {
                $bandwidth = $configRef->{'cbQosQueueingCfgBandwidth64'};
            }
            
            if( not defined($bandwidth) )
            {
                # a queue without bandwidth does not have any statistics,
                # so we skip it
                next;
            }                

            if( $priorityQ )
            {
                $subtreeName = 'Priority queue';
            }
            elsif( $flowQ )
            {
                $subtreeName = 'Flow queue';
            }
            else
            {
                $subtreeName = 'Queue';
            }
            
            $objectName = $bandwidth;
            my $units = $configRef->{'cbQosQueueingCfgBandwidthUnits'};
            $subtreeName .= ' ' . $bandwidth . ' ' . $units;
            $objectNick = 'qu_' . $bandwidth;
            $param->{'cbqos-queueing-bandwidth'} = $bandwidth;
            my $legend = sprintf('Guaranteed Bandwidth: %d %s;',
                               $bandwidth, $units);


            push( @templates,
                  'CiscoIOS_cbQoS::cisco-cbqos-queueing-meters' );
            $subtreeComment = 'Queueing statistics';
            
            $val = $configRef->{'cbQosQueueingCfgAggregateQLimit'};
            if( defined($val) )
            {
                $legend .=
                    sprintf('Max Queue Size: %d %s;',
                            $val,
                            $configRef->{'cbQosQueueingCfgQLimitUnits'});
            }
            elsif( defined( $configRef->{'cbQosQueueingCfgAggregateQSize'} ) )
            {
                $legend .=
                    sprintf('Max Queue Size: %d packets;',
                            $configRef->{'cbQosQueueingCfgAggregateQSize'});
            }

            $val = $configRef->{'cbQosQueueingCfgIndividualQSize'};
            if( defined($val) and $val > 0 )
            {
                $legend .=
                    sprintf('Individual Flow Queue Size: %d packets;', $val);
            }

            $val = $configRef->{'cbQosQueueingCfgDynamicQNumber'};
            if( defined($val) and $val > 0 )
            {
                $legend .= sprintf('Max Dynamic Queues: %d;', $val);
            }

            $val = $configRef->{'cbQosQueueingCfgPrioBurstSize'};
            if( defined($val) and $val > 0 )
            {
                $legend .= sprintf('Priority Burst Size: %d bytes;', $val);
            }

            $param->{'legend'} = $legend;
        }
        elsif( $objType eq 'randomDetect')
        {
            $subtreeName = 'WRED';
            $objectName = 'WRED';
            $subtreeComment = 'Weighted Random Early Detect Statistics';
            my $val = $configRef->{'cbQosREDCfgExponWeight'};

            if( defined($val) )
            {
                $param->{'legend'} = sprintf('Exponential Weight: %d;', $val);
            }

            push( @templates, 'CiscoIOS_cbQoS::cisco-cbqos-red-subtree' );

            if( $configRef->{'cbQosREDCfgDscpPrec'} == 1 )
            {
                Error('Precedence-based WRED is not supported');
            }
        }
        elsif( $objType eq 'trafficShaping' )
        {
            my $legend = 'Committed Rate: ';
            my $rateType = $configRef->{'cbQosTSCfgRateType'};
            
            if( defined($rateType) and $rateType eq 'percentage' )
            {
                my $pc = $configRef->{'cbQosTSCfgPercentRateValue'};
                $objectName = $pc;
                $subtreeName = sprintf('Shape %d%%', $pc );
                $objectNick = 'ts_' . $pc . '_pc';                
                $legend .= sprintf('%d%%;', $pc);
            }
            else
            {
                my $rate = $configRef->{'cbQosTSCfgRate'};
                if( not defined($rate) )
                {
                    $rate = $configRef->{'cbQosTSCfgRate64'};
                }
                $objectName = $rate;
                $subtreeName = sprintf('Shape %d bps', $rate );
                $objectNick = 'ts_' . $rate;
                $param->{'cbqos-shaping-rate'} = $rate;
                $legend .= sprintf('%d bps;', $rate);
            }

            $subtreeComment = 'Traffic shaping statistics';
            
            push( @templates,
                  'CiscoIOS_cbQoS::cisco-cbqos-shaping-meters' );
            
            my $val = $configRef->{'cbQosTSCfgBurstSize'};
            if( defined($val) )
            {
                $legend .= sprintf('Burst Size: %d bits;', $val);
            }

            $val = $configRef->{'cbQosTSCfgExtBurstSize'};
            if( defined($val) )
            {
                $legend .= sprintf('Ext Burst Size: %d bits;', $val);
            }

            $val = $configRef->{'cbQosTSCfgLimitType'};
            if( defined($val) )
            {
                $legend .= sprintf('Limit: %s;', $val);
            }

            $val = $configRef->{'cbQosTSCfgAdaptiveEnabled'};
            if( defined($val) and $val == 1 )
            {
                $legend .= 'Adaptive: yes;';
            }
            
            $param->{'legend'} = $legend;
        }
        elsif( $objType eq 'police' )
        {
            my $rateType = $configRef->{'cbQosPoliceCfgRateType'};
            my $legend = 'Committed Rate: ';

            if( defined($rateType) and $rateType eq 'percentage' )
            {
                my $pc = $configRef->{'cbQosPoliceCfgPercentRateValue'};
                $objectName = $pc;
                $subtreeName = sprintf('Police %d%%', $pc );
                $objectNick = 'p_' . $pc . '_pc';
                $legend .= sprintf('%d%%;', $pc );
            }
            elsif( defined($rateType) and $rateType eq 'cps' )
            {
                my $cps = $configRef->{'cbQosPoliceCfgCellRate'};
                $objectName = $cps;
                $subtreeName = sprintf('Police %d cps', $cps );
                $objectNick = 'p_' . $cps . '_cps';
                $legend .= sprintf('%d cps;', $cps );
            }
            else
            {
                my $rate = $configRef->{'cbQosPoliceCfgRate'};
                if( not defined($rate) )
                {
                    $rate = $configRef->{'cbQosPoliceCfgRate64'};
                }
                $objectName = $rate;
                $subtreeName = sprintf('Police %d bps', $rate );
                $objectNick = 'p_' . $rate;
                $legend .= sprintf('%d bps;', $rate );
                $param->{'cbqos-police-rate'} = $rate;
            }

            my @labels =
                (
                 'Burst Size: %d Octets',     'cbQosPoliceCfgBurstSize',
                 'Ext Burst Size: %d Octets', 'cbQosPoliceCfgExtBurstSize',
                 'Conform Action: %s',        'cbQosPoliceCfgConformAction',
                 'Conform Set Value: %d',     'cbQosPoliceCfgConformSetValue',
                 'Exceed Action: %s',         'cbQosPoliceCfgExceedAction',
                 'Exceed Set Value: %d',      'cbQosPoliceCfgExceedSetValue',
                 'Violate Action: %s',        'cbQosPoliceCfgViolateAction',
                 'Violate Set Value: %d',     'cbQosPoliceCfgViolateSetValue',
                );

            while( scalar(@labels) )
            {
                my $format = shift @labels;
                my $var = shift @labels;

                my $value = $configRef->{$var};
                if( defined($value) )
                {
                    $legend .= sprintf($format, $value) . ';';
                }
            }
            
            $param->{'legend'} = $legend;
            $subtreeComment = 'Rate policing statistics';
            push( @templates, 'CiscoIOS_cbQoS::cisco-cbqos-police-meters' );
        }
        else
        {
            $buildSubtree = 0;
        }

        if( $buildSubtree )
        {
            $param->{'node-display-name'} = $subtreeName;
            $subtreeName =~ s/\W+/_/g;
            $subtreeName =~ s/_+$//;
            $objectNick =~ s/\W+/_/g;
            $objectNick =~ s/_+$//;

            if( $objectNick )
            {
                if( $parentObjNick ne '' )
                {
		    $objectNick = $parentObjNick . '_' . $objectNick;
                }
                
                $param->{'cbqos-object-nick'} = $objectNick;
            }

	    my $fullName = '';
            if( $parentFullName ) {
                $fullName .= $parentFullName . ':';
            }

            $fullName .= $objectName . ':' . $objTypeMap{$objType};

            if( not $data->{'cbqos_persistent_indexing'} )
            {
                $param->{'cbqos-full-name'} = $fullName;
            }
            
            $param->{'comment'} = $subtreeComment;
            $param->{'cbqos-object-name'} = $objectName;
            $param->{'cbqos-object-descr'} = $subtreeComment;
            
            if( ($parentObjType ne '') and ($parentObjName ne '') )
            {
                $param->{'cbqos-object-descr'} .= ' in ' .
                    $parentObjType . ': ' . $parentObjName;
            }
            
            my $objectNode = $cb->addSubtree( $parentNode, $subtreeName,
                                              $param, \@templates );

            if( $objType eq 'randomDetect')
            {
                my $ref = $data->{'cbqos_redcfg'}{$objConfIndex};
                foreach my $dscp
                    (sort {translateDscpValue($a) <=> translateDscpValue($b)}
                     keys %{$ref})
                {
                    my $cfg = $ref->{$dscp};
                    my $dscpN = translateDscpValue( $dscp );

                    my $redParam = {
                        'comment' => sprintf('DSCP %d', $dscpN),
                        'cbqos-red-dscp' => $dscpN
                        };

                    if( defined( $cfg->{'cbQosREDClassCfgThresholdUnit'} ) )
                    {
                        $redParam->{'legend'} =
                            sprintf('Min Threshold: %d %s;' .
                                    'Max Threshold: %d %s;',
                                    $cfg->{'cbQosREDClassCfgMinThreshold'},
                                    $cfg->{'cbQosREDClassCfgThresholdUnit'},
                                    $cfg->{'cbQosREDClassCfgMaxThreshold'},
                                    $cfg->{'cbQosREDClassCfgThresholdUnit'});
                    }
                    elsif( defined($cfg->{'cbQosREDCfgMinThreshold'}) and
                           defined($cfg->{'cbQosREDCfgMaxThreshold'}) )
                    {
                        $redParam->{'legend'} =
                            sprintf('Min Threshold: %d packets;' .
                                    'Max Threshold: %d packets;',
                                    $cfg->{'cbQosREDCfgMinThreshold'},
                                    $cfg->{'cbQosREDCfgMaxThreshold'});
                    }
                    
                    $cb->addSubtree
                        ( $objectNode, $dscp, $redParam,
                          ['CiscoIOS_cbQoS::cisco-cbqos-red-meters'] );
                }
            }
            else
            {
                # Recursivery build children
                buildChildrenConfigs( $data, $cb, $objectNode,
                                      $policyObjectIndex,
                                      $objType, $objectName, $objectNick,
                                      $fullName);
            }
        }
    }

    return;
}


my $policyActionTranslation = {
    0 => 'unknown',
    1 => 'transmit',
    2 => 'setIpDSCP',
    3 => 'setIpPrecedence',
    4 => 'setQosGroup',
    5 => 'drop',
    6 => 'setMplsExp',
    7 => 'setAtmClp',
    8 => 'setFrDe',
    9 => 'setL2Cos',
    10 => 'setDiscardClass'
    };

my $truthValueTranslation = {
    1 => 'enabled',
    2 => 'disabled'
    };

my $queueUnitTranslation = {
    1 => 'packets',
    2 => 'cells',
    3 => 'bytes',
    4 => 'ms',
    5 => 'us'
    };

my $qosRateType = {
    1 => 'bps',
    2 => 'percentage',
    3 => 'cps',
    4 => 'per_thousand',
    5 => 'per_million',
};

my %cbQosValueTranslation =
    (
     'cbQosIfType' => {
         1 => 'mainInterface',
         2 => 'subInterface',
         3 => 'frDLCI',
         4 => 'atmPVC',
         5 => 'controlPlane',
         6 => 'vlanPort',
         7 => 'evc',
         # this value is not in officeial MIB, but ASR1000 IOS 16.5.1b uses it
         8 => 'tunnel' }, 

     'cbQosPolicyDirection' => {
         1 => 'input',
         2 => 'output' },

     'cbQosObjectsType' => {
         1 => 'policymap',
         2 => 'classmap',
         3 => 'matchStatement',
         4 => 'queueing',
         5 => 'randomDetect',
         6 => 'trafficShaping',
         7 => 'police',
         8 => 'set' },

     'cbQosCMInfo' => {
         1 => 'none',
         2 => 'all',
         3 => 'any'
         },
     
     'cbQosQueueingCfgBandwidthUnits'   => {
         0 => 'bps',  # some routers return this when no bandwidth is defined
         1 => 'kbps',
         2 => 'percent',
         3 => 'percent_remaining',
         4 => 'ratio_remaining',
         5 => 'per_thousand',
         6 => 'per_million',
     },
     
     'cbQosREDClassCfgThresholdUnit'    => $queueUnitTranslation,
     
     'cbQosQueueingCfgFlowEnabled'      => $truthValueTranslation,
     'cbQosQueueingCfgPriorityEnabled'  => $truthValueTranslation,

     'cbQosQueueingCfgQLimitUnits'      => $queueUnitTranslation,
     
     'cbQosTSCfgLimitType' => {
         1 => 'average',
         2 => 'peak'
         },

     'cbQosTSCfgRateType' => $qosRateType,
     
     'cbQosPoliceCfgConformAction'  => $policyActionTranslation,
     'cbQosPoliceCfgExceedAction'   => $policyActionTranslation,
     'cbQosPoliceCfgViolateAction'  => $policyActionTranslation,
     'cbQosPoliceCfgRateType'  => $qosRateType,
    );

sub translateCbQoSValue
{
    my $value = shift;
    my $name = shift;

    # Chop heading and trailing space
    $value =~ s/^\s+//;
    $value =~ s/\s+$//;

    if( defined( $cbQosValueTranslation{$name} ) )
    {
        if( not defined( $cbQosValueTranslation{$name}{$value} ) )
        {
            Error('Unknown value to translate for ' . $name .
                  ': "' . $value . '"');
            return undef;
        }

        $value = $cbQosValueTranslation{$name}{$value};
    }

    return $value;
}


my %dscpValueTranslation =
    (
     'CS1'  => 8,
     'AF11' => 10,
     'AF12' => 12,
     'AF13' => 14,
     'CS2'  => 16,
     'AF21' => 18,
     'AF22' => 20,
     'AF23' => 22,
     'CS3'  => 24,
     'AF31' => 26,
     'AF32' => 28,
     'AF33' => 30,
     'CS4'  => 32,
     'AF41' => 34,
     'AF42' => 36,
     'AF43' => 38,
     'CS5'  => 40,
     'EF'   => 46,
     'CS6'  => 48,
     'CS7'  => 56
     );

sub translateDscpValue
{
    my $value = shift;
    
    if( $value =~ /[a-zA-Z]/ )
    {
        my $val = uc $value;
        if( not defined( $dscpValueTranslation{$val} ) )
        {
            Error('Cannot translate DSCP value: ' . $value );
            $value = 0;
        }
        else
        {
            $value = $dscpValueTranslation{$val};
        }
    }
    return $value;
}


#######################################
# Selectors interface: we're re-using RFC2863_IF_MIB actions
#

{
    foreach my $name ('QoSStats', 'NoQoSStats')
    {
        $Torrus::DevDiscover::RFC2863_IF_MIB::knownSelectorActions{$name} =
            'CiscoIOS_cbQoS';
    }
}

#######################################
# Selectors interface: cbQoS
#

$Torrus::DevDiscover::selectorsRegistry{'cbQoS'} = {
    'getObjects'      => \&getSelectorObjects,
    'getObjectName'   => \&getSelectorObjectName,
    'checkAttribute'  => \&checkSelectorAttribute,
    'applyAction'     => \&applySelectorAction,
};


my %selObjectNameAttr =
    (
     'policymap' => 'cbQosPolicyMapName',
     'classmap'  => 'cbQosCMName'
     );



sub getSelectorObjects
{
    my $devdetails = shift;
    my $objType = shift;

    my $data = $devdetails->data();
    my @ret;

    foreach my $INDEX (sort keys %{$data->{'cbqos_objects'}})
    {
        my $type = $data->{'cbqos_objects'}{$INDEX}{'cbQosObjectsType'};
        if( defined($selObjectNameAttr{$type}) )
        {
            push(@ret, $INDEX);
        }
    }

    return @ret;
}


sub checkSelectorAttribute
{
    my $devdetails = shift;
    my $object = shift;
    my $objType = shift;
    my $attr = shift;
    my $checkval = shift;

    my $data = $devdetails->data();
    my $objectRef = $data->{'cbqos_objects'}{$object};
    my $objConfIndex  = $objectRef->{'cbQosConfigIndex'};
    my $configRef     = $data->{'cbqos_objcfg'}{$objConfIndex};

    my $type = $objectRef->{'cbQosObjectsType'};
    my $value = $configRef->{$selObjectNameAttr{$type}};    
    
    if( ($type eq 'policymap') and ($attr =~ /^PMName\d*$/) )
    {
        return( ($value =~ $checkval) ? 1:0 );
    }
    elsif( ($type eq 'classmap') and ($attr =~ /^CMName\d*$/) )
    {
        return( ($value =~ $checkval) ? 1:0 );
    }

    return 0;
}


sub getSelectorObjectName
{
    my $devdetails = shift;
    my $object = shift;
    my $objType = shift;
    
    my $data = $devdetails->data();
    my $objectRef = $data->{'cbqos_objects'}{$object};
    my $objConfIndex  = $objectRef->{'cbQosConfigIndex'};
    my $configRef     = $data->{'cbqos_objcfg'}{$objConfIndex};

    my $type = $objectRef->{'cbQosObjectsType'};
    my $value = $configRef->{$selObjectNameAttr{$type}};    

    return $type . '::' . $value;
}


# Other discovery modules can add their interface actions here
our %knownSelectorActions;
{
    foreach my $name
        (
         'NoQoSStats',
         'QoSStats',
         'SkipObect',
         )
    {
        $knownSelectorActions{$name} = 'cbQoS';
    }
}

                            
sub applySelectorAction
{
    my $devdetails = shift;
    my $object = shift;
    my $objType = shift;
    my $action = shift;
    my $arg = shift;

    my $data = $devdetails->data();
    my $objectRef = $data->{'cbqos_objects'}{$object};
    
    if( defined( $knownSelectorActions{$action} ) )
    {
        $objectRef->{'selectorActions'}{$action} = $arg;
    }
    else
    {
        Error('Unknown cbQoS selector action: ' . $action);
    }

    return;
}




1;


# Local Variables:
# mode: perl
# indent-tabs-mode: nil
# perl-indent-level: 4
# End:
