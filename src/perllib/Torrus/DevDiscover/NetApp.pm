#  Copyright (C) 2011  Dean Hamstead
#  Copyright (C) 2004  Shawn Ferry
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

# $Id: NetApp.pm,v 1.10 2011/01/25 00:54:11 robertcourtney Exp $
# Shawn Ferry <sferry at sevenspace dot com> <lalartu at obscure dot org>

# NetApp.com storage products

package Torrus::DevDiscover::NetApp;

use strict;
use Torrus::Log;

$Torrus::DevDiscover::registry{'NetApp'} = {
    'sequence'     => 500,
    'checkdevtype' => \&checkdevtype,
    'discover'     => \&discover,
    'buildConfig'  => \&buildConfig
};

our %oiddef = (
    'netapp'         => '1.3.6.1.4.1.789',
    'netapp1'        => '1.3.6.1.4.1.789.1',
    'netappProducts' => '1.3.6.1.4.1.789.2',

    # netapp product
    'netapp_product'                => '1.3.6.1.4.1.789.1.1',
    'netapp_productVersion'         => '1.3.6.1.4.1.789.1.1.2.0',
    'netapp_productId'              => '1.3.6.1.4.1.789.1.1.3.0',
    'netapp_productModel'           => '1.3.6.1.4.1.789.1.1.5.0',
    'netapp_productFirmwareVersion' => '1.3.6.1.4.1.789.1.1.6.0',

    # netapp sysstat
    'netapp_sysStat'          => '1.3.6.1.4.1.789.1.2',
    'netapp_sysStat_cpuCount' => '1.3.6.1.4.1.789.1.2.1.6.0',

    # netapp nfs
    'netapp_nfs'           => '1.3.6.1.4.1.789.1.3',
    'netapp_nfsIsLicensed' => '1.3.6.1.4.1.789.1.3.3.1.0',

    # At a glance Lookup values seem to be the most common as opposed to
    # collecting NFS stats for v2 and v3 (and eventually v4 ) if No lookups
    # have been performed at discovery time we assume that vX is not in use.
    'netapp_tv2cLookups' => '1.3.6.1.4.1.789.1.3.2.2.3.1.5.0',
    'netapp_tv3cLookups' => '1.3.6.1.4.1.789.1.3.2.2.4.1.4.0',

    # netapp CIFS
    'netapp_cifs'           => '1.3.6.1.4.1.789.1.7',
    'netapp_cifsIsLicensed' => '1.3.6.1.4.1.789.1.7.21.0',

    # 4 - 19 should also be interesting
    # particularly cluster netcache stats

    # netapp filesystem count
    'netapp_dfNumber' => '1.3.6.1.4.1.789.1.5.6.0',

    # netapp filesystem details
    'netapp_dfTable'         => '1.3.6.1.4.1.789.1.5.4',
    'netapp_dfFileSys'       => '1.3.6.1.4.1.789.1.5.4.1.2',
    'netapp_dfPctUsedDisk'   => '1.3.6.1.4.1.789.1.5.4.1.6',
    'netapp_dfPctUsedInodes' => '1.3.6.1.4.1.789.1.5.4.1.9',
    'netapp_dfMountedOn'     => '1.3.6.1.4.1.789.1.5.4.1.9',
    'netapp_dfStatus'        => '1.3.6.1.4.1.789.1.5.4.1.20',
    'netapp_dfType'          => '1.3.6.1.4.1.789.1.5.4.1.23',

    # netapp volumes
    'netapp_volNumber' => '1.3.6.1.4.1.789.1.5.9.0',

    #       netappFiler     OBJECT IDENTIFIER ::= { netappProducts 1 }
    #       netappNetCache  OBJECT IDENTIFIER ::= { netappProducts 2 }
    #       netappClusteredFiler    OBJECT IDENTIFIER ::= { netappProducts 3 }

);

sub checkdevtype {
    my $dd         = shift;
    my $devdetails = shift;

    return $dd->checkSnmpTable('netapp');
}

sub discover {
    my $dd         = shift;
    my $devdetails = shift;

    my $session = $dd->session();
    my $data    = $devdetails->data();

    my $result = $dd->retrieveSnmpOIDs(
        'netapp_productModel',   'netapp_productId',
        'netapp_productVersion', 'netapp_productFirmwareVersion',
        'netapp_nfsIsLicensed',  'netapp_cifsIsLicensed',
        'netapp_tv2cLookups',    'netapp_tv3cLookups',
        'netapp_dfNumber',       'netapp_volNumber'
    );

    $data->{'param'}->{'comment'} = sprintf( '%s %s: %s %s',
        $result->{'netapp_productModel'},
        $result->{'netapp_productId'},
        $result->{'netapp_productVersion'},
        $result->{'netapp_productFirmwareVersion'} );

    # At a glance Lookup values seem to be the most common as opposed to
    # collecting NFS stats for v2 and v3 (and eventually v4 ) if No lookups
    # have been performed at discovery time we assume that nfsvX is not in use.

    if ( $result->{'netapp_nfsIsLicensed'} == 2 ) {
        if ( $result->{'netapp_tv2cLookups'} > 0 ) {
            $devdetails->setCap('NetApp::nfsv2');
        }

        if ( $result->{'netapp_tv3cLookups'} > 0 ) {
            $devdetails->setCap('NetApp::nfsv3');
        }
    }

    if ( $result->{'netapp_cifsIsLicensed'} == 2 ) {
        $devdetails->setCap('NetApp::cifs');
    }

    # read the dfNumber oid to find the number of filesystems
    if ( $result->{'netapp_dfNumber'} > 0 ) {

        # set capability -> leads to template inclusion (?)
        $devdetails->setCap('NetApp::filesys');

        # query table, returns hash with oids => values.
        my $dfTable =
          $session->get_table( -baseoid => $dd->oiddef('netapp_dfTable') );

        if ( not defined $dfTable ) {
            Error('Cannot retrieve dfTable');
            return 0;
        }

        # store hash (oids) for later reference - make available to other class.
        $devdetails->storeSnmpVars($dfTable);

# get indices - used for interfaces/indexed oids e.g. inOctets.0, .1, .2... returns a list of numbers/indices
        for my $dfIndex (
            $devdetails->getSnmpIndices( $dd->oiddef('netapp_dfFileSys') ) )
        {

#my $dfFileSys = $devdetails->snmpVar($dd->oiddef('netapp_dfFileSys') .'.'. $dfIndex);
#next if $dfFileSys =~ m|/.snapshot|; # example ignore snapshot fs's

            my $filesystem = {};
            $data->{'filesystems'}{$dfIndex}  = $filesystem;
            $filesystem->{'params'}           = {};
            $filesystem->{'vendor_templates'} = [];
            $filesystem->{$_} =
              $devdetails->snmpVar( $dd->oiddef("netapp_$_") . '.' . $dfIndex )
              for qw/dfType dfFileSys dfMountedOn/;
        }
    }

    return 1;
}

sub buildConfig {
    my $devdetails = shift;
    my $cb         = shift;
    my $devNode    = shift;
    my $data       = $devdetails->data();

    $cb->addParams( $devNode, $data->{'params'} );

    # Add CPU Template
    my $cpuNode =
      $cb->addSubtree( $devNode, 'Netapp_CPU', undef, ['NetApp::CPU'] );

    # Add Misc Stats
    $cb->addTemplateApplication( $devNode, 'NetApp::misc' );

    if ( $devdetails->hasCap('NetApp::nfsv2') ) {
        $cb->addTemplateApplication( $devNode, 'NetApp::nfsv2' );
    }

    if ( $devdetails->hasCap('NetApp::nfsv3') ) {
        $cb->addTemplateApplication( $devNode, 'NetApp::nfsv3' );
    }

    if ( $devdetails->hasCap('NetApp::cifs') ) {
        Debug("Would add cifs here\n");

        #$cb->addTemplateApplication( $devNode, 'NetApp::cifs');
    }

    if ( $devdetails->hasCap('NetApp::filesys') ) {

        #$cb->addTemplateApplication( $devNode, 'NetApp::filesys');
        my $fstree =
          $cb->addSubtree( $devNode, 'Filesystems',
            { 'comment' => 'Filesystems usage' }, [] );

        my $precedence = 100000;
        for (
            sort {
                $data->{'filesystems'}->{$a}->{'dfFileSys'}
                  cmp $data->{'filesystems'}->{$b}->{'dfFileSys'}
            }
            keys %{ $data->{'filesystems'} }
          )
        {
            my $fs = $data->{'filesystems'}->{$_};

            ( my $subtreeName = $fs->{'dfFileSys'} ) =~ s|/|_|g;
            my $params = $fs->{'params'};
            $params->{'interface-index'} = $_;

            #$params->{'description'} = $fs->{'dfFileSys'};
            $params->{'node-display-name'} = $fs->{'dfFileSys'};
            $params->{'precedence'}        = $precedence--;

            my $childNode =
              $cb->addSubtree( $fstree, $subtreeName, $params,
                ['NetApp::filesys'] );

            foreach my $leaf ( 'Pct_Inodes_Used', 'Pct_Disk_Used' ) {
                my $host    = $devdetails->param('snmp-host');
                my $path    = $cb->getElementPath($childNode) . $leaf;
                my $fsDescr = $fs->{'dfFileSys'};

                my $serviceid = Torrus::Optus::ServiceID::getServiceID(
                    {
                        host        => $host,
                        path        => $path,
                        leaf        => $leaf,
                        module      => 'NetApp::Filesys',
                        module_data => $fsDescr
                    }
                );

                $cb->addLeaf( $childNode, $leaf,
                    { 'ext-service-id' => $serviceid, }, undef );
            }
        }
    }
}

1;

# Local Variables:
# mode: perl
# indent-tabs-mode: nil
# perl-indent-level: 4
# End:
