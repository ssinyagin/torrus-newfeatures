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

# Stanislav Sinyagin <ssinyagin@yahoo.com>

## no critic (Modules::RequireFilenameMatchesPackage)


package Torrus::Collector::Cisco_cbQoS;

use Torrus::Collector::Cisco_cbQoS_Params;

use strict;
use warnings;

use Torrus::ConfigTree;
use Torrus::Collector::SNMP;
use Torrus::Log;
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
         'atmPVC'         => 4,
         'controlPlane'   => 5,
         'vlanPort'       => 6,
         'evc'            => 7,
     },

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
     );


sub translateCbQoSValue
{
    my $value = shift;
    my $name = shift;

    if( defined($value) )
    {
        if( defined( $cbQosValueTranslation{$name} ) )
        {
            if( not defined( $cbQosValueTranslation{$name}{$value} ) )
            {
                die('Unknown value to translate for ' . $name .
                    ': "' . $value . '"');
            }
            
            $value = $cbQosValueTranslation{$name}{$value};
        }
    }
    else
    {
        $value = 0;
    }

    return $value;
}


my %servicePolicyTableParams =
    (
     'cbQosIfType'                     => 'cbqos-interface-type',
     'cbQosPolicyDirection'            => 'cbqos-direction',
     'cbQosFrDLCI'                     => 'cbqos-fr-dlci',
     'cbQosAtmVPI'                     => 'cbqos-atm-vpi',
     'cbQosAtmVCI'                     => 'cbqos-atm-vci',
     'cbQosEntityIndex'                => 'cbqos-phy-ent-idx',
     'cbQosVlanIndex'                  => 'cbqos-vlan-idx',
     'cbQosEVC'                        => 'cbqos-evc',
     );


# This list defines the order for entries mapping in
# $ServicePolicyMapping

my @servicePolicyTableEntries =
    ( 'cbQosIfType', 'cbQosPolicyDirection', 'cbQosIfIndex',
      'cbQosFrDLCI', 'cbQosAtmVPI', 'cbQosAtmVCI',
      'cbQosEntityIndex', 'cbQosVlanIndex', 'cbQosEVC' );


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

my %ServicePolicyTable;
my %ServicePolicyMapping;
my %ObjectsTable;
my %CfgTable;
our $qosTablesRetrieveAfterStartMinInterval = 150;

# This is first executed per target

$Torrus::Collector::initTarget{'cisco-cbqos'} = \&initTarget;

# Derive 'snmp-object' from cbQoS maps and pass the control to SNMP collector

sub initTarget
{
    my $collector = shift;
    my $token = shift;

    my $tref = $collector->tokenData( $token );
    my $cref = $collector->collectorData( 'cisco-cbqos' );

    $cref->{'ciscoQosEnabled'}{$token} = 1;
    
    $collector->registerDeleteCallback( $token, \&deleteTarget );
    
    my $hosthash = 
        Torrus::Collector::SNMP::getHostHash( $collector, $token );
    if( not defined( $hosthash ) )
    {
        $collector->deleteTarget($token);
        return 0;
    }
    $tref->{'hosthash'} = $hosthash;

    return initTargetAttributes( $collector, $token );
}


# Recursively create the object name

sub make_full_name
{
    my $objhash = shift;
    my $hosthash = shift;
    my $attr = shift;
    my $cref = shift;
    

    # Compose the object ID as "parent:type:name" string
    my $objectID = '';
    
    my $parentIndex = $attr->{'cbQosParentObjectsIndex'};
    if( $parentIndex > 0 )
    {
	$objectID =
            make_full_name($objhash, $hosthash,
                           $objhash->{$parentIndex}, $cref);
    }

    if( $objectID ) {
        $objectID .= ':';
    }

    my $objType = $attr->{'cbQosObjectsType'};

    my $objCfgIndex = $attr->{'cbQosConfigIndex'};
    
    my $objNameOid = $objTypeAttributes{$objType}{'name-oid'};

    if( defined($objNameOid) )
    {
        my $name = $CfgTable{$hosthash}{$objCfgIndex}{$objNameOid};
        if( defined($name) )
        {
            $objectID .= $name;
        }
    }
    
    $objectID .= ':' . $objType;

    return $objectID;
}


sub initTargetAttributes
{
    my $collector = shift;
    my $token = shift;

    my $tref = $collector->tokenData( $token );
    my $cref = $collector->collectorData( 'cisco-cbqos' );
    my $hosthash = $tref->{'hosthash'};

    if( $collector->param( $token, 'cbqos-persistent-indexing' ) eq 'yes' )
    {
        # Prepare the object for snmp collector
        my $oid = $collector->param( $token, 'snmp-object' );
        my $policyIndex = $collector->param( $token, 'cbqos-policy-index' );
        my $objectIndex = $collector->param( $token, 'cbqos-object-index' );
        $oid =~ s/POL/$policyIndex/;
        $oid =~ s/OBJ/$objectIndex/;
        $collector->setParam( $token, 'snmp-object', $oid );
        
        return Torrus::Collector::SNMP::initTargetAttributes
            ( $collector, $token );
    }
    
    if( not Torrus::Collector::SNMP::isMapReady($hosthash,
                                                $oiddef{'ifDescr'}) )
    {
        # ifDescr mapping tables are not yet ready
        $cref->{'cbQoSNeedsRemapping'}{$token} = 1;
        return 1;
    }

    
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

    # Net::SNMP does not allow blocking sessions while non-blocking sessions
    # still exist. We flush them here
    Torrus::Collector::SNMP::start_snmp_dispatcher();
        
    my $session = Torrus::Collector::SNMP::openBlockingSession
        ( $collector, $token, $hosthash );
    if( not defined($session) )
    {
        return 0;
    }

    my $maxrepetitions = $collector->param($token, 'snmp-maxrepetitions');

    # Retrieve and translate cbQosServicePolicyTable

    if( not defined $ServicePolicyTable{$hosthash} )
    {
        Debug('Retrieving Cisco cbQoS maps from ' . $hosthash);

        my $ref = {};
        $ServicePolicyTable{$hosthash} = $ref;

        my $result =
            $session->get_table
            ( -baseoid => $oiddef{'cbQosServicePolicyTable'},
              -maxrepetitions => $maxrepetitions );
        if( not defined( $result ) )
        {
            Error('Error retrieving cbQosServicePolicyTable from ' .
                  $hosthash . ': ' . $session->error());
            
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
            if( defined($entryName) )
            {
                $ref->{$policyIndex}{$entryName} = $val;
            }
        }

        my $mapRef = {};
        $ServicePolicyMapping{$hosthash} = $mapRef;

        foreach my $policyIndex ( keys %{$ref} )
        {
            my $mapString = '';
            foreach my $entryName ( @servicePolicyTableEntries )
            {
                my $value = $ref->{$policyIndex}{$entryName};
                $value = 0 unless defined($value);
                $mapString .= sprintf( '%d:', $value );
            }
            $mapRef->{$mapString} = $policyIndex;
        }
    }

    # Retrieve config information from cbQosxxxCfgTable

    if( not defined $CfgTable{$hosthash} )
    {
        my $ref = {};
        $CfgTable{$hosthash} = $ref;

        foreach my $table ( 'cbQosPolicyMapName', 'cbQosCMName',
                            'cbQosMatchStmtName', 'cbQosQueueingCfgBandwidth',
                            'cbQosTSCfgRate', 'cbQosPoliceCfgRate' )
        {
            my $result =
                $session->get_table( -baseoid => $oiddef{$table},
                                     -maxrepetitions => $maxrepetitions );
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

    if( not defined $ObjectsTable{$hosthash} )
    {
        my $ref = {};
        $ObjectsTable{$hosthash} = $ref;

        my $result =
            $session->get_table( -baseoid => $oiddef{'cbQosObjectsTable'},
                                 -maxrepetitions => $maxrepetitions );
        if( not defined( $result ) )
        {
            Error('Error retrieving cbQosObjectsTable from ' . $hosthash .
                  ': ' . $session->error());

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

        while( my( $oid, $val ) = each %{$result} )
        {
            my $prefixlen = rindex( $oid, '.' );
            my $objIndex = substr( $oid, $prefixlen + 1 );
            my $prefixOid = substr( $oid, 0, $prefixlen );

            $prefixlen = rindex( $prefixOid, '.' );
            my $policyIndex = substr( $prefixOid, $prefixlen + 1 );
            $prefixOid = substr( $prefixOid, 0, $prefixlen );

            my $entryName = $oidrev{$prefixOid};

            $objects{$policyIndex}{$objIndex}{$entryName} = $val;
        }

        while( my( $policyIndex, $objhash ) = each %objects )
        {
            while( my( $objIndex, $attr ) = each %{$objhash} )
            {
                my $objType = $attr->{'cbQosObjectsType'};
                next if not defined( $objTypeAttributes{$objType} );

                my $objectID =
                    make_full_name( $objhash, $hosthash, $attr, $cref );

                $ref->{$policyIndex}{$objectID} = $objIndex;
            }
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

    my $mapRef = $ServicePolicyMapping{$hosthash};

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

    my $theObjectID = $collector->param($token, 'cbqos-full-name');
    
    my $theObjectIndex = $ObjectsTable{$hosthash}->{
        $thePolicyIndex}{$theObjectID};

    if( not defined( $theObjectIndex ) )
    {
        Error('Cannot find object index for ' . $thePolicyIndex . ':' .
              '--' . $theObjectID);
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

$Torrus::Collector::postProcess{'cisco-cbqos'} = \&postProcess;

sub postProcess
{
    my $collector = shift;
    my $cref = shift;

    # We use some SNMP collector internals
    my $scref = $collector->collectorData( 'snmp' );

    my %remapping_hosts;
    
    # Flush all QoS object mapping
    foreach my $token ( keys %{$scref->{'needsRemapping'}},
                        keys %{$cref->{'cbQoSNeedsRemapping'}} )
    {
        if( $cref->{'ciscoQosEnabled'}{$token} )
        {
            my $tref = $collector->tokenData( $token );
            my $hosthash = $tref->{'hosthash'};    

            if( not defined($remapping_hosts{$hosthash}) )
            {
                $remapping_hosts{$hosthash} = [];
            }
            push(@{$remapping_hosts{$hosthash}}, $token);
        }
    }

    while(my ($hosthash, $tokens) = each %remapping_hosts )
    {
        if( time() - $collector->whenStarted() >
            $qosTablesRetrieveAfterStartMinInterval )
        {
            Debug('Flushing Cisco cbQoS maps for ' . $hosthash);
            delete $ServicePolicyTable{$hosthash};
            delete $ServicePolicyMapping{$hosthash};
            delete $ObjectsTable{$hosthash};
            delete $CfgTable{$hosthash};
        }

        foreach my $token (@{$tokens})
        {
            delete $scref->{'needsRemapping'}{$token};
            delete $cref->{'cbQoSNeedsRemapping'}{$token};
            if( not initTargetAttributes( $collector, $token ) )
            {
                $collector->deleteTarget($token);
            }
        }
    }

    return;
}


# Callback executed by Collector

sub deleteTarget
{
    my $collector = shift;
    my $token = shift;

    my $cref = $collector->collectorData( 'cisco-cbqos' );

    delete $cref->{'ciscoQosEnabled'}{$token};

    Torrus::Collector::SNMP::deleteTarget( $collector, $token );

    return;
}



1;


# Local Variables:
# mode: perl
# indent-tabs-mode: nil
# perl-indent-level: 4
# End:
