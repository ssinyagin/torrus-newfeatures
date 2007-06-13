#
#  Copyright (C) 2007  Jon Nistor
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
# Jon Nistor <nistor at snickers.org>

# Juniper JunOS Discovery Module
# NOTE: For Class of service, if you are noticing that you are not seeing
#       all of your queue names show up, this is due to an SNMP bug.
#       Solution: Put place-holder names for those queues such as:
#                 "UNUSED-queue-#"
#       This is in reference to JunOS 7.6

package Torrus::DevDiscover::JunOS;

use strict;
use Torrus::Log;


$Torrus::DevDiscover::registry{'JunOS'} = {
    'sequence'     => 500,
    'checkdevtype' => \&checkdevtype,
    'discover'     => \&discover,
    'buildConfig'  => \&buildConfig
    };


our %oiddef =
    (
     # JUNIPER-SMI
     'jnxProducts'          => '1.3.6.1.4.1.2636.1',
     'jnxBoxDescr'          => '1.3.6.1.4.1.2636.3.1.2.0',
     'jnxBoxSerialNo'       => '1.3.6.1.4.1.2636.3.1.3.0',

     # Class of Service (jnxCosIfqStatsTable was deprecated,
     #                   use jnxCosQstatTable)
     #             COS  - Class Of Service
     #             RED  - Random Early Detection
     #             PLP  - Packet Loss Priority
     #             DSCP - Differential Service Code Point

     'jnxCosFcIdToFcName'   => '1.3.6.1.4.1.2636.3.15.3.1.2',
     'jnxCosQstatQedPkts'   => '1.3.6.1.4.1.2636.3.15.4.1.3'
     );


sub checkdevtype
{
    my $dd = shift;
    my $devdetails = shift;

    if( not $dd->oidBaseMatch
        ( 'jnxProducts',
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

    # NOTE: Comments and Serial number of device
    my $chassisSerial =
        $dd->retrieveSnmpOIDs( 'jnxBoxDescr', 'jnxBoxSerialNo' );
    if( defined( $chassisSerial ) )
    {
        $data->{'param'}{'comment'} =
            $chassisSerial->{'jnxBoxDescr'} . ', Hw Serial#: ' .
            $chassisSerial->{'jnxBoxSerialNo'};
    }

    # NOTE: Class of Service
    if( $devdetails->param('JunOS::disable-cos') ne 'yes' )
    {
        # Get the output Queue number
        my $cosQueueNumTable =
            $session->get_table( -baseoid =>
                                 $dd->oiddef('jnxCosFcIdToFcName'));
        $devdetails->storeSnmpVars( $cosQueueNumTable );
        if ( $cosQueueNumTable )
        {
            $devdetails->setCap('jnxCoS');
    
            foreach my $cosFcIndex
                ( $devdetails->getSnmpIndices
                  ($dd->oiddef('jnxCosFcIdToFcName') ))
            {
                my $cosFcNameOid = $dd->oiddef('jnxCosFcIdToFcName') . "." .
                    $cosFcIndex;
                my $cosFcName    = $cosQueueNumTable->{$cosFcNameOid};
                $data->{'cos'}{'queue'}{$cosFcIndex} = $cosFcName;

                Debug("JunOS::CoS  FcInfo index: " .
                      "$cosFcIndex  name: $cosFcName");
            }

            # We need to find out all the interfaces that have CoS enabled
            # on them. We will use jnxCosQstatQedPkts as our reference point.
            my $cosIfIndex =
                $session->get_table( -baseoid =>
                                     $dd->oiddef('jnxCosQstatQedPkts'));
            $devdetails->storeSnmpVars( $cosIfIndex );
    
            foreach my $INDEX
                ( $devdetails->getSnmpIndices
                  ($dd->oiddef('jnxCosQstatQedPkts') ) )
            {
                my( $ifIndex, $cosQueueIndex ) = split( '\.', $INDEX );
                $data->{'cos'}{'ifIndex'}{$ifIndex} = 1;
            }
        }
    } # END of JunOS::disable-cos    
    return 1;
}


sub buildConfig
{
    my $devdetails = shift;
    my $cb = shift;
    my $devNode = shift;
    my $data = $devdetails->data();

    # Class of Service information
    if( $devdetails->hasCap('jnxCoS') )
    {
        my $nodeTop = $cb->addSubtree( $devNode, 'CoS_Stats',
                                       { 'precendence' => 1000 },
                                       [ 'JunOS::junos-cos-subtree']);
        
        foreach my $ifIndex ( sort {$a <=> $b} keys
                              %{$data->{'cos'}{'ifIndex'}} )
        {
            my $interface = $data->{'interfaces'}{$ifIndex};
            my $ifAlias   = $interface->{'ifAlias'};
            my $ifDescr   = $interface->{'ifDescr'};
            my $ifName    = $interface->{'ifNameT'};
	    next if (!$ifName);  # Skip to next since port is likely 'disabled'

	    # Add Subtree per port
	    my $nodePort =
                $cb->addSubtree( $nodeTop, $ifName,
                                 { 'comment'    => $ifAlias,
                                   'precedence' => 1000 - $ifIndex });

            # Loop to create subtree's for each QueueName/ID pair
            foreach my $cosIndex ( sort keys %{$data->{'cos'}{'queue'}} )
            {
                my $cosName  = $data->{'cos'}{'queue'}{$cosIndex};
                
                # Add Leaf for each one
                Debug("JunOS::CoS  addSubtree ifIndex: $ifIndex " . 
                      " ($ifName -> $cosName)");
                $cb->addSubtree( $nodePort, $cosName,
                                 { 'comment'    => "Class: " . $cosName,
                                   'cos-index'  => $cosIndex,
                                   'cos-name'   => $cosName,
                                   'ifDescr'    => $ifDescr,
                                   'ifIndex'    => $ifIndex,
                                   'ifName'     => $ifName,
                                   'legend'     => "",
                                   'precedence' => 1000 - $cosIndex },
                                 [ 'JunOS::junos-cos-leaf' ]);
            } # end foreach (INDEX of queue's [Q-ID])
        } # end foreach (INDEX of port)
    } # end if HasCap->{CoS}
}

1;


# Local Variables:
# mode: perl
# indent-tabs-mode: nil
# perl-indent-level: 4
# End:
