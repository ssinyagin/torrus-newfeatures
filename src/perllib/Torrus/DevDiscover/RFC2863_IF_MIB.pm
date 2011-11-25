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

# Standard IF_MIB discovery, which should apply to most devices

package Torrus::DevDiscover::RFC2863_IF_MIB;

use strict;
use warnings;

use Torrus::Log;


$Torrus::DevDiscover::registry{'RFC2863_IF_MIB'} = {
    'sequence'     => 50,
    'checkdevtype' => \&checkdevtype,
    'discover'     => \&discover,
    'buildConfig'  => \&buildConfig,
    'buildGlobalConfig' => \&buildGlobalConfig
    };


our %oiddef =
    (
     'ifTable'          => '1.3.6.1.2.1.2.2',
     'ifDescr'          => '1.3.6.1.2.1.2.2.1.2',
     'ifType'           => '1.3.6.1.2.1.2.2.1.3',
     'ifSpeed'          => '1.3.6.1.2.1.2.2.1.5',
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
     'ifHighSpeed'      => '1.3.6.1.2.1.31.1.1.1.15',     
     'ifAlias'          => '1.3.6.1.2.1.31.1.1.1.18'
     );



# Just curious, are there any devices without ifTable?
sub checkdevtype
{
    my $dd = shift;
    my $devdetails = shift;

    return $dd->checkSnmpTable('ifTable');
}


sub discover
{
    my $dd = shift;
    my $devdetails = shift;
    
    my $session = $dd->session();
    
    ## Fill in per-interface data. This is normally done within discover(),
    ## but in our case we want to give other modules more control as early
    ## as possible.

    # Define the tables used for subtree naming, interface indexing,
    # and RRD file naming
    my $data = $devdetails->data();

    $data->{'param'}{'has-inout-leaves'} = 'yes';
    
    # Pre-populate the interfaces table, so that other modules may
    # delete unneeded interfaces
    my $includeAdmDown =
        $devdetails->paramEnabled('RFC2863_IF_MIB::list-admindown-interfaces');
    my $includeNotpresent =
        $devdetails->paramEnabled
        ('RFC2863_IF_MIB::list-notpresent-interfaces');
    my $excludeOperDown =
        $devdetails->paramEnabled('RFC2863_IF_MIB::exclude-down-interfaces');

    my $ifAdminStatus = $dd->walkSnmpTable('ifAdminStatus');
    my $ifOperStatus  = $dd->walkSnmpTable('ifOperStatus');
    my $ifType        = $dd->walkSnmpTable('ifType');
    my $ifDescr       = $dd->walkSnmpTable('ifDescr');
    my $ifSpeed       = $dd->walkSnmpTable('ifSpeed');
    
    while( my($ifIndex, $admStatus) = each %{$ifAdminStatus} )
    {
        my $operStatus = $ifOperStatus->{$ifIndex};
        next unless (defined($admStatus) and defined($operStatus));

        if( ( $admStatus == 1 or $includeAdmDown ) and
            ( $operStatus != 6 or $includeNotpresent ) and
            ( $operStatus != 2 or not $excludeOperDown ) )
        {
            my $interface = {};
            $data->{'interfaces'}{$ifIndex} = $interface;

            $interface->{'param'} = {};
            $interface->{'vendor_templates'} = [];

            $interface->{'ifIndex'} = $ifIndex;
            $interface->{'ifAdminStatus'} = $admStatus;
            $interface->{'ifOperStatus'} = $operStatus;
     
            $interface->{'ifType'} = $ifType->{$ifIndex};

            my $descr = $ifDescr->{$ifIndex};
            if( defined($descr) )
            {
                $interface->{'ifDescr'} = $descr;
                $descr =~ s/\W/_/g;
                # Some SNMP agents send extra zero byte at the end
                $descr =~ s/_+$//;
                $interface->{'ifDescrT'} = $descr;
            }

            my $speed = $ifSpeed->{$ifIndex};
            if( defined($speed) and $speed > 0 )
            {
                $interface->{'ifSpeed'} = $speed;
            }
        }
    }

    # Process IF-MIB::ifXTable
    
    if( not $devdetails->hasCap('disable_ifXTable') )
    {
        my $ifName      = $dd->walkSnmpTable('ifName');
        my $ifAlias     = $dd->walkSnmpTable('ifAlias');
        my $ifHighSpeed = $dd->walkSnmpTable('ifHighSpeed');

        my $found_ifName = 0;
        my $found_ifAlias = 0;
        
        while( my ($ifIndex, $interface) = each %{$data->{'interfaces'}} )
        {
            my $iname = $ifName->{$ifIndex};
            if( defined($iname) )
            {
                if( $iname !~ /\w/ )
                {
                    $iname = $interface->{'ifDescr'};
                    Warn('Empty or invalid ifName for interface: ' .
                         $iname);
                }
                
                $interface->{'ifName'} = $iname;
                $iname =~ s/\W/_/g;
                $interface->{'ifNameT'} = $iname;
                $found_ifName = 1;
            }

            my $alias = $ifAlias->{$ifIndex};
            if( defined($alias) )
            {
                $interface->{'ifAlias'} = $alias;
                $found_ifAlias = 1;
            }

            my $hspeed = $ifHighSpeed->{$ifIndex};
            if( defined($hspeed) and $hspeed > 0 )
            {
                $interface->{'ifHighSpeed'} = $hspeed;
            }
        }

        if( $found_ifName )
        {
            $devdetails->setCap('ifName');
        }

        if( $found_ifAlias )
        {
            $devdetails->setCap('ifAlias');
        }
    }

    if( not $devdetails->hasCap('interfaceNamingProprietary') )
    {
        ## Set default interface index mapping

        my $valid_ifDescr = validateReference($devdetails, 'ifDescr');
        my $valid_ifName = ( $devdetails->hasCap('ifName') and
                             validateReference($devdetails, 'ifName') );
        
        if( $valid_ifDescr )
        {
            $data->{'nameref'}{'ifSubtreeName'}   = 'ifDescrT';
            $data->{'nameref'}{'ifReferenceName'} = 'ifDescr';

            # ifnick-from-ifname forces the indexing even if it's not unique
            
            if( ($devdetails->paramEnabled
                 ('RFC2863_IF_MIB::ifnick-from-ifname')
                 and $devdetails->hasCap('ifName'))
                or
                $valid_ifName )
            {
                $data->{'nameref'}{'ifNick'} = 'ifNameT';
            }
            else
            {
                $data->{'nameref'}{'ifNick'} = 'ifDescrT';
            }
        }
        elsif( $valid_ifName )
        {
            $data->{'nameref'}{'ifSubtreeName'} = 'ifNameT';
            $data->{'nameref'}{'ifReferenceName'} = 'ifName';
            $data->{'nameref'}{'ifNick'} = 'ifNameT';
            $data->{'param'}{'ifindex-table'} = '$ifName';
        }
        else
        {
            $devdetails->setCap('interfaceIndexingPersistent');
            $data->{'nameref'}{'ifSubtreeName'} = 'ifIndex';
            $data->{'nameref'}{'ifReferenceName'} = 'ifIndex';
            $data->{'nameref'}{'ifNick'} = 'ifIndex';
        }
        
        if( $devdetails->hasCap('ifAlias') )
        {
            $data->{'nameref'}{'ifComment'} = 'ifAlias';
        }
    } 
    
    ## Process hints on interface indexing
    ## The capability 'interfaceIndexingManaged' disables the hints
    ## and lets the vendor discovery module to operate the indexing
    
    if( not $devdetails->hasCap('interfaceIndexingManaged') and
        not $devdetails->hasCap('interfaceIndexingPersistent') )
    {
        my $hint =
            $devdetails->param('RFC2863_IF_MIB::ifindex-map-hint');
        if( defined( $hint ) )
        {
            if( $hint eq 'ifName' )
            {
                if( not $devdetails->hasCap('ifName') )
                {
                    Error('Cannot use ifName interface mapping: ifName is '.
                          'not supported by device');
                    return 0;
                }
                else
                {
                    $data->{'nameref'}{'ifReferenceName'} = 'ifName';
                    $data->{'param'}{'ifindex-table'} = '$ifName';
                }
            }
            elsif( $hint eq 'ifPhysAddress' )
            {
                $data->{'param'}{'ifindex-map'} = '$IFIDX_MAC';
                retrieveMacAddresses( $dd, $devdetails );
            }
            elsif( $hint eq 'ifIndex' )
            {
                $devdetails->setCap('interfaceIndexingPersistent');
            }
            else
            {
                Error('Unknown value of RFC2863_IF_MIB::ifindex-map-hint: ' .
                      $hint);
            }
        }
            
        $hint =
            $devdetails->param('RFC2863_IF_MIB::subtree-name-hint');
        if( defined( $hint ) )
        {
            if( $hint eq 'ifName' )
            {
                $data->{'nameref'}{'ifSubtreeName'} = 'ifNameT';
            }
            else
            {
                Error('Unknown value of RFC2863_IF_MIB::subtree-name-hint: ' .
                      $hint);
            }
        }
        
        $hint =
            $devdetails->param('RFC2863_IF_MIB::nodeid-hint');
        if( defined( $hint ) )
        {
            $data->{'nameref'}{'ifNodeid'} = $hint;
        }
    }
    
    if( $devdetails->hasCap('interfaceIndexingPersistent') )
    {
        $data->{'param'}{'ifindex-map'} = '$IFIDX_IFINDEX';
        storeIfIndexParams( $devdetails );
    }

    if( not defined( $data->{'nameref'}{'ifNodeid'} ) )
    {
        $data->{'nameref'}{'ifNodeid'} = 'ifNodeid';
    }
    
    if( not defined( $data->{'nameref'}{'ifNodeidPrefix'} ) )
    {
        $data->{'nameref'}{'ifNodeidPrefix'} = 'ifNodeidPrefix';
    }
    
    # Filter out the interfaces if needed

    if( ref( $data->{'interfaceFilter'} ) )
    {
        # sort is only needed for a nicer debug output
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
                      $interface->{$data->{'nameref'}{'ifReferenceName'}});
                delete $data->{'interfaces'}{$ifIndex};
            }
        }
    }
    
    ## Explore counters available for each interface

    my $ifInOctets      = $dd->walkSnmpTable('ifInOctets');
    my $ifOutOctets     = $dd->walkSnmpTable('ifOutOctets');
    my $ifInUcastPkts   = $dd->walkSnmpTable('ifInUcastPkts');
    my $ifOutUcastPkts  = $dd->walkSnmpTable('ifOutUcastPkts');
    my $ifInDiscards    = $dd->walkSnmpTable('ifInDiscards');
    my $ifOutDiscards   = $dd->walkSnmpTable('ifOutDiscards');
    my $ifInErrors      = $dd->walkSnmpTable('ifInErrors');
    my $ifOutErrors     = $dd->walkSnmpTable('ifOutErrors');

    my $suppressHCCounters =
        ($devdetails->paramEnabled('RFC2863_IF_MIB::suppress-hc-counters')
         or
         $devdetails->hasCap('suppressHCCounters'));

    my $ifHCInOctets     = {};
    my $ifHCOutOctets    = {};
    my $ifHCInUcastPkts  = {};
    my $ifHCOutUcastPkts = {};

    if( not $suppressHCCounters )
    {
        $ifHCInOctets     = $dd->walkSnmpTable('ifHCInOctets');
        $ifHCOutOctets    = $dd->walkSnmpTable('ifHCOutOctets');
        $ifHCInUcastPkts  = $dd->walkSnmpTable('ifHCInUcastPkts');
        $ifHCOutUcastPkts = $dd->walkSnmpTable('ifHCOutUcastPkts');
    }

    while( my ($ifIndex, $interface) = each %{$data->{'interfaces'}} )
    {
        if( defined($ifInOctets->{$ifIndex}) and
            defined($ifOutOctets->{$ifIndex}) )
        {
            $interface->{'hasOctets'} = 1;
        }

        if( defined($ifInUcastPkts->{$ifIndex}) and
            defined($ifOutUcastPkts->{$ifIndex}) )
        {
            $interface->{'hasUcastPkts'} = 1;
        }
        
        if( defined($ifInDiscards->{$ifIndex}) )
        {
            $interface->{'hasInDiscards'} = 1;
        }

        if( defined($ifOutDiscards->{$ifIndex}) )
        {
            $interface->{'hasOutDiscards'} = 1;
        }

        if( defined($ifInErrors->{$ifIndex}) )
        {
            $interface->{'hasInErrors'} = 1;
        }

        if( defined($ifOutErrors->{$ifIndex}) )
        {
            $interface->{'hasOutErrors'} = 1;
        }

        # A well-known bug in Cisco IOS: HC counters are implemented,
        # but always zero. Catch it here if possible.

        if(  not $suppressHCCounters )
        {
            if( defined($ifHCInOctets->{$ifIndex}) and
                defined($ifHCOutOctets->{$ifIndex}) )
            {
                if( not $interface->{'hasOctets'} )
                {
                    $interface->{'hasHCOctets'} = 1;
                }
                else
                {
                    if( ($ifInOctets->{$ifIndex} == 0 or
                         $ifHCInOctets->{$ifIndex} > 0)
                        and
                        ($ifOutOctets->{$ifIndex} == 0 or
                         $ifHCOutOctets->{$ifIndex} > 0) )
                    {
                        $interface->{'hasHCOctets'} = 1;
                    }
                }
            }

            if( $interface->{'hasHCOctets'} and
                defined($ifHCInUcastPkts->{$ifIndex}) and
                defined($ifHCOutUcastPkts->{$ifIndex}) )
            {
                $interface->{'hasHCUcastPkts'} = 1;
            }
        }
    }

    push( @{$data->{'templates'}}, 'RFC2863_IF_MIB::rfc2863-ifmib-hostlevel' );

    return 1;
}


sub buildConfig
{
    my $devdetails = shift;
    my $cb = shift;
    my $devNode = shift;
    my $globalData = shift;

    my $data = $devdetails->data();

    if( scalar( keys %{$data->{'interfaces'}} ) == 0 )
    {
        return;
    }   
    
    # Make sure that ifNick and ifSubtreeName are unique across interfaces

    uniqueEntries( $devdetails, $data->{'nameref'}{'ifNick'} );
    uniqueEntries( $devdetails, $data->{'nameref'}{'ifSubtreeName'} );

    # If other discovery modules don't set nodeid reference, fall back to
    # default interface reference
    
    # Bandwidth usage
    my %bandwidthLimits;
    my $bandwidthUsageConfigured = 0;
    my $bandwidthUsageActive = 0;
    
    if( $devdetails->paramEnabled('RFC2863_IF_MIB::bandwidth-usage') )
    {
        $bandwidthUsageConfigured = 1;
        foreach my $intfLimit
            ( split( /\s*;\s*/,
                     $devdetails->paramString
                     ('RFC2863_IF_MIB::bandwidth-limits') ) )
        {
            my( $intf, $limitIn, $limitOut ) = split( /\s*:\s*/, $intfLimit );
            $bandwidthLimits{$intf}{'In'} = $limitIn;
            $bandwidthLimits{$intf}{'Out'} = $limitOut;
        }
    }
    
    # Build interface parameters

    my $nInterfaces = 0;
   
    foreach my $ifIndex ( keys %{$data->{'interfaces'}} )
    {
        my $interface = $data->{'interfaces'}{$ifIndex};

        next if $interface->{'excluded'};
        $nInterfaces++;

        $interface->{'param'}{'searchable'} = 'yes';
        
        $interface->{'param'}{'interface-iana-type'} = $interface->{'ifType'};

        $interface->{'param'}{'interface-name'} =
            $interface->{$data->{'nameref'}{'ifReferenceName'}};

        $interface->{'param'}{'node-display-name'} =
            $interface->{$data->{'nameref'}{'ifReferenceName'}};

        $interface->{'param'}{'interface-nick'} =
            $interface->{$data->{'nameref'}{'ifNick'}};

        if( defined($data->{'nameref'}{'ifVendorSpecific'}) and
            defined($interface->{$data->{'nameref'}{'ifVendorSpecific'}}) )
        {
            $interface->{'param'}{'interface-vendor-specific'} =
                $interface->{$data->{'nameref'}{'ifVendorSpecific'}};
        }

        if( not defined( $interface->{$data->{'nameref'}{'ifNodeidPrefix'}} ) )
        {
            $interface->{$data->{'nameref'}{'ifNodeidPrefix'}} =
                'if//%nodeid-device%//';
        }
        
        if( not defined( $interface->{$data->{'nameref'}{'ifNodeid'}} ) )
        {
            $interface->{$data->{'nameref'}{'ifNodeid'}} =
                $interface->{$data->{'nameref'}{'ifReferenceName'}};
        }

        # A per-interface value which is used by leafs in IF-MIB templates
        $interface->{'param'}{'nodeid-interface'} =
            $interface->{$data->{'nameref'}{'ifNodeidPrefix'}} .
            $interface->{$data->{'nameref'}{'ifNodeid'}};
        
        $interface->{'param'}{'nodeid'} = '%nodeid-interface%';        

        if( defined $data->{'nameref'}{'ifComment'} and
            not defined( $interface->{'param'}{'comment'} ) and
            $interface->{$data->{'nameref'}{'ifComment'}} ne '' )
        {
            my $comment = $interface->{$data->{'nameref'}{'ifComment'}};
            $interface->{'param'}{'comment'} = $comment;
            $interface->{'param'}{'interface-comment'} = $comment;
        }

        # Order the interfaces by ifIndex, not by interface name
        $interface->{'param'}{'precedence'} = sprintf('%d', 100000-$ifIndex);

        $interface->{'param'}{'devdiscover-nodetype'} =
            'RFC2863_IF_MIB::interface';

        if( $bandwidthUsageConfigured )
        {
            my $subtreeName =
                $interface->{$data->{'nameref'}{'ifSubtreeName'}};
            
            if( defined( $bandwidthLimits{$subtreeName} ) )
            {
                $interface->{'param'}{'bandwidth-limit-in'} =
                    $bandwidthLimits{$subtreeName}{'In'};
                $interface->{'param'}{'bandwidth-limit-out'} =
                    $bandwidthLimits{$subtreeName}{'Out'};
            }

            # Bandwidth usage parameters may be added by some other modules

            if( defined($interface->{'param'}{'bandwidth-limit-in'}) and
                defined($interface->{'param'}{'bandwidth-limit-out'}) and
                ( $interface->{'hasOctets'} or $interface->{'hasHCOctets'} ) )
            {
                $bandwidthUsageActive = 1;
                $interface->{'hasBandwidthUsage'} = 1;
            }
            else
            {
                delete $interface->{'param'}{'bandwidth-limit-in'};
                delete $interface->{'param'}{'bandwidth-limit-out'};
            }
        }
    }

    if( $nInterfaces == 0 )
    {
        return;
    }

    if( $devdetails->paramEnabled('RFC2863_IF_MIB::noout') )
    {
        return;
    }

    # explicitly excluded interfaces    
    my %excludeName;
    my $nExplExcluded = 0;
        
    foreach my $name
        ( split( /\s*,\s*/,
                 $devdetails->paramString
                 ('RFC2863_IF_MIB::exclude-interfaces') ) )
    {
        $excludeName{$name} = 1;
    }

    # explicitly listed interfaces
    my %onlyName;
 
    foreach my $name
        ( split( /\s*,\s*/,
                 $devdetails->paramString('RFC2863_IF_MIB::only-interfaces') ) )
    {
        $onlyName{$name} = 1;
    }
    
    my $onlyNamesDefined = (scalar(keys %onlyName) > 0);

    # tokenset member interfaces of the form
    # Format: tset:intf,intf; tokenset:intf,intf;
    # Format for global parameter:
    #     tset:host/intf,host/intf; tokenset:host/intf,host/intf;
    my %tsetMember;
    my %tsetMemberApplied;
    foreach my $memList
        ( split( /\s*;\s*/,
                 $devdetails->paramString
                 ('RFC2863_IF_MIB::tokenset-members') ) )
    {
        my ($tset, $list) = split( /\s*:\s*/, $memList );
        foreach my $intfName ( split( /\s*,\s*/, $list ) )
        {
            if( $intfName =~ /\// )
            {
                my( $host, $intf ) = split( '/', $intfName );
                if( $host eq $devdetails->param('snmp-host') )
                {
                    $tsetMember{$intf}{$tset} = 1;
                }
            }
            else
            {
                $tsetMember{$intfName}{$tset} = 1;
            }
        }
    }
           
        
    # External storage serviceid assignment
    my %extStorage;
    my %extStorageTrees;
    
    foreach my $srvDef
        ( split( /\s*,\s*/,
                 $devdetails->paramString
                 ('RFC2863_IF_MIB::external-serviceid') ) )
    {
        my ( $serviceid, $intfName, $direction, $trees ) =
            split( /\s*:\s*/, $srvDef );
        
        if( $intfName =~ /\// )
        {
            my( $host, $intf ) = split( '/', $intfName );
            if( $host eq $devdetails->param('snmp-host') )
            {
                $intfName = $intf;
            }
            else
            {
                $intfName = undef;
            }
        }
        
        if( defined($intfName) and $intfName ne '' )
        {
            if( defined( $trees ) )
            {
                # Trees are listed with '|' as separator,
                # whereas compiler expects commas
                
                $trees =~ s/\s*\|\s*/,/g;
            }
            
            if( $direction eq 'Both' )
            {
                $extStorage{$intfName}{'In'} = $serviceid . '_IN';
                $extStorageTrees{$serviceid . '_IN'} = $trees;
                
                $extStorage{$intfName}{'Out'} = $serviceid . '_OUT';
                $extStorageTrees{$serviceid . '_OUT'} = $trees;
            }
            else
            {
                $extStorage{$intfName}{$direction} = $serviceid;
                $extStorageTrees{$serviceid} = $trees;
            }
        }
    }

    # Sums of several interfaces into single graphs (via CDef collector)
    # RFC2863_IF_MIB::traffic-summaries: the list of sums to create;
    # RFC2863_IF_MIB::traffic-XXX-path: the full path of the summary leaf
    # RFC2863_IF_MIB::traffic-XXX-comment: description
    # RFC2863_IF_MIB::traffic-XXX-interfaces: list of interfaces to add
    #   format: "intf,intf" or "host/intf, host/intf"
    my %trafficSummary;
    foreach my $summary
        ( split( /\s*,\s*/,
                 $devdetails->paramString
                 ('RFC2863_IF_MIB::traffic-summaries') ) )
    {
        $globalData->{'RFC2863_IF_MIB::summaryAttr'}{
            $summary}{'path'} =
                $devdetails->param
                ('RFC2863_IF_MIB::traffic-' . $summary . '-path');
        
        $globalData->{'RFC2863_IF_MIB::summaryAttr'}{
            $summary}{'comment'} =
                $devdetails->param
                ('RFC2863_IF_MIB::traffic-' . $summary . '-comment');
            
        $globalData->{'RFC2863_IF_MIB::summaryAttr'}{
            $summary}{'data-dir'} = $devdetails->param('data-dir');
        
        # get the intreface names for this host
        foreach my $intfName
            ( split( /\s*,\s*/,
                     $devdetails->paramString
                     ('RFC2863_IF_MIB::traffic-' . $summary . '-interfaces')
              ) )
        {
            if( $intfName =~ /\// )
            {
                my( $host, $intf ) = split( '/', $intfName );
                if( $host eq $devdetails->param('snmp-host') )
                {
                    $trafficSummary{$intf}{$summary} = 1;
                }
            }
            else
            {
                $trafficSummary{$intfName}{$summary} = 1;
            }
        }
    }
    
    # interface-level parameters to copy
    my @intfCopyParams = ();
    @intfCopyParams =
        split( /\s*,\s*/m,
               $devdetails->paramString('RFC2863_IF_MIB::copy-params') );
    
    # Build configuration tree

    my $subtreeName = $devdetails->paramString('RFC2863_IF_MIB::subtree-name');
    if( $subtreeName eq '' )
    {
        $subtreeName = 'Interface_Counters';
    }
    
    my $subtreeParams = {};
    my $subtreeComment =
        $devdetails->paramString('RFC2863_IF_MIB::subtree-comment');

    if( $subtreeComment ne '' )
    {
        $subtreeParams->{'comment'} = $subtreeComment;
    }

    if( $bandwidthUsageActive )
    {
        $subtreeParams->{'overview-shortcuts'} = 'traffic,errors,bandwidth';
    }
    
    my $countersNode =
        $cb->addSubtree( $devNode, $subtreeName, $subtreeParams,
                         ['RFC2863_IF_MIB::rfc2863-ifmib-subtree'] );
    
    foreach my $ifIndex ( sort {$a<=>$b} keys %{$data->{'interfaces'}} )
    {
        my $interface = $data->{'interfaces'}{$ifIndex};

        if( $interface->{'selectorActions'}{'RemoveInterface'} )
        {
            $interface->{'excluded'} = 1;
            Debug('Removing interface by selector action: ' .
                  $interface->{$data->{'nameref'}{'ifReferenceName'}});
        }

        # Some vendor-specific modules may exclude some interfaces
        next if $interface->{'excluded'};

        # Create a subtree for the interface
        my $ifSubtreeName = $interface->{$data->{'nameref'}{'ifSubtreeName'}};

        if( $onlyNamesDefined )
        {
            if( not $onlyName{$ifSubtreeName} )
            {
                $interface->{'excluded'} = 1;
                $nExplExcluded++;
                next;
            }
        }
        
        if( $excludeName{$ifSubtreeName} )
        {
            $interface->{'excluded'} = 1;
            $nExplExcluded++;
            next;
        }
        elsif( $ifSubtreeName eq '' )
        {
            Warn('Excluding an interface with empty name: ifIndex=' .
                 $ifIndex);
            next;
        }

        my @templates = ();

        if( $interface->{'hasHCOctets'} )
        {
            push( @templates, 'RFC2863_IF_MIB::ifxtable-hcoctets' );
        }
        elsif( $interface->{'hasOctets'} )
        {
            push( @templates, 'RFC2863_IF_MIB::iftable-octets' );
        }

        if( $interface->{'hasOctets'} or $interface->{'hasHCOctets'} )
        {
            $interface->{'hasChild'}{'Bytes_In'} = 1;
            $interface->{'hasChild'}{'Bytes_Out'} = 1;
            $interface->{'hasChild'}{'InOut_bps'} = 1;            

            foreach my $dir ( 'In', 'Out' )
            {
                if( defined( $interface->{'selectorActions'}->
                             {$dir . 'BytesMonitor'} ) )
                {
                    $interface->{'childCustomizations'}->{
                        'Bytes_' . $dir}->{'monitor'} =
                            $interface->{'selectorActions'}->{
                                $dir . 'BytesMonitor'};
                }

                if( defined( $interface->{'selectorActions'}->
                             {$dir . 'BytesParameters'} ) )
                {
                    my @pairs =
                        split('\s*;\s*',
                              $interface->{'selectorActions'}{
                                  $dir . 'BytesParameters'});
                    
                    foreach my $pair( @pairs )
                    {
                        my ($param, $val) = split('\s*=\s*', $pair);
                        $interface->{'childCustomizations'}->{
                            'Bytes_' . $dir}->{$param} = $val;
                    }
                }
            }

            if( defined( $interface->{'selectorActions'}{'HoltWinters'} ) )
            {
                push( @templates, '::holt-winters-defaults' );
            }

            if( defined( $interface->{'selectorActions'}{'NotifyPolicy'} ) )
            {
                $interface->{'param'}{'notify-policy'} =
                    $interface->{'selectorActions'}{'NotifyPolicy'};
            }
        }

        if( not $interface->{'selectorActions'}{'NoPacketCounters'} )
        {
            my $has_someting = 0;
            if( $interface->{'hasHCUcastPkts'} )
            {
                push( @templates, 'RFC2863_IF_MIB::ifxtable-hcucast-packets' );
                $has_someting = 1;
            }
            elsif( $interface->{'hasUcastPkts'} )
            {
                push( @templates, 'RFC2863_IF_MIB::iftable-ucast-packets' );
                $has_someting = 1;
            }

            if( $has_someting )
            {
                $interface->{'hasChild'}{'Packets_In'} = 1;            
                $interface->{'hasChild'}{'Packets_Out'} = 1;            
            }
        }

        if( not $interface->{'selectorActions'}{'NoDiscardCounters'} )
        {
            if( $interface->{'hasInDiscards'} )
            {
                push( @templates, 'RFC2863_IF_MIB::iftable-discards-in' );
                $interface->{'hasChild'}{'Discards_In'} = 1;            

                if( defined
                    ($interface->{'selectorActions'}->{'InDiscardsMonitor'}) )
                {
                    $interface->{'childCustomizations'}->{
                        'Discards_In'}->{'monitor'} =
                            $interface->{'selectorActions'}{
                                'InDiscardsMonitor'};
                }
            }
            
            if( $interface->{'hasOutDiscards'} )
            {
                push( @templates, 'RFC2863_IF_MIB::iftable-discards-out' );
                $interface->{'hasChild'}{'Discards_Out'} = 1;
                
                if( defined( $interface->{'selectorActions'}->{
                    'OutDiscardsMonitor'} ) )
                {
                    $interface->{'childCustomizations'}->{
                        'Discards_Out'}->{'monitor'} =
                            $interface->{'selectorActions'}{
                                'OutDiscardsMonitor'};
                }
            }
        }
        

        if( not $interface->{'selectorActions'}{'NoErrorCounters'} )
        {
            if( $interface->{'hasInErrors'} )
            {
                push( @templates, 'RFC2863_IF_MIB::iftable-errors-in' );
                $interface->{'hasChild'}{'Errors_In'} = 1;            

                if( defined( $interface->{'selectorActions'}->{
                    'InErrorsMonitor'} ) )
                {
                    $interface->{'childCustomizations'}->{
                        'Errors_In'}->{'monitor'} =
                            $interface->{'selectorActions'}{'InErrorsMonitor'};
                }
            }

            if( $interface->{'hasOutErrors'} )
            {
                push( @templates, 'RFC2863_IF_MIB::iftable-errors-out' );
                $interface->{'hasChild'}{'Errors_Out'} = 1;            

                if( defined( $interface->{'selectorActions'}->{
                    'OutErrorsMonitor'} ) )
                {
                    $interface->{'childCustomizations'}->{
                        'Errors_Out'}->{'monitor'} =
                            $interface->{'selectorActions'}{
                                'OutErrorsMonitor'};
                }
            }
        }

            
        if( defined( $interface->{'selectorActions'}{'TokensetMember'} ) )
        {
            foreach my $tset
                ( split('\s*,\s*',
                        $interface->{'selectorActions'}{'TokensetMember'}) )
            {
                $tsetMember{$ifSubtreeName}{$tset} = 1;
            }
        }
        
        if( defined( $interface->{'selectorActions'}{'Parameters'} ) )
        {
            my @pairs = split('\s*;\s*',
                              $interface->{'selectorActions'}{'Parameters'});
            foreach my $pair( @pairs )
            {
                my ($param, $val) = split('\s*=\s*', $pair);
                $interface->{'param'}{$param} = $val;
            }
        }
        
        if( $interface->{'ifSpeedMonitoring'} )
        {
            my $speedDefined = 0;
            if( not $interface->{'ignoreHighSpeed'} and
                defined($interface->{'ifHighSpeed'}) )
            {
                push( @templates, 'RFC2863_IF_MIB::iftable-ifhighspeed' );
                $speedDefined = 1;
            }
            elsif( defined($interface->{'ifSpeed'}) )
            {
                push( @templates, 'RFC2863_IF_MIB::iftable-ifspeed' );
                $speedDefined = 1;
            }

            if( $speedDefined and $bandwidthUsageConfigured )
            {
                if( not defined($interface->{
                    'childCustomizations'}->{'InOut_bps'}) )
                {
                    $interface->{'childCustomizations'}->{'InOut_bps'} = {};
                }
                
                my $param = $interface->{'childCustomizations'}->{'InOut_bps'};
                $param->{'ds-expr-bw'} = '{Speed}';
                $param->{'graph-legend-bw'} = 'Available bandwidth';
                $param->{'line-style-bw'} = 'LINE1';
                $param->{'line-color-bw'} = '##HruleMax';
                $param->{'line-order-bw'} = 10;
                $param->{'ds-names'} = 'in,out,bw';

                push(@templates,
                     'RFC2863_IF_MIB::interface-bandwidth-usage-ifspeed');
            }

        }
        elsif( $bandwidthUsageActive and $interface->{'hasBandwidthUsage'} )
        {
            push( @templates,
                  'RFC2863_IF_MIB::interface-bandwidth-usage' );
        }

        if( ref( $interface->{'templates'} ) )
        {
            push( @templates, @{$interface->{'templates'}} );
        }

        # Add vendor templates
        push( @templates, @{$interface->{'vendor_templates'}} );
        
        # Add subtree only if there are template references

        if( defined( $interface->{'selectorActions'}{'AddTemplates'} ) )
        {
            push( @templates,
                  split('\s*,\s*',
                        $interface->{'selectorActions'}{'AddTemplates'}) );
        }        
            
        if( scalar( @templates ) > 0 )
        {
            # process interface-level parameters to copy

            foreach my $param ( @intfCopyParams )
            {
                my $val =
                    $devdetails->paramString('RFC2863_IF_MIB::' .
                                             $param . '::' . $ifSubtreeName );
                if( $val ne '' )
                {
                    $interface->{'param'}{$param} = $val;
                }
            }

            if( defined( $tsetMember{$ifSubtreeName} ) )
            {
                my $tsetList =
                    join( ',', sort keys %{$tsetMember{$ifSubtreeName}} );
                
                $interface->{'childCustomizations'}->{'InOut_bps'}->{
                    'tokenset-member'} = $tsetList;
                $tsetMemberApplied{$ifSubtreeName} = 1;
            }

            if( defined( $extStorage{$ifSubtreeName} ) )
            {
                foreach my $dir ( 'In', 'Out' )
                {
                    if( defined( $extStorage{$ifSubtreeName}{$dir} ) )
                    {
                        my $serviceid = $extStorage{$ifSubtreeName}{$dir};

                        my $params = {
                            'storage-type'      => 'rrd,ext',
                            'ext-service-id'    => $serviceid,
                            'ext-service-units' => 'bytes' };
                        
                        if( defined( $extStorageTrees{$serviceid} )
                            and $extStorageTrees{$serviceid} ne '' )
                        {
                            $params->{'ext-service-trees'} =
                                $extStorageTrees{$serviceid};
                        }

                        foreach my $param ( keys %{$params} )
                        {
                            $interface->{'childCustomizations'}->{
                                'Bytes_' . $dir}{$param} = $params->{$param};
                        }
                    }
                }
            }
            
            my $intfNode =
                $cb->addSubtree( $countersNode, $ifSubtreeName,
                                 $interface->{'param'}, \@templates );

            if( defined( $interface->{'childCustomizations'} ) )
            {
                foreach my $childName
                    ( sort keys %{$interface->{'childCustomizations'}} )
                {
                    if( $interface->{'hasChild'}{$childName} )
                    {
                        $cb->addLeaf
                            ( $intfNode, $childName,
                              $interface->{'childCustomizations'}->{
                                  $childName} );
                    }
                }
            }

            # If the interafce is a member of traffic summary
            if( defined( $trafficSummary{$ifSubtreeName} ) )
            {
                foreach my $summary ( keys %{$trafficSummary{$ifSubtreeName}} )
                {
                    addTrafficSummaryElement( $globalData,
                                              $summary, $intfNode );
                }
            }
        }
    }
    
    if( $nExplExcluded > 0 )
    {
        Debug('Explicitly excluded ' . $nExplExcluded .
              ' RFC2863_IF_MIB interfaces');
    }

    if( scalar(keys %tsetMember) > 0 )
    {
        my @failedIntf;
        foreach my $intfName ( keys %tsetMember )
        {
            if( not $tsetMemberApplied{$intfName} )
            {
                push( @failedIntf, $intfName );
            }
        }

        if( scalar( @failedIntf ) > 0 )
        {
            Warn('The following interfaces were not added to tokensets, ' .
                 'probably because they do not exist or are explicitly ' .
                 'excluded: ' .
                 join(' ', sort @failedIntf));
        }
    }                 
    
    $cb->{'statistics'}{'interfaces'} += $nInterfaces;
    if( not defined($cb->{'statistics'}{'max-interfaces-per-host'})
        or
        $cb->{'statistics'}{'max-interfaces-per-host'} < $nInterfaces )
    {
        $cb->{'statistics'}{'max-interfaces-per-host'} = $nInterfaces;
    }

    return;
}


sub addTrafficSummaryElement
{
    my $globalData = shift;
    my $summary = shift;
    my $node = shift;

    if( not defined( $globalData->{
        'RFC2863_IF_MIB::summaryMembers'}{$summary} ) )
    {
        $globalData->{'RFC2863_IF_MIB::summaryMembers'}{$summary} = [];
    }

    push( @{$globalData->{'RFC2863_IF_MIB::summaryMembers'}{$summary}},
          $node );
    return;
}
      

sub buildGlobalConfig
{
    my $cb = shift;
    my $globalData = shift;

    if( not defined( $globalData->{'RFC2863_IF_MIB::summaryMembers'} ) )
    {
        return;
    }
    
    foreach my $summary ( keys %{$globalData->{
        'RFC2863_IF_MIB::summaryMembers'}} )
    {
        next if scalar( @{$globalData->{
            'RFC2863_IF_MIB::summaryMembers'}{$summary}} ) == 0;

        my $attr = $globalData->{'RFC2863_IF_MIB::summaryAttr'}{$summary};
        my $path = $attr->{'path'};

        if( not defined( $path ) )
        {
            Error('Missing the path for traffic summary ' . $summary);
            next;
        }

        Debug('Building summary: ' . $summary);
        
        # Chop the first and last slashes
        $path =~ s/^\///;
        $path =~ s/\/$//;
        
        # generate subtree path XML
        my $subtreeNode = undef;
        foreach my $subtreeName ( split( '/', $path ) )
        {
            $subtreeNode = $cb->addSubtree( $subtreeNode, $subtreeName, {
                'comment'  => $attr->{'comment'},
                'data-dir' => $attr->{'data-dir'} } );
        }

        foreach my $dir ('In', 'Out')
        {
            my $rpn = '';
            foreach my $member ( @{$globalData->{
                'RFC2863_IF_MIB::summaryMembers'}{$summary}} )
            {
                my $memRef = '{' . $cb->getElementPath($member) .
                    'Bytes_' . $dir . '}';
                if( $rpn eq '' )
                {
                    $rpn = $memRef;
                }
                else
                {
                    $rpn .= ',' . $memRef . ',+';
                }
            }
            
            my $param = {
                'rpn-expr' => $rpn,
                'data-file' => 'summary_' . $summary . '.rrd',
                'rrd-ds' => 'Bytes' . $dir };
          
            $cb->addLeaf( $subtreeNode, 'Bytes_' . $dir, $param,
                          ['::cdef-collector-defaults'] );
        }
    }

    return;
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
    return;
}


# check if a given reference returns unique names and no empty values

sub validateReference
{
    my $devdetails = shift;
    my $nameref = shift;

    my $data = $devdetails->data();
    my %seen;

    foreach my $ifIndex ( sort {$a<=>$b} keys %{$data->{'interfaces'}} )
    {
        my $interface = $data->{'interfaces'}{$ifIndex};

        my $entry = $interface->{$nameref};
        if( not defined($entry) or $entry eq '' )
        {
            Debug($nameref . ' contains empty entries');
            return 0;
        }
        if( $seen{$entry} )
        {
            Debug($nameref . ' contains duplicate entries: "' . $entry . '"');
            return 0;
        }
        $seen{$entry} = 1;
    }

    $devdetails->setCap('uniqueNames_' . $nameref);
    return 1;
}


sub uniqueEntries
{
    my $devdetails = shift;
    my $nameref = shift;

    my $data = $devdetails->data();
    my %count;

    foreach my $ifIndex ( sort {$a<=>$b} keys %{$data->{'interfaces'}} )
    {
        my $interface = $data->{'interfaces'}{$ifIndex};
        
        my $entry = $interface->{$nameref};
        if( not defined($entry) or $entry eq '' )
        {
            $entry = $interface->{$nameref} = '_';
        }
        
        if( defined($count{$entry}) and $count{$entry} > 0 )
        {
            my $new_entry = sprintf('%s%d', $entry, int( $count{$entry} ) );
            $interface->{$nameref} = $new_entry;
            $count{$new_entry}++;
        }
        $count{$entry}++;
    }
    return;
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

    foreach my $ifIndex ( sort {$a<=>$b} keys %{$data->{'interfaces'}} )
    {
        my $interface = $data->{'interfaces'}{$ifIndex};

        my $macaddr = $devdetails->snmpVar($dd->oiddef('ifPhysAddress') .
                                           '.' . $ifIndex);

        if( defined( $macaddr ) and $macaddr ne '' )
        {
            $interface->{'MAC'} = $macaddr;
            $interface->{'param'}{'interface-macaddr'} = $macaddr;
        }
        else
        {
            Warn('Excluding interface without MAC address: ' .
                  $interface->{$data->{'nameref'}{'ifReferenceName'}});
            delete $data->{'interfaces'}{$ifIndex};
        }
    }
    return;
}


# For devices with fixed ifIndex mapping it populates interface-index parameter


sub storeIfIndexParams
{
    my $devdetails = shift;

    my $data = $devdetails->data();

    foreach my $ifIndex ( keys %{$data->{'interfaces'}} )
    {
        my $interface = $data->{'interfaces'}{$ifIndex};
        $interface->{'param'}{'interface-index'} = $ifIndex;        
    }

    return;
}

#######################################
# Selectors interface
#

$Torrus::DevDiscover::selectorsRegistry{'RFC2863_IF_MIB'} = {
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
    return( sort {$a<=>$b} keys (%{$devdetails->data()->{'interfaces'}}) );
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
    else
    {
        my $value;
        my $operator = '=~';
        if( $attr eq 'ifComment' and
            defined($data->{'nameref'}{'ifComment'}) )
        {
            $value = $interface->{$data->{'nameref'}{'ifComment'}};
        }
        elsif( $attr eq 'ifType' )
        {
            $value = $interface->{'ifType'};
            $operator = '==';
        }
        else
        {
            Error('Unknown RFC2863_IF_MIB selector attribute: ' . $attr);
            $value = '';
        }

        return eval( '$value' . ' ' . $operator . '$checkval' ) ? 1:0;
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
    ( 'InBytesMonitor'    => 'RFC2863_IF_MIB',
      'OutBytesMonitor'   => 'RFC2863_IF_MIB',
      'InDiscardsMonitor'  => 'RFC2863_IF_MIB',
      'OutDiscardsMonitor' => 'RFC2863_IF_MIB',
      'InErrorsMonitor'   => 'RFC2863_IF_MIB',
      'OutErrorsMonitor'  => 'RFC2863_IF_MIB',
      'NotifyPolicy'      => 'RFC2863_IF_MIB',
      'HoltWinters'       => 'RFC2863_IF_MIB',
      'NoPacketCounters'  => 'RFC2863_IF_MIB',
      'NoDiscardCounters' => 'RFC2863_IF_MIB',
      'NoErrorCounters'   => 'RFC2863_IF_MIB',
      'RemoveInterface'   => 'RFC2863_IF_MIB',
      'TokensetMember'    => 'RFC2863_IF_MIB',
      'Parameters'        => 'RFC2863_IF_MIB',
      'InBytesParameters' => 'RFC2863_IF_MIB',
      'OutBytesParameters' => 'RFC2863_IF_MIB',
      'AddTemplates'       => 'RFC2863_IF_MIB' );

                            
sub applySelectorAction
{
    my $devdetails = shift;
    my $object = shift;
    my $objType = shift;
    my $action = shift;
    my $arg = shift;

    my $data = $devdetails->data();
    my $interface = $data->{'interfaces'}{$object};

    if( defined( $knownSelectorActions{$action} ) )
    {
        if( not $devdetails->isDevType( $knownSelectorActions{$action} ) )
        {
            Error('Action ' . $action . ' is applied to a device that is ' .
                  'not of type ' . $knownSelectorActions{$action} .
                  ': ' . $devdetails->param('system-id'));
        }
        $interface->{'selectorActions'}{$action} = $arg;
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
