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
#  Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.

# $Id$
# Stanislav Sinyagin <ssinyagin@yahoo.com>

package Torrus::Collector::Cisco_cbQoS;

use Torrus::Collector::Cisco_cbQoS_Params;

use Torrus::ConfigTree;
use Torrus::Collector::SNMP;
use Torrus::Log;

use strict;
use Net::hostent;
use Socket;
use Net::SNMP qw(:snmp);

# Register the collector type
$Torrus::Collector::collectorTypes{'cisco-cbqos'} = 1;


# List of needed parameters and default values

$Torrus::Collector::params{'cisco-cbqos'} =
    \%Torrus::Collector::Cisco_cbQoS_Params::requiredLeafParams;

# Copy parameters from SNMP collector
while( my($key, $val) = each %{$Torrus::Collector::params{'snmp'}} )
{
    $Torrus::Collector::params{'cisco-cbqos'}{$key} = $val;
}

my %oiddef =
    (
     # IF-MIB
     'ifDescr'          => '1.3.6.1.2.1.2.2.1.2',

     # CISCO-CLASS-BASED-QOS-MIB
     'cbQosServicePolicyTable'         => '1.3.6.1.4.1.9.9.166.1.1.1',
     'cbQosPolicyIndex'                => '1.3.6.1.4.1.9.9.166.1.1.1.1.1',
     'cbQosIfType'                     => '1.3.6.1.4.1.9.9.166.1.1.1.1.2',
     'cbQosPolicyDirection'            => '1.3.6.1.4.1.9.9.166.1.1.1.1.3',
     'cbQosIfIndex'                    => '1.3.6.1.4.1.9.9.166.1.1.1.1.4',
     'cbQosFrDLCI'                     => '1.3.6.1.4.1.9.9.166.1.1.1.1.5',
     'cbQosAtmVPI'                     => '1.3.6.1.4.1.9.9.166.1.1.1.1.6',
     'cbQosAtmVCI'                     => '1.3.6.1.4.1.9.9.166.1.1.1.1.7',
     # These two are accepted and ignored, probably will be supported later.
     # In some older IOSes these object don't present in the table
     'cbQosEntityIndex'                => '1.3.6.1.4.1.9.9.166.1.1.1.1.8',
     'cbQosVlanIndex'                  => '1.3.6.1.4.1.9.9.166.1.1.1.1.9',

     'cbQosObjectsTable'               => '1.3.6.1.4.1.9.9.166.1.5.1',
     'cbQosObjectsIndex'               => '1.3.6.1.4.1.9.9.166.1.5.1.1.1',
     'cbQosConfigIndex'                => '1.3.6.1.4.1.9.9.166.1.5.1.1.2',
     'cbQosObjectsType'                => '1.3.6.1.4.1.9.9.166.1.5.1.1.3',
     'cbQosParentObjectsIndex'         => '1.3.6.1.4.1.9.9.166.1.5.1.1.4',

     'cbQosPolicyMapName'              => '1.3.6.1.4.1.9.9.166.1.6.1.1.1',
     'cbQosCMName'                     => '1.3.6.1.4.1.9.9.166.1.7.1.1.1',
     'cbQosMatchStmtName'              => '1.3.6.1.4.1.9.9.166.1.8.1.1.1',
     'cbQosQueueingCfgBandwidth'       => '1.3.6.1.4.1.9.9.166.1.9.1.1.1',
     'cbQosPoliceCfgRate'              => '1.3.6.1.4.1.9.9.166.1.12.1.1.1',
     'cbQosTSCfgRate'                  => '1.3.6.1.4.1.9.9.166.1.13.1.1.1',
     );

my %oidrev;

while( my($name, $oid) = each %oiddef )
{
    $oidrev{$oid} = $name;
}

my $policyActionTranslation = {
    'transmit'          => 1,
    'setIpDSCP'         => 2,
    'setIpPrecedence'   => 3,
    'setQosGroup'       => 4,
    'drop'              => 5,
    'setMplsExp'        => 6,
    'setAtmClp'         => 7,
    'setFrDe'           => 8,
    'setL2Cos'          => 9,
    'setDiscardClass'   => 10
    };

my %cbQosValueTranslation =
    (
     'cbQosIfType' => {
         'mainInterface'  => 1,
         'subInterface'   => 2,
         'frDLCI'         => 3,
         'atmPVC'         => 4 },

     'cbQosPolicyDirection' => {
         'input'          => 1,
         'output'         => 2 },

     'cbQosObjectsType' => {
         'policymap'      => 1,
         'classmap'       => 2,
         'matchStatement' => 3,
         'queueing'       => 4,
         'randomDetect'   => 5,
         'trafficShaping' => 6,
         'police'         => 7,
         'set'            => 8 },

     'cbQosPoliceCfgConformAction'  => $policyActionTranslation,
     'cbQosPoliceCfgExceedAction'   => $policyActionTranslation,
     'cbQosPoliceCfgViolateAction'  => $policyActionTranslation
     );


sub translateCbQoSValue
{
    my $value = shift;
    my $name = shift;

    if( defined( $cbQosValueTranslation{$name} ) )
    {
        if( not defined( $cbQosValueTranslation{$name}{$value} ) )
        {
            die('Unknown value to translate for ' . $name .
                ': "' . $value . '"');
        }

        $value = $cbQosValueTranslation{$name}{$value};
    }

    return $value;
}


my %servicePolicyTableParams =
    (
     'cbQosIfType'                     => 'cbqos-interface-type',
     'cbQosPolicyDirection'            => 'cbqos-direction',
     'cbQosFrDLCI'                     => 'cbqos-fr-dlci',
     'cbQosAtmVPI'                     => 'cbqos-atm-vpi',
     'cbQosAtmVCI'                     => 'cbqos-atm-vci'
     );


# This list defines the order for entries mapping in
# $cref->{'ServicePolicyMapping'}

my @servicePolicyTableEntries =
    ( 'cbQosIfType', 'cbQosPolicyDirection', 'cbQosIfIndex',
      'cbQosFrDLCI', 'cbQosAtmVPI', 'cbQosAtmVCI' );


my %objTypeAttributes =
    (
     # 'policymap'
     1 => {
         'name-oid'   => 'cbQosPolicyMapName' },

     # 'classmap'
     2 => {
         'name-param' => 'cbqos-class-map-name',
         'name-oid'   => 'cbQosCMName' },
     
     # 'matchStatement'
     3 => {
         'name-param' => 'cbqos-match-statement-name',
         'name-oid'   => 'cbQosMatchStmtName' },

     # 'queueing'
     4 => {
         'name-param' => 'cbqos-queueing-bandwidth',
         'name-oid'   => 'cbQosQueueingCfgBandwidth' },

     # 'randomDetect'     
     5 => {},
     
     # 'trafficShaping'
     6 => {
         'name-param' => 'cbqos-shaping-rate',
         'name-oid'   => 'cbQosTSCfgRate' },
     
     # 'police'
     7 => {
         'name-param' => 'cbqos-police-rate',
         'name-oid'   => 'cbQosPoliceCfgRate' }
     );


# This is first executed per target

$Torrus::Collector::initTarget{'cisco-cbqos'} =
    \&Torrus::Collector::Cisco_cbQoS::initTarget;

# Derive 'snmp-object' from cbQoS maps and pass the control to SNMP collector

sub initTarget
{
    my $collector = shift;
    my $token = shift;

    my $tref = $collector->tokenData( $token );
    my $cref = $collector->collectorData( 'cisco-cbqos' );

    $cref->{'QosEnabled'}{$token} = 1;
    
    $collector->registerDeleteCallback
        ( $token, \&Torrus::Collector::Cisco_cbQoS::deleteTarget );
    
    my $ipaddr =
        Torrus::Collector::SNMP::getHostIpAddress( $collector, $token );
    if( not defined( $ipaddr ) )
    {
        $collector->deleteTarget($token);
        return 0;
    }
    $tref->{'ipaddr'} = $ipaddr;

    return Torrus::Collector::Cisco_cbQoS::initTargetAttributes
        ( $collector, $token );
}


sub initTargetAttributes
{
    my $collector = shift;
    my $token = shift;

    my $tref = $collector->tokenData( $token );
    my $cref = $collector->collectorData( 'cisco-cbqos' );

    if( Torrus::Collector::SNMP::activeMappingSessions() > 0 )
    {
        # ifDescr mapping tables are not yet ready
        $cref->{'cbQoSNeedsRemapping'}{$token} = 1;
        return 1;
    }

    my $ipaddr = $tref->{'ipaddr'};
    my $port = $collector->param($token, 'snmp-port');

    my $version = $collector->param($token, 'snmp-version');
    my $community;
    if( $version eq '1' or $version eq '2c' )
    {
        $community = $collector->param($token, 'snmp-community');
    }
    else
    {
        # We use community string to identify the agent.
        # For SNMPv3, it's the user name
        $community = $collector->param($token, 'snmp-username');
    }

    my $hosthash = join('|', $ipaddr, $port, $community);
    $tref->{'hosthash'} = $hosthash;
    
    if( Torrus::Collector::SNMP::isHostDead( $collector, $hosthash ) )
    {
        return 0;
    }

    if( not Torrus::Collector::SNMP::checkUnreachableRetry
        ( $collector, $hosthash ) )
    {
        return 1;
    }

    my $ifDescr = $collector->param($token, 'cbqos-interface-name');
    my $ifIndex =
        Torrus::Collector::SNMP::lookupMap( $collector, $token,
                                            $hosthash,
                                            $oiddef{'ifDescr'}, $ifDescr );

    if( not defined( $ifIndex ) )
    {
        Debug('ifDescr mapping tables are not yet ready for ' . $hosthash);
        $cref->{'cbQoSNeedsRemapping'}{$token} = 1;
        return 1;
    }
    elsif( $ifIndex eq 'notfound' )
    {
        Error("Cannot find ifDescr mapping for $ifDescr at $hosthash");
        return undef;
    }
    
    my $session = Torrus::Collector::SNMP::openBlockingSession
        ( $collector, $token, $hosthash );
    if( not defined($session) )
    {
        return 0;
    }

    # Retrieve and translate cbQosServicePolicyTable

    if( not defined $cref->{'ServicePolicyTable'}{$hosthash} )
    {
        Debug("Retrieving Cisco cbQoS maps from $ipaddr");

        my $ref = {};
        $cref->{'ServicePolicyTable'}{$hosthash} = $ref;

        my $result =
            $session->get_table( -baseoid =>
                                 $oiddef{'cbQosServicePolicyTable'} );
        if( not defined( $result ) )
        {
            Error("Error retrieving cbQosServicePolicyTable from $ipaddr: " .
                  $session->error());
            
            # When the remote agent is reacheable, but system objecs are
            # not implemented, we get a positive error_status
            if( $session->error_status() == 0 )
            {
                return Torrus::Collector::SNMP::probablyDead
                    ( $collector, $hosthash );
            }
            else
            {
                return 0;
            }
        }

        while( my( $oid, $val ) = each %{$result} )
        {
            my $prefixlen = rindex( $oid, '.' );
            my $prefixOid = substr( $oid, 0, $prefixlen );
            my $policyIndex = substr( $oid, $prefixlen + 1 );

            my $entryName = $oidrev{$prefixOid};
            if( not defined $entryName )
            {
                Warn("Unknown OID: $prefixOid");
            }
            else
            {
                $ref->{$policyIndex}{$entryName} = $val;
            }
        }

        my $mapRef = {};
        $cref->{'ServicePolicyMapping'}{$hosthash} = $mapRef;

        foreach my $policyIndex ( keys %{$ref} )
        {
            my $mapString = '';
            foreach my $entryName ( @servicePolicyTableEntries )
            {
                $mapString .=
                    sprintf( '%d:', $ref->{$policyIndex}{$entryName} );
            }
            $mapRef->{$mapString} = $policyIndex;
        }
    }

    # Retrieve config information from cbQosxxxCfgTable

    if( not defined $cref->{'CfgTable'}{$hosthash} )
    {
        my $ref = {};
        $cref->{'CfgTable'}{$hosthash} = $ref;

        foreach my $table ( 'cbQosPolicyMapName', 'cbQosCMName',
                            'cbQosMatchStmtName', 'cbQosQueueingCfgBandwidth',
                            'cbQosTSCfgRate', 'cbQosPoliceCfgRate' )
        {
            my $result = $session->get_table( -baseoid => $oiddef{$table} );
            if( defined( $result ) )
            {
                while( my( $oid, $val ) = each %{$result} )
                {
                    # Chop heading and trailing space
                    $val =~ s/^\s+//;
                    $val =~ s/\s+$//;

                    my $prefixlen = rindex( $oid, '.' );
                    my $prefixOid = substr( $oid, 0, $prefixlen );
                    my $cfgIndex = substr( $oid, $prefixlen + 1 );

                    my $entryName = $oidrev{$prefixOid};
                    if( not defined $entryName )
                    {
                        Warn("Unknown OID: $prefixOid");
                    }
                    else
                    {
                        $ref->{$cfgIndex}{$entryName} = $val;
                    }
                }
            }
        }
    }

    # Retrieve and translate cbQosObjectsTable

    if( not defined $cref->{'ObjectsTable'}{$hosthash} )
    {
        my $ref = {};
        $cref->{'ObjectsTable'}{$hosthash} = $ref;

        my $result =
            $session->get_table( -baseoid =>
                                 $oiddef{'cbQosObjectsTable'} );
        if( not defined( $result ) )
        {
            Error("Error retrieving cbQosObjectsTable from $ipaddr: " .
                  $session->error());

            # When the remote agent is reacheable, but system objecs are
            # not implemented, we get a positive error_status
            if( $session->error_status() == 0 )
            {
                return Torrus::Collector::SNMP::probablyDead
                    ( $collector, $hosthash );
            }
            else
            {
                return 0;
            }
        }

        my $confIndexOid = $oiddef{'cbQosConfigIndex'};
        my $objTypeOid = $oiddef{'cbQosObjectsType'};

        my %objects;
        my %objPolicyIdx;

        while( my( $oid, $val ) = each %{$result} )
        {
            my $prefixlen = rindex( $oid, '.' );
            my $objIndex = substr( $oid, $prefixlen + 1 );
            my $prefixOid = substr( $oid, 0, $prefixlen );

            $prefixlen = rindex( $prefixOid, '.' );
            my $policyIndex = substr( $prefixOid, $prefixlen + 1 );
            $prefixOid = substr( $prefixOid, 0, $prefixlen );

            my $entryName = $oidrev{$prefixOid};

            $objects{$objIndex}{$entryName} = $val;
            $objPolicyIdx{$objIndex} = $policyIndex;
        }

        while( my( $objIndex, $attr ) = each %objects )
        {
            my $policyIndex = $objPolicyIdx{$objIndex};

            my $objType = $attr->{'cbQosObjectsType'};
            next if not defined( $objTypeAttributes{$objType} );
                                
            # Compose the object ID as "parent:type:name" string
            my $objectID = '';
            
            my $parentIndex = $attr->{'cbQosParentObjectsIndex'};
            if( $parentIndex > 0 )
            {
                my $parentType = $objects{$parentIndex}{'cbQosObjectsType'};

                my $parentCfgIndex =
                    $objects{$parentIndex}{'cbQosConfigIndex'};
                
                my $parentNameOid =
                    $objTypeAttributes{$parentType}{'name-oid'};

                my $parentName = 
                    $cref->{'CfgTable'}{$hosthash}{
                        $parentCfgIndex}{$parentNameOid};
                
                $objectID .= $parentName . ':';
            }

            $objectID .= $objType  . ':';

            my $objCfgIndex = $attr->{'cbQosConfigIndex'};

            my $objNameOid = $objTypeAttributes{$objType}{'name-oid'};

            if( defined($objNameOid) )
            {
                $objectID .= $cref->{'CfgTable'}{$hosthash}{
                    $objCfgIndex}{$objNameOid};
            }
            
            $ref->{$policyIndex}{$objectID} = $objIndex;
        }
    }

    # Finished retrieving tables
    # now find the snmp-object from token parameters

    # Prepare values for cbQosServicePolicyTable match
    
    my %policyParamValues = ( 'cbQosIfIndex' => $ifIndex );
    while( my($name, $param) = each %servicePolicyTableParams )
    {
        my $val = $collector->param($token, $param);
        $val = translateCbQoSValue( $val, $name );
        $policyParamValues{$name} = $val;
    }

    # Find the entry in cbQosServicePolicyTable

    my $mapRef = $cref->{'ServicePolicyMapping'}{$hosthash};

    my $mapString = '';
    foreach my $entryName ( @servicePolicyTableEntries )
    {
        $mapString .=
            sprintf( '%d:', $policyParamValues{$entryName} );
    }

    my $thePolicyIndex = $mapRef->{$mapString};
    if( not defined( $thePolicyIndex ) )
    {
        Error('Cannot find cbQosServicePolicyTable mapping for ' .
              $mapString);
        return undef;
    }

    # compose the object ID from token parameters as "parent:type:name" string

    my $theObjectID = $collector->param($token, 'cbqos-parent-name');
    if( length( $theObjectID ) > 0 )
    {
        $theObjectID .= ':';
    }

    my $theObjectType =
        translateCbQoSValue( $collector->param($token, 'cbqos-object-type'),
                             'cbQosObjectsType' );

    $theObjectID .= $theObjectType . ':';

    my $objNameParam = $objTypeAttributes{$theObjectType}{'name-param'};
    if( defined($objNameParam) )
    {
        $theObjectID .= $collector->param( $token, $objNameParam );
    }
    
    my $theObjectIndex = $cref->{'ObjectsTable'}{$hosthash}->{
        $thePolicyIndex}{$theObjectID};

    if( not defined( $theObjectIndex ) )
    {
        Error('Cannot find object index for ' . $thePolicyIndex . ':' .
              $theObjectType . '--' . $theObjectID);
        return undef;
    }

    # Finally we got the object to monitor!

    # Prepare the object for snmp collector
    my $theOid = $collector->param( $token, 'snmp-object' );
    $theOid =~ s/POL/$thePolicyIndex/;
    $theOid =~ s/OBJ/$theObjectIndex/;
    $collector->setParam( $token, 'snmp-object', $theOid );

    return Torrus::Collector::SNMP::initTargetAttributes( $collector, $token );
}


# Main collector cycle is actually the SNMP collector

$Torrus::Collector::runCollector{'cisco-cbqos'} =
    \&Torrus::Collector::SNMP::runCollector;


# Execute this after the collector has finished

$Torrus::Collector::postProcess{'cisco-cbqos'} =
    \&Torrus::Collector::Cisco_cbQoS::postProcess;

sub postProcess
{
    my $collector = shift;
    my $cref = shift;

    # We use some SNMP collector internals
    my $scref = $collector->collectorData( 'snmp' );

    # Flush all QoS object mapping
    foreach my $token ( keys %{$scref->{'needsRemapping'}},
                        keys %{$cref->{'cbQoSNeedsRemapping'}} )
    {
        if( $cref->{'QosEnabled'}{$token} )
        {
            my $tref = $collector->tokenData( $token );
            my $hosthash = $tref->{'hosthash'};    
            
            delete $cref->{'ServicePolicyTable'}{$hosthash};
            delete $cref->{'ServicePolicyMapping'}{$hosthash};
            delete $cref->{'ObjectsTable'}{$hosthash};
            delete $cref->{'CfgTable'}{$hosthash};
            
            delete $scref->{'needsRemapping'}{$token};
            delete $cref->{'cbQoSNeedsRemapping'}{$token};
            if( not Torrus::Collector::Cisco_cbQoS::initTargetAttributes
                ( $collector, $token ) )
            {
                $collector->deleteTarget($token);
            }
        }
    }
}


# Callback executed by Collector

sub deleteTarget
{
    my $collector = shift;
    my $token = shift;

    my $cref = $collector->collectorData( 'cisco-cbqos' );

    delete $cref->{'QosEnabled'}{$token};

    Torrus::Collector::SNMP::deleteTarget( $collector, $token );
}
    

1;


# Local Variables:
# mode: perl
# indent-tabs-mode: nil
# perl-indent-level: 4
# End:
