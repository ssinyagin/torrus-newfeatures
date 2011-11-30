#  Copyright (C) 2011  Stanislav Sinyagin
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

# Stanislav Sinyagin <ssinyagin@yahoo.com>

# HDSL/SHDSL Line statistics.

package Torrus::DevDiscover::RFC4319_HDSL2_SHDSL_LINE_MIB;

use strict;
use warnings;

use Torrus::Log;


$Torrus::DevDiscover::registry{'RFC4319_HDSL2_SHDSL_LINE_MIB'} = {
    'sequence'     => 100,
    'checkdevtype' => \&checkdevtype,
    'discover'     => \&discover,
    'buildConfig'  => \&buildConfig
    };


our %oiddef =
    (
     # HDSL2-SHDSL-LINE-MIB
     'hdsl2ShdslStatusNumAvailRepeaters' => '1.3.6.1.2.1.10.48.1.2.1.1',
     'hdsl2ShdslEndpointCurrSnrMgn' => '1.3.6.1.2.1.10.48.1.5.1.2',
     );

my %hdslUnitId =
    (
     1 => 'xtuC',
     2 => 'xtuR',
     3 => 'xru1',
     4 => 'xru2',
     5 => 'xru3',
     6 => 'xru4',
     7 => 'xru5',
     8 => 'xru6',
     9 => 'xru7',
     10 => 'xru8',
     );

my %hdslUnitSide =
    (
     1 => 'Network Side',
     2 => 'Customer Side',
     );


my %default_hdsl_oids =
    (
     'hdsl-curr-atn-oid' => 'hdsl2ShdslEndpointCurrAtn',
     'hdsl-curr-snr-oid' => 'hdsl2ShdslEndpointCurrSnrMgn',
     'hdsl-intvl-es-oid' => 'hdsl2Shdsl15MinIntervalES',
     'hdsl-intvl-ses-oid' => 'hdsl2Shdsl15MinIntervalSES',
     'hdsl-intvl-crc-oid' => 'hdsl2Shdsl15MinIntervalCRCanomalies',
     'hdsl-intvl-losws-oid' => 'hdsl2Shdsl15MinIntervalLOSWS',
     'hdsl-intvl-uas-oid' => 'hdsl2Shdsl15MinIntervalUAS',
     );


sub checkdevtype
{
    my $dd = shift;
    my $devdetails = shift;

    my $data = $devdetails->data();

    if( not $dd->checkSnmpTable('hdsl2ShdslStatusNumAvailRepeaters') )
    {
        return 0;
    }

    return 1;
}


sub discover
{
    my $dd = shift;
    my $devdetails = shift;

    my $data = $devdetails->data();
    my $session = $dd->session();

    my $oidmapping = 
        $data->{'RFC4319_HDSL2_SHDSL_LINE_MIB'}{'oidmapping'};
    
    $data->{'HDSLLine'} = {};
    $data->{'HDSLLineProps'} = {};

    my %unit_instances;

    # Find all HDSL line ifIndex values and units
    {
        my $oidname = 'hdsl2ShdslStatusNumAvailRepeaters';
        if( defined($oidmapping) and defined($oidmapping->{$oidname}) )
        {
            $oidname = $oidmapping->{$oidname};
        }
            
        my $table = $dd->walkSnmpTable($oidname);
        
        while( my( $ifIndex, $val ) = each %{$table} )
        {
            # xtuC and xtuR are always present
            $unit_instances{$ifIndex}{1} = 1;
            $unit_instances{$ifIndex}{2} = 1;
            
            # check the repeaters
            my $unitId = 3;
            my $nRepeaters = int($val);
            $data->{'HDSLLineProps'}{$ifIndex}{'repeaters'} = $nRepeaters;
            $data->{'HDSLLineProps'}{$ifIndex}{'wirepairs'} = 0;
            
            while( $nRepeaters > 0 )
            {
                $unit_instances{$ifIndex}{$unitId} = 1;
                $unitId++;
                $nRepeaters--;
            }
        }
    }

    # Discover the available line stats
    {
        my $oidname = 'hdsl2ShdslEndpointCurrSnrMgn';
        if( defined($oidmapping) and defined($oidmapping->{$oidname}) )
        {
            $oidname = $oidmapping->{$oidname};
        }

        my $table = $dd->walkSnmpTable($oidname);

        while( my( $INDEX, $val ) = each %{$table} )
        {
            my($ifIndex, $unitId, $side, $wirepair) =
                split(/\./, $INDEX);
            if( $unit_instances{$ifIndex}{$unitId} )
            {
                $data->{'HDSLLine'}{$ifIndex}{$INDEX} = {
                    'hdsl-unit-id' => $unitId,
                    'hdsl-unit' => $hdslUnitId{$unitId},
                    'hdsl-side' => $hdslUnitSide{$side},
                    'hdsl-wirepair' => 'Wirepair ' . $wirepair,
                };
                
                # find out how many wirepairs this line consists of
                if( $data->{'HDSLLineProps'}{$ifIndex}{'wirepairs'} <
                    $wirepair )
                {
                    $data->{'HDSLLineProps'}{$ifIndex}{'wirepairs'} =
                        $wirepair;
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
    
    if( scalar(keys %{$data->{'HDSLLine'}}) == 0 )
    {
        return;
    }
        
    # Build SNR subtree
    my $subtreeName = 'SHDSL_Line_Stats';

    my $subtreeParam = {
        'node-display-name'   => 'SHDSL line statistics',
    };

    my $oidmapping = 
        $data->{'RFC4319_HDSL2_SHDSL_LINE_MIB'}{'oidmapping'};
    
    while(my ($oidparam, $oidname) = each %default_hdsl_oids)
    {
        if( defined($oidmapping) and defined($oidmapping->{$oidname}) )
        {
            $oidname = $oidmapping->{$oidname};
        }
        $subtreeParam->{$oidparam} = "\$" . $oidname;
    }
    
    my $subtreeNode =
        $cb->addSubtree($devNode, $subtreeName, $subtreeParam,
                        ['RFC4319_HDSL2_SHDSL_LINE_MIB::hdsl-subtree']);

    my $precedence = 1000;
    
    foreach my $ifIndex ( sort {$a<=>$b} %{$data->{'HDSLLine'}} )
    {
        my $interface = $data->{'interfaces'}{$ifIndex};
        next if (not defined($interface) or $interface->{'excluded'});
        
        my $ifSubtreeName = $interface->{$data->{'nameref'}{'ifSubtreeName'}};

        my $ifParam = {
            'collector-timeoffset-hashstring' =>'%system-id%:%interface-nick%',
            'precedence'     => $precedence,
        };
        
        if( defined($data->{'nameref'}{'ifComment'}) and
            defined($interface->{$data->{'nameref'}{'ifComment'}}) )
        {
            $ifParam->{'comment'} =
                $interface->{$data->{'nameref'}{'ifComment'}};
        }

        $ifParam->{'interface-name'} =
            $interface->{$data->{'nameref'}{'ifReferenceName'}};
        $ifParam->{'interface-nick'} =
            $interface->{$data->{'nameref'}{'ifNick'}};
        $ifParam->{'node-display-name'} =
            $interface->{$data->{'nameref'}{'ifReferenceName'}};

        if( defined($data->{'nameref'}{'ifVendorSpecific'}) and
            defined($interface->{$data->{'nameref'}{'ifVendorSpecific'}}) )
        {
            $ifParam->{'interface-vendor-specific'} =
                $interface->{$data->{'nameref'}{'ifVendorSpecific'}};
        }
        
        $ifParam->{'nodeid-dslinterface'} =
            'dsl//%nodeid-device%//' .
            $interface->{$data->{'nameref'}{'ifNodeid'}};
        
        $ifParam->{'nodeid'} = '%nodeid-dslinterface%';
                        
        my $ifSubtree = $cb->addSubtree
            ( $subtreeNode, $ifSubtreeName, $ifParam ,
              ['RFC4319_HDSL2_SHDSL_LINE_MIB::hdsl-interface']);
        
        $precedence--;

        my @snr_membernames;
        my $snr_mg_params = {
            'node-display-name' => 'SNR Margins overview',
            'comment' => 'Summary graph for all SNR values',
            'precedence' => 10010,
            'ds-type' => 'rrd-multigraph',
            'vertical-label' => 'dB',
            'graph-lower-limit' => 0,
            'nodeid' => '%nodeid-dslinterface%//signal_ovw',
        };
        
        my @err_membernames;
        my $err_mg_params = {
            'node-display-name' => 'Line errors overview',
            'comment' => 'Summary graph for all errors',
            'precedence' => 10000,
            'ds-type' => 'rrd-multigraph',
            'vertical-label' => 'Errors',
            'graph-lower-limit' => 0,
            'nodeid' => '%nodeid-dslinterface%//errors_ovw',
        };

        my $linenum = 1;
        
        foreach my $INDEX (sort {$a cmp $b}
                           keys %{$data->{'HDSLLine'}{$ifIndex}})
        {
            my $linedata = $data->{'HDSLLine'}{$ifIndex}{$INDEX};
            my $endpoint = $linedata->{'hdsl-unit'};
            if( $data->{'HDSLLineProps'}{$ifIndex}{'repeaters'} > 0 )
            {
                $endpoint .= ', ' . $linedata->{'hdsl-side'};
            }

            if( $data->{'HDSLLineProps'}{$ifIndex}{'wirepairs'} > 1 )
            {
                $endpoint .= ', ' . $linedata->{'hdsl-wirepair'};
            }

            my $epSubtreeName = $endpoint;
            $epSubtreeName =~ s/\W+/_/g;

            my $epNick = $INDEX;
            $epNick =~ s/\./_/g;

            my $param = {
                'comment' => 'Detailed endpoint statistics',
                'node-display-name' => $endpoint,
                'hdsl-index' => $INDEX,
                'hdsl-endpoint-nick' => $epNick,
                'precedence' => $precedence,
            };

            $param->{'descriptive-nickname'} =
                '%system-id%:%interface-name% ' . $endpoint;

            $param->{'nodeid-dslendpoint'} =
                '%nodeid-dslinterface%//' . $epSubtreeName;
            
            $param->{'nodeid'} = '%nodeid-dslendpoint%';
                        
            $precedence--;
            
            $cb->addSubtree( $ifSubtree, $epSubtreeName, $param,
                             ['RFC4319_HDSL2_SHDSL_LINE_MIB::hdsl-endpoint'] );
            
            push( @snr_membernames, $epNick );
            $snr_mg_params->{'ds-expr-' . $epNick} =
                '{' . $epSubtreeName . '/SNR_Margin}';
            $snr_mg_params->{'graph-legend-' . $epNick} = $endpoint . ' SNR';
            $snr_mg_params->{'line-style-' . $epNick} = 'LINE2';
            $snr_mg_params->{'line-color-' . $epNick} = '##clr' . $linenum;
            $snr_mg_params->{'line-order-' . $epNick} = $linenum;


            push( @err_membernames, $epNick );
            $err_mg_params->{'ds-expr-' . $epNick} =
                '{' . $epSubtreeName . '/Prev_15min_ES},' .
                '{' . $epSubtreeName . '/Prev_15min_SES},+,' .
                '{' . $epSubtreeName . '/Prev_15min_CRCA},+,' .
                '{' . $epSubtreeName . '/Prev_15min_LOSWS},+,' .
                '{' . $epSubtreeName . '/Prev_15min_UAS},+';
            $err_mg_params->{'graph-legend-' . $epNick} =
                $endpoint . ' line errors';
            $err_mg_params->{'line-style-' . $epNick} = 'LINE2';
            $err_mg_params->{'line-color-' . $epNick} = '##clr' . $linenum;
            $err_mg_params->{'line-order-' . $epNick} = $linenum;

            $linenum++;
        }

        $snr_mg_params->{'ds-names'} = join(',', @snr_membernames);
        $cb->addLeaf( $ifSubtree, 'SNR_Summary', $snr_mg_params );

        $err_mg_params->{'ds-names'} = join(',', @err_membernames);
        $cb->addLeaf( $ifSubtree, 'Error_Summary', $err_mg_params );
    }
    
    return;
}


1;


# Local Variables:
# mode: perl
# indent-tabs-mode: nil
# perl-indent-level: 4
# End:
