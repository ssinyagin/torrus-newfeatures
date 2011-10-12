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

    $data->{'HDSLLine'} = {};
    $data->{'HDSLLineProps'} = {};

    my %unit_instances;

    # Find all HDSL line ifIndex values and units
    {
        my $base = $dd->oiddef('hdsl2ShdslStatusNumAvailRepeaters');
        my $table = $session->get_table( -baseoid => $base );
        my $prefixLen = length( $base ) + 1;
        
        if( defined($table) )
        {            
            while( my( $oid, $val ) = each %{$table} )
            {
                my $ifIndex = substr( $oid, $prefixLen );
                
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
    }

    # Discover the available line stats
    {
        my $base = $dd->oiddef('hdsl2ShdslEndpointCurrSnrMgn');
        my $table = $session->get_table( -baseoid => $base );
        my $prefixLen = length( $base ) + 1;
        
        if( defined($table) )
        {            
            while( my( $oid, $val ) = each %{$table} )
            {
                my $INDEX = substr( $oid, $prefixLen );
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
    }
    
    return 1;
}



sub buildConfig
{
    my $devdetails = shift;
    my $cb = shift;
    my $devNode = shift;

    # Build SNR subtree
    my $subtreeName = 'DSL_Line_Stats';

    my $param = {
        'node-display-name'   => 'DSL line statistics',
    };
    
    my $subtreeNode =
        $cb->addSubtree($devNode, $subtreeName, $param,
                        ['RFC4319_HDSL2_SHDSL_LINE_MIB::hdsl-subtree']);

    my $data = $devdetails->data();
    my $precedence = 1000;
    
    foreach my $ifIndex ( sort {$a<=>$b} %{$data->{'HDSLLine'}} )
    {
        my $interface = $data->{'interfaces'}{$ifIndex};
        next if not defined($interface);
        
        my $ifSubtreeName = $interface->{$data->{'nameref'}{'ifSubtreeName'}};

        my $ifParam = {
            'interface-name' => $interface->{'param'}{'interface-name'},
            'interface-nick' => $interface->{'param'}{'interface-nick'},
            'node-display-name' => $interface->{'param'}{'node-display-name'},
            'collector-timeoffset-hashstring' =>'%system-id%:%interface-nick%',
            'comment'        => $interface->{'param'}{'comment'},
            'precedence'     => $precedence,
        };
        
        my $ifSubtree = $cb->addSubtree
            ( $subtreeNode, $ifSubtreeName, $ifParam ,
              ['RFC4319_HDSL2_SHDSL_LINE_MIB::hdsl-interface']);
        
        $precedence--;

        my @snr_membernames;
        my $snr_mg_params = {
            'comment' => 'SNR Margins overview',
            'precedence' => 1000,
            'ds-type' => 'rrd-multigraph',
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
                'node-display-name' => $endpoint,
                'hdsl-index' => $INDEX,
                'hdsl-endpoint-nick' => $epNick,
                'precedence' => $precedence,
            };
            
            $precedence--;
            
            $cb->addSubtree( $ifSubtree, $epSubtreeName, $param,
                             ['RFC4319_HDSL2_SHDSL_LINE_MIB::hdsl-endpoint'] );
            
            push( @snr_membernames, $epNick );
            $snr_mg_params->{'ds-expr-' . $epNick} =
                '{' . $epSubtreeName . '/SNR_Margin}';
            $snr_mg_params->{'graph-legend-' . $epNick} = $endpoint;
            $snr_mg_params->{'line-style-' . $epNick} = 'LINE2';
            $snr_mg_params->{'line-color-' . $epNick} = '##clr' . $linenum;
            $snr_mg_params->{'line-order-' . $epNick} = $linenum;

            $linenum++;
        }

        $snr_mg_params->{'ds-names'} = join(',', @snr_membernames);
        $cb->addLeaf( $ifSubtree, 'SNR_Summary', $snr_mg_params );
    }
    
}


1;


# Local Variables:
# mode: perl
# indent-tabs-mode: nil
# perl-indent-level: 4
# End:
