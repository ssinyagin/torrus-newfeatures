#
#  Discovery module for Denkovi Assembly Electronics
#
#  Copyright (C) 2018 Jon Nistor
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

# Jon Nistor <nistor at snickers.org>
#
# NOTE: Options for this module
#       Denkovi::disable-input-analog
#       Denkovi::disable-input-digital
#       Denkovi::disable-output-digital
#	Denkovi::disable-output-pwm
#

# Liebert discovery module
package Torrus::DevDiscover::Denkovi;

use strict;
use warnings;

use Torrus::Log;


$Torrus::DevDiscover::registry{'Denkovi'} = {
    'sequence'     => 500,
    'checkdevtype' => \&checkdevtype,
    'discover'     => \&discover,
    'buildConfig'  => \&buildConfig
    };

our %oiddef =
    (
     # DENKOVI-MIB::DAEnetIP4
     'Product'			=> '1.3.6.1.4.1.42505.1',

     # 
     'Name'			=> '1.3.6.1.4.1.42505.1.1.1.0',
     'Version'			=> '1.3.6.1.4.1.42505.1.1.2.0',
     'Date'			=> '1.3.6.1.4.1.42505.1.1.3.0',

     # DENKOVI-MIB::Setup
     'DigitalInputsTable'	=> '1.3.6.1.4.1.42505.1.2.1',
     'DigitalInputNumber'	=> '1.3.6.1.4.1.42505.1.2.1.1.1',
     'DigitalInputDescription'	=> '1.3.6.1.4.1.42505.1.2.1.1.2',

     'AnalogInputsTable'	=> '1.3.6.1.4.1.42505.1.2.2',
     'AnalogInputNumber'	=> '1.3.6.1.4.1.42505.1.2.2.1.1',
     'AnalogInputDescription'	=> '1.3.6.1.4.1.42505.1.2.2.1.2',

     'DigitalOutputsTable'	=> '1.3.6.1.4.1.42505.1.2.3',
     'DigitalOutputNumber'	=> '1.3.6.1.4.1.42505.1.2.3.1.1',
     'DigitalOutputDescription'	=> '1.3.6.1.4.1.42505.1.2.3.1.2',

     'PWMOutputsTable'		=> '1.3.6.1.4.1.42505.1.2.4',
     'PWMOutputNumber'          => '1.3.6.1.4.1.42505.1.2.4.1.1',
     'PWMOutputDescription'     => '1.3.6.1.4.1.42505.1.2.4.1.2'

     );

sub checkdevtype
{
    my $dd = shift;
    my $devdetails = shift;

    if( not $dd->oidBaseMatch ( 'Product',
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
    my $Info = $dd->retrieveSnmpOIDs ( 'Name', 'Version', 'Date' );

    # SNMP: System comment
    $data->{'param'}{'comment'} =
            $Info->{'Name'} . ", Version: " .  $Info->{'Version'} .
            ", Date: " . $Info->{'Date'};
    Debug("Device ID: " . $data->{'param'}{'comment'} );

    # $data->{'param'}{'snmp-oids-per-pdu'} = 10;

    # --------------
    # INPUT: Digital
    if( $devdetails->paramDisabled('Denkovi::disable-input-digital') ) 
    {

        # POLL: Grab Entry Table for Input:Digital
        my $idTable = $session->get_table(
                 -baseoid => $dd->oiddef('DigitalInputNumber') );
        $devdetails->storeSnmpVars( $idTable );

        if( defined( $idTable ) )
        {
        	$devdetails->setCap('input-digital');

                foreach my $index ( $devdetails->getSnmpIndices(
                                    $dd->oiddef('DigitalInputNumber') ) )
                {
                    Debug( "Denkovi: Digital Input index: $index" );
                    $data->{'denkovi'}{'input-digital'}{$index}{'idx'} = $index;
                }
        }

        # POLL: Fetch description of index/input
        my $descTable = $session->get_table(
                 -baseoid => $dd->oiddef('DigitalInputDescription') );
        $devdetails->storeSnmpVars( $descTable );

        if( defined( $descTable ) )
        {
        	foreach my $index ( $devdetails->getSnmpIndices(
        			    $dd->oiddef('DigitalInputDescription') ) )
                {
        	    my $inputOID  = $dd->oiddef('DigitalInputDescription')
        			    . "." . $index;
        	    my $inputDesc = $descTable->{$inputOID};

                    $data->{'denkovi'}{'input-digital'}{$index}{'desc'} = $inputDesc;
                    Debug( "Denkovi: Digital Input index: $index, Desc: $inputDesc" );
                }
        }
    }


    # -------------
    # INPUT: Analog
    if( $devdetails->paramDisabled('Denkovi::disable-input-analog') ) 
    {
        # POLL: Grab Entry Table for Input:Analog
        my $idTable = $session->get_table(
                 -baseoid => $dd->oiddef('AnalogInputNumber') );
        $devdetails->storeSnmpVars( $idTable );

        if( defined( $idTable ) )
        {
        	$devdetails->setCap('input-analog');

                foreach my $index ( $devdetails->getSnmpIndices(
                                    $dd->oiddef('AnalogInputNumber') ) )
                {
                    Debug( "Denkovi: Analog Input index: $index" );
                    $data->{'denkovi'}{'input-analog'}{$index}{'idx'} = $index;
                }
        }

        # POLL: Fetch description of index/input
        my $descTable = $session->get_table(
                 -baseoid => $dd->oiddef('AnalogInputDescription') );
        $devdetails->storeSnmpVars( $descTable );

        if( defined( $descTable ) )
        {
        	foreach my $index ( $devdetails->getSnmpIndices(
        			    $dd->oiddef('AnalogInputDescription') ) )
                {
        	    my $inputOID  = $dd->oiddef('AnalogInputDescription')
        			    . "." . $index;
        	    my $inputDesc = $descTable->{$inputOID};

                    $data->{'denkovi'}{'input-analog'}{$index}{'desc'} = $inputDesc;
                    Debug( "Denkovi: Analog Input index: $index, Desc: $inputDesc" );
                }
        }
    }

    # -------------------------------------------------------------------------
    # INPUT: Digital Outputs Table [ idx 3 ]
    #
    if( $devdetails->paramDisabled('Denkovi::disable-output-digital') ) 
    {
        # POLL: Grab Entry Table for DigitalOutputsTable
        my $idTable = $session->get_table(
                 -baseoid => $dd->oiddef('DigitalOutputNumber') );
        $devdetails->storeSnmpVars( $idTable );

        if( defined( $idTable ) )
        {
        	$devdetails->setCap('output-digital');

                foreach my $index ( $devdetails->getSnmpIndices(
                                    $dd->oiddef('DigitalOutputNumber') ) )
                {
                    Debug( "Denkovi: Digital Output index: $index" );
                    $data->{'denkovi'}{'output-digital'}{$index}{'idx'} = $index;
                }
        }

        # POLL: Fetch description of index/output
        my $descTable = $session->get_table(
                 -baseoid => $dd->oiddef('DigitalOutputDescription') );
        $devdetails->storeSnmpVars( $descTable );

        if( defined( $descTable ) )
        {
        	foreach my $index ( $devdetails->getSnmpIndices(
        			    $dd->oiddef('DigitalOutputDescription') ) )
                {
        	    my $outputOID  = $dd->oiddef('DigitalOutputDescription')
        			    . "." . $index;
        	    my $outputDesc = $descTable->{$outputOID};

                    $data->{'denkovi'}{'output-digital'}{$index}{'desc'} = $outputDesc;
                    Debug( "Denkovi: Digital Output index: $index, Desc: $outputDesc" );
                }
        }
    }

    # -------------------------------------------------------------------------
    # INPUT: Analog Outputs (PWM) [ idx 4 ]
    #
    if( $devdetails->paramDisabled('Denkovi::disable-output-analog') ) 
    {
        # POLL: Grab Entry Table for PWMOutputsTable
        my $idTable = $session->get_table(
                 -baseoid => $dd->oiddef('PWMOutputNumber') );
        $devdetails->storeSnmpVars( $idTable );

        if( defined( $idTable ) )
        {
        	$devdetails->setCap('output-analog');

                foreach my $index ( $devdetails->getSnmpIndices(
                                    $dd->oiddef('PWMOutputNumber') ) )
                {
                    Debug( "Denkovi: Analog Output index: $index" );
                    $data->{'denkovi'}{'output-analog'}{$index}{'idx'} = $index;
                }
        }

        # POLL: Fetch description of index/input
        my $descTable = $session->get_table(
                 -baseoid => $dd->oiddef('PWMOutputDescription') );
        $devdetails->storeSnmpVars( $descTable );

        if( defined( $descTable ) )
        {
        	foreach my $index ( $devdetails->getSnmpIndices(
        			    $dd->oiddef('PWMOutputDescription') ) )
                {
        	    my $outputOID  = $dd->oiddef('PWMOutputDescription')
        			    . "." . $index;
        	    my $outputDesc = $descTable->{$outputOID};

                    $data->{'denkovi'}{'output-analog'}{$index}{'desc'} = $outputDesc;
                    Debug( "Denkovi: Analog Output index: $index, Desc: $outputDesc" );
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


    if( $devdetails->hasCap('input-analog') )
    {
      my $nodeTop = $cb->addSubtree( $devNode, 'Analog', undef,
         		[ 'Denkovi::input-analog-subtree' ] );

      # ----------------------------------------------------------------
      # PROG: Figure out how many indexes we have
      foreach my $index ( keys %{$data->{'denkovi'}{'input-analog'}} )
      {
        my $inputDesc = $data->{'denkovi'}{'input-analog'}{$index}{'desc'};
        Debug("Denkovi: analog input idx: $index, desc: $inputDesc");
          
        my $param = {
            'comment'    => "$inputDesc",
            'data-file'  => "%system-id%_input_analog_$index.rrd",
            'input-desc' => $data->{'denkovi'}{'input-analog'}{$index}{'desc'},
            'input-idx'  => $index
        };

        my @template;
        push( @template, 'Denkovi::input-analog-value-subtree' );

        my $nodeLeaf = $cb->addSubtree( $nodeTop, 'input_' . $index, $param, \@template );
      } # END: foreach my $index
    } # END


    return;
}

1;

# Local Variables:
# mode: perl
# indent-tabs-mode: nil
# perl-indent-level: 4
# End:
