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
#  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 02111-1307, USA.

# Stanislav Sinyagin <ssinyagin@yahoo.com>

# ADSL Line statistics.

# We assume that adslAturPhysTable is always present when adslAtucPhysTable
# is there. Probably that's wrong, and needs to be redesigned.

package Torrus::DevDiscover::RFC2662_ADSL_LINE;

use strict;
use warnings;

use Torrus::Log;


$Torrus::DevDiscover::registry{'RFC2662_ADSL_LINE'} = {
    'sequence'     => 100,
    'checkdevtype' => \&checkdevtype,
    'discover'     => \&discover,
    'buildConfig'  => \&buildConfig
    };


our %oiddef =
    (
     # ADSL-LINE-MIB
     'adslAtucCurrSnrMgn'         => '1.3.6.1.2.1.10.94.1.1.2.1.4',
     'adslAtucCurrAtn'            => '1.3.6.1.2.1.10.94.1.1.2.1.5',
     'adslAtucCurrAttainableRate' => '1.3.6.1.2.1.10.94.1.1.2.1.8',
     'adslAtucChanCurrTxRate'     => '1.3.6.1.2.1.10.94.1.1.4.1.2',
     
     'adslAturCurrSnrMgn'         => '1.3.6.1.2.1.10.94.1.1.3.1.4',
     'adslAturCurrAtn'            => '1.3.6.1.2.1.10.94.1.1.3.1.5',
     'adslAturCurrAttainableRate' => '1.3.6.1.2.1.10.94.1.1.3.1.8',
     'adslAturChanCurrTxRate'     => '1.3.6.1.2.1.10.94.1.1.5.1.2',

     'adslAtucPerfCurr1DayLofs'   => '1.3.6.1.2.1.10.94.1.1.6.1.17',
     'adslAtucPerfCurr1DayLoss'   => '1.3.6.1.2.1.10.94.1.1.6.1.18',
     'adslAtucPerfCurr1DayLprs'   => '1.3.6.1.2.1.10.94.1.1.6.1.20',
     'adslAtucPerfCurr1DayESs'    => '1.3.6.1.2.1.10.94.1.1.6.1.21',
     'adslAtucPerfCurr1DayInits'  => '1.3.6.1.2.1.10.94.1.1.6.1.22',

     'adslAturPerfCurr1DayLofs'   => '1.3.6.1.2.1.10.94.1.1.7.1.13',
     'adslAturPerfCurr1DayLoss'   => '1.3.6.1.2.1.10.94.1.1.7.1.14',
     'adslAturPerfCurr1DayLprs'   => '1.3.6.1.2.1.10.94.1.1.7.1.15',
     'adslAturPerfCurr1DayESs'    => '1.3.6.1.2.1.10.94.1.1.7.1.16',
     );



sub checkdevtype
{
    my $dd = shift;
    my $devdetails = shift;

    my $data = $devdetails->data();

    if( not $dd->checkSnmpTable('adslAtucCurrSnrMgn') )
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

    $data->{'AdslLine'} = {};
    
    foreach my $oidname
        ( 'adslAtucCurrSnrMgn',
          'adslAtucCurrAtn',
          'adslAtucCurrAttainableRate',
          'adslAtucChanCurrTxRate',
          'adslAturCurrSnrMgn',
          'adslAturCurrAtn',
          'adslAturCurrAttainableRate',
          'adslAturChanCurrTxRate',
          'adslAtucPerfCurr1DayLofs',
          'adslAtucPerfCurr1DayLoss',
          'adslAtucPerfCurr1DayLprs',
          'adslAtucPerfCurr1DayESs',
          'adslAtucPerfCurr1DayInits',
          'adslAturPerfCurr1DayLofs',
          'adslAturPerfCurr1DayLoss',
          'adslAturPerfCurr1DayLprs',
          'adslAturPerfCurr1DayESs',
          )
    {
        my $base = $dd->oiddef($oidname);
        my $table = $session->get_table( -baseoid => $base );
        my $prefixLen = length( $base ) + 1;
        
        if( defined($table) )
        {            
            while( my( $oid, $val ) = each %{$table} )
            {
                my $ifIndex = substr( $oid, $prefixLen );
                $data->{'AdslLine'}{$ifIndex}{$oidname} = 1;
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
    my $subtreeName = 'ADSL_Line_Stats';

    my $subtreeParam = {
        'precedence'          => '-600',
        'node-display-name'   => 'ADSL line statistics',
        'comment'             => 'ADSL line signal quality and performance',
        };
    
    my $subtreeNode = $cb->addSubtree( $devNode, $subtreeName, $subtreeParam );

    my $data = $devdetails->data();
    my $precedence = 1000;
    
    foreach my $ifIndex ( sort {$a<=>$b} %{$data->{'AdslLine'}} )
    {
        my $interface = $data->{'interfaces'}{$ifIndex};
        next if not defined($interface);
        
        my $ifSubtreeName = $interface->{$data->{'nameref'}{'ifSubtreeName'}};

        my $ifParam = {
            'collector-timeoffset-hashstring' =>'%system-id%:%interface-nick%',
            'precedence'     => $precedence,
        };

        $ifParam->{'interface-name'} =
            $interface->{$data->{'nameref'}{'ifReferenceName'}};
        $ifParam->{'interface-nick'} =
            $interface->{$data->{'nameref'}{'ifNick'}};
        $ifParam->{'node-display-name'} =
            $interface->{$data->{'nameref'}{'ifReferenceName'}};

        $ifParam->{'nodeid-interface'} =
            'adsl-' .
            $interface->{$data->{'nameref'}{'ifNodeidPrefix'}} .
            $interface->{$data->{'nameref'}{'ifNodeid'}};

        if( defined($data->{'nameref'}{'ifComment'}) and
            defined($interface->{$data->{'nameref'}{'ifComment'}}) )
        {
            $ifParam->{'comment'} =
                $interface->{$data->{'nameref'}{'ifComment'}};
        }
        
        my $templates = [];
        my $childParams = {};
        my $adslIntf = $data->{'AdslLine'}{$ifIndex};

        my $applySelectors = sub
        {
            my $selectorSuffix = shift;
            my $leafSuffix = shift;
            
            foreach my $end ('Atuc', 'Atur')
            {
                my $arg = $adslIntf->{'selectorActions'}{
                    $end . $selectorSuffix};
                if( defined($arg) )
                {
                    $childParams->{$end . '_' . $leafSuffix}{'monitor'} = $arg;
                }
            }
        };

                
        if( $adslIntf->{'adslAtucCurrSnrMgn'} and
            $adslIntf->{'adslAturCurrSnrMgn'} )
        {
            push( @{$templates}, 'RFC2662_ADSL_LINE::adsl-line-snr');
            &{$applySelectors}('SnrMonitor', 'SnrMgn');
        }
        
        if( $adslIntf->{'adslAtucCurrAtn'} and
            $adslIntf->{'adslAturCurrAtn'} )
        {
            push( @{$templates}, 'RFC2662_ADSL_LINE::adsl-line-atn');
            &{$applySelectors}('AtnMonitor', 'Atn');
        }

        if( $adslIntf->{'adslAtucCurrAttainableRate'} and
            $adslIntf->{'adslAturCurrAttainableRate'} )
        {
            push( @{$templates}, 'RFC2662_ADSL_LINE::adsl-line-attrate');
            &{$applySelectors}('AttRateMonitor', 'AttainableRate');
        }
        
        if( $adslIntf->{'adslAtucChanCurrTxRate'} and
            $adslIntf->{'adslAturChanCurrTxRate'} )
        {
            push( @{$templates}, 'RFC2662_ADSL_LINE::adsl-channel-txrate');
            &{$applySelectors}('TxRateMonitor', 'CurrTxRate');
        }

        if( $adslIntf->{'adslAtucPerfCurr1DayLofs'} and
            $adslIntf->{'adslAturPerfCurr1DayLofs'} )
        {
            push( @{$templates}, 'RFC2662_ADSL_LINE::adsl-perf-lofs');
            &{$applySelectors}('LofsMonitor', 'Lofs');
        }

        if( $adslIntf->{'adslAtucPerfCurr1DayLoss'} and
            $adslIntf->{'adslAturPerfCurr1DayLoss'} )
        {
            push( @{$templates}, 'RFC2662_ADSL_LINE::adsl-perf-loss');
            &{$applySelectors}('LossMonitor', 'Loss');
        }

        if( $adslIntf->{'adslAtucPerfCurr1DayLprs'} and
            $adslIntf->{'adslAturPerfCurr1DayLprs'} )
        {
            push( @{$templates}, 'RFC2662_ADSL_LINE::adsl-perf-lprs');
            &{$applySelectors}('LprsMonitor', 'Lprs');
        }

        if( $adslIntf->{'adslAtucPerfCurr1DayESs'} and
            $adslIntf->{'adslAturPerfCurr1DayESs'} )
        {
            push( @{$templates}, 'RFC2662_ADSL_LINE::adsl-perf-ess');
            &{$applySelectors}('ESsMonitor', 'ESs');
        }

        if( $adslIntf->{'adslAtucPerfCurr1DayInits'} )
        {
            push( @{$templates}, 'RFC2662_ADSL_LINE::adsl-perf-inits');
            my $arg = $adslIntf->{'selectorActions'}{'AtucInitsMonitor'};
            if( defined($arg) )
            {
                $childParams->{'Atuc_Inits'}{'monitor'} = $arg;
            }
        }
        
        if( scalar(@{$templates}) > 0 )
        {
            my $lineNode = $cb->addSubtree( $subtreeNode, $ifSubtreeName,
                                            $ifParam, $templates );

            if( scalar(keys %{$childParams}) > 0 )
            {
                foreach my $childName ( sort keys %{$childParams} )
                {
                    $cb->addLeaf
                        ( $lineNode, $childName,
                          $childParams->{$childName} );
                }
            }
        }
    }

    return;
}


#######################################
# Selectors interface
#

$Torrus::DevDiscover::selectorsRegistry{'RFC2662_ADSL_LINE'} = {
    'getObjects'      => \&getSelectorObjects,
    'getObjectName'   => \&getSelectorObjectName,
    'checkAttribute'  => \&checkSelectorAttribute,
    'applyAction'     => \&applySelectorAction,
};


## Objects are interface indexes

sub getSelectorObjects
{
    my $devdetails = shift;
    my $objType = shift;
    return( sort {$a<=>$b} keys (%{$devdetails->data()->{'AdslLine'}}) );
}


sub checkSelectorAttribute
{
    my $devdetails = shift;
    my $object = shift;
    my $objType = shift;
    my $attr = shift;
    my $checkval = shift;

    my $data = $devdetails->data();
    my $interface = $data->{'interfaces'}{$object};
    
    if( $attr =~ /^ifSubtreeName\d*$/ )
    {
        my $value = $interface->{$data->{'nameref'}{'ifSubtreeName'}};
        my $match = 0;
        foreach my $chkexpr ( split( /\s+/, $checkval ) )
        {
            if( $value =~ $chkexpr )
            {
                $match = 1;
                last;
            }
        }
        return $match;        
    }
}


sub getSelectorObjectName
{
    my $devdetails = shift;
    my $object = shift;
    my $objType = shift;
    
    my $data = $devdetails->data();
    my $interface = $data->{'interfaces'}{$object};
    return $interface->{$data->{'nameref'}{'ifSubtreeName'}};
}


# Other discovery modules can add their interface actions here
our %knownSelectorActions =
    ( 'AtucSnrMonitor'     => 'RFC2662_ADSL_LINE',
      'AturSnrMonitor'     => 'RFC2662_ADSL_LINE',
      'AtucAtnMonitor'     => 'RFC2662_ADSL_LINE',
      'AturAtnMonitor'     => 'RFC2662_ADSL_LINE',
      'AtucAttRateMonitor' => 'RFC2662_ADSL_LINE',
      'AturAttRateMonitor' => 'RFC2662_ADSL_LINE',
      'AtucTxRateMonitor'  => 'RFC2662_ADSL_LINE',
      'AturTxRateMonitor'  => 'RFC2662_ADSL_LINE',
      'AtucLofsMonitor'    => 'RFC2662_ADSL_LINE',
      'AturLofsMonitor'    => 'RFC2662_ADSL_LINE',
      'AtucLossMonitor'    => 'RFC2662_ADSL_LINE',
      'AturLossMonitor'    => 'RFC2662_ADSL_LINE',
      'AtucLprsMonitor'    => 'RFC2662_ADSL_LINE',
      'AturLprsMonitor'    => 'RFC2662_ADSL_LINE',
      'AtucESsMonitor'     => 'RFC2662_ADSL_LINE',
      'AturESsMonitor'     => 'RFC2662_ADSL_LINE',
      'AtucInitsMonitor'   => 'RFC2662_ADSL_LINE',
    );

                            
sub applySelectorAction
{
    my $devdetails = shift;
    my $object = shift;
    my $objType = shift;
    my $action = shift;
    my $arg = shift;

    my $data = $devdetails->data();
    my $adslIntf = $data->{'AdslLine'}{$object};

    if( defined( $knownSelectorActions{$action} ) )
    {
        if( not $devdetails->isDevType( $knownSelectorActions{$action} ) )
        {
            Error('Action ' . $action . ' is applied to a device that is ' .
                  'not of type ' . $knownSelectorActions{$action} .
                  ': ' . $devdetails->param('system-id'));
        }
        $adslIntf->{'selectorActions'}{$action} = $arg;
    }
    else
    {
        Error('Unknown RFC2863_IF_MIB selector action: ' . $action);
    }

    return;
}




1;


# Local Variables:
# mode: perl
# indent-tabs-mode: nil
# perl-indent-level: 4
# End:
