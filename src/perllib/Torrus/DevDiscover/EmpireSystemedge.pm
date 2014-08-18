#  Copyright (C) 2003-2012 Shawn Ferry, Roman Hochuli
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
# Roman Hochuli <roman dot hochuli at nexellent dot ch> <roman at hochu dot li>

package Torrus::DevDiscover::EmpireSystemedge;

use strict;
use Torrus::Log;
use Data::Dumper;

$Torrus::DevDiscover::registry{'EmpireSystemedge'} = {
    'sequence'     => 500,
    'checkdevtype' => \&checkdevtype,
    'discover'     => \&discover,
    'buildConfig'  => \&buildConfig
    };


# define the oids that are needed to determine support,
# capabilities and information about the device
our %oiddef =
    (
     'empire'                   => '1.3.6.1.4.1.546',

     'sysedge_opmode'           => '1.3.6.1.4.1.546.1.1.1.17.0',
     'empireSystemType'         => '1.3.6.1.4.1.546.1.1.1.12.0',

     # Empire Cpu Table
     'empireCpuStatsTable'      => '1.3.6.1.4.1.546.13.1.1',
     'empireCpuStatsIndex'      => '1.3.6.1.4.1.546.13.1.1.1',
     'empireCpuStatsDescr'      => '1.3.6.1.4.1.546.13.1.1.2',

     # Empire Cpu Totals
     'empireCpuTotalWait'       => '1.3.6.1.4.1.546.13.5.0',

     # Empire Swap Counters
     'empireNumPageSwapIns'      => '1.3.6.1.4.1.546.1.1.7.8.18.0',

     # Empire Load Average
     'empireLoadAverage'        => '1.3.6.1.4.1.546.1.1.7.8.26.0',

     # Empire Device Table and Oids
     'empireDevTable'           => '1.3.6.1.4.1.546.1.1.1.7.1',
     'empireDevIndex'           => '1.3.6.1.4.1.546.1.1.1.7.1.1',
     'empireDevMntPt'           => '1.3.6.1.4.1.546.1.1.1.7.1.3',
     'empireDevBsize'           => '1.3.6.1.4.1.546.1.1.1.7.1.4',
     'empireDevTblks'           => '1.3.6.1.4.1.546.1.1.1.7.1.5',
     'empireDevType'            => '1.3.6.1.4.1.546.1.1.1.7.1.10',
     'empireDevDevice'          => '1.3.6.1.4.1.546.1.1.1.7.1.2',

     # Empire Device Stats Table and Oids
     'empireDiskStatsTable'      => '1.3.6.1.4.1.546.12.1.1',
     'empireDiskStatsIndex'      => '1.3.6.1.4.1.546.12.1.1.1',
     'empireDiskStatsHostIndex'  => '1.3.6.1.4.1.546.12.1.1.9',
     'hrDeviceDescr'             => '1.3.6.1.2.1.25.3.2.1.3',

     # Empire Performance and related oids
     'empirePerformance'        => '1.3.6.1.4.1.546.1.1.7',
     'empireNumTraps'           => '1.3.6.1.4.1.546.1.1.7.8.15.0',

     # Empire Process Stats
     'empireRunq'               => '1.3.6.1.4.1.546.1.1.7.8.4.0',
     'empireDiskWait'           => '1.3.6.1.4.1.546.1.1.7.8.5.0',
     'empirePageWait'           => '1.3.6.1.4.1.546.1.1.7.8.6.0',
     'empireSwapActive'         => '1.3.6.1.4.1.546.1.1.7.8.7.0',
     'empireSleepActive'        => '1.3.6.1.4.1.546.1.1.7.8.8.0',

     # Empire Extensions NTREGPERF
     'empireNTREGPERF'          => '1.3.6.1.4.1.546.5.7',

     'empireDnlc'               => '1.3.6.1.4.1.546.1.1.11',
     'empireRpc'                => '1.3.6.1.4.1.546.8.1',
     'empireNfs'                => '1.3.6.1.4.1.546.8.2',
     'empireMon'                => '1.3.6.1.4.1.546.6.1.1',
     'empirePmon'               => '1.3.6.1.4.1.546.15.1.1',
     'empireLog'                => '1.3.6.1.4.1.546.11.1.1',
     
     # Empire Service Response Extension
     'empireSvcTable'           => '1.3.6.1.4.1.546.16.6.10.1',
     'empireSvcIndex'           => '1.3.6.1.4.1.546.16.6.10.1.1',
     'empireSvcDescr'           => '1.3.6.1.4.1.546.16.6.10.1.2',
     'empireSvcType'            => '1.3.6.1.4.1.546.16.6.10.1.3',
     'empireSvcTotRespTime'     => '1.3.6.1.4.1.546.16.6.10.1.12',
     'empireSvcAvailability'    => '1.3.6.1.4.1.546.16.6.10.1.17',
     'empireSvcConnTime'        => '1.3.6.1.4.1.546.16.6.10.1.23',
     'empireSvcTransTime'       => '1.3.6.1.4.1.546.16.6.10.1.28',
     'empireSvcThroughput'      => '1.3.6.1.4.1.546.16.6.10.1.37',
     'empireSvcDestination'     => '1.3.6.1.4.1.546.16.6.10.1.45',
     );

our %storageDescTranslate =  ( '/' => {'subtree' => 'root' } );

# template => 1 if specific templates for the name explicitly exist,
# othewise the template used is based on ident
#
# Generally only hosts that have been directly observed should have
# templates, the "unix" and "nt" templates are generally aiming for the
# lowest common denominator.
#
# templates also need to be added to devdiscover-config.pl
#
#    Templated "names" require a specific template for each of the
#    following base template types:
#    <template name="empire-swap-counters-NAME">
#    <template name="empire-counters-NAME">
#    <template name="empire-total-cpu-NAME">
#    <template name="empire-total-cpu-raw-NAME">
#    <template name="empire-cpu-NAME">
#    <template name="empire-cpu-raw-NAME">
#    <template name="empire-disk-stats-NAME">
#
#    i.e.
#    <template name="empire-swap-counters-solarisSparc">
#    <template name="empire-counters-solarisSparc">
#    <template name="empire-total-cpu-solarisSparc">
#    <template name="empire-total-cpu-raw-solarisSparc">
#    <template name="empire-cpu-solarisSparc">
#    <template name="empire-cpu-raw-solarisSparc">
#    <template name="empire-disk-stats-solarisSparc">
#


our %osTranslate =
    (
     1  => { 'name' => 'unknown',   'ident' => 'unknown', 'template' => 0, },
     2  => { 'name' => 'solarisSparc', 'ident' => 'unix', 'template' => 1, },
     3  => { 'name' => 'solarisIntel', 'ident' => 'unix', 'template' => 0, },
     4  => { 'name' => 'solarisPPC',   'ident' => 'unix', 'template' => 0, },
     5  => { 'name' => 'sunosSparc',   'ident' => 'unix', 'template' => 0, },
     6  => { 'name' => 'hpux9Parisc',  'ident' => 'unix', 'template' => 0, },
     7  => { 'name' => 'hpux10Parisc', 'ident' => 'unix', 'template' => 0, },
     8  => { 'name' => 'nt351Intel',   'ident' => 'nt',   'template' => 0, },
     9  => { 'name' => 'nt351Alpha',   'ident' => 'nt',   'template' => 0, },
     10 => { 'name' => 'nt40Intel',    'ident' => 'nt',   'template' => 1, },
     11 => { 'name' => 'nt40Alpha',    'ident' => 'nt',   'template' => 0, },
     12 => { 'name' => 'irix62Mips',   'ident' => 'unix', 'template' => 0, },
     13 => { 'name' => 'irix63Mips',   'ident' => 'unix', 'template' => 0, },
     14 => { 'name' => 'irix64Mips',   'ident' => 'unix', 'template' => 0, },
     15 => { 'name' => 'aix41RS6000',  'ident' => 'unix', 'template' => 0, },
     16 => { 'name' => 'aix42RS6000',  'ident' => 'unix', 'template' => 0, },
     17 => { 'name' => 'aix43RS6000',  'ident' => 'unix', 'template' => 0, },
     18 => { 'name' => 'irix65Mips',   'ident' => 'unix', 'template' => 0, },
     19 => { 'name' => 'digitalUNIX',  'ident' => 'unix', 'template' => 0, },
     20 => { 'name' => 'linuxIntel',   'ident' => 'unix', 'template' => 1, },
     21 => { 'name' => 'hpux11Parisc', 'ident' => 'unix', 'template' => 0, },
     22 => { 'name' => 'nt50Intel',    'ident' => 'nt',   'template' => 1, },
     23 => { 'name' => 'nt50Alpha',    'ident' => 'nt',   'template' => 0, },
     25 => { 'name' => 'aix5RS6000',   'ident' => 'unix', 'template' => 1, },
     26 => { 'name' => 'nt52Intel',    'ident' => 'nt',   'template' => 0, }, # linuxIA64
     27 => { 'name' => 'linuxIntel',   'ident' => 'unix', 'template' => 1, },
     28 => { 'name' => 'hpux11IA64',   'ident' => 'unix', 'template' => 0, }, # nt52IA64 Windows 2003 Itanium
     29 => { 'name' => 'nt50Intel',    'ident' => 'nt',   'template' => 1, }, # nt52X64  Windows 2003 x64 (AMD64 or EMT64)
     30 => { 'name' => 'nt50Intel',    'ident' => 'nt',   'template' => 1, },
     31 => { 'name' => 'linuxIntel',   'ident' => 'unix', 'template' => 1, }, # nt52IA64 Windows 2003 Itanium
     33 => { 'name' => 'nt50Intel',    'ident' => 'nt',   'template' => 1, }, # nt50Intel Windows 2008 32bit
     35 => { 'name' => 'nt50Intel',    'ident' => 'nt',   'template' => 1, }, # nt50Intel Windows 2008 R2 64bit or Windows 2012 
     );

# Solaris Virtual Interface Filtering
our $interfaceFilter;
my %solarisVirtualInterfaceFilter;
my %winNTInterfaceFilter;

# Key is some unique symbolic name, does not mean anything
# ifType is the number to match the interface type
# ifDescr is the regexp to match the interface description
%solarisVirtualInterfaceFilter = (
    'Virtual Interface (iana 62)' => {
        'ifType'    =>  62,             # Obsoleted
        'ifDescr'   =>  '^\w+:\d+$',    # Virtual Interface in the form xxx:1
                                        # e.g. eri:1 eri1:2
        },

    'Virtual Interface' => {
        'ifType'    =>  6,
        'ifDescr'   =>  '^\w+:\d+$',    # Virtual Interface in the form xxx:1
                                        # e.g. eri:1 eri1:2
        },
    );


# Key is some unique symbolic name, does not mean anything
# ifType is the number to match the interface type
# ifDescr is the regexp to match the interface description
# shameless rip-off from MicrsoftWindows.pm
%winNTInterfaceFilter =
    (
     'MS TCP Loopback interface' => {
         'ifType'  => 24                        # softwareLoopback
         },
     
     'Tunnel' => {
         'ifType'  => 131                       # tunnel
         },
     
     'PPP' => {
         'ifType'  => 23                        # ppp
         },
     
     'WAN Miniport Ethernet' => {
         'ifType'  => 6,                        # ethernetCsmacd
         'ifDescr' => '^WAN[-|\s+]Miniport'
         },
     
     'QoS Packet Scheduler' => {
         'ifType'  => 6,                        # ethernetCsmacd
         'ifDescr' => 'QoS\s+Packet\s+Scheduler'
         },

     'LightWeight Filter' => {
         'ifType'  => 6,                        # ethernetCsmacd
         'ifDescr' => 'WFP\s+LightWeight\s+Filter'
         },

     'LightWeight Filter MAC Native' => {
         'ifType'  => 6,                        # ethernetCsmacd
         'ifDescr' => 'WFP\s+Native\s+MAC\s+Layer\s+LightWeight\s+Filter'
         },

     'LightWeight Filter MAC 802.3' => {
         'ifType'  => 6,                        # ethernetCsmacd
         'ifDescr' => 'WFP\s+802.3\s+MAC\s+Layer\s+LightWeight\s+Filter'
         },

     'Microsoft Kernel Debug Network Adapter' => {
         'ifType'  => 6,                        # ethernetCsmacd
         'ifDescr' => 'Microsoft\s+Kernel\s+Debug\s+Network\s+Adapter'
         },
     );
 

our $storageGraphTop;
our $storageHiMark;
our $shortTemplate;
our $longTemplate;

sub checkdevtype
{
    my $dd = shift;
    my $devdetails = shift;

    my $session = $dd->session();
    my $data = $devdetails->data();

    if( not $dd->checkSnmpTable( 'empire' ) )
    {
        return 0;
    }

    my $result = $dd->retrieveSnmpOIDs( 'sysedge_opmode' );
    if( $result->{'sysedge_opmode'} == 2 )
    {
        Error("Sysedge Agent NOT Licensed");
        $devdetails->setCap('SysedgeNotLicensed');
    }

    # Empire OS Type (Needed here for interface filtering)
    my $empireOsType =
        $session->get_request( -varbindlist =>
                               [ $dd->oiddef('empireSystemType') ] );

    if( $session->error_status() == 0 )
    {
        my $sysType = $empireOsType->{$dd->oiddef('empireSystemType')};

        if( not defined($osTranslate{$sysType}) )
        {
            Warn('Unknown value in empireSystemType: ' . $sysType);
            return 0;
        }

        my $tr = $osTranslate{$sysType};
        
        $devdetails->setCap('EmpireSystemedge::' . $tr->{ident} );
        $devdetails->{'os_ident'} = $tr->{ident};

        $devdetails->setCap('EmpireSystemedge::' . $tr->{name} );
        $devdetails->{'os_name'} = $tr->{name};

        $devdetails->{'os_name_template'} = $tr->{template};
    }

    # Exclude Virtual Interfaces on Solaris
    if( $devdetails->{'os_name'} =~ /solaris/i ) {

        $interfaceFilter = \%solarisVirtualInterfaceFilter;
        &Torrus::DevDiscover::RFC2863_IF_MIB::addInterfaceFilter
            ($devdetails, $interfaceFilter);
    }

    # Exclude strange interfaces on Windows
    # shameless rip-off from MicrsoftWindows.pm
    if( ( $devdetails->{'os_name'} =~ /nt40/i ) or ( $devdetails->{'os_name'} =~ /nt50/i )) {

        $interfaceFilter = \%winNTInterfaceFilter;
        &Torrus::DevDiscover::RFC2863_IF_MIB::addInterfaceFilter
            ($devdetails, $interfaceFilter);
        $devdetails->setCap('interfaceIndexingManaged');
    }

    return 1;
}


sub discover
{
    my $dd = shift;
    my $devdetails = shift;

    my $session = $dd->session();
    my $data = $devdetails->data();


    # Exclude strange interfaces on Windows
    # shameless rip-off from MicrsoftWindows.pm
    if( ( $devdetails->{'os_name'} =~ /nt40Intel/i ) or ( $devdetails->{'os_name'} =~ /nt50Intel/i )) {

        # to keep backward compatibility we set the interface
        # comment explicitly to '' if there is no ifAlias table
        # which _may_ be the case with very old versions of
        # Microsoft Windows
        if ( not $devdetails->hasCap( 'ifAlias' ) )
        {
            Debug("No ifAlias present to setting ifComment to ''");
            $data->{'nameref'}{'ifComment'} = '';
        }

        $data->{'nameref'}{'ifComment'} = ''; # suggest?
        $data->{'param'}{'ifindex-map'} = '$IFIDX_MAC';
        Torrus::DevDiscover::RFC2863_IF_MIB::retrieveMacAddresses( $dd, $devdetails );
        $data->{'nameref'}{'ifNick'} = 'MAC';
        $data->{'nameref'}{'ifNodeid'} = 'MAC';    
    }


    # Empire Cpu Totals

    if($dd->checkSnmpTable('empireCpuTotalWait')) {
        $devdetails->setCap('EmpireSystemedge::CpuTotal::Wait');
    }


    # The layout of these discover-procedures look somewhat nuts but walking the tables first and testing later if it returns
    # values uses one less snmp-request than checking for the existance of the tables first and walking them again later. 
    # This brings a whopping ~0.0090s/device faster discovery. See discussion here:
    # https://github.com/medea61/torrus-newfeatures/commit/ba958bd27011243a3daa55c8bd657d4c8bf9d04c#commitcomment-1702848
    
    # Empire Dev Stats Table

    {
        my $indices = $dd->walkSnmpTable('empireDiskStatsIndex');
        my $hrtable = $dd->walkSnmpTable('hrDeviceDescr');

        if((scalar(keys %{$indices}) > 0) && (scalar(keys %{$hrtable}) > 0)) {
            my $dshostindex = $dd->walkSnmpTable('empireDiskStatsHostIndex');

            $devdetails->setCap('EmpireSystemedge::DiskStats');
            $data->{'empireDiskStats'} = {};
            $data->{'empireDiskStats'}{'indices'} = [];


            while( my( $index, $value ) = each %{$indices} ) {
                push(@{$data->{'empireDiskStats'}{'indices'}}, $index);

                $data->{'empireDiskStats'}{$index}{'templates'} = [];
                $data->{'empireDiskStats'}{$index}{'param'}{'HRINDEX'} = $dshostindex->{$index};
                $data->{'empireDiskStats'}{$index}{'param'}{'comment'} = $hrtable->{$dshostindex->{$index}};

                if(not defined($hrtable->{$dshostindex->{$index}})) {
                    $data->{'empireDiskStats'}{$index}{'param'}{'disk-stats-description'} = 'Index ' . $dshostindex->{$index};
                } else {
                    $data->{'empireDiskStats'}{$index}{'param'}{'disk-stats-description'} = $hrtable->{$dshostindex->{$index}};                
                }

                my $nick = $hrtable->{$dshostindex->{$index}};
                $nick =~ s/^\///;
                $nick =~ s/\W/_/g;
                $data->{'empireDiskStats'}{$index}{'param'}{'disk-stats-nick'} = $nick;
            }
        }
    }


    # Empire Dev Table

    {
        my $indices = $dd->walkSnmpTable('empireDevIndex');

        if(scalar(keys %{$indices}) > 0) {
            my $types = $dd->walkSnmpTable('empireDevType');
            my $descr = $dd->walkSnmpTable('empireDevMntPt');
            my $bsize = $dd->walkSnmpTable('empireDevBsize');
            my $device = $dd->walkSnmpTable('empireDevDevice');
            my $size = $dd->walkSnmpTable('empireDevTblks');

            $devdetails->setCap('EmpireSystemedge::Devices');
            $data->{'empireDev'} = {};
            $data->{'empireDev'}{'indices'} = [];

            while( my( $index, $value ) = each %{$indices} ) {
                if ($bsize->{$index} and defined ($descr->{$index})) {
                    push(@{$data->{'empireDev'}{'indices'}}, $index);

                    $data->{'empireDev'}{$index}{'templates'} = [];
                    $data->{'empireDev'}{$index}{'param'}{'storage-description'} = $descr->{$index};
                    $data->{'empireDev'}{$index}{'param'}{'storage-device'} = $device->{$index};
                    $data->{'empireDev'}{$index}{'param'}{'node-display-name'} = $device->{$index};

                    my $comment = $types->{$index};
                    if( $descr->{$index} =~ /^\// )
                    {
                        $comment .= ' (' . $descr->{$index} . ')';
                    }
                    $data->{'empireDev'}{$index}{'param'}{'comment'} = $comment;

                    my $devdescr = $descr->{$index};
                    if( $storageDescTranslate{$descr->{$index}}{'subtree'} )
                    {
                        $devdescr = $storageDescTranslate{$descr->{$index}}{'subtree'};
                    }
                    $devdescr =~ s/^\///;
                    $devdescr =~ s/\W/_/g;
                    $data->{'empireDev'}{$index}{'param'}{'storage-nick'} = $devdescr;

                    my $units = $bsize->{$index};
                    $data->{'empireDev'}{$index}{'param'}{'collector-scale'} = sprintf('%d,*', $units);

                    if($size->{$index}) {
                        if($storageGraphTop > 0)
                        {
                            $data->{'empireDev'}{$index}{'param'}{'graph-upper-limit'} = sprintf('%e', $units * $size->{$index} * $storageGraphTop / 100 );
                        }

                        if( $storageHiMark > 0 )
                        {
                            $data->{'empireDev'}{$index}{'param'}{'upper-limit'} = sprintf('%e', $units * $size->{$index} * $storageHiMark / 100 );
                        }
                    }

                }
            }

            $devdetails->clearCap('hrStorage');
        }
    }


    # Empire Per - Cpu Table

    {
        my $indices = $dd->walkSnmpTable('empireCpuStatsIndex');

        if(scalar(keys %{$indices}) > 0) {
            my $table = $dd->walkSnmpTable('empireCpuStatsTable');
            my $cpuStatsDescr = 2;

            $devdetails->setCap('EmpireSystemedge::CpuStats');
            $data->{'empireCpuStats'} = {};
            $data->{'empireCpuStats'}{'indices'} = [];

            while( my( $index, $value ) = each %{$indices} ) {
                push(@{$data->{'empireCpuStats'}{'indices'}}, $index);

                $data->{'empireCpuStats'}{$index}{'templates'} = [];
                $data->{'empireCpuStats'}{$index}{'param'}{'INDEX'} = $index;
                $data->{'empireCpuStats'}{$index}{'param'}{'cpu'} = 'CPU' . $index;
                $data->{'empireCpuStats'}{$index}{'param'}{'descr'} = $table->{$cpuStatsDescr . '.' . $index};
                $data->{'empireCpuStats'}{$index}{'param'}{'comment'} = $data->{'empireCpuStats'}{$index}{'param'}{'descr'} . ' (' . 'CPU ' . $index . ')';

            }
        }
    }


    # Empire Load Average

    if($dd->checkSnmpTable('empireLoadAverage')) {
        $devdetails->setCap('EmpireSystemedge::LoadAverage');
        my $ref = {'indices' => []};
        $data->{'empireLoadAverage'} = $ref;
    }
    

    # Empire Swap Counters

    if($dd->checkSnmpTable('empireNumPageSwapIns')) {
        $devdetails->setCap('EmpireSystemedge::SwapCounters');
    }
    

    # Empire Counter Traps

    if($dd->checkSnmpTable('empireNumTraps')) {
        $devdetails->setCap('EmpireSystemedge::CounterTraps');
    }
    

    # Empire Performance

    if($dd->checkSnmpTable('empirePerformance')) {
        $devdetails->setCap('EmpireSystemedge::Performance');

        if($dd->checkSnmpTable('empireRunq'))
        {
            $devdetails->setCap('EmpireSystemedge::RunQ');
        }
        
        if($dd->checkSnmpTable('empireDiskWait'))
        {
            $devdetails->setCap('EmpireSystemedge::DiskWait');
        }
        
        if($dd->checkSnmpTable('empirePageWait'))
        {
            $devdetails->setCap('EmpireSystemedge::PageWait');
        }
        
        if($dd->checkSnmpTable('empireSwapActive'))
        {
            $devdetails->setCap('EmpireSystemedge::SwapActive');
        }
        
        if($dd->checkSnmpTable('empireSleepActive'))
        {
            $devdetails->setCap('EmpireSystemedge::SleepActive');
        }
    }


    # Empire Service Checks

    {
        my $indices = $dd->walkSnmpTable('empireSvcIndex');

        if(scalar(keys %{$indices}) > 0) {
            my $table = $dd->walkSnmpTable('empireSvcTable');
            my $svcDescr = 2;
            my $svcType = 3;
            my $svcTotRespTime = 12;

            my $found = 0;
            $data->{'empireSvcStats'} = {};
            $data->{'empireSvcStats'}{'indices'} = [];


            while( my( $index, $value ) = each %{$indices} ) {
                push(@{$data->{'empireSvcStats'}{'indices'}}, $index);

                if($table->{$svcType . '.' . $index} eq "4") {
                    $found = 1;
                   
                    $data->{'empireSvcStats'}{$index}{'param'}{'INDEX'} = $index;
                    $data->{'empireSvcStats'}{$index}{'param'}{'id'} = 'Responder_' . $index;
                    $data->{'empireSvcStats'}{$index}{'param'}{'descr'} = $table->{$svcDescr . '.' . $index};
                    $data->{'empireSvcStats'}{$index}{'param'}{'descr'} = $table->{$svcDescr . '.' . $index};

                    if ( defined $devdetails->{'params'}->{'node-display-name'} ) {
                        $data->{'empireSvcStats'}{$index}{'param'}{'name'} = $devdetails->{'params'}->{'node-display-name'};
                    }
                    elsif ( defined $devdetails->{'params'}->{'symbolic-name'} ) {
                        $data->{'empireSvcStats'}{$index}{'param'}{'name'} = $devdetails->{'params'}->{'symbolic-name'};
                    }
                    else {
                        $data->{'empireSvcStats'}{$index}{'param'}{'name'} = $data->{'param'}->{'snmp-host'};
                    }
                }
            }

            if( $found ) {
                $devdetails->setCap('EmpireSystemedge::ServiceResponse');
            }                
        }
    }


    # Empire NTREGPERF

    {
        my $indices = $dd->walkSnmpTable('empireNTREGPERF');
        if(scalar(keys %{$indices}) > 0) {
            $devdetails->setCap('EmpireSystemedge::empireNTREGPERF');
            $data->{'empireNTREGPERF'} = {};
            $data->{'empireNTREGPERF'}{'indices'} = [];

            while( my( $index, $value ) = each %{$indices} ) {
                push(@{$data->{'empireSvcStats'}{'indices'}}, $index);

                $Torrus::ConfigBuilder::templateRegistry->{'EmpireSystemedge::NTREGPERF_' . $index} = {};
                $Torrus::ConfigBuilder::templateRegistry->{'EmpireSystemedge::NTREGPERF_' . $index}{'name'}='EmpireSystemedge::NTREGPERF_' . $index;
                $Torrus::ConfigBuilder::templateRegistry->{'EmpireSystemedge::NTREGPERF_' . $index}{'source'}='vendor/empire.systemedge.ntregperf.xml';
            } 
        }
    }

#NOT CONFIGURED## Empire DNLC
#NOT CONFIGURED#    my $empireDnlc = $session->get_table( -baseoid =>
#NOT CONFIGURED#        $dd->oiddef('empireDnlc') );
#NOT CONFIGURED#    if( defined $empirePerformance )
#NOT CONFIGURED#    {
#NOT CONFIGURED#        # don't do this until we use the data
#NOT CONFIGURED#        #$devdetails->setCap('empirednlc');
#NOT CONFIGURED#        #$devdetails->storeSnmpVars( $empireDnlc );
#NOT CONFIGURED#    }
#NOT CONFIGURED#
#NOT CONFIGURED## Empire RPC
#NOT CONFIGURED#    my $empireRpc = $session->get_table( -baseoid =>
#NOT CONFIGURED#        $dd->oiddef('empireRpc') );
#NOT CONFIGURED#    if( defined $empireRpc )
#NOT CONFIGURED#    {
#NOT CONFIGURED#        # don't do this until we use the data
#NOT CONFIGURED#        #$devdetails->setCap('empirerpc');
#NOT CONFIGURED#        #$devdetails->storeSnmpVars( $empireRpc );
#NOT CONFIGURED#    }
#NOT CONFIGURED#
#NOT CONFIGURED## Empire NFS
#NOT CONFIGURED#    my $empireNfs = $session->get_table( -baseoid =>
#NOT CONFIGURED#        $dd->oiddef('empireNfs') );
#NOT CONFIGURED#    if( defined $empireRpc )
#NOT CONFIGURED#    {
#NOT CONFIGURED#        # don't do this until we use the data
#NOT CONFIGURED#        #$devdetails->setCap('empirenfs');
#NOT CONFIGURED#        #$devdetails->storeSnmpVars( $empireNfs );
#NOT CONFIGURED#    }
#NOT CONFIGURED#
#NOT CONFIGURED## Empire Mon Entries
#NOT CONFIGURED#    my $empireMon = $session->get_table( -baseoid =>
#NOT CONFIGURED#        $dd->oiddef('empireMon') );
#NOT CONFIGURED#    if( ref( $empireMon ) )
#NOT CONFIGURED#    {
#NOT CONFIGURED#        # don't do this until we use the data
#NOT CONFIGURED#        #$devdetails->setCap('empiremon');
#NOT CONFIGURED#        #$devdetails->storeSnmpVars( $empireMon );
#NOT CONFIGURED#    }
#NOT CONFIGURED#
#NOT CONFIGURED## Empire Process Monitor Entries
#NOT CONFIGURED#    my $empirePmon = $session->get_table( -baseoid =>
#NOT CONFIGURED#        $dd->oiddef('empirePmon') );
#NOT CONFIGURED#    if( ref( $empirePmon ) )
#NOT CONFIGURED#    {
#NOT CONFIGURED#        # don't do this until we use the data
#NOT CONFIGURED#        #$devdetails->setCap('empirePmon');
#NOT CONFIGURED#        #$devdetails->storeSnmpVars( $empirePmon );
#NOT CONFIGURED#    }
#NOT CONFIGURED#
#NOT CONFIGURED## Empire Log Monitor Entries
#NOT CONFIGURED#    my $empireLog = $session->get_table( -baseoid =>
#NOT CONFIGURED#        $dd->oiddef('empireLog') );
#NOT CONFIGURED#    if( ref( $empireLog ) )
#NOT CONFIGURED#    {
#NOT CONFIGURED#        # don't do this until we use the data
#NOT CONFIGURED#        #$devdetails->setCap('empireLog');
#NOT CONFIGURED#        #$devdetails->storeSnmpVars( $empireLog );
#NOT CONFIGURED#    }

    return 1;
}


sub buildConfig
{
    my $devdetails = shift;
    my $cb = shift;
    my $devNode = shift;
    my $data = $devdetails->data();

    my $mononlyTree = "Mon_Only";
    my $monParam = {
        'precedence'    => '-100000',
        'comment'       => 'Place to Stash Monitoring Data ',
        'hidden'        => 'yes',
    };

    my $monNode = $cb->addSubtree( $devNode, $mononlyTree, $monParam );
    $cb->addTemplateApplication
        ( $monNode, 'EmpireSystemedge::sysedge_opmode' );

    if( $devdetails->hasCap('SysedgeNotLicensed') )
    {
        return 1;
    }

    my $os_target;
    if( $devdetails->{'os_name_template'} )
    {
        $os_target = $devdetails->{'os_name'};
    }
    else
    {
        $os_target = $devdetails->{'os_ident'};
        Warn("Using Generic OS Templates '$os_target' for os: "
             .  $devdetails->{'os_name'} );
    }

    my $subtreeName = "Storage";

    my $param = {
        'precedence'    => '-1000',
        'comment'       => 'Storage Information',
    };

    my $StorageNode = $cb->addSubtree( $devNode, $subtreeName, $param );

    # Empire Devices(Storage)
    if( $devdetails->hasCap('EmpireSystemedge::Devices') )
    {
        my $subtreeName = "VolumeInfo";

        my $param = {
            'precedence'    => '-1000',
            'comment'       => 'Physical/Logical Volume Information',
            'node-display-name' => 'Volume Information',
        };

        my $subtreeNode =
            $cb->addSubtree( $StorageNode, $subtreeName, $param,
                             [ 'EmpireSystemedge::empire-device-subtree' ] );

        foreach my $INDEX ( sort {$a<=>$b} @{$data->{'empireDev'}{'indices'}} )
        {
            my $ref = $data->{'empireDev'}{$INDEX};

            # Display in index order
            $ref->{'param'}->{'precedence'} = sprintf("%d", 2000 - $INDEX);

            $cb->addSubtree( $subtreeNode, $ref->{'param'}{'storage-nick'},
                             $ref->{'param'},
                             [ 'EmpireSystemedge::empire-device' ] );
        }
    }

    # Empire Device Stats
    if( $devdetails->hasCap('EmpireSystemedge::DiskStats') )
    {
        my $subtreeName = "DiskInfo";

        my $param = {
            'precedence'        => '-1000',
            'comment'           => 'Physical/Logical Disk Information',
            'node-display-name' => 'Disk Information',
        };

        # dynamically make overview-subleaves links visible
        if ( $os_target =~ /nt40/i or $os_target =~ /nt50/i or $os_target =~ /solaris/i ) {
            $param->{'has-overview-shortcuts'} = 'yes';
            $param->{'overview-shortcuts'} = 'rw,util,qlen';
        }
        elsif ( $os_target =~ /aix/i ) {
            $param->{'has-overview-shortcuts'} = 'yes';
            $param->{'overview-shortcuts'} = 'rw,util';
        }
        elsif ( $os_target =~ /linux/i or $os_target =~ /unix/i ) {
            $param->{'has-overview-shortcuts'} = 'yes';
            $param->{'overview-shortcuts'} = 'rw';
        }
        else {
            # basically we should never get down here...
            $param->{'has-overview-shortcuts'} = 'no';
        }

        my $subtreeNode =
            $cb->addSubtree( $StorageNode, $subtreeName, $param,
                             ['EmpireSystemedge::empire-disk-stats-subtree']);

        foreach my $INDEX
            ( sort {$a<=>$b} @{$data->{'empireDiskStats'}{'indices'}} )
        {
            my $ref = $data->{'empireDiskStats'}{$INDEX};
            # Display in index order
            $ref->{'param'}->{'precedence'} = sprintf("%d", 1000 - $INDEX);

            $cb->addSubtree( $subtreeNode, $ref->{'param'}{'disk-stats-nick'},
                             $ref->{'param'},
                             [ 'EmpireSystemedge::empire-disk-stats-' .
                               $os_target, ] );

        }
    }


    # Performance Subtree
    my $subtreeName= "System_Performance";

    my $param = {
        'precedence'     => '-900',
        'comment'        => 'System, CPU and memory statistics'
        };

    my @perfTemplates = ();

    # Empire Load Average
    if( $devdetails->hasCap('EmpireSystemedge::LoadAverage') )
    {
        push( @perfTemplates, 'EmpireSystemedge::empire-load' );
    }

    # Empire Performance
    if( $devdetails->hasCap('EmpireSystemedge::Performance') )
    {
        push( @perfTemplates, 'EmpireSystemedge::empire-memory' );
    }

    push( @perfTemplates,
          'EmpireSystemedge::empire-counters-' . $devdetails->{'os_name'},
          'EmpireSystemedge::empire-swap-counters-' . $devdetails->{'os_name'},
          'EmpireSystemedge::empire-total-cpu-' .  $devdetails->{'os_name'},
          'EmpireSystemedge::empire-total-cpu-raw-' .  $devdetails->{'os_name'},
          );

    if( $devdetails->hasCap('EmpireSystemedge::RunQ') )
    {
        push( @perfTemplates, 'EmpireSystemedge::empire-runq' );
    }

    if( $devdetails->hasCap('EmpireSystemedge::DiskWait') )
    {
        push( @perfTemplates, 'EmpireSystemedge::empire-diskwait' );
    }

    if( $devdetails->hasCap('EmpireSystemedge::PageWait') )
    {
        push( @perfTemplates, 'EmpireSystemedge::empire-pagewait' );
    }

    if( $devdetails->hasCap('EmpireSystemedge::SwapActive') )
    {
        push( @perfTemplates, 'EmpireSystemedge::empire-swapactive' );
    }

    if( $devdetails->hasCap('EmpireSystemedge::SleepActive') )
    {
        push( @perfTemplates, 'EmpireSystemedge::empire-sleepactive' );
    }

    my $PerformanceNode = $cb->addSubtree( $devNode, $subtreeName,
                                           $param, \@perfTemplates   );

    # Empire CPU Stats
    if( $devdetails->hasCap('EmpireSystemedge::CpuStats') )
    {
        my $ref = $data->{'empireCpuStats'};

        my $subtreeName = "CpuStats";

        my $param = {
            'precedence'    => '-1100',
            'comment'       => 'Per-CPU Statistics',
        };

        my $subtreeNode =
            $cb->addSubtree( $PerformanceNode, $subtreeName, $param,
                             [ 'EmpireSystemedge::empire-cpu-subtree' ] );

        foreach my $INDEX
            ( sort {$a<=>$b} @{$data->{'empireCpuStats'}{'indices'} } )
        {
            my $ref = $data->{'empireCpuStats'}{$INDEX};

            # Display in index order
            $ref->{'param'}->{'precedence'} = sprintf("%d", 1000 - $INDEX);

            $cb->addSubtree
                ( $subtreeNode, $ref->{'param'}{'cpu'},
                  $ref->{'param'},
                  ['EmpireSystemedge::empire-cpu-' . $os_target,
                   'EmpireSystemedge::empire-cpu-raw-' . $os_target],
                  );
        }
    }

    if( $devdetails->hasCap('EmpireSystemedge::empireNTREGPERF') )
    {
        Debug("EmpireSystemedge::NTREGPERF");
        my $ntregTree = "NT_REG_PERF";
        my $ntregParam = {
            'precedence'    => '-10000',
            'comment'       => 'NT Reg Perf',
        };
        my $ntregnode =
            $cb->addSubtree( $devNode, $ntregTree, $ntregParam );

        foreach my $INDEX
            ( sort {$a<=>$b} @{$data->{'empireNTREGPERF'}{'indices'} } )
        {
            my $ref = $data->{'empireNTREGPERF'}{$INDEX};
            $cb->addTemplateApplication
                ( $ntregnode, 'EmpireSystemedge::NTREGPERF_' . $INDEX );

        }

    }

    if( $devdetails->hasCap('EmpireSystemedge::ServiceResponse') )
    {
        Debug("Empire SysEdge ServiceResponse");

        my $ref = $data->{'empireSvcStats'};
        
        my $subtreeName = "Service_Response_Checks";
        my $param = {
            'precedence'        => '-1200',
            'comment'           => 'Service Response Statistics',
            'node-display-name' => 'Service Response Checks',
        };

        my $subtreeNode =
            $cb->addSubtree( $devNode, $subtreeName, $param,
                             [ 'EmpireSystemedge::empire-svc-subtree' ] );
        
        foreach my $INDEX
            ( sort {$a<=>$b} @{$data->{'empireSvcStats'}{'indices'} } )
        {
            my $ref = $data->{'empireSvcStats'}{$INDEX};

            # Display in index order
            $ref->{'param'}->{'precedence'} = sprintf("%d", 1000 - $INDEX);
            $ref->{'param'}->{'node-display-name'} = "Responder " . $ref->{'param'}{'descr'};
            $ref->{'param'}->{'graph-title'} = $ref->{'param'}{'name'} . " - " . $ref->{'param'}{'descr'} . " - Responsetime";

            $cb->addLeaf
                ( $subtreeNode, $ref->{'param'}{'id'},
                  $ref->{'param'},
                  ['EmpireSystemedge::empire-svc-response'],
                  );
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
