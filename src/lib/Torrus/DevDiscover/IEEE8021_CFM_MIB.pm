#  Copyright (C) 2018  Stanislav Sinyagin
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

# Stanislav Sinyagin <ssinyagin@k-open.com>

# Discovery module for IEEE8021-CFM-MIB
# This module does not generate any XML, but provides information
# for other discovery modules

package Torrus::DevDiscover::IEEE8021_CFM_MIB;

use strict;
use warnings;

use Torrus::Log;

$Torrus::DevDiscover::registry{'IEEE8021_CFM_MIB'} = {
    'sequence'     => 100,
    'checkdevtype' => \&checkdevtype,
    'discover'     => \&discover,
    'buildConfig'  => \&buildConfig
    };


our %oiddef =
    (
     # IEEE8021-CFM-MIB
     'dot1agCfmMdTable'        => '1.3.111.2.802.1.1.8.1.5.2',
     'dot1agCfmMdFormat'       => '1.3.111.2.802.1.1.8.1.5.2.1.2',
     'dot1agCfmMdName'         => '1.3.111.2.802.1.1.8.1.5.2.1.3',
     'dot1agCfmMdMdLevel'      => '1.3.111.2.802.1.1.8.1.5.2.1.4',
     'dot1agCfmMdRowStatus'    => '1.3.111.2.802.1.1.8.1.5.2.1.8',
     
     'dot1agCfmMaNetFormat'    => '1.3.111.2.802.1.1.8.1.6.1.1.2',
     'dot1agCfmMaNetName'      => '1.3.111.2.802.1.1.8.1.6.1.1.3',
     'dot1agCfmMaNetCcmInterval' => '1.3.111.2.802.1.1.8.1.6.1.1.4',
     'dot1agCfmMaNetRowStatus' => '1.3.111.2.802.1.1.8.1.6.1.1.5',

     'dot1agCfmMepIfIndex'     => '1.3.111.2.802.1.1.8.1.7.1.1.2',
     'dot1agCfmMepDirection'   => '1.3.111.2.802.1.1.8.1.7.1.1.3',
     'dot1agCfmMepPrimaryVid'  => '1.3.111.2.802.1.1.8.1.7.1.1.4',
     'dot1agCfmMepActive'      => '1.3.111.2.802.1.1.8.1.7.1.1.5',
     
     );

my %ccmIntervalMap =
    (
     0 => 'invalid',
     1 => '300Hz',
     2 => '10ms',
     3 => '100ms',
     4 => '1s',
     5 => '10s',
     6 => '1min',
     7 => '10min',
     );


sub checkdevtype
{
    my $dd = shift;
    my $devdetails = shift;

    my $session = $dd->session();
    my $data = $devdetails->data();

    return( $dd->checkSnmpTable('dot1agCfmMdTable') );
}


sub discover
{
    my $dd = shift;
    my $devdetails = shift;

    my $data = $devdetails->data();
    my $session = $dd->session();

    $data->{'dot1ag'} = {};

    my $mdFormat = $dd->walkSnmpTable('dot1agCfmMdFormat');
    my $mdName = $dd->walkSnmpTable('dot1agCfmMdName');
    my $mdMdLevel = $dd->walkSnmpTable('dot1agCfmMdMdLevel');
    my $mdRowStatus = $dd->walkSnmpTable('dot1agCfmMdRowStatus');
    
    foreach my $mdIndex ( keys %{$mdRowStatus} )
    {
        next if $mdRowStatus->{$mdIndex} != 1;

        my $format = $mdFormat->{$mdIndex};
        if( $format == 0 )
        {
            Warn('dot1agCfmMdFormat.' . $mdIndex . ' is zero');
            next;
        }
        
        next if $format == 1;       
        
        my $name;
        my $nameRaw = $mdName->{$mdIndex};
        if( $format == 2 or $format == 4 )
        {
            $name = $nameRaw;
        }
        elsif( $format == 3 )
        {
            # the best we can do, maybe will do better
            $name = unpack('h*', $nameRaw);
            Warn('Interpretation of dot1agCfmMdName.' . $mdIndex .
                 ' might not be correct');
        }
        else
        {
            Error('Unsupported value (' . $format . ') in dot1agCfmMdFormat.' .
                  $mdIndex);
            next;
        }
        
        $data->{'dot1ag'}{$mdIndex} = {
            'name' => $name,
            'level' => $mdMdLevel->{$mdIndex},
        };            
    }

    my $maFormat = $dd->walkSnmpTable('dot1agCfmMaNetFormat');
    my $maName = $dd->walkSnmpTable('dot1agCfmMaNetName');
    my $maCcmInterval = $dd->walkSnmpTable('dot1agCfmMaNetCcmInterval');
    my $maRowStatus = $dd->walkSnmpTable('dot1agCfmMaNetRowStatus');
    
    foreach my $maIndex ( keys %{$maRowStatus} )
    {
        next if $maRowStatus->{$maIndex} != 1;
        
        my $format = $maFormat->{$maIndex};
        if( $format == 0 )
        {
            Warn('dot1agCfmMaNetFormat.' . $maIndex . ' is zero');
            next;
        }

        my $warn; # some presentations need more testing
        my $name;
        my $nameRaw = $maName->{$maIndex};
        
        if( $format == 1 ) # primaryVid
        {
            $warn = 1;
            $name = 'VID' . unpack('n', $nameRaw);            
        }
        elsif( $format == 2 )
        {
            $name = $nameRaw;
        }
        elsif( $format == 3 )
        {
            $warn = 1;
            $name = unpack('n', $nameRaw);
        }
        elsif( $format == 4 )
        {
            $warn = 1;
            $name = 'VPN' . join(unpack('h*', $nameRaw));
        }
        else
        {
            Error('Unsupported value (' . $format .
                  ') in dot1agCfmMaNetFormat.' . $maIndex);
            next;
        }

        if( $warn )
        {
            Warn('Interpretation of dot1agCfmMaNetName.' . $maIndex .
                 ' might not be correct: ' . $name);
        }

        my $intvl = $ccmIntervalMap{$maCcmInterval->{$maIndex}};
        if( not defined($intvl) )
        {
            Error('Unsupported value ('. $maCcmInterval->{$maIndex} .
                  ') in dot1agCfmMaNetCcmInterval.' . $maIndex);
            $intvl = 'invalid';
        }

        my ($mdIndex, $ma) = split(/\./, $maIndex);
        $data->{'dot1ag'}{$mdIndex}{'ma'}{$ma} = {
            'name' => $name,
            'interval' => $intvl,
        };
    }
        
    my $mepIfIndex = $dd->walkSnmpTable('dot1agCfmMepIfIndex');
    my $mepDirection = $dd->walkSnmpTable('dot1agCfmMepDirection');
    my $mepVid = $dd->walkSnmpTable('dot1agCfmMepPrimaryVid');
    my $mepActive = $dd->walkSnmpTable('dot1agCfmMepActive');

    foreach my $mepIndex (keys %{$mepIfIndex})
    {
        my $ifIndex = $mepIfIndex->{$mepIndex};
        my $interface = $data->{'interfaces'}{$ifIndex};
        next if $interface->{'excluded'};

        my $dir = ($mepDirection->{$mepIndex} == 1) ? 'down':'up';

        my $ref = {
            'ifIndex' => $ifIndex,
            'direction' => $dir,
        };

        if( defined($mepActive) and defined($mepActive->{$mepIndex}) )
        {
            $ref->{'active'} = $mepActive->{$mepIndex} == 1 ? 1:0;
        }

        if( defined($mepVid) and defined($mepVid->{$mepIndex}) )
        {
            $ref->{'VID'} = $mepVid->{$mepIndex};
        }
                
        my ($mdIndex, $ma, $mep) = split(/\./, $mepIndex);
        $data->{'dot1ag'}{$mdIndex}{'ma'}{$ma}{'mep'}{$mep} = $ref;
    }
    
    return 1;
}


sub buildConfig
{
    my $devdetails = shift;
    my $cb = shift;
    my $devNode = shift;
    return;
}


1;


# Local Variables:
# mode: perl
# indent-tabs-mode: nil
# perl-indent-level: 4
# End:
