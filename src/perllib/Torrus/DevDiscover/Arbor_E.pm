#
#  Discovery module for Arbor|E Series devices
#  Formerly Ellacoya Networks
#
#  Copyright (C) 2008 Jon Nistor
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
# Jon Nistor <nistor at snickers.org>
#
# NOTE: Options for this module
#	Arbor_E::disable-e30-bundle
#	Arbor_E::enable-e30-bundle-name-rrd
#       Arbor_E::disable-e30-buffers
#       Arbor_E::disable-e30-cpu
#       Arbor_E::disable-e30-flowdev
#	Arbor_E::disable-e30-fwdTable
#	Arbor_E::disable-e30-hdd
#	Arbor_E::enable-e30-hdd-errors
#	Arbor_E::disable-e30-mem
#

# Arbor_E devices discovery
package Torrus::DevDiscover::Arbor_E;

use strict;
use Torrus::Log;


$Torrus::DevDiscover::registry{'Arbor_E'} = {
    'sequence'     => 500,
    'checkdevtype' => \&checkdevtype,
    'discover'     => \&discover,
    'buildConfig'  => \&buildConfig
    };

our %oiddef =
    (
     # ELLACOYA-MIB
     'eProducts'	  => '1.3.6.1.4.1.3813.2',
     'codeVer'            => '1.3.6.1.4.1.3813.1.4.1.1.0',
     'sysIdSerialNum'	  => '1.3.6.1.4.1.3813.1.4.1.5.2.0',
     'hDriveErrModel'     => '1.3.6.1.4.1.3813.1.4.2.10.16.0',
     'hDriveErrSerialNum' => '1.3.6.1.4.1.3813.1.4.2.10.17.0',
     'cpuUtilization'	  => '1.3.6.1.4.1.3813.1.4.4.1.0',
     'cpuIndex'		  => '1.3.6.1.4.1.3813.1.4.4.2.1.1', # e100

     # ELLACOYA-MIB::cpuCounters (available in 7.5.x -- slowpath counters)
     'cpuCounters'        => '1.3.6.1.4.1.3813.1.4.4.10',
     'slowpathCounters'   => '1.3.6.1.4.1.3813.1.4.4.10.1',
     'sigCounters'        => '1.3.6.1.4.1.3813.1.4.4.10.2',

     # ELLACOYA-MIB::flow
     'flowPoolNameD1'     => '1.3.6.1.4.1.3813.1.4.5.1.1.1.2',
     'flowPoolNameD2'     => '1.3.6.1.4.1.3813.1.4.5.2.1.1.2',

     # ELLACOYA-MIB::bundleStatsTable
     'bundleName'         => '1.3.6.1.4.1.3813.1.4.12.1.1.2',

     # ELLACOYA-MIB::l2tp (available in 7.5.x)
     'l2tpConfigEnabled'             => '1.3.6.1.4.1.3813.1.4.18.1.1.0',
     'l2tpSecureEndpointIpAddress'   => '1.3.6.1.4.1.3813.1.4.18.3.2.1.1.1',
     'l2tpSecureEndpointOverlapping' => '1.3.6.1.4.1.3813.1.4.18.3.2.1.1.3',

     );

our %eChassisName =
    (
        '1'  => 'e16k',
        '2'  => 'e4k',
        '3'  => 'e30 Revision: R',
        '4'  => 'e30 Revision: S',
        '5'  => 'e30 Revision: T',
        '6'  => 'e30 Revision: U',
        '7'  => 'e30 Revision: V',
	'8'  => 'e100',
    );

sub checkdevtype
{
    my $dd = shift;
    my $devdetails = shift;

    if( not $dd->oidBaseMatch
        ( 'eProducts', $devdetails->snmpVar( $dd->oiddef('sysObjectID') ) ) )
    {
        return 0;
    }
   
    $devdetails->setCap('interfaceIndexingPersistent');

    return 1;
}


sub discover
{
    my $dd = shift;
    my $devdetails = shift;

    my $session = $dd->session();
    my $data = $devdetails->data();

    # PROG: Grab versions, serials and type of chassis.
    my $eInfo = $dd->retrieveSnmpOIDs
                   ( 'codeVer', 'sysIdSerialNum', 'sysObjectID' );
    $eInfo->{'modelNum'} = $eInfo->{'sysObjectID'};
    $eInfo->{'modelNum'} =~ s/.*(\d)$/$1/; # Last digit

    # SNMP: System comment
    $data->{'param'}{'comment'} =
            "Arbor " . $eChassisName{$eInfo->{'modelNum'}} .
            ", Hw Serial#: " . $eInfo->{'sysIdSerialNum'} .
            ", Version: " .  $eInfo->{'codeVer'};


    # ------------------------------------------------------------------------
    # Arbor_E e30 related material here
    if( $eInfo->{'modelNum'} < 8 )
    {
        # PROG: Set Capability to be the e30 device
        $devdetails->setCap("e30");
        Debug("Arbor_E: Found " . $eChassisName{$eInfo->{'modelNum'}} );

        # PROG: See if some of the options are disabled
        if( $devdetails->param('Arbor_E::disable-e30-buffers') ne 'yes' )
	{
            $devdetails->setCap("e30-buffers");
        }

        if( $devdetails->param('Arbor_E::disable-e30-cpu') ne 'yes' )
        {
            $devdetails->setCap("e30-cpu");
        }

        if( $devdetails->param('Arbor_E::disable-e30-flowdev') ne 'yes' )
        {
            $devdetails->setCap("e30-flowLookup");

            # Flow Lookup Device information
            # Figure out what pools exist for the 2 flow switching modules
	    # ------------------------------------------------------------
            my $switchingModules = 2; # Hard coded, 2 on the e30 device

            foreach my $flowModule (1 .. $switchingModules) {
                Debug("e30:  Flow Lookup Device " . $flowModule);

                my $flowPoolOid  = 'flowPoolNameD' . $flowModule;
                my $flowModTable = $session->get_table (
                                  -baseoid => $dd->oiddef($flowPoolOid) );
                $devdetails->storeSnmpVars ( $flowModTable );

                # PROG: Look for pool names and indexes and store them.
                if( $flowModTable ) {
                    foreach my $flowPoolIDX ( $devdetails->getSnmpIndices(
                                                $dd->oiddef($flowPoolOid) ) )
                    {
                        my $flowPoolName = $flowModTable->{
                               $dd->oiddef($flowPoolOid) . '.' . $flowPoolIDX};

                        $data->{'e30'}{'flowModule'}{$flowModule}{$flowPoolIDX}
                              = $flowPoolName;

                        Debug("e30:    IDX: $flowPoolIDX  Pool: $flowPoolName");

                    } # END: foreach my $flowPoolIDX
                } # END: if $flowModTable
            } # END: foreach my $flowModule
        }

        if( $devdetails->param('Arbor_E::disable-e30-fwdTable') ne 'yes' )
        {
            $devdetails->setCap("e30-fwdTable");
        }

        if( $devdetails->param('Arbor_E::disable-e30-hdd') ne 'yes' )
        {
            $devdetails->setCap("e30-hdd");

            # SNMP: Add harddrive comment information
            $eInfo = $dd->retrieveSnmpOIDs( 'hDriveErrModel',
                                            'hDriveErrSerialNum' );

            $data->{'e30'}{'hddModel'}  = $eInfo->{'hDriveErrModel'};
            $data->{'e30'}{'hddSerial'} = $eInfo->{'hDriveErrSerialNum'};

            # PROG: Do we want errors as well?
            if( $devdetails->param('Arbor_E::enable-e30-hdd-errors') ne 'yes' )
            {
                $devdetails->setCap("e30-hdd-errors");
            }
        }

        if( $devdetails->param('Arbor_E::disable-e30-l2tp') ne 'yes' )
        {
            # 1 - disabled, 2 - enabled, 3 - session aware
            $eInfo = $dd->retrieveSnmpOIDs('l2tpConfigEnabled');

            if( $eInfo->{'l2tpConfigEnabled'} > 1 )
            {
                $devdetails->setCap("e30-l2tp");

                my $l2tpSecEndTable = $session->get_table(
                       -baseoid => $dd->oiddef('l2tpSecureEndpointIpAddress') );
		$devdetails->storeSnmpVars( $l2tpSecEndTable );

                Debug("e30: L2TP secure endpoints found:");
                foreach my $SEP ( $devdetails->getSnmpIndices(
                                  $dd->oiddef('l2tpSecureEndpointIpAddress') ) )
		{
			next if( ! $SEP );
			$data->{'e30'}{'l2tpSEP'}{$SEP} = 0;
                        Debug("e30:    $SEP");
		}
            } # END: if l2tpConfigEnabled
        }

        # Memory usage on system
        if( $devdetails->param('Arbor_E::disable-e30-mem') ne 'yes' )
        {
            $devdetails->setCap("e30-mem");
        }

        # Traffic statistics per Bundle
        if( $devdetails->param('Arbor_E::disable-bundle') ne 'yes' )
        {
            # Set capability 
            $devdetails->setCap("e30-bundle");

            # Pull table information
            my $bundleTable = $session->get_table(
                                -baseoid => $dd->oiddef('bundleName') );
            $devdetails->storeSnmpVars( $bundleTable );

            Debug("e30: Bundle Information id:name");
            foreach my $bundleID (
                       $devdetails->getSnmpIndices( $dd->oiddef('bundleName') ))
            {
                    my $bundleName = $bundleTable->{$dd->oiddef('bundleName') .
                                        '.' . $bundleID};
                    $data->{'e30'}{'bundleID'}{$bundleID} = $bundleName;
	
                    Debug("e30:    $bundleID $bundleName");
            } # END foreache my $bundleID
        } # END if Arbor_E::disable-bundle

        # PROG: Counters
        if( $devdetails->param('Arbor_E::disable-e30-slowpath') ne 'yes' )
        {
            # Slowpath counters are available as of 7.5.x
            my $counters = $session->get_table(
                            -baseoid => $dd->oiddef('slowpathCounters') );
            $devdetails->storeSnmpVars( $counters );

            if( $counters )
            {
                $devdetails->setCap("e30-slowpath");
            }
        }
    }

    # ------------------------------------------------------------------------
    # Arbor E100 related material here
    if( $eInfo->{'modelNum'} == 8 )
    {
        Debug("Arbor_E: Found " . $eChassisName{$eInfo->{'modelNum'}} );
        Debug("Arbor_E: Currently e100 has no supported extras...");
    }

    # ------------------------------------------------------------------------
    # Arbor Unsupported devices
    if( $eInfo->{'modelNum'} > 8 )
    {
        Debug("Arbor_E: unsupported device found!");
        return 0;
    }

    return 1;
}


sub buildConfig
{
    my $devdetails = shift;
    my $cb = shift;
    my $devNode = shift;
    my $data = $devdetails->data();

    # PROG: Lets do e30 first ...
    if( $devdetails->hasCap("e30") )
    {
        if( $devdetails->hasCap("e30-buffers") )
        {
            $cb->addTemplateApplication($devNode, 'Arbor_E::e30-buffers');
        }

        if( $devdetails->hasCap("e30-bundle") )
        {
            # Create topLevel subtree
            my $bundleNode = $cb->addSubtree( $devNode, 'Bundle_Stats',
                                    { 'comment' => 'Bundle statistics' },
                                    [ 'Arbor_E::e30-bundle-subtree' ]);

            foreach my $bundleID
                ( sort {$a <=> $b} keys %{$data->{'e30'}{'bundleID'}} )
            {
                my $srvName     =  $data->{'e30'}{'bundleID'}{$bundleID};
                my $subtreeName =  $srvName;
                   $subtreeName =~ s/\W/_/g; 
                my $bundleRRD	= $bundleID;
                if( $devdetails->param('Arbor_E::enable-e30-bundle-name-rrd')
                    eq 'yes' )
                {
                    # Filenames written out as the bundle name
                    $bundleRRD =  lc($srvName);
                    $bundleRRD =~ s/\W/_/g;
                }

                $cb->addSubtree( $bundleNode, $subtreeName,
                                 { 'comment'          => $srvName,
                                   'e30-bundle-index' => $bundleID,
                                   'e30-bundle-name'  => $srvName,
                                   'e30-bundle-rrd'   => $bundleRRD,
                                   'precedence'       => 1000 - $bundleID },
                                 [ 'Arbor_E::e30-bundle' ]);
            } # END foreach my $bundleID
        }

        if( $devdetails->hasCap("e30-cpu") )
        {
            $cb->addTemplateApplication($devNode, 'Arbor_E::e30-cpu');
        }

        if( $devdetails->hasCap("e30-fwdTable") )
        {
            $cb->addTemplateApplication($devNode, 'Arbor_E::e30-fwdTable');
        }

        if( $devdetails->hasCap("e30-hdd") )
        {
            my $comment = "Model: "  . $data->{'e30'}{'hddModel'} . ", " .
                          "Serial: " . $data->{'e30'}{'hddSerial'};
            my $subtree = "Hard_Drive";
            my @templates;
            push( @templates, 'Arbor_E::e30-hdd-subtree');
            push( @templates, 'Arbor_E::e30-hdd');

            if( $devdetails->hasCap("e30-hdd-errors") )
            {
                push( @templates, 'Arbor_E::e30-hdd-errors');
            }

            my $hdNode = $cb->addSubtree($devNode, $subtree,
                                        { 'comment' => $comment },
                                        \@templates);
        }

        if( $devdetails->hasCap("e30-l2tp") )
        {
            # PROG: First add the appropriate template
            my $l2tpNode = $cb->addSubtree( $devNode, 'L2TP', undef,
                                          [ 'Arbor_E::e30-l2tp-subtree' ]);

            # PROG: Cycle through the SECURE EndPoint devices
            if( $data->{'e30'}{'l2tpSEP'} )
            {
                # PROG: Add the assisting template first
                my $l2tpEndNode = $cb->addSubtree( $l2tpNode, 'Secure_Endpoint',
                             { 'comment' => 'Secure endpoint parties' },
                             [ 'Arbor_E::e30-l2tp-secure-endpoints-subtree' ]);

                foreach my $SEP ( keys %{$data->{'e30'}{'l2tpSEP'}} )
                {
                  my $endPoint =  $SEP;
                     $endPoint =~ s/\W/_/g;

                  $cb->addSubtree($l2tpEndNode, $endPoint,
                              { 'e30-l2tp-ep'   => $SEP,
                                'e30-l2tp-file' => $endPoint },
                              [ 'Arbor_E::e30-l2tp-secure-endpoints-leaf' ]);
                } # END: foreach
            }
        }

        if( $devdetails->hasCap("e30-mem") )
        {
            $cb->addTemplateApplication($devNode, 'Arbor_E::e30-mem');
        }

        if( $devdetails->hasCap("e30-flowLookup") )
        {
            # PROG: Flow Lookup Device (pool names)
            my $flowNode = $cb->addSubtree( $devNode, 'Flow_Lookup',
                                          { 'comment' => 'Switching modules' },
                                            undef );

            my $flowLookup = $data->{'e30'}{'flowModule'};

            foreach my $flowDevIdx ( keys %{$flowLookup} )
            {
                my $flowNodeDev = $cb->addSubtree( $flowNode,
                                  'Flow_Lookup_' .  $flowDevIdx,
                                  { 'comment' => 'Switching module '
                                                  . $flowDevIdx },
                                  [ 'Arbor_E::e30-flowlkup-subtree' ] );

                # PROG: Find all the pool names and add Subtree
                foreach my $flowPoolIdx ( keys %{$flowLookup->{$flowDevIdx}} )
                {
                    my $poolName = $flowLookup->{$flowDevIdx}{$flowPoolIdx};

                    my $poolNode = $cb->addSubtree( $flowNodeDev, $poolName,
                                   { 'comment' => 'Flow Pool: ' . $poolName,
                                     'e30-flowdevidx'   => $flowDevIdx,
                                     'e30-flowpoolidx'  => $flowPoolIdx,
                                     'e30-flowpoolname' => $poolName,
                                     'precedence'       => 1000 - $flowPoolIdx},
                                   [ 'Arbor_E::e30-flowlkup-leaf' ]);
                } # END: foreach my $flowPoolIdx
            } # END: foreach my $flowDevIdx
        } # END: hasCap e30-flowLookup

        if( $devdetails->hasCap("e30-slowpath") )
        {
            my $slowNode = $cb->addSubtree( $devNode, 'SlowPath', undef,
                                          [ 'Arbor_E::e30-slowpath' ]);
        }
    } # END: if e30 device

    # -----------------------------------------------------
    # E100 series...

}

1;

# Local Variables:
# mode: perl
# indent-tabs-mode: nil
# perl-indent-level: 4
# End:
