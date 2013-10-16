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

        if( $data->{'AdslLine'}{$ifIndex}{'adslAtucCurrSnrMgn'} and
            $data->{'AdslLine'}{$ifIndex}{'adslAturCurrSnrMgn'} )
        {
            push( @{$templates}, 'RFC2662_ADSL_LINE::adsl-line-snr');
        }
        
        if( $data->{'AdslLine'}{$ifIndex}{'adslAtucCurrAtn'} and
            $data->{'AdslLine'}{$ifIndex}{'adslAturCurrAtn'} )
        {
            push( @{$templates}, 'RFC2662_ADSL_LINE::adsl-line-atn');
        }

        if( $data->{'AdslLine'}{$ifIndex}{'adslAtucCurrAttainableRate'} and
            $data->{'AdslLine'}{$ifIndex}{'adslAturCurrAttainableRate'} )
        {
            push( @{$templates}, 'RFC2662_ADSL_LINE::adsl-line-attrate');
        }
        
        if( $data->{'AdslLine'}{$ifIndex}{'adslAtucChanCurrTxRate'} and
            $data->{'AdslLine'}{$ifIndex}{'adslAturChanCurrTxRate'} )
        {
            push( @{$templates}, 'RFC2662_ADSL_LINE::adsl-channel-txrate');
        }

        if( $data->{'AdslLine'}{$ifIndex}{'adslAtucPerfCurr1DayLofs'} and
            $data->{'AdslLine'}{$ifIndex}{'adslAturPerfCurr1DayLofs'} )
        {
            push( @{$templates}, 'RFC2662_ADSL_LINE::adsl-perf-lofs');
        }

        if( $data->{'AdslLine'}{$ifIndex}{'adslAtucPerfCurr1DayLoss'} and
            $data->{'AdslLine'}{$ifIndex}{'adslAturPerfCurr1DayLoss'} )
        {
            push( @{$templates}, 'RFC2662_ADSL_LINE::adsl-perf-loss');
        }

        if( $data->{'AdslLine'}{$ifIndex}{'adslAtucPerfCurr1DayLprs'} and
            $data->{'AdslLine'}{$ifIndex}{'adslAturPerfCurr1DayLprs'} )
        {
            push( @{$templates}, 'RFC2662_ADSL_LINE::adsl-perf-lprs');
        }

        if( $data->{'AdslLine'}{$ifIndex}{'adslAtucPerfCurr1DayESs'} and
            $data->{'AdslLine'}{$ifIndex}{'adslAturPerfCurr1DayESs'} )
        {
            push( @{$templates}, 'RFC2662_ADSL_LINE::adsl-perf-ess');
        }

        if( $data->{'AdslLine'}{$ifIndex}{'adslAtucPerfCurr1DayInits'} )
        {
            push( @{$templates}, 'RFC2662_ADSL_LINE::adsl-perf-inits');
        }
        
        if( scalar(@{$templates}) > 0 )
        {
            $cb->addSubtree( $subtreeNode, $ifSubtreeName,
                             $ifParam, $templates );
        }
    }

    return;
}


1;


# Local Variables:
# mode: perl
# indent-tabs-mode: nil
# perl-indent-level: 4
# End:
