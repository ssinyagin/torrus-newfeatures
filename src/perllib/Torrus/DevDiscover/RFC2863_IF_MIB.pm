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
#  Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.

# $Id$
# Stanislav Sinyagin <ssinyagin@yahoo.com>

# Standard IF_MIB discovery, which should apply to most devices

package Torrus::DevDiscover::RFC2863_IF_MIB;

use strict;
use Torrus::Log;


$Torrus::DevDiscover::registry{'RFC2863_IF_MIB'} = {
    'sequence'     => 10,
    'checkdevtype' => \&checkdevtype,
    'discover'     => \&discover,
    'buildConfig'  => \&buildConfig
    };


our %oiddef =
    (
     'ifTable'          => '1.3.6.1.2.1.2.2',
     'ifDescr'          => '1.3.6.1.2.1.2.2.1.2',
     'ifType'           => '1.3.6.1.2.1.2.2.1.3',
     'ifPhysAddress'    => '1.3.6.1.2.1.2.2.1.6',
     'ifAdminStatus'    => '1.3.6.1.2.1.2.2.1.7',
     'ifOperStatus'     => '1.3.6.1.2.1.2.2.1.8',
     'ifInOctets'       => '1.3.6.1.2.1.2.2.1.10',
     'ifInUcastPkts'    => '1.3.6.1.2.1.2.2.1.11',
     'ifInDiscards'     => '1.3.6.1.2.1.2.2.1.13',
     'ifInErrors'       => '1.3.6.1.2.1.2.2.1.14',
     'ifOutOctets'      => '1.3.6.1.2.1.2.2.1.16',
     'ifOutUcastPkts'   => '1.3.6.1.2.1.2.2.1.17',
     'ifOutDiscards'    => '1.3.6.1.2.1.2.2.1.19',
     'ifOutErrors'      => '1.3.6.1.2.1.2.2.1.20',
     'ifXTable'         => '1.3.6.1.2.1.31.1.1',
     'ifName'           => '1.3.6.1.2.1.31.1.1.1.1',
     'ifHCInOctets'     => '1.3.6.1.2.1.31.1.1.1.6',
     'ifHCInUcastPkts'  => '1.3.6.1.2.1.31.1.1.1.7',
     'ifHCOutOctets'    => '1.3.6.1.2.1.31.1.1.1.10',
     'ifHCOutUcastPkts' => '1.3.6.1.2.1.31.1.1.1.11',
     'ifAlias'          => '1.3.6.1.2.1.31.1.1.1.18'
     );



# Just curious, are there any devices without ifTable?
sub checkdevtype
{
    my $dd = shift;
    my $devdetails = shift;

    my $session = $dd->session();

    my $ifTable =
        $session->get_table( -baseoid => $dd->oiddef('ifTable') );
    if( not defined $ifTable )
    {
        return 0;
    }
    $devdetails->storeSnmpVars( $ifTable );

    my $ifXTable =
        $session->get_table( -baseoid => $dd->oiddef('ifXTable') );
    if( defined $ifXTable )
    {
        $devdetails->storeSnmpVars( $ifXTable );
        $devdetails->setCap('ifXTable');

        if( $devdetails->hasOID( $dd->oiddef('ifName') ) )
        {
            $devdetails->setCap('ifName');
        }

        if( $devdetails->hasOID( $dd->oiddef('ifAlias') ) )
        {
            $devdetails->setCap('ifAlias');
        }
    }

    ## Fill in per-interface data. This is normally done within discover(),
    ## but in our case we want to give other modules more control as early
    ## as possible.

    # Define the tables used for subtree naming, interface indexing,
    # and RRD file naming
    my $data = $devdetails->data();

    $data->{'param'}{'has-inout-leaves'} = 'yes';

    $data->{'nameref'}{'ifSubtreeName'} = 'ifDescrT';
    $data->{'nameref'}{'ifHumanName'}   = 'ifDescr';

    if( $devdetails->hasCap('ifName') )
    {
        $data->{'nameref'}{'ifNick'} = 'ifNameT';
    }
    else
    {
        $data->{'nameref'}{'ifNick'} = 'ifDescrT';
    }

    if( $devdetails->hasCap('ifAlias') )
    {
        $data->{'nameref'}{'ifComment'} = 'ifAlias';
    }

    # Pre-populate the interfaces table, so that other modules may
    # delete unneeded interfaces
    foreach my $ifIndex
        ( $devdetails->getSnmpIndices( $dd->oiddef('ifDescr') ) )
    {
        if( $Torrus::DevDiscover::listAdminDownInterfaces or
            $devdetails->snmpVar($dd->oiddef('ifAdminStatus') .
                                 '.' . $ifIndex) == 1 )
        {
            my $interface = {};
            $data->{'interfaces'}{$ifIndex} = $interface;

            $interface->{'param'} = {};
            $interface->{'vendor_templates'} = [];

            $interface->{'ifType'} =
                $devdetails->snmpVar($dd->oiddef('ifType') . '.' . $ifIndex);

            my $descr = $devdetails->snmpVar($dd->oiddef('ifDescr') .
                                             '.' . $ifIndex);
            $interface->{'ifDescr'} = $descr;
            $descr =~ s/\W/_/g;
            # Some SNMP agents send extra zero byte at the end
            $descr =~ s/_+$//;
            $interface->{'ifDescrT'} = $descr;

            if( $devdetails->hasCap('ifName') )
            {
                my $iname = $devdetails->snmpVar($dd->oiddef('ifName') .
                                                 '.' . $ifIndex);
                if( $iname !~ /\w/ )
                {
                    $iname = $interface->{'ifDescr'};
                    Warn('Empty or invalid ifName for interface ' . $iname);
                }
                $interface->{'ifName'} = $iname;
                $iname =~ s/\W/_/g;
                $interface->{'ifNameT'} = $iname;
            }

            if( $devdetails->hasCap('ifAlias') )
            {
                $interface->{'ifAlias'} =
                    $devdetails->snmpVar($dd->oiddef('ifAlias') .
                                         '.' . $ifIndex);
            }
        }
    }

    push( @{$data->{'templates'}}, 'RFC2863_IF_MIB::rfc2863-ifmib-hostlevel' );

    return 1;
}


sub discover
{
    my $dd = shift;
    my $devdetails = shift;

    # Generate parameter values from data that was built in checkdevtype()
    # and other modules

    my $data = $devdetails->data();

    # Filter out the interfaces if needed

    if( ref( $data->{'interfaceFilter'} ) )
    {
        foreach my $ifIndex ( sort {$a<=>$b} keys %{$data->{'interfaces'}} )
        {
            my $interface = $data->{'interfaces'}{$ifIndex};
            my $match = 0;

            foreach my $filterHash ( @{$data->{'interfaceFilter'}} )
            {
                last if $match;
                foreach my $filter ( values %{$filterHash} )
                {
                    last if $match;

                    if( defined( $filter->{'ifType'} ) and
                        $interface->{'ifType'} == $filter->{'ifType'} )
                    {
                        if( not defined( $filter->{'ifDescr'} ) or
                            $interface->{'ifDescr'} =~ $filter->{'ifDescr'} )
                        {
                            $match = 1;
                        }
                    }
                }
            }

            if( $match )
            {
                Debug('Excluding interface: ' .
                      $interface->{$data->{'nameref'}{'ifHumanName'}});
                delete $data->{'interfaces'}{$ifIndex};
            }
        }
    }

    my $suppressHCCounters =
        $devdetails->param('RFC2863_IF_MIB::suppress-hc-counters') eq 'yes';

    # Explore each interface capability

    foreach my $ifIndex ( keys %{$data->{'interfaces'}} )
    {
        my $interface = $data->{'interfaces'}{$ifIndex};

        if( $devdetails->hasOID( $dd->oiddef('ifInOctets') .
                                 '.' . $ifIndex )
            and
            $devdetails->hasOID( $dd->oiddef('ifOutOctets') .
                                 '.' . $ifIndex ) )
        {
            $interface->{'hasOctets'} = 1;
        }

        if( $devdetails->hasOID( $dd->oiddef('ifInUcastPkts') .
                                 '.' . $ifIndex )
            and
            $devdetails->hasOID( $dd->oiddef('ifOutUcastPkts') .
                                 '.' . $ifIndex ) )
        {
            $interface->{'hasUcastPkts'} = 1;
        }

        if( $devdetails->hasOID( $dd->oiddef('ifInDiscards') .
                                 '.' . $ifIndex ) )
        {
            $interface->{'hasInDiscards'} = 1;
        }

        if( $devdetails->hasOID( $dd->oiddef('ifOutDiscards') .
                                 '.' . $ifIndex ) )
        {
            $interface->{'hasOutDiscards'} = 1;
        }

        if( $devdetails->hasOID( $dd->oiddef('ifInErrors') .
                                 '.' . $ifIndex ) )
        {
            $interface->{'hasInErrors'} = 1;
        }

        if( $devdetails->hasOID( $dd->oiddef('ifOutErrors') .
                                 '.' . $ifIndex ) )
        {
            $interface->{'hasOutErrors'} = 1;
        }

        if( $devdetails->hasCap('ifXTable') and not $suppressHCCounters )
        {
            if( $devdetails->hasOID( $dd->oiddef('ifHCInOctets') .
                                     '.' . $ifIndex )
                and
                $devdetails->hasOID( $dd->oiddef('ifHCOutOctets') .
                                     '.' . $ifIndex ) )
            {
                $interface->{'hasHCOctets'} = 1;
            }

            if( $devdetails->hasOID( $dd->oiddef('ifHCInUcastPkts') .
                                     '.' . $ifIndex )
                and
                $devdetails->hasOID( $dd->oiddef('ifHCOutUcastPkts') .
                                     '.' . $ifIndex ) )
            {
                $interface->{'hasHCUcastPkts'} = 1;
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

    if( scalar( keys %{$data->{'interfaces'}} ) == 0 )
    {
        return;
    }   
    
    # Make sure that ifNick and ifSubtreeName are unique across interfaces

    uniqueEntries( $devdetails, $data->{'nameref'}{'ifNick'} );
    uniqueEntries( $devdetails, $data->{'nameref'}{'ifSubtreeName'} );

    # Build interface parameters

    my $nInterfaces = 0;
   
    foreach my $ifIndex ( keys %{$data->{'interfaces'}} )
    {
        my $interface = $data->{'interfaces'}{$ifIndex};

        next if $interface->{'excluded'};
        $nInterfaces++;

        $interface->{'param'}{'interface-iana-type'} = $interface->{'ifType'};

        $interface->{'param'}{'interface-name'} =
            $interface->{$data->{'nameref'}{'ifHumanName'}};

        $interface->{'param'}{'interface-nick'} =
            $interface->{$data->{'nameref'}{'ifNick'}};

        if( defined $data->{'nameref'}{'ifComment'} and
            not defined( $interface->{'param'}{'comment'} ) and
            length( $interface->{$data->{'nameref'}{'ifComment'}} ) > 0 )
        {
            $interface->{'param'}{'comment'} =
                $interface->{$data->{'nameref'}{'ifComment'}};
        }

        # Order the interfaces by ifIndex, not by interface name
        $interface->{'param'}{'precedence'} = sprintf('%d', 100000-$ifIndex);

        $interface->{'param'}{'devdiscover-nodetype'} =
            'RFC2863_IF_MIB::interface';
    }

    if( $nInterfaces == 0 )
    {
        return;
    }

    # explicitly excluded interfaces    
    my %excludeName;
    my $excludeNameList =
        $devdetails->param('RFC2863_IF_MIB::exclude-interfaces');
    my $nExplExcluded = 0;
        
    if( defined( $excludeNameList ) and length( $excludeNameList ) > 0 )
    {
        foreach my $name ( split( /\s*,\s*/, $excludeNameList ) )
        {
            $excludeName{$name} = 1;
        }
    }

    # tokenset member interfaces of the form
    # Format: tset:intf,intf; tokenset:intf,intf;
    my %tsetMember;
    my $tsetMembership =
        $devdetails->param('RFC2863_IF_MIB::tokenset-members');
    if( defined( $tsetMembership ) and length( $tsetMembership ) > 0 )
    {
        foreach my $memList ( split( /\s*;\s*/, $tsetMembership ) )
        {
            my ($tset, $list) = split( /\s*:\s*/, $memList );
            foreach my $intfName ( split( /\s*,\s*/, $list ) )
            {
                $tsetMember{$intfName}{$tset} = 1;
            }
        }
    }

    # interface-level parameters to copy
    my @intfCopyParams = ();
    my $copyParams = $devdetails->param('RFC2863_IF_MIB::copy-params');
    if( defined( $copyParams ) and length( $copyParams ) > 0 )
    {
        @intfCopyParams = split( /\s*,\s*/m, $copyParams );
    }
    
    # Build configuration tree

    my $subtreeName = $devdetails->param('RFC2863_IF_MIB::subtree-name');
    if( length( $subtreeName ) == 0 )
    {
        $subtreeName = 'Interface_Counters';
    }
    my $countersNode =
        $cb->addSubtree( $devNode, $subtreeName, undef,
                         ['RFC2863_IF_MIB::rfc2863-ifmib-subtree'] );

    if( $devdetails->param('RFC2863_IF_MIB::errors-monitor') eq 'yes' )
    {
        $cb->setVar( $countersNode, 'RFC2863_IF_MIB::errors-monitor', 'true' );
    }
    
    foreach my $ifIndex ( sort {$a<=>$b} keys %{$data->{'interfaces'}} )
    {
        my $interface = $data->{'interfaces'}{$ifIndex};

        # Some vendor-specific modules may exclude some interfaces
        next if $interface->{'excluded'};
        
        # Create a subtree for the interface
        my $subtreeName = $interface->{$data->{'nameref'}{'ifSubtreeName'}};

        if( $excludeName{$subtreeName} )
        {
            $nExplExcluded++;
            next;
        }
        
        my @templates;

        if( $interface->{'hasHCOctets'} )
        {
            push( @templates, 'RFC2863_IF_MIB::ifxtable-hcoctets' );
        }
        elsif( $interface->{'hasOctets'} )
        {
            push( @templates, 'RFC2863_IF_MIB::iftable-octets' );
        }

        if( $interface->{'hasHCUcastPkts'} )
        {
            push( @templates, 'RFC2863_IF_MIB::ifxtable-hcucast-packets' );
        }
        elsif( $interface->{'hasUcastPkts'} )
        {
            push( @templates, 'RFC2863_IF_MIB::iftable-ucast-packets' );
        }

        if( $interface->{'hasInDiscards'} )
        {
            push( @templates, 'RFC2863_IF_MIB::iftable-discards-in' );
        }

        if( $interface->{'hasOutDiscards'} )
        {
            push( @templates, 'RFC2863_IF_MIB::iftable-discards-out' );
        }

        if( $interface->{'hasInErrors'} )
        {
            push( @templates, 'RFC2863_IF_MIB::iftable-errors-in' );
        }

        if( $interface->{'hasOutErrors'} )
        {
            push( @templates, 'RFC2863_IF_MIB::iftable-errors-out' );
        }

        if( ref( $interface->{'templates'} ) )
        {
            push( @templates, @{$interface->{'templates'}} );
        }

        # Add vendor templates
        push( @templates, @{$interface->{'vendor_templates'}} );
        
        # Add subtree only if there are template references

        if( scalar( @templates ) > 0 )
        {
            # process interface-level parameters to copy

            foreach my $param ( @intfCopyParams )
            {
                my $val = $devdetails->param('RFC2863_IF_MIB::' .
                                             $param . '::' . $subtreeName );
                if( defined( $val ) and length( $val ) > 0 )
                {
                    $interface->{'param'}{$param} = $val;
                }
            }
            
            my $intfNode =
                $cb->addSubtree( $countersNode, $subtreeName,
                                 $interface->{'param'}, \@templates );

            if( defined( $tsetMember{$subtreeName} ) )
            {
                my $tsetList =
                    join( ',', sort keys %{$tsetMember{$subtreeName}} );

                $cb->addLeaf( $intfNode, 'InOut_bps',
                              { 'tokenset-member' => $tsetList } );
            }            
        }
    }

    if( $nExplExcluded > 0 )
    {
        Debug('Explicitly excluded ' . $nExplExcluded .
              ' RFC2863_IF_MIB interfaces');
    }
    
    $cb->{'statistics'}{'interfaces'} += $nInterfaces;
    if( $cb->{'statistics'}{'max-interfaces-per-host'} < $nInterfaces )
    {
        $cb->{'statistics'}{'max-interfaces-per-host'} = $nInterfaces;
    }
}


# $filterHash is a hash reference
# Key is some unique symbolic name, does not mean anything
# $filterHash->{$key}{'ifType'} is the number to match the interface type
# $filterHash->{$key}{'ifDescr'} is the regexp to match the interface
# description

sub addInterfaceFilter
{
    my $devdetails = shift;
    my $filterHash = shift;

    my $data = $devdetails->data();

    if( not ref( $data->{'interfaceFilter'} ) )
    {
        $data->{'interfaceFilter'} = [];
    }

    push( @{$data->{'interfaceFilter'}}, $filterHash );
}


sub uniqueEntries
{
    my $devdetails = shift;
    my $nameref = shift;

    my $data = $devdetails->data();
    my %count = ();

    foreach my $ifIndex ( sort {$a<=>$b} keys %{$data->{'interfaces'}} )
    {
        my $interface = $data->{'interfaces'}{$ifIndex};

        my $entry = $interface->{$nameref};
        if( length($entry) == 0 )
        {
            $entry = $interface->{$nameref} = '_';
        }
        if( int( $count{$entry} ) > 0 )
        {
            my $new_entry = sprintf('%s%d', $entry, int( $count{$entry} ) );
            $interface->{$nameref} = $new_entry;
            $count{$new_entry}++;
        }
        $count{$entry}++;
    }
}

# For devices which require MAC address-to-interface mapping,
# this function fills in the appropriate interface-macaddr parameters.
# To get use of MAC mapping, set
#     $data->{'param'}{'ifindex-map'} = '$IFIDX_MAC';


sub retrieveMacAddresses
{
    my $dd = shift;
    my $devdetails = shift;

    my $data = $devdetails->data();

    foreach my $ifIndex
        ( $devdetails->getSnmpIndices( $dd->oiddef('ifPhysAddress') ) )
    {
        # Check if the interface wasn't filtered out
        if( exists( $data->{'interfaces'}{$ifIndex} ) )
        {
            my $interface = $data->{'interfaces'}{$ifIndex};
            
            my $macaddr = $devdetails->snmpVar($dd->oiddef('ifPhysAddress') .
                                               '.' . $ifIndex);
            $interface->{'param'}{'interface-macaddr'} = $macaddr;
        }
    }
}


1;


# Local Variables:
# mode: perl
# indent-tabs-mode: nil
# perl-indent-level: 4
# End:
