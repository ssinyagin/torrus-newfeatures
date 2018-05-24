#  Copyright (C) 2013 Stanislav Sinyagin
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

# Metro Ethernet Forum MEF-SOAM-PM-MIB
# The module requires IEEE8021-CFM-MIB as pre-requisite

package Torrus::DevDiscover::MEF_SOAM_PM_MIB;

use strict;
use warnings;

use Torrus::Log;
use Data::Dumper;

$Torrus::DevDiscover::registry{'MEF_SOAM_PM_MIB'} = {
    'sequence'     => 110,
    'checkdevtype' => \&checkdevtype,
    'discover'     => \&discover,
    'buildConfig'  => \&buildConfig
    };


our %oiddef =    
    (
     # LM measurement configuration
     'mefSoamLmCfgTable'              => '1.3.6.1.4.1.15007.1.3.1.2.1',
     'mefSoamLmCfgType'               => '1.3.6.1.4.1.15007.1.3.1.2.1.1.2',
     'mefSoamLmCfgEnabled'            => '1.3.6.1.4.1.15007.1.3.1.2.1.1.4',
     'mefSoamLmCfgMeasurementEnable'  => '1.3.6.1.4.1.15007.1.3.1.2.1.1.5',
     'mefSoamLmCfgDestMacAddress'     => '1.3.6.1.4.1.15007.1.3.1.2.1.1.14',
     'mefSoamLmCfgDestMepId'          => '1.3.6.1.4.1.15007.1.3.1.2.1.1.15',
     'mefSoamLmCfgDestIsMepId'        => '1.3.6.1.4.1.15007.1.3.1.2.1.1.16',
     
     # DM measurement configuration
     'mefSoamDmCfgTable'              => '1.3.6.1.4.1.15007.1.3.1.3.1',
     'mefSoamDmCfgType'               => '1.3.6.1.4.1.15007.1.3.1.3.1.1.2',
     'mefSoamDmCfgEnabled'            => '1.3.6.1.4.1.15007.1.3.1.3.1.1.4',
     'mefSoamDmCfgMeasurementEnable'  => '1.3.6.1.4.1.15007.1.3.1.3.1.1.5',
     'mefSoamDmCfgDestMacAddress'     => '1.3.6.1.4.1.15007.1.3.1.3.1.1.14',
     'mefSoamDmCfgDestMepId'          => '1.3.6.1.4.1.15007.1.3.1.3.1.1.15',
     'mefSoamDmCfgDestIsMepId'        => '1.3.6.1.4.1.15007.1.3.1.3.1.1.16',
     );


# mefSoamLmCfgType values
my $lmTypeDef = {
    '1' => 'LMM',
    '2' => 'SLM',
    '3' => 'CCM'
    };

# bit flags and templates for LM measurements
my $lmMeasuremens = {
    'bForwardAvgFlr' => {
        'bit' => 4,
        'template' => 'MEF_SOAM_PM_MIB::mef-soam-lm-forward-avg-flr',
    },
    'bBackwardAvgFlr' => {
        'bit' => 9,
        'template' => 'MEF_SOAM_PM_MIB::mef-soam-lm-backward-avg-flr',
    },
};


# mefSoamDmCfgType values
my $dmTypeDef = {
    '1' => 'DMM',
    '2' => '1DMtx',
    '3' => '1DMrx'
    };

# bit flags and templates for LM measurements
my $dmMeasuremens = {
    'bFrameDelayTwoWayMin' => {
        'bit' => 3,
        'template' => 'MEF_SOAM_PM_MIB::mef-soam-dm-twoway-min',
    },
    'bFrameDelayTwoWayMax' => {
        'bit' => 4,
        'template' => 'MEF_SOAM_PM_MIB::mef-soam-dm-twoway-max',
    },
    'bFrameDelayTwoWayAvg' => {
        'bit' => 5,
        'template' => 'MEF_SOAM_PM_MIB::mef-soam-dm-twoway-avg',
    },
};



sub checkdevtype
{
    my $dd = shift;
    my $devdetails = shift;

    my $found = 0;
    
    if( not $devdetails->isDevType('IEEE8021_CFM_MIB') )
    {
        return 0;
    }

    if( $dd->checkSnmpTable('mefSoamLmCfgTable') )
    {
        $found = 1;
        $devdetails->setCap('mefSoamLmCfgTable');
    }

    if( $dd->checkSnmpTable('mefSoamDmCfgTable') )
    {
        $found = 1;
        $devdetails->setCap('mefSoamDmCfgTable');
    }
        
    return $found;
}


sub discover
{
    my $dd = shift;
    my $devdetails = shift;

    my $data = $devdetails->data();
    my $session = $dd->session();
    
    # LM test configurations
    if( $devdetails->hasCap('mefSoamLmCfgTable') )
    {
        # INDEX { dot1agCfmMdIndex,
        #         dot1agCfmMaIndex,
        #         dot1agCfmMepIdentifier,
        #         mefSoamLmCfgIndex
        
        my $lmcfg = {};
        foreach my $oidname
            (
             'mefSoamLmCfgTable',
             'mefSoamLmCfgType',
             'mefSoamLmCfgEnabled',
             'mefSoamLmCfgMeasurementEnable',
             'mefSoamLmCfgDestMacAddress',
             'mefSoamLmCfgDestMepId',
             'mefSoamLmCfgDestIsMepId',
             )
        {
            $lmcfg->{$oidname} = $dd->walkSnmpTable($oidname);
        }

        foreach my $idx (keys %{$lmcfg->{'mefSoamLmCfgType'}})
        {
            if( $lmcfg->{'mefSoamLmCfgEnabled'}{$idx} != 1 )
            {
                next;
            }
            
            my $ref = {};

            my ($md, $ma, $mep, $cfgidx) = split(/\./, $idx);
            
            $ref->{'md'} = $md;
            $ref->{'ma'} = $ma;
            $ref->{'mep'} = $mep;
            
            $ref->{'type'} = $lmTypeDef->{
                $lmcfg->{'mefSoamLmCfgType'}{$idx}};

            if( $lmcfg->{'mefSoamLmCfgDestIsMepId'}{$idx} == 1 )
            {
                $ref->{'target_is_mep'} = 1;
                $ref->{'target'} = $lmcfg->{'mefSoamLmCfgDestMepId'}{$idx};
            }
            else
            {
                $ref->{'target_is_mep'} = 0;
                $ref->{'target'} =
                    $lmcfg->{'mefSoamLmCfgDestMacAddress'}{$idx};
            }                    
                
            $ref->{'templates'} = [];
            
            my $measrmtBits = $lmcfg->{'mefSoamLmCfgMeasurementEnable'}{$idx};
            foreach my $measrmt (sort {$lmMeasuremens->{$a}{'bit'} <=>
                                           $lmMeasuremens->{$b}{'bit'}}
                                 keys %{$lmMeasuremens})
            {
                my $offset = $lmMeasuremens->{$measrmt}{'bit'};
                if( $dd->checkBit($measrmtBits, $offset) )
                {
                    push(@{$ref->{'templates'}},
                         $lmMeasuremens->{$measrmt}{'template'});
                }
            }

            if( scalar(@{$ref->{'templates'}}) > 0 )
            {
                $data->{'mefSoamLm'}{$idx} = $ref;
            }
        }

        my $count = scalar(keys %{$data->{'mefSoamLm'}});
        Debug('Found ' . $count . ' SOAM LM measurements');
        if( $count > 0 )
        {
            $devdetails->setCap('mefSoamLm');
        }
    }

    if( $devdetails->hasCap('mefSoamDmCfgTable') )
    {
        # DM test configurations
        # INDEX {
        #        dot1agCfmMdIndex,
        #        dot1agCfmMaIndex, 
        #        dot1agCfmMepIdentifier, 
        #        mefSoamDmCfgIndex
        #       }


        my $dmcfg = {};
        foreach my $oidname
            (
             'mefSoamDmCfgType',
             'mefSoamDmCfgEnabled',
             'mefSoamDmCfgMeasurementEnable',
             'mefSoamDmCfgDestMacAddress',
             'mefSoamDmCfgDestMepId',
             'mefSoamDmCfgDestIsMepId',
             )
        {
            $dmcfg->{$oidname} = $dd->walkSnmpTable($oidname);
        }

        foreach my $idx (keys %{$dmcfg->{'mefSoamDmCfgType'}})
        {
            if( $dmcfg->{'mefSoamDmCfgEnabled'}{$idx} != 1 )
            {
                next;
            }

            my $ref = {};

            my ($md, $ma, $mep, $cfgidx) = split(/\./, $idx);
            
            $ref->{'md'} = $md;
            $ref->{'ma'} = $ma;
            $ref->{'mep'} = $mep;
            
            $ref->{'type'} = $dmTypeDef->{
                $dmcfg->{'mefSoamDmCfgType'}{$idx}};
            
            if( $dmcfg->{'mefSoamDmCfgDestIsMepId'}{$idx} == 1 )
            {
                $ref->{'target_is_mep'} = 1;
                $ref->{'target'} = $dmcfg->{'mefSoamDmCfgDestMepId'}{$idx};
            }
            else
            {
                $ref->{'target_is_mep'} = 0;
                $ref->{'target'} =
                    $dmcfg->{'mefSoamDmCfgDestMacAddress'}{$idx};
            }                    

            $ref->{'templates'} = [];
            
            my $measrmtBits = $dmcfg->{'mefSoamDmCfgMeasurementEnable'}{$idx};
            foreach my $measrmt (sort {$dmMeasuremens->{$a}{'bit'} <=>
                                           $dmMeasuremens->{$b}{'bit'}}
                                 keys %{$dmMeasuremens})
            {
                my $offset = $dmMeasuremens->{$measrmt}{'bit'};
                if( $dd->checkBit($measrmtBits, $offset) )
                {
                    push(@{$ref->{'templates'}},
                         $dmMeasuremens->{$measrmt}{'template'});
                }
            }

            if( scalar(@{$ref->{'templates'}}) > 0 )
            {
                $data->{'mefSoamDm'}{$idx} = $ref;
            }
        }

        my $count = scalar(keys %{$data->{'mefSoamDm'}});
        Debug('Found ' . $count . ' SOAM DM measurements');
        if( $count > 0 )
        {
            $devdetails->setCap('mefSoamDm');
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

    if( $devdetails->hasCap('mefSoamLm') )
    {
        my $lmNodeParam = {
            'comment' => 'SOAM Frame Loss Measurement statistics',
            'node-display-name' => 'SOAM LM',
        };
        
        my $lmNode =
            $cb->addSubtree( $devNode, 'SOAM-LM', $lmNodeParam,
                             ['MEF_SOAM_PM_MIB::mef-soam-lm-subtree'] );

        buildSoamConfig($devdetails, $cb, $lmNode, 'mefSoamLm');
    }

    if( $devdetails->hasCap('mefSoamDm') )
    {
        my $dmNodeParam = {
            'comment' => 'SOAM Frame Delay Measurement statistics',
            'node-display-name' => 'SOAM DM',
        };
        
        my $dmNode =
            $cb->addSubtree( $devNode, 'SOAM-DM', $dmNodeParam,
                             ['MEF_SOAM_PM_MIB::mef-soam-dm-subtree'] );

        buildSoamConfig($devdetails, $cb, $dmNode, 'mefSoamDm');
    }
    
    return;
}
    

sub buildSoamConfig
{
    my $devdetails = shift;
    my $cb = shift;
    my $node = shift;
    my $soamtype = shift;

    my $soamtypeshort = $soamtype eq 'mefSoamLm' ? 'lm':'dm';
        
    my $data = $devdetails->data();
    my $soamdata = $data->{$soamtype};
    
    foreach my $idx (sort keys %{$soamdata})
    {
        my $ref = $soamdata->{$idx};
        my $md = $ref->{'md'};
        my $ma = $ref->{'ma'};
        my $mep = $ref->{'mep'};
        
        my $mddata = $data->{'dot1ag'}{$md};
        if( not defined($mddata) )
        {
            Error('Cannot find IEEE8021-CFM-MIB MD: ' . $md);
            next;
        }
        
        my $madata = $data->{'dot1ag'}{$md}{'ma'}{$ma};
        if( not defined($madata) )
        {
            Error('Cannot find IEEE8021-CFM-MIB MA: ' .
                  join('.', $md, $ma));
            next;
        }
        
        my $mepdata = $data->{'dot1ag'}{$md}{'ma'}{$ma}{'mep'}{$mep};
        if( not defined($mepdata) )
        {
            Error('Cannot find IEEE8021-CFM-MIB MEP: ' .
                  join('.', $md, $ma, $mep));
            next;
        }                       

        my $interface = $data->{'interfaces'}{$mepdata->{'ifIndex'}};
        if( not defined($interface) )
        {
            Error('Cannot find interface index ' . $mepdata->{'ifIndex'} .
                  ' for MEP ' . join('.', $md, $ma, $mep));
            next;
        }            
        
        my $ifname =
            $interface->{$data->{'nameref'}{'ifReferenceName'}};
        
        my $legend =
            'MD Name:' . $mddata->{'name'} . ';' .
            'MA Name:' . $madata->{'name'} . ';' .
            'Interval:' . $madata->{'interval'} . ';' .
            'MEP:' . $mep . ';' .
            'Interface:' . $ifname . ';' .
            'Measurement type: ' . $ref->{'type'} . ';' .
            'Target: ' . $ref->{'target'};

        my $descr = $madata->{'name'} . ' ' . $mep . '->' . $ref->{'target'};
        my $gtitle = '%system-id% ' . $descr;
        
        my $nodeid = 'soam//%nodeid-device%' . '//' . $idx . '//' . 
            $soamtypeshort;
             
        my $param = {
            'mef-soam-cfg-index' => $idx,
            'node-display-name' => $descr,
            'mef-mp-description' => $descr,
            'mef-soam-nodeid' => $nodeid,
            'nodeid' => $nodeid,
            'legend' => $legend,
            'graph-title' => $gtitle,
        };
        
        my $subtreeName = $idx;
        
        $cb->addSubtree( $node, $subtreeName, $param, $ref->{'templates'} );
    }

    return;
}



1;


# Local Variables:
# mode: perl
# indent-tabs-mode: nil
# perl-indent-level: 4
# End:
