#  Copyright (C) 2002-2016  Stanislav Sinyagin
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

# Cisco IOS Service Assurance Agent
# TODO:
#   should really consider rtt-type and rtt-echo-protocol when applying
#   per-rtt templates
#
#   translate TOS bits into DSCP values

package Torrus::DevDiscover::CiscoIOS_SAA;

use strict;
use warnings;

use Socket qw(inet_ntoa);
use Torrus::Log;

$Torrus::DevDiscover::registry{'CiscoIOS_SAA'} = {
    'sequence'     => 600,
    'checkdevtype' => \&checkdevtype,
    'discover'     => \&discover,
    'buildConfig'  => \&buildConfig
    };


our %oiddef =
    (
     # CISCO-RTTMON-MIB
     'rttMonCtrlAdminTable'               => '1.3.6.1.4.1.9.9.42.1.2.1',
     'rttMonCtrlAdminOwner'               => '1.3.6.1.4.1.9.9.42.1.2.1.1.2',
     'rttMonCtrlAdminTag'                 => '1.3.6.1.4.1.9.9.42.1.2.1.1.3',
     'rttMonCtrlAdminRttType'             => '1.3.6.1.4.1.9.9.42.1.2.1.1.4',
     'rttMonCtrlAdminFrequency'           => '1.3.6.1.4.1.9.9.42.1.2.1.1.6',
     'rttMonCtrlAdminStatus'              => '1.3.6.1.4.1.9.9.42.1.2.1.1.9',
     'rttMonEchoAdminTable'               => '1.3.6.1.4.1.9.9.42.1.2.2',
     'rttMonEchoAdminProtocol'            => '1.3.6.1.4.1.9.9.42.1.2.2.1.1',
     'rttMonEchoAdminTargetAddress'       => '1.3.6.1.4.1.9.9.42.1.2.2.1.2',
     'rttMonEchoAdminPktDataRequestSize'  => '1.3.6.1.4.1.9.9.42.1.2.2.1.3',
     'rttMonEchoAdminTargetPort'          => '1.3.6.1.4.1.9.9.42.1.2.2.1.5',
     'rttMonEchoAdminTOS'                 => '1.3.6.1.4.1.9.9.42.1.2.2.1.9',
     'rttMonEchoAdminTargetAddressString' => '1.3.6.1.4.1.9.9.42.1.2.2.1.11',
     'rttMonEchoAdminNameServer'          => '1.3.6.1.4.1.9.9.42.1.2.2.1.12',
     'rttMonEchoAdminURL'                 => '1.3.6.1.4.1.9.9.42.1.2.2.1.15',
     'rttMonEchoAdminInterval'            => '1.3.6.1.4.1.9.9.42.1.2.2.1.17',
     'rttMonEchoAdminNumPackets'          => '1.3.6.1.4.1.9.9.42.1.2.2.1.18',
     'rttMonEchoAdminTargetMPID'          => '1.3.6.1.4.1.9.9.42.1.2.2.1.49',
     'rttMonEchoAdminTargetDomainName'    => '1.3.6.1.4.1.9.9.42.1.2.2.1.50',
     'rttMonEchoAdminTargetEVC'           => '1.3.6.1.4.1.9.9.42.1.2.2.1.54',
     'rttMonEchoAdminSourceMPID'          => '1.3.6.1.4.1.9.9.42.1.2.2.1.66',
     );


our %appltemplates =
    ('jitterAppl' => ['CiscoIOS_SAA::cisco-rtt-jitter-subtree']);


our %adminInterpret =
    (
     'rttMonCtrlAdminOwner' => {
         'order'   => 10,
         'legend'  => 'Owner: %s;',
         'param'   => 'rtt-owner'
         },

     'rttMonCtrlAdminTag' => {
         'order'   => 20,
         'legend'  => 'Tag: %s;',
         'comment' => '%s: ',
         'param'   => 'rtt-tag'
         },

     'rttMonCtrlAdminRttType' => {
         'order'   => 30,
         'legend'  => 'Type: %s;',
         'translate' => \&translateRttType,
         'param'   => 'rtt-type'
         },

     'rttMonCtrlAdminFrequency' => {
         'order'   => 40,
         'legend'  => 'Frequency: %d seconds;',
         'param'   => 'rtt-frequency'
         },

     'rttMonEchoAdminProtocol' => {
         'order'   => 50,
         'legend'  => 'Protocol: %s;',
         'translate' => \&translateRttEchoProtocol,
         'param'   => 'rtt-echo-protocol'
         },

     'rttMonEchoAdminTargetAddress' => {
         'order'   => 60,
         'legend'  => 'Target: %s;',
         'comment' => 'Target=%s ',
         'translate' => \&translateRttTargetAddr,
         'param'   => 'rtt-echo-target-addr',
         'ignore-text' => '0.0.0.0'
         },

     'rttMonEchoAdminPktDataRequestSize' => {
         'order'   => 70,
         'legend'  => 'Packet size: %d octets;',
         'param'   => 'rtt-echo-request-size'
         },

     'rttMonEchoAdminTargetPort' => {
         'order'   => 80,
         'legend'  => 'Port: %d;',
         'param'   => 'rtt-echo-port',
         'ignore-numeric' => 0
         },

     'rttMonEchoAdminTOS' => {
         'order'   => 90,
         'legend'  => 'TOS: %d;',
         'comment' => 'TOS=%d ',
         'param'   => 'rtt-echo-tos',
         'ignore-numeric' => 0
         },

     'rttMonEchoAdminTargetAddressString' => {
         'order'   => 100,
         'legend'  => 'Address string: %s;',
         'param'   => 'rtt-echo-addr-string'
         },

     'rttMonEchoAdminNameServer' => {
         'order'   => 110,
         'legend'  => 'NameServer: %s;',
         'translate' => \&translateRttTargetAddr,
         'param'   => 'rtt-echo-name-server',
         'ignore-text' => '0.0.0.0'
         },

     'rttMonEchoAdminURL' => {
         'order'   => 120,
         'legend'  => 'URL: %s;',
         'param'   => 'rtt-echo-url'
         },

     'rttMonEchoAdminInterval' => {
         'order'   => 130,
         'legend'  => 'Interval: %d milliseconds;',
         'param'   => 'rtt-echo-interval',
         'ignore-numeric' => 0
         },

     'rttMonEchoAdminNumPackets' => {
         'order'   => 140,
         'legend'  => 'Packets: %d;',
         'param'   => 'rtt-echo-num-packets',
         'ignore-numeric' => 0
         },

     'rttMonEchoAdminTargetMPID' => {
         'order'   => 150,
         'legend'  => 'Target MPID: %d;',
         'param'   => 'rtt-echo-target-mpid',
     },

     'rttMonEchoAdminTargetDomainName' => {
         'order'   => 160,
         'legend'  => 'Target Domain: %s;',
         'param'   => 'rtt-echo-target-mdname',
     },
         
     'rttMonEchoAdminTargetEVC' => {
         'order'   => 170,
         'legend'  => 'Target EVC: %s;',
         'param'   => 'rtt-echo-target-evc',
     },
     
     'rttMonEchoAdminSourceMPID' => {
         'order'   => 180,
         'legend'  => 'Source MPID: %d;',
         'param'   => 'rtt-echo-source-mpid',
     },
         
     );



sub checkdevtype
{
    my $dd = shift;
    my $devdetails = shift;

    my $session = $dd->session();

    if( $devdetails->isDevType('CiscoIOS') )
    {
        if( $dd->checkSnmpTable('rttMonCtrlAdminTable') )
        {
            return 1;
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

    $data->{'cisco_rtt'} = {};
    $data->{'soam_entries'} = {};

    my $adminValues = {};
    foreach my $adminField
        ( sort {$adminInterpret{$a}{'order'} <=>
                    $adminInterpret{$b}{'order'}}
          keys %adminInterpret )
    {
        my $table = $dd->walkSnmpTable($adminField);
        if( scalar(keys %{$table}) > 0 )
        {
            $adminValues->{$adminField} = $table;
        }
    }
            
    my $rttStatus = $dd->walkSnmpTable('rttMonCtrlAdminStatus');

    foreach my $rttIndex (keys %{$rttStatus})
    {
        # we're interested in Active agents only
        if( $rttStatus->{$rttIndex} != 1 )
        {
            next;
        }

        my $ref = {};
        $ref->{'param'} = {};

        my $comment = '';
        my $legend = '';

        foreach my $adminField
            ( sort {$adminInterpret{$a}{'order'} <=>
                        $adminInterpret{$b}{'order'}}
              keys %{$adminValues} )
        {
            my $value = $adminValues->{$adminField}{$rttIndex};
            
            if( defined( $value ) and length( $value ) > 0 )
            {
                my $intrp = $adminInterpret{$adminField};
                if( ref( $intrp->{'translate'} ) )
                {
                    $value = &{$intrp->{'translate'}}( $value );
                }

                next unless defined($value);
                
                if( ( defined( $intrp->{'ignore-numeric'} ) and
                      $value == $intrp->{'ignore-numeric'} )
                    or
                    ( defined( $intrp->{'ignore-text'} ) and
                      $value eq $intrp->{'ignore-text'} ) )
                {
                    next;
                }

                if( defined( $intrp->{'param'} ) )
                {
                    $ref->{'param'}{$intrp->{'param'}} = $value;
                }

                if( defined( $intrp->{'comment'} ) )
                {
                    $comment .= sprintf( $intrp->{'comment'}, $value );
                }

                if( defined( $intrp->{'legend'} ) )
                {
                    $legend .= sprintf( $intrp->{'legend'}, $value );
                }
            }
        }

        $ref->{'param'}{'rtt-index'} = $rttIndex;
        $ref->{'param'}{'comment'} = $comment;
        $ref->{'param'}{'legend'} = $legend;

        my $type = $adminValues->{'rttMonCtrlAdminRttType'}{$rttIndex};

        if( $type == 24 or $type == 23 )
        {
            $ref->{'nodeid-prefix'} =
                'soam//%nodeid-device%' . '//' . $rttIndex;

            my $mdname = $ref->{'param'}{'rtt-echo-target-mdname'};
            if( not defined($mdname) )
            {
                Error('CFM measurement without MD Name: idx=' . $rttIndex);
                next;
            }
        
            my $md;
            foreach my $mdidx (keys %{$data->{'dot1ag'}})
            {
                if( $data->{'dot1ag'}{$mdidx}{'name'} eq $mdname )
                {
                    $md = $mdidx;
                    last;
                }
            }

            if( not defined($md) )
            {
                Error('Cannot find IEEE8021-CFM-MIB MD: ' . $mdname);
                next;
            }

            my $mddata = $data->{'dot1ag'}{$md};

            my $maname = $ref->{'param'}{'rtt-echo-target-evc'};
            my $ma;
            foreach my $maidx (keys %{$mddata->{'ma'}})
            {
                if( $mddata->{'ma'}{$maidx}{'name'} eq $maname )
                {
                    $ma = $maidx;
                    last;
                }
            }
            
            if( not defined($ma) )
            {
                Error('Cannot find IEEE8021-CFM-MIB MA: ' .
                      join('.', $mdname, $maname));
                next;
            }

            my $mep = $ref->{'param'}{'rtt-echo-source-mpid'};                
            
            $ref->{'md'} = $md;
            $ref->{'ma'} = $ma;
            $ref->{'mep'} = $mep;
        }            
        
        if( $type == 24 )
        {
            if( $devdetails->isDevType('IEEE8021_CFM_MIB') )
            {
                $ref->{'templates'} =
                    ['CiscoIOS_SAA::cisco-saa-soam-lm'];
                $data->{'cisco_soam_lmm'}{$rttIndex} = $ref;
            }
            else
            {
                Error("Found SAA measurement of SOAM LMM, but " .
                      $devdetails->param('snmp-host') . " is not of type " .
                      "IEEE8021_CFM_MIB");
            }
        }   
        elsif( $type == 23 )
        {
            if( $devdetails->isDevType('IEEE8021_CFM_MIB') )
            {
                $ref->{'templates'} =
                    ['CiscoIOS_SAA::cisco-saa-soam-dm'];
                $data->{'cisco_soam_dmm'}{$rttIndex} = $ref;
            }
            else
            {
                Error("Found SAA measurement of SOAM DMM, but " .
                      $devdetails->param('snmp-host') . " is not of type " .
                      "IEEE8021_CFM_MIB");
            }   
        }
        else
        {
            $data->{'cisco_rtt'}{$rttIndex} = $ref;
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

    if( scalar(keys %{$data->{'cisco_rtt'}}) > 0 )
    {
        my $subtreeNode =
            $cb->addSubtree( $devNode, 'SAA', undef,
                             ['CiscoIOS_SAA::cisco-saa-subtree']);
        
        foreach my $rttIndex ( sort {$a<=>$b} keys %{$data->{'cisco_rtt'}} )
        {
            my $subtreeName = 'rtt_' . $rttIndex;
            my $param = $data->{'cisco_rtt'}{$rttIndex}{'param'};
            $param->{'precedence'} = sprintf('%d', 10000 - $rttIndex);
            
            my $templates = [];
            my $proto = $param->{'rtt-echo-protocol'};        
            if( defined($proto) and defined($appltemplates{$proto}) )
            {
                push(@{$templates}, @{$appltemplates{$proto}});
            }
            
            if( scalar(@{$templates}) == 0 )
            {
                push(@{$templates}, 'CiscoIOS_SAA::cisco-rtt-echo-subtree');
            }
            
            $cb->addSubtree( $subtreeNode, $subtreeName, $param, $templates );
        }
    }

    if( scalar(keys %{$data->{'cisco_soam_lmm'}}) > 0 )
    {
        my $lmNodeParam = {
            'comment' => 'SOAM Frame Loss Measurement with Cisco SAA',
            'node-display-name' => 'SAA SOAM LM',
        };
        
        my $lmNode =
            $cb->addSubtree( $devNode, 'SAA-SOAM-LM', $lmNodeParam,
                             ['CiscoIOS_SAA::cisco-saa-soam-lm-subtree'] );

        buildSoamConfig($devdetails, $cb, $lmNode, 'cisco_soam_lmm');
    }
        
    if( scalar(keys %{$data->{'cisco_soam_dmm'}}) > 0 )
    {
        my $dmNodeParam = {
            'comment' => 'SOAM Delay Measurement with Cisco SAA',
            'node-display-name' => 'SAA SOAM DM',
        };
        
        my $dmNode =
            $cb->addSubtree( $devNode, 'SAA-SOAM-DM', $dmNodeParam,
                             ['CiscoIOS_SAA::cisco-saa-soam-dm-subtree'] );

        buildSoamConfig($devdetails, $cb, $dmNode, 'cisco_soam_dmm');
    }

    return;
}


sub buildSoamConfig
{
    my $devdetails = shift;
    my $cb = shift;
    my $node = shift;
    my $soamtype = shift;

    my $soamtypeshort = $soamtype eq 'cisco_soam_lmm' ? 'lm':'dm';
        
    my $data = $devdetails->data();
    my $soamdata = $data->{$soamtype};
    
    foreach my $idx (sort keys %{$soamdata})
    {
        my $ref = $soamdata->{$idx};
        my $md = $ref->{'md'};
        my $ma = $ref->{'ma'};
        my $mep = $ref->{'mep'};


        my $mddata = $data->{'dot1ag'}{$md};
        my $madata = $mddata->{'ma'}{$ma};
        
        my $mepdata = $madata->{'mep'}{$mep};
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

        my $targetmep = $ref->{'param'}{'rtt-echo-target-mpid'};
            
        my $legend =
            'MD Name:' . $mddata->{'name'} . ';' .
            'MA Name:' . $madata->{'name'} . ';' .
            'Interval:' . $madata->{'interval'} . ';' .
            'MEP:' . $mep . ';' .
            'Interface:' . $ifname . ';' .
            'Measurement type: ' . $ref->{'param'}{'rtt-echo-protocol'} . ';' .
            'Target: ' . $targetmep;

        my $descr = $madata->{'name'} . ' ' . $mep . '->' . $targetmep;
        my $gtitle = '%system-id% ' . $descr;
        
        my $nodeid = $ref->{'nodeid-prefix'} . '//' . $soamtypeshort;

        $ref->{'param'}{'node-display-name'} = $descr;
           
        $ref->{'param'}{'nodeid'} = $nodeid;
        $ref->{'param'}{'cisco-soam-nodeid'} = $nodeid;
        $ref->{'param'}{'legend'} = $legend;
        $ref->{'param'}{'graph-title'} = $gtitle;
        $ref->{'param'}{'soam-md-name'} = $mddata->{'name'};
        $ref->{'param'}{'soam-ma-name'} = $madata->{'name'};
        
        my $subtreeName = $idx;
        
        $cb->addSubtree( $node, $subtreeName,
                         $ref->{'param'}, $ref->{'templates'} );
    }

    return;
}



my %rttType =
    (
     1  => 'echo',
     2  => 'pathEcho',
     3  => 'fileIO',
     4  => 'script',
     5  => 'udpEcho',
     6  => 'tcpConnect',
     7  => 'http',
     8  => 'dns',
     9  => 'jitter',
     10 => 'dlsw',
     11 => 'dhcp',
     12 => 'ftp',
     13 => 'voip',
     14 => 'rtp',
     15 => 'lspGroup',
     16 => 'icmpjitter',
     17 => 'lspPing',
     18 => 'lspTrace',
     19 => 'ethernetPing',
     20 => 'ethernetJitter',
     21 => 'lspPingPseudowire',
     22 => 'video',
     23 => 'y1731Delay',
     24 => 'y1731Loss',
     25 => 'mcastJitter',
     );

sub translateRttType
{
    my $value = shift;
    return $rttType{$value};
}


my %rttEchoProtocol =
    (
     1  =>  'notApplicable',
     2  =>  'ipIcmpEcho',
     3  =>  'ipUdpEchoAppl',
     4  =>  'snaRUEcho',
     5  =>  'snaLU0EchoAppl',
     6  =>  'snaLU2EchoAppl',
     7  =>  'snaLU62Echo',
     8  =>  'snaLU62EchoAppl',
     9  =>  'appleTalkEcho',
     10 =>  'appleTalkEchoAppl',
     11 =>  'decNetEcho',
     12 =>  'decNetEchoAppl',
     13 =>  'ipxEcho',
     14 =>  'ipxEchoAppl',
     15 =>  'isoClnsEcho',
     16 =>  'isoClnsEchoAppl',
     17 =>  'vinesEcho',
     18 =>  'vinesEchoAppl',
     19 =>  'xnsEcho',
     20 =>  'xnsEchoAppl',
     21 =>  'apolloEcho',
     22 =>  'apolloEchoAppl',
     23 =>  'netbiosEchoAppl',
     24 =>  'ipTcpConn',
     25 =>  'httpAppl',
     26 =>  'dnsAppl',
     27 =>  'jitterAppl',
     28 =>  'dlswAppl',
     29 =>  'dhcpAppl',
     30 =>  'ftpAppl',
     31 =>  'mplsLspPingAppl',
     32 =>  'voipAppl',
     33 =>  'rtpAppl',
     34 =>  'icmpJitterAppl',
     35 =>  'ethernetPingAppl',
     36 =>  'ethernetJitterAppl',
     37 =>  'videoAppl',
     38 =>  'y1731dmm',
     39 =>  'y17311dm',
     40 =>  'y1731lmm',
     41 =>  'mcastJitterAppl',
     42 =>  'y1731slm',     
     );

sub translateRttEchoProtocol
{
    my $value = shift;
    return $rttEchoProtocol{$value};
}

sub translateRttTargetAddr
{
    my $value = shift;
    $value =~ s/^0x//;
    return inet_ntoa( pack( 'H8', $value ) );
}


1;


# Local Variables:
# mode: perl
# indent-tabs-mode: nil
# perl-indent-level: 4
# End:
