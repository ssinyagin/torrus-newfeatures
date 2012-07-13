#  Copyright (C) 2012 Stanislav Sinyagin
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

# Comtech EF Data satellite modems

package Torrus::DevDiscover::ComtechEFData;

use strict;
use warnings;

use Torrus::Log;


$Torrus::DevDiscover::registry{'ComtechEFData'} = {
    'sequence'     => 500,
    'checkdevtype' => \&checkdevtype,
    'discover'     => \&discover,
    'buildConfig'  => \&buildConfig
    };


our %oiddef =
    (
     'ComtechEFData'     => '1.3.6.1.4.1.6247',
     'cdm570'            => '1.3.6.1.4.1.6247.24',
     'cdm570TxFrequency' => '1.3.6.1.4.1.6247.24.1.2.2.1.0',
     'cdm570TxDataRate'  => '1.3.6.1.4.1.6247.24.1.2.2.2.0',
     'cdm570RxFrequency' => '1.3.6.1.4.1.6247.24.1.2.3.1.0',
     'cdm570RxDataRate'  => '1.3.6.1.4.1.6247.24.1.2.3.2.0',
     'cdmipWanFpgaRxPayLoadCount' => '1.3.6.1.4.1.6247.4.8.5.6.0',
     );


my %cdm570_OID = (
    'cdm570TxFrequency' => 'cdm-wan-tx-freq',
    'cdm570TxDataRate'  => 'cdm-wan-tx-rate',
    'cdm570RxFrequency' => 'cdm-wan-rx-freq',
    'cdm570RxDataRate'  => 'cdm-wan-rx-rate',
    );

sub checkdevtype
{
    my $dd = shift;
    my $devdetails = shift;

    my $sysObjectID = $devdetails->snmpVar( $dd->oiddef('sysObjectID') );
    
    if( not $dd->oidBaseMatch( 'ComtechEFData', $sysObjectID ) )
    {
        return 0;
    }

    if( $dd->oidBaseMatch( 'cdm570', $sysObjectID ) )
    {
        $devdetails->setCap('cdm570');
    }

    $devdetails->setCap('interfaceIndexingPersistent');
    
    &Torrus::DevDiscover::RFC2863_IF_MIB::addInterfaceFilter
        ($devdetails,
         {
             'loopback' => {
                 'ifType'  => 24,   # softwareLoopback
                 'ifDescr' => 'loopback'
             }
         });
    
    return 1;
}


sub discover
{
    my $dd = shift;
    my $devdetails = shift;

    my $data = $devdetails->data();
    my $session = $dd->session();
    
    $data->{'param'}{'snmp-oids-per-pdu'} = 10;

    # Get TX/RX frequency and data rate
    if( $devdetails->hasCap('cdm570') )
    {
        my @oids = ();
        foreach my $var ( sort keys %cdm570_OID )
        {
            push( @oids, $dd->oiddef($var) );
        }

        my $result = $session->get_request( -varbindlist => \@oids );
        if( not defined $result )
        {
            Error('Failed to get CDM570 radio parameters');
            return 0;
        }
        
        foreach my $var ( keys %cdm570_OID )
        {
            my $val = $result->{$dd->oiddef($var)};
            if( not defined($val) )
            {
                $val = 0;
            }
            $data->{'cdm570'}{$var} = $val;
            $data->{'param'}{$cdm570_OID{$var}} = $val;
        }
    }
        
    # Check if IP cotroller is present
    {
        my $oid = $dd->oiddef('cdmipWanFpgaRxPayLoadCount');        
        my $result = $session->get_request( -varbindlist => [$oid] );
        
        if( $session->error_status() == 0 and
            defined( $result ) and
            defined($result->{$oid}) )
        {
            $devdetails->setCap('CDMIPController');
        }
    }
    return 1;
}


sub buildConfig
{
    my $devdetails = shift;
    my $cb = shift;
    my $devNode = shift;

    if( $devdetails->hasCap('cdm570') )
    {
        $cb->addTemplateApplication($devNode, 'ComtechEFData::cdm570');
    }
    
    if( $devdetails->hasCap('CDMIPController') )
    {
        $cb->addTemplateApplication($devNode, 'ComtechEFData::cdmip');
    }
    
    return;
}



1;


# Local Variables:
# mode: perl
# indent-tabs-mode: nil
# perl-indent-level: 4
# End:
