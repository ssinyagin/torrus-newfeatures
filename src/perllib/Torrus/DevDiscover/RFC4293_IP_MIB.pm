#  Copyright (C) 2014  Stanislav Sinyagin
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

# IP-MIB traffic statistics

# Different routers and software versions implement this MIB to a
# different extent, so these statistics need to be enabled explicitly by
# discovery parameters. By default, IP-MIB stats are not discovered.


package Torrus::DevDiscover::RFC4293_IP_MIB;

use strict;
use warnings;

use Torrus::Log;


$Torrus::DevDiscover::registry{'RFC4293_IP_MIB'} = {
    'sequence'     => 100,
    'checkdevtype' => \&checkdevtype,
    'discover'     => \&discover,
    'buildConfig'  => \&buildConfig
    };



our %oiddef =
    (
     # IP-MIB
     'ipIfStatsHCInOctets_ipv4'         => '1.3.6.1.2.1.4.31.3.1.6.1',
     'ipIfStatsHCInOctets_ipv6'         => '1.3.6.1.2.1.4.31.3.1.6.2',
     );


my %inetVersion = (ipv4 => 1, ipv6 => 2);


sub checkdevtype
{
    my $dd = shift;
    my $devdetails = shift;

    my $data = $devdetails->data();
    my $matched = 0;
    
    if( $devdetails->paramEnabled('RFC4293_IP_MIB::ipv4-stats') and
        $dd->checkSnmpTable('ipIfStatsHCInOctets_ipv4') )
    {
        $matched = 1;
        $devdetails->setCap('ipIfStatsHCInOctets_ipv4');
    }
    
    if( $devdetails->paramEnabled('RFC4293_IP_MIB::ipv6-stats') and
        $dd->checkSnmpTable('ipIfStatsHCInOctets_ipv6') )
    {
        $matched = 1;
        $devdetails->setCap('ipIfStatsHCInOctets_ipv6');
    }

    return $matched;
}


sub discover
{
    my $dd = shift;
    my $devdetails = shift;

    my $data = $devdetails->data();
    my $session = $dd->session();

    foreach my $ipver ('ipv4', 'ipv6')
    {
        if( $devdetails->hasCap('ipIfStatsHCInOctets_' . $ipver) )
        {
            my $ifStats = $dd->walkSnmpTable('ipIfStatsHCInOctets_' . $ipver);
            foreach my $ifIndex (keys %{$ifStats})
            {
                my $interface = $data->{'interfaces'}{$ifIndex};
                next if not defined($interface);
                next if $interface->{'excluded'};
                
                $data->{'ipIfStats'}{$ipver}{$ifIndex} = 1;
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

    foreach my $ipverUC ('IPv4', 'IPv6')
    {
        my $ipver = lc($ipverUC);
        next unless $devdetails->hasCap('ipIfStatsHCInOctets_' . $ipver);
        
        my $subtreeName = $ipverUC . '_Stats';
        
        my $subtreeParam = {
            'precedence'          => '-600',
            'node-display-name'   => $ipverUC . ' traffic statistics',
            'comment'        => 'per-interface in/out bytes for ' . $ipverUC,
            'ipmib-ipver' => $inetVersion{$ipver},
            'ipmib-ipver-name' => $ipver,
            'ipmib-ipver-nameuc' => $ipverUC,
        };
        
        my $subtreeNode =
            $cb->addSubtree( $devNode, $subtreeName, $subtreeParam,
                             ['RFC4293_IP_MIB::rfc4293-ipmib-subtree']);
        
        my $precedence = 1000;        
        foreach my $ifIndex ( sort {$a<=>$b} %{$data->{'ipIfStats'}{$ipver}} )
        {
            my $interface = $data->{'interfaces'}{$ifIndex};
            next if not defined($interface);
            next if $interface->{'excluded'};

            my $ifSubtreeName =
                $interface->{$data->{'nameref'}{'ifSubtreeName'}};

            my $ifParam = {};
            
            $ifParam->{'collector-timeoffset-hashstring'} =
                '%system-id%:%interface-nick%';
            $ifParam->{'precedence'} = $precedence;
            
            $ifParam->{'graph-title'} =
                '%system-id%:%interface-name% ' . $ipverUC;
            
            $ifParam->{'interface-name'} =
                $interface->{$data->{'nameref'}{'ifReferenceName'}};
            $ifParam->{'interface-nick'} =
                $interface->{$data->{'nameref'}{'ifNick'}};
            $ifParam->{'node-display-name'} =
                $interface->{$data->{'nameref'}{'ifReferenceName'}};
            
            $ifParam->{'nodeid-interface'} =
                $ipver . '-' .
                $interface->{$data->{'nameref'}{'ifNodeidPrefix'}} .
                $interface->{$data->{'nameref'}{'ifNodeid'}};
            
            if( defined($data->{'nameref'}{'ifComment'}) and
                defined($interface->{$data->{'nameref'}{'ifComment'}}) )
            {
                $ifParam->{'comment'} =
                    $interface->{$data->{'nameref'}{'ifComment'}};
            }

            my $templates = ['RFC4293_IP_MIB::ipifstats-hcoctets'];
            my $childParams = {};

            my $actionsRef =
                $data->{'ipIfStats_SelectorActions'}{$ipver}{$ifIndex};
            if( defined($actionsRef) )
            {
                foreach my $dir ( 'In', 'Out' )
                {
                    if( defined( $actionsRef->{$dir . 'BytesMonitor'} ) )
                    {
                        $childParams->{
                            'Bytes_' . $dir}->{'monitor'} =
                                $actionsRef->{$dir . 'BytesMonitor'};
                    }

                    if( defined( $actionsRef->{$dir . 'BytesParameters'} ) )
                    {
                        my @pairs =
                            split('\s*;\s*',
                                  $actionsRef->{$dir . 'BytesParameters'});
                        
                        foreach my $pair( @pairs )
                        {
                            my ($param, $val) = split('\s*=\s*', $pair);
                            $childParams->{
                                'Bytes_' . $dir}->{$param} = $val;
                        }
                    }
                }
            }
                        
            if( scalar(@{$templates}) > 0 )
            {
                my $intfNode = $cb->addSubtree( $subtreeNode, $ifSubtreeName,
                                                $ifParam, $templates );
                
                if( scalar(keys %{$childParams}) > 0 )
                {
                    foreach my $childName ( sort keys %{$childParams} )
                    {
                        $cb->addLeaf
                            ( $intfNode, $childName,
                              $childParams->{$childName} );
                    }
                }
            }
        }
    }
        
    return;
}



#######################################
# Selectors interface
#

$Torrus::DevDiscover::selectorsRegistry{'RFC4293_IP_MIB_v4'} = {
    'getObjects'      => \&v4_getSelectorObjects,
    'getObjectName'   => \&v4_getSelectorObjectName,
    'checkAttribute'  => \&v4_checkSelectorAttribute,
    'applyAction'     => \&v4_applySelectorAction,
};

$Torrus::DevDiscover::selectorsRegistry{'RFC4293_IP_MIB_v6'} = {
    'getObjects'      => \&v6_getSelectorObjects,
    'getObjectName'   => \&v6_getSelectorObjectName,
    'checkAttribute'  => \&v6_checkSelectorAttribute,
    'applyAction'     => \&v6_applySelectorAction,
};


sub v4_getSelectorObjects {getSelectorObjects('ipv4', @_)};
sub v4_getSelectorObjectName {getSelectorObjectName('ipv4', @_)};
sub v4_checkSelectorAttribute {checkSelectorAttribute('ipv4', @_)};
sub v4_applySelectorAction {applySelectorAction('ipv4', @_)};

sub v6_getSelectorObjects {getSelectorObjects('ipv6', @_)};
sub v6_getSelectorObjectName {getSelectorObjectName('ipv6', @_)};
sub v6_checkSelectorAttribute {checkSelectorAttribute('ipv6', @_)};
sub v6_applySelectorAction {applySelectorAction('ipv6', @_)};


## Objects are interface indexes

sub getSelectorObjects
{
    my $ipver = shift;
    my $devdetails = shift;
    my $objType = shift;
    return( sort {$a<=>$b} keys
            (%{$devdetails->data()->{'ipIfStats'}{$ipver}}) );
}


sub checkSelectorAttribute
{
    my $ipver = shift;
    my $devdetails = shift;
    my $object = shift;
    my $objType = shift;
    my $attr = shift;
    my $checkval = shift;

    my $data = $devdetails->data();
    my $interface = $data->{'interfaces'}{$object};
    if( not defined($interface) or $interface->{'excluded'} )
    {
        return 0;
    }
    
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

    return 0;
}


sub getSelectorObjectName
{
    my $ipver = shift;
    my $devdetails = shift;
    my $object = shift;
    my $objType = shift;
    
    my $data = $devdetails->data();
    my $interface = $data->{'interfaces'}{$object};
    return $interface->{$data->{'nameref'}{'ifSubtreeName'}};
}


our %knownSelectorActions =
    (
     'InBytesMonitor'    => 'RFC4293_IP_MIB',
     'OutBytesMonitor'   => 'RFC4293_IP_MIB',
     'InBytesParameters' => 'RFC4293_IP_MIB',
     'OutBytesParameters' => 'RFC4293_IP_MIB',
    );

                            
sub applySelectorAction
{
    my $ipver = shift;
    my $devdetails = shift;
    my $object = shift;
    my $objType = shift;
    my $action = shift;
    my $arg = shift;

    my $data = $devdetails->data();

    if( defined( $knownSelectorActions{$action} ) )
    {
        if( not $devdetails->isDevType( $knownSelectorActions{$action} ) )
        {
            Error('Action ' . $action . ' is applied to a device that is ' .
                  'not of type ' . $knownSelectorActions{$action} .
                  ': ' . $devdetails->param('system-id'));
        }
        $data->{'ipIfStats_SelectorActions'}{$ipver}{$object}{$action} = $arg;
    }
    else
    {
        Error('Unknown RFC4293_IP_MIB selector action: ' . $action);
    }

    return;
}







1;


# Local Variables:
# mode: perl
# indent-tabs-mode: nil
# perl-indent-level: 4
# End:
