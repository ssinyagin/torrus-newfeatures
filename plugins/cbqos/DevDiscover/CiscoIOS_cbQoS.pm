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

# Stanislav Sinyagin <ssinyagin@yahoo.com>

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
     'cbQosPoliceCfgRateType'          => '1.3.6.1.4.1.9.9.166.1.12.1.1.12',

     'cbQosTSCfgTable'                 => '1.3.6.1.4.1.9.9.166.1.13.1',
     'cbQosTSCfgRate'                  => '1.3.6.1.4.1.9.9.166.1.13.1.1.1',
     'cbQosTSCfgBurstSize'             => '1.3.6.1.4.1.9.9.166.1.13.1.1.2',
     'cbQosTSCfgExtBurstSize'          => '1.3.6.1.4.1.9.9.166.1.13.1.1.3',
     'cbQosTSCfgAdaptiveEnabled'       => '1.3.6.1.4.1.9.9.166.1.13.1.1.4',
     'cbQosTSCfgLimitType'             => '1.3.6.1.4.1.9.9.166.1.13.1.1.6',
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
    
    while( my($INDEX, $value) = each %{$cbQosObjectsType} )
    {
        $data->{'cbqos_objects'}{$INDEX}{'cbQosObjectsType'} =
            translateCbQoSValue( $value, 'cbQosObjectsType' );
    }

    my $cbQosConfigIndex =
        $dd->walkSnmpTable('cbQosConfigIndex');
    my $cbQosParentObjectsIndex =
        $dd->walkSnmpTable('cbQosParentObjectsIndex');
    
    my $needTables = {};

    foreach my $INDEX (keys %{$data->{'cbqos_objects'}})
    {
        my ($policyIndex, $objectIndex) = split(/\./o, $INDEX);

        if( not exists( $data->{'cbqos_policies'}{$policyIndex} ) )
        {
            delete $data->{'cbqos_objects'}{$INDEX};
            next;
        }

        my $object = $data->{'cbqos_objects'}{$INDEX};
        $object->{'cbQosPolicyIndex'} = $policyIndex;
        $object->{'cbQosConfigIndex'} = $cbQosConfigIndex->{$INDEX};

        my $objType = $object->{'cbQosObjectsType'};

        # Store only objects of supported types
        my $takeit = $supportedObjectTypes{$objType};

        # Suppress unneeded objects
        if( $takeit and
            $devdetails->paramEnabled('CiscoIOS_cbQoS::classmaps-only')
            and
            $objType ne 'policymap' and
            $objType ne 'classmap' )
        {
            $takeit = 0;
        }
        
        if( $takeit and
            $devdetails->paramEnabled
            ('CiscoIOS_cbQoS::suppress-match-statements')
            and
            $objType eq 'matchStatement' )
        {
            $takeit = 0;
        }

        if( $takeit )
        {
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
        else
        {
            delete $data->{'cbqos_objects'}{$INDEX};
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
                  'cbQosQueueingCfgAggregateQLimit' );
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
            push( @rows,
                  'cbQosTSCfgRate',
                  'cbQosTSCfgBurstSize',
                  'cbQosTSCfgExtBurstSize',
                  'cbQosTSCfgAdaptiveEnabled',
                  'cbQosTSCfgLimitType' );
            $mandatory{'cbQosTSCfgRate'} = 1;
        }
        elsif( $objType eq 'police' )
        {
            # if cbQosPoliceCfgRateType specifies other than bps, the
            # collector cannot use cbQosPoliceCfgRate as a name index, and
            # that complicates things. Probably someday someone sponsors a fix
            my $val = $cfgData->{$dd->oiddef('cbQosPoliceCfgRateType') .'.'.
                                     $objConfIndex};
            if( defined($val) and $val != 1 )
            {
                Warn('cbQosPoliceCfgRateType for ' . $objConfIndex .
                     ' has unsupported value(' . $val . ')');
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
                  'cbQosPoliceCfgViolateSetValue' );
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
                     'cbQosConfigIndex=' . $objConfIndex . ', row=' . $row);
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

    my $topNode =
        $cb->addSubtree( $devNode, 'QoS_Stats', undef,
                         ['CiscoIOS_cbQoS::cisco-cbqos-subtree']);

    if( $devdetails->paramDisabled('CiscoIOS_cbQoS::suppress-dropnobuf') )
    {
        $cb->setVar( $topNode, 'CiscoIOS_cbQoS::CMNoBufDrop', 'true' );
    }
    
    # Recursively build a subtree for every policy

    buildChildrenConfigs( $data, $cb, $topNode, '0', '', '', '', '' );
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

                if( defined( $interface ) and not $interface->{'excluded'} )
                {
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
                }
                else
                {
                    $buildSubtree = 0;
                }
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
            my $bandwidth = $configRef->{'cbQosQueueingCfgBandwidth'};
            $objectName = $bandwidth;

            my $units = $configRef->{'cbQosQueueingCfgBandwidthUnits'};

            $subtreeName = 'Bandwidth ' . $bandwidth . ' ' . $units;
            $subtreeComment = 'Queueing statistics';
            $objectNick = 'qu_' . $bandwidth;
            $param->{'cbqos-queueing-bandwidth'} = $bandwidth;
            push( @templates,
                  'CiscoIOS_cbQoS::cisco-cbqos-queueing-meters' );

            my $legend = sprintf('Guaranteed Bandwidth: %d %s;',
                                 $bandwidth, $units);

            my $val = $configRef->{'cbQosQueueingCfgFlowEnabled'};
            if( defined($val) )
            {
                $legend .= 'Flow: ' . $val . ';';
            }

            $val = $configRef->{'cbQosQueueingCfgPriorityEnabled'};
            if( defined($val) )
            {
                $legend .= 'Priority: ' . $val . ';';
            }
            
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
            $param->{'legend'} =
                sprintf('Exponential Weight: %d;',
                        $configRef->{'cbQosREDCfgExponWeight'});
            push( @templates,
                  'CiscoIOS_cbQoS::cisco-cbqos-red-subtree' );

            if( $configRef->{'cbQosREDCfgDscpPrec'} == 1 )
            {
                Error('Precedence-based WRED is not supported');
            }
        }
        elsif( $objType eq 'trafficShaping' )
        {
            my $rate = $configRef->{'cbQosTSCfgRate'};
            $objectName = $rate;
            $subtreeName = sprintf('Shape %d bps', $rate );
            $subtreeComment = 'Traffic shaping statistics';
            $objectNick = 'ts_' . $rate;
            $param->{'cbqos-shaping-rate'} = $rate;
            push( @templates,
                  'CiscoIOS_cbQoS::cisco-cbqos-shaping-meters' );

            my $legend = sprintf('Committed Rate: %d bits/second;', $rate);
            
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
            my $rate = $configRef->{'cbQosPoliceCfgRate'};
            $objectName = $rate;

            $subtreeName = sprintf('Police %d bps', $rate );
            $subtreeComment = 'Rate policing statistics';
            $objectNick = 'p_' . $rate;
            $param->{'cbqos-police-rate'} = $rate;
            push( @templates,
                  'CiscoIOS_cbQoS::cisco-cbqos-police-meters' );

            $param->{'legend'} =
                sprintf('Committed Rate: %d bits/second;' .
                        'Burst Size: %d Octets;' .
                        'Ext Burst Size: %d Octets;' .
                        'Conform Action: %s;' .
                        'Conform Set Value: %d;' .
                        'Exceed Action: %s;' .
                        'Exceed Set Value: %d;' .
                        'Violate Action: %s;' .
                        'Violate Set Value: %d',
                        $rate,
                        $configRef->{'cbQosPoliceCfgBurstSize'},
                        $configRef->{'cbQosPoliceCfgExtBurstSize'},
                        $configRef->{'cbQosPoliceCfgConformAction'},
                        $configRef->{'cbQosPoliceCfgConformSetValue'},
                        $configRef->{'cbQosPoliceCfgExceedAction'},
                        $configRef->{'cbQosPoliceCfgExceedSetValue'},
                        $configRef->{'cbQosPoliceCfgViolateAction'},
                        $configRef->{'cbQosPoliceCfgViolateSetValue'});
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

            $param->{'cbqos-full-name'} = $fullName;
            $param->{'comment'} = $subtreeComment;
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
                    else
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


my %cbQosValueTranslation =
    (
     'cbQosIfType' => {
         1 => 'mainInterface',
         2 => 'subInterface',
         3 => 'frDLCI',
         4 => 'atmPVC',
         5 => 'controlPlane',
         6 => 'vlanPort',
         7 => 'evc' },

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
         4 => 'ratio_remaining'
         },
     
     'cbQosREDClassCfgThresholdUnit'    => $queueUnitTranslation,
     
     'cbQosQueueingCfgFlowEnabled'      => $truthValueTranslation,
     'cbQosQueueingCfgPriorityEnabled'  => $truthValueTranslation,

     'cbQosQueueingCfgQLimitUnits'      => $queueUnitTranslation,
     
     'cbQosTSCfgLimitType' => {
         1 => 'average',
         2 => 'peak'
         },
     
     'cbQosPoliceCfgConformAction'  => $policyActionTranslation,
     'cbQosPoliceCfgExceedAction'   => $policyActionTranslation,
     'cbQosPoliceCfgViolateAction'  => $policyActionTranslation
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


1;


# Local Variables:
# mode: perl
# indent-tabs-mode: nil
# perl-indent-level: 4
# End:
