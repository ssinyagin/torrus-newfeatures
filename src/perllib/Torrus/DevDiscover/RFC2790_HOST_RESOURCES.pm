#  Copyright (C) 2003 Shawn Ferry, Stanislav Sinyagin
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

# Shawn Ferry <sferry at sevenspace dot com> <lalartu at obscure dot org>
# Stanislav Sinyagin <ssinyagin@yahoo.com>

# Standard HOST_RESOURCES_MIB discovery, which should apply to most hosts.

# The CPU indexing is not persistent, and may change after the target host
# reboot. This needs a re-discover, and the old CPU usage data may be lost.


package Torrus::DevDiscover::RFC2790_HOST_RESOURCES;

use strict;
use warnings;

use Torrus::Log;

$Torrus::DevDiscover::registry{'RFC2790_HOST_RESOURCES'} = {
    'sequence'     => 100,
    'checkdevtype' => \&checkdevtype,
    'discover'     => \&discover,
    'buildConfig'  => \&buildConfig
    };


# define the oids that are needed to determine support,
# capabilities and information about the device
our %oiddef =
    (
     'hrSystemUptime'               => '1.3.6.1.2.1.25.1.1.0',
     'hrSystemNumUsers'             => '1.3.6.1.2.1.25.1.5.0',
     'hrSystemProcesses'            => '1.3.6.1.2.1.25.1.6.0',
     'hrSystemMaxProcesses'         => '1.3.6.1.2.1.25.1.7.0',
     'hrMemorySize'                 => '1.3.6.1.2.1.25.2.2.0',
     'hrStorageTable'               => '1.3.6.1.2.1.25.2.3.1',
     'hrStorageIndex'               => '1.3.6.1.2.1.25.2.3.1.1',
     'hrStorageType'                => '1.3.6.1.2.1.25.2.3.1.2',
     'hrStorageDescr'               => '1.3.6.1.2.1.25.2.3.1.3',
     'hrStorageAllocationUnits'     => '1.3.6.1.2.1.25.2.3.1.4',
     'hrStorageSize'                => '1.3.6.1.2.1.25.2.3.1.5',
     'hrStorageUsed'                => '1.3.6.1.2.1.25.2.3.1.6',
     'hrStorageAllocationFailures'  => '1.3.6.1.2.1.25.2.3.1.7',
     'hrProcessorLoad'              => '1.3.6.1.2.1.25.3.3.1.2',
     );


our %storageDescTranslate =  ( '/' => {'subtree' => 'root' } );

# storage type names from MIB
my %storageTypes =
    (
     1  => 'Other Storage',
     2  => 'Physical Memory (RAM)',
     3  => 'Virtual Memory',
     4  => 'Fixed Disk',
     5  => 'Removable Disk',
     6  => 'Floppy Disk',
     7  => 'Compact Disk',
     8  => 'RAM Disk',
     9  => 'Flash Memory',
     10 => 'Network File System'
     );

our $storageGraphTop;
our $storageHiMark;

sub checkdevtype
{
    my $dd = shift;
    my $devdetails = shift;

    my $session = $dd->session();
    my $data = $devdetails->data();

    return $dd->checkSnmpOID('hrSystemUptime');
}


sub discover
{
    my $dd = shift;
    my $devdetails = shift;

    my $data = $devdetails->data();
    my $session = $dd->session();

    if( $dd->checkSnmpOID('hrSystemNumUsers') )
    {
        $devdetails->setCap('hrSystemNumUsers');
    }

    if( $dd->checkSnmpOID('hrSystemProcesses') )
    {
        $devdetails->setCap('hrSystemProcesses');
    }

    # hrStorage support
    my $hrStorageTable = $session->get_table( -baseoid =>
                                              $dd->oiddef('hrStorageTable') );
    if( defined( $hrStorageTable ) )
    {
        $devdetails->storeSnmpVars( $hrStorageTable );

        $data->{'hrStorage'} = {};

        foreach my $INDEX
            ( $devdetails->getSnmpIndices($dd->oiddef('hrStorageIndex') ) )
        {
            my $typeNum = $devdetails->snmpVar( $dd->oiddef('hrStorageType') .
                                                '.' . $INDEX );
            $typeNum =~ s/^[0-9.]+\.(\d+)$/$1/;

            my $descr = $devdetails->snmpVar($dd->oiddef('hrStorageDescr')
                                             . '.' . $INDEX);

            my $used =  $devdetails->snmpVar($dd->oiddef('hrStorageUsed')
                                             . '.' . $INDEX);

            if( defined( $used ) and $storageTypes{$typeNum} )
            {
                my $ref = { 'param' => {}, 'templates' => [] };
                $data->{'hrStorage'}{$INDEX} = $ref;
                my $param = $ref->{'param'};

                $param->{'storage-description'} = $descr;

                my $comment = $storageTypes{$typeNum};
                if( $descr =~ /^\// )
                {
                    $comment .= ' (' . $descr . ')';
                }
                $param->{'comment'} = $comment;

                if( $storageDescTranslate{$descr}{'subtree'} )
                {
                    $descr = $storageDescTranslate{$descr}{'subtree'};
                }
                $descr =~ s/^\///;
                $descr =~ s/\W/_/g;
                $param->{'storage-nick'} = $descr;

                my $units =
                    $devdetails->snmpVar
                    ($dd->oiddef('hrStorageAllocationUnits') . '.' . $INDEX);

                $param->{'collector-scale'} = sprintf('%d,*', $units);

                my $size =
                    $devdetails->snmpVar
                    ($dd->oiddef('hrStorageSize') . '.' . $INDEX);

                if( $size )
                {
                    if( $storageGraphTop > 0 )
                    {
                        $param->{'graph-upper-limit'} =
                            sprintf('%e',
                                    $units * $size * $storageGraphTop / 100 );
                    }

                    if( $storageHiMark > 0 )
                    {
                        $param->{'upper-limit'} =
                            sprintf('%e',
                                    $units * $size * $storageHiMark / 100 );
                    }
                }

                push( @{ $ref->{'templates'} },
                      'RFC2790_HOST_RESOURCES::hr-storage-usage' );
            }
        }

        if( scalar( keys %{$data->{'hrStorage'}} ) > 0 )
        {
            $devdetails->setCap('hrStorage');
        }
    }

    # hrProcessor support
    {
        my $base = $dd->oiddef('hrProcessorLoad');
        my $table = $session->get_table( -baseoid => $base );
        if( defined($table) )
        {
            $data->{'hrProcessors'} = [];
            my $prefixLen = length( $base ) + 1;
        
            while( my( $oid, $load ) = each %{$table} )
            {
                push( @{$data->{'hrProcessors'}}, substr( $oid, $prefixLen ));
            }

            if( scalar( @{$data->{'hrProcessors'}} ) > 0 )
            {
                $devdetails->setCap('hrProcessor');
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

    { # Anon sub for System Performance
        my $subtreeName =
            $devdetails->paramString
            ('RFC2790_HOST_RESOURCES::sysperf-subtree-name');
        if( $subtreeName eq '' )
        {
            $subtreeName = 'System_Performance';
            $devdetails->setParam
                ('RFC2790_HOST_RESOURCES::sysperf-subtree-name', $subtreeName);
        }

        my @templates =
            ('RFC2790_HOST_RESOURCES::hr-system-performance-subtree',
             'RFC2790_HOST_RESOURCES::hr-system-uptime');
        if( $devdetails->hasCap('hrSystemNumUsers') )
        {
            push( @templates, 'RFC2790_HOST_RESOURCES::hr-system-num-users' );
        }

        if( $devdetails->hasCap('hrSystemProcesses') )
        {
            push( @templates, 'RFC2790_HOST_RESOURCES::hr-system-processes' );
        }

        my $subtreeNode = $cb->addSubtree( $devNode, $subtreeName,
                                           {}, \@templates );

        if( $devdetails->hasCap('hrProcessor') )
        {
            foreach my $INDEX ( sort {$a<=>$b} @{$data->{'hrProcessors'}} )
            {
                my $cpuName = 'CPU_' . $INDEX . '_Load';
                
                my $param = {
                    'cpu-id' => $INDEX,
                    'node-display-name' => 'CPU ' . $INDEX . ' Load',
                    'precedence' => sprintf("%d", 1000 - $INDEX),
                };
                
                $cb->addLeaf( $subtreeNode, $cpuName, $param,
                              ['RFC2790_HOST_RESOURCES::hr-processor-load']);
                
            }
        }
    }

    if( $devdetails->hasCap('hrStorage') )
    {
        # Build hrstorage subtree
        my $subtreeName = 'Storage_Used';

        my $param = {};
        my @templates = ('RFC2790_HOST_RESOURCES::hr-storage-subtree');
        my $subtreeNode = $cb->addSubtree( $devNode, $subtreeName,
                                           $param, \@templates  );

        foreach my $INDEX ( sort {$a<=>$b} keys %{$data->{'hrStorage'}} )
        {
            my $ref = $data->{'hrStorage'}{$INDEX};

            #Display in index order, This is generally good(tm)
            $ref->{'param'}->{'precedence'} = sprintf("%d", 1000 - $INDEX);

            $cb->addLeaf( $subtreeNode, $ref->{'param'}{'storage-nick'},
                          $ref->{'param'}, $ref->{'templates'} );
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
