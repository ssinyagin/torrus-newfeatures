#  Copyright (C) 2003  Shawn Ferry
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

# $Id$
# Shawn Ferry <lalartu at obscure dot org> <sferry at sevenspace dot com>

# Cisco Firewall devices discovery

package Torrus::DevDiscover::CiscoFirewall;

use strict;
use Torrus::Log;

our $VERSION = 1.0;

$Torrus::DevDiscover::registry{'CiscoFirewall'} = {
    'sequence'     => 510,
    'checkdevtype' => \&checkdevtype,
    'discover'     => \&discover,
    'buildConfig'  => \&buildConfig
    };


our %oiddef =
    (
     # CISCO-FIREWALL
     'ciscoFirewallMIB'            => '1.3.6.1.4.1.9.9.147',
     'cfwBasicEventsTableLastRow'  => '1.3.6.1.4.1.9.9.147.1.1.4',
     'cfwConnectionStatTable'      => '1.3.6.1.4.1.9.9.147.1.2.2.2.1',
     'cfwConnectionStatMax'        => '1.3.6.1.4.1.9.9.147.1.2.2.2.1.5.40.7',
     );


# Not all interfaces are normally needed to monitor.
# You may override the interface filtering in devdiscover-siteconfig.pl:
# redefine $Torrus::DevDiscover::CiscoFirewall::interfaceFilter
# or define $Torrus::DevDiscover::CiscoFirewall::interfaceFilterOverlay

our $interfaceFilter;
our $interfaceFilterOverlay;
my %fwInterfaceFilter;

if( not defined( $interfaceFilter ) )
{
    $interfaceFilter = \%fwInterfaceFilter;
}


# Key is some unique symbolic name, does not mean anything
# ifType is the number to match the interface type
# ifDescr is the regexp to match the interface description
%fwInterfaceFilter =
    (
     'TunnelN' => {
         'ifType'  => 1,                      # other
         'ifName'  => '^Tunnel'
     },
    );



sub checkdevtype
{
    my $dd = shift;
    my $devdetails = shift;

    my $session = $dd->session();
    my $data = $devdetails->data();

    if( not ($devdetails->isDevType('CiscoGeneric')
             and
             $dd->checkSnmpTable('ciscoFirewallMIB')) )
    {
        return 0;
    }

    &Torrus::DevDiscover::RFC2863_IF_MIB::addInterfaceFilter
        ($devdetails, $interfaceFilter);
    
    if( defined( $interfaceFilterOverlay ) )
    {
        &Torrus::DevDiscover::RFC2863_IF_MIB::addInterfaceFilter
            ($devdetails, $interfaceFilterOverlay);
    }

    $devdetails->setCap('interfaceIndexingManaged');

    return 1;
}


sub discover
{
    my $dd = shift;
    my $devdetails = shift;

    my $data = $devdetails->data();
    my $session = $dd->session();

    $data->{'nameref'}{'ifReferenceName'} = 'ifName';
    $data->{'nameref'}{'ifSubtreeName'} = 'ifNameT';
    $data->{'param'}{'ifindex-table'} = '$ifName';

    if( not defined( $data->{'param'}{'snmp-oids-per-pdu'} ) )
    {
        my $oidsPerPDU =
            $devdetails->param('CiscoFirewall::snmp-oids-per-pdu');
        if( $oidsPerPDU == 0 )
        {
            $oidsPerPDU = 10;
        }
        $data->{'param'}{'snmp-oids-per-pdu'} = $oidsPerPDU;
    }

    if( $dd->checkSnmpOID('cfwConnectionStatMax') )
    {
        $devdetails->setCap('CiscoFirewall::connections');
    }
    
    # I have not seen a system that supports this.
    if( $dd->checkSnmpOID('cfwBasicEventsTableLastRow') )
    {
        $devdetails->setCap('CiscoFirewall::events');
    }

    return 1;
}


sub buildConfig
{
    my $devdetails = shift;
    my $cb = shift;
    my $devNode = shift;
    my $data = $devdetails->data();

    my $fwStatsTree = "Firewall_Stats";
    my $fwStatsParam = {
        'precedence' => '-1000',
        'comment'    => 'Firewall Stats',
    };

    my @templates = ('CiscoFirewall::cisco-firewall-subtree');
    
    if( $devdetails->hasCap('CiscoFirewall::connections') )
    {
        push( @templates, 'CiscoFirewall::connections');
    }

    if( $devdetails->hasCap('CiscoFirewall::events') )
    {
        push( @templates, 'CiscoFirewall::events');
    }

    $cb->addSubtree( $devNode, $fwStatsTree, $fwStatsParam, \@templates );
}




1;


# Local Variables:
# mode: perl
# indent-tabs-mode: nil
# perl-indent-level: 4
# End:
