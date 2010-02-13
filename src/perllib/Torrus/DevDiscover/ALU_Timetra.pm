#
#  Discovery module for Alcatel-Lucent ESS and SR routers
#
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
#  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 02111-1307, USA.

# $Id$
# Stanislav Sinyagin <ssinyagin@yahoo.com>
#

# Currently tested with following Alcatel-Lucent devices:
#  * ESS 7450


package Torrus::DevDiscover::ALU_Timetra;

use strict;
use Torrus::Log;


$Torrus::DevDiscover::registry{'ALU_Timetra'} = {
    'sequence'     => 500,
    'checkdevtype' => \&checkdevtype,
    'discover'     => \&discover,
    'buildConfig'  => \&buildConfig
    };



our %oiddef =
    (
     # TIMETRA-CHASSIS-MIB
     'tmnxChassisTotalNumber'     => '1.3.6.1.4.1.6527.3.1.2.2.1.1.0',
     
     # TIMETRA-GLOBAL-MIB
     'timetraReg'                 => '1.3.6.1.4.1.6527.1',
     'timetraServiceRouters'      => '1.3.6.1.4.1.6527.1.3',
     'timetraServiceSwitches'     => '1.3.6.1.4.1.6527.1.6',
     'alcatel7710ServiceRouters'  => '1.3.6.1.4.1.6527.1.9',

     # TIMETRA-SERV-MIB
     'custDescription'  => '1.3.6.1.4.1.6527.3.1.2.4.1.3.1.3',
     'svcCustId'        => '1.3.6.1.4.1.6527.3.1.2.4.2.2.1.4',
     'svcDescription'   => '1.3.6.1.4.1.6527.3.1.2.4.2.2.1.6',
     'sapDescription'   => '1.3.6.1.4.1.6527.3.1.2.4.3.2.1.5',

     # TIMETRA-PORT-MIB (chassis ID hardcoded to 1)
     'tmnxPortEncapType' => '1.3.6.1.4.1.6527.3.1.2.2.4.2.1.12.1',     
     );


my %essInterfaceFilter =
    (
     'system'  => {
         'ifType'  => 24,                     # softwareLoopback
         'ifName' => '^system'
         },
     );



sub checkdevtype
{
    my $dd = shift;
    my $devdetails = shift;

    my $objectID = $devdetails->snmpVar( $dd->oiddef('sysObjectID') );
    
    if( $dd->oidBaseMatch( 'timetraReg', $objectID ) )
    {
        my $session = $dd->session();
        my $oid = $dd->oiddef('tmnxChassisTotalNumber');
        my $result = $session->get_request( $oid );
        if( $result->{$oid} != 1 )
        {
            Error('Multi-chassis ALU 7x50 equipment is not yet supported');
            return 0;
        }
            
        if( $dd->oidBaseMatch( 'timetraServiceSwitches', $objectID ) )
        {
            $devdetails->setCap('ALU_ESS7450');
            
            $devdetails->setCap('interfaceIndexingManaged');
            $devdetails->setCap('interfaceIndexingPersistent');
            
            &Torrus::DevDiscover::RFC2863_IF_MIB::addInterfaceFilter
                ($devdetails, \%essInterfaceFilter);
            
            return 1;
        }
        else
        {
            # placeholder for future developments
            Error('This model of Alcatel-Lucent equipment ' .
                  'is not yet supported');
            return 0;
        }
    }
    
    return 0;
}




sub discover
{
    my $dd = shift;
    my $devdetails = shift;

    my $session = $dd->session();
    my $data = $devdetails->data();

    # WARNING: This code is tested only with ESS7450
    
    # Amend RFC2863_IF_MIB references
    $data->{'nameref'}{'ifSubtreeName'}    = 'ifNameT';
    $data->{'nameref'}{'ifReferenceName'}  = 'ifName';
    $data->{'nameref'}{'ifNick'} = 'ifNameT';
    $data->{'nameref'}{'ifComment'} = 'ifDescr';
    
    if( $devdetails->param('ALU_Timetra::full-ifdescr') ne 'yes' )
    { 
        $data->{'nameref'}{'ifComment'} = 'ifStrippedDescr';
        
        foreach my $ifIndex ( keys %{$data->{'interfaces'}} )
        {
            my $interface = $data->{'interfaces'}{$ifIndex};
            my $descr = $interface->{'ifDescr'};
            
            # in 7450, ifdescr is 3 comma-separated values:
            # STRING: 1/1/1, 10/100/Gig Ethernet SFP, "COMMENT"
            # Strip everything except the actual comment.
            
            if( $descr =~ /\"(.+)\"/ )
            {
                $descr = $1;
            }
            
            $interface->{'ifStrippedDescr'} = $descr;
        }
    }

    # Get customers
    {
        my $oid = $dd->oiddef('custDescription');
        my $custDescrTable = $session->get_table( -baseoid => $oid );        
        my $prefixLen = length( $oid ) + 1;
        
        while( my( $oid, $descr ) = each %{$custDescrTable} )
        {
            my $custId = substr( $oid, $prefixLen );
            $data->{'timetraCustDescr'}{$custId} = $descr;
        }
    }
        
    
    # Get Service Descriptions
    {
        my $oid = $dd->oiddef('svcDescription');
        my $svcDescrTable = $session->get_table( -baseoid => $oid );        
        my $prefixLen = length( $oid ) + 1;

        while( my( $oid, $descr ) = each %{$svcDescrTable} )
        {
            my $svcId = substr( $oid, $prefixLen );
            $data->{'timetraSvc'}{$svcId} = {
                'description' => $descr,
                'sap' => {}
                };
        }
    }

    # Get mapping of Services to Customers
    {
        my $oid = $dd->oiddef('svcCustId');
        my $svcCustIdTable = $session->get_table( -baseoid => $oid );        
        my $prefixLen = length( $oid ) + 1;
        
        while( my( $oid, $custId ) = each %{$svcCustIdTable} )
        {
            my $svcId = substr( $oid, $prefixLen );
            
            $data->{'timetraCustSvc'}{$custId}{$svcId} = 1;
        }
    }

    
    # Get port encapsulations
    {
        my $oid = $dd->oiddef('tmnxPortEncapType');
        
        my $portEncapTable = $session->get_table( -baseoid => $oid );        
        my $prefixLen = length( $oid ) + 1;

        while( my( $oid, $encap ) = each %{$portEncapTable} )
        {
            my $ifIndex = substr( $oid, $prefixLen );
            if( defined( $data->{'interfaces'}{$ifIndex} ) )
            {
                $data->{'interfaces'}{$ifIndex}{'tmnxPortEncapType'} = $encap;
            }
        }
    }

    
    # Get SAP information
    {
        my $oid = $dd->oiddef('sapDescription');
        
        my $sapDescrTable = $session->get_table( -baseoid => $oid );        
        my $prefixLen = length( $oid ) + 1;

        while( my( $oid, $descr ) = each %{$sapDescrTable} )
        {
            my $sapFullID = substr( $oid, $prefixLen );

            my ($svcId, $ifIndex, $sapEncapValue) =
                split(/\./o, $sapFullID);

            my $ref = $data->{'timetraSvc'}{$svcId}{'sap'};
            if( not defined( $ref ) )
            {
                Error('Cannot find Service ID ' . $svcId);
                next;
            }

            if( not defined( $data->{'interfaces'}{$ifIndex} ) )
            {
                Warn('IfIndex ' . $ifIndex . ' is not in interfaces table, ' .
                     'skipping SAP');
                next;
            }
            
            my $encap = $data->{'interfaces'}{$ifIndex}{'tmnxPortEncapType'};

            # Compose the SAP name depending on port encapsulation.
            
            my $sapName = $data->{'interfaces'}{$ifIndex}{'ifName'};

            if( $encap == 1 )  # nullEncap
            {
                # do nothing
            }
            elsif( $encap == 2 )  # qEncap
            {
                # sapEncapValue is equal to VLAN ID
                $sapName .= ':' . $sapEncapValue;
            }
            elsif( $encap == 10 )  # qinqEncap
            {
                # sapEncapValue contains inner and outer VLAN IDs
                
                my $outer = $sapEncapValue & 0xffff;
                my $inner = $sapEncapValue >> 16;
                if( $inner == 4095 )
                {
                    # default SAP
                    $inner = '*';
                }

                $sapName .= ':' . $outer . '.' . $inner;
            }
            elsif( $encap == 3 ) # mplsEncap
            {
                # sapEncapValue contains the 20-bit LSP ID
                # we should probably do something more here
                $sapName .= ':' . $sapEncapValue;
            }
            else
            {
                Warn('Encapsulation type ' . $encap . ' is not supported yet');
                $sapName .= ':' . $sapEncapValue;
            }
            
            $ref->{$sapFullID} = {
                'description' => $descr,
                'port' => $ifIndex,
                'name' => $sapName,
                'encval' => $sapEncapValue
                };
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


    if( defined( $data->{'timetraSvc'} ) )
    {
        my $customersNode = $cb->addSubtree( $devNode, 'Customers' );

        foreach my $custId (sort {$a <=> $b} keys %{$data->{'timetraCustSvc'}})
        {
            # count the number of SAPs
            my $nSaps = 0;
            foreach my $svcId ( keys %{$data->{'timetraCustSvc'}{$custId}} )
            {
                my $ref = $data->{'timetraSvc'}{$svcId}{'sap'};
                if( defined( $ref ) )
                {
                    $nSaps += scalar( keys %{$ref} );
                }
            }

            if( $nSaps == 0 )
            {
                next;
            }
            
            my $param = {
                'precedence' => 100000 - $custId,
                'comment'    => $data->{'timetraCustDescr'}{$custId},
            };
            
            my $custNode = $cb->addSubtree( $customersNode,
                                            $custId, $param );
            
            my $precedence = 10000;
            
            foreach my $svcId
                ( keys %{$data->{'timetraCustSvc'}{$custId}} )
            {
                my $ref = $data->{'timetraSvc'}{$svcId}{'sap'};
                
                if( defined($ref ) )
                {                    
                    foreach my $sapID
                        ( sort {sapCompare($ref->{$a}, $ref->{$b})}
                          keys %{$ref} )
                    {                        
                        my $sapDescr = $ref->{$sapID}{'description'};
                        if( length( $sapDescr ) == 0 )
                        {
                            $sapDescr = $data->{'timetraSvc'}{$svcId}->{
                                'description'};
                        }

                        my $subtreeName = $ref->{$sapID}{'name'};
                        $subtreeName =~ s/\W/_/go;

                        my $comment = $ref->{$sapID}{'name'};
                        if( length( $sapDescr ) > 0 )
                        {
                            $comment .= ': ' . $sapDescr;
                        }

                        my $legend = '';                        
                        
                        if( length($data->{'timetraCustDescr'}{$custId}) > 0 )
                        {
                            $legend .= 'Customer:' .
                                $devdetails->screenSpecialChars
                                ( $data->{'timetraCustDescr'}{$custId} ) . ';';
                        }
                        
                        if( length($data->{'timetraSvc'}{$svcId}->{
                            'description'}) > 0 )
                        {
                            $legend .= 'Service:' .
                                $devdetails->screenSpecialChars
                                ( $data->{'timetraSvc'}{$svcId}->{
                                    'description'} ) . ';';
                        }
                        
                        $legend .= 'SAP: ' .
                            $devdetails->screenSpecialChars
                            ( $ref->{$sapID}{'name'} );
                        
                        
                        my $param = {
                            'comment'          => $comment,
                            'timetra-sap-id'   => $sapID,
                            'timetra-sap-name' => $ref->{$sapID}{'name'},
                            'precedence'       => $precedence--,
                            'legend'           => $legend,
                        };

                        $cb->addSubtree( $custNode, $subtreeName, $param,
                                         ['ALU_Timetra::alu-timetra-sap']);
                    }
                }
            }                            
        }
    }    
}


sub sapCompare
{
    my $a = shift;
    my $b = shift;

    if( $a->{'port'} == $b->{'port'} )
    {
        return ( $a->{'encval'} <=> $b->{'encval'} );
    }
    else
    {
        return ( $a->{'port'} <=> $b->{'port'} );
    }
}
      


1;

# Local Variables:
# mode: perl
# indent-tabs-mode: nil
# perl-indent-level: 4
# End:
