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

# Stanislav Sinyagin <ssinyagin@k-open.com>

# Discovery module for ENTITY-MIB (RFC 2737)
# This module does not generate any XML, but provides information
# for other discovery modules

package Torrus::DevDiscover::RFC2737_ENTITY_MIB;

use strict;
use warnings;

use Torrus::Log;


$Torrus::DevDiscover::registry{'RFC2737_ENTITY_MIB'} = {
    'sequence'     => 100,
    'checkdevtype' => \&checkdevtype,
    'discover'     => \&discover,
    'buildConfig'  => \&buildConfig
    };


our %oiddef =
    (
     # ENTITY-MIB
     'entPhysicalDescr'        => '1.3.6.1.2.1.47.1.1.1.1.2',
     'entPhysicalContainedIn'  => '1.3.6.1.2.1.47.1.1.1.1.4',
     'entPhysicalName'         => '1.3.6.1.2.1.47.1.1.1.1.7'
     );



sub checkdevtype
{
    my $dd = shift;
    my $devdetails = shift;

    my $session = $dd->session();
    my $data = $devdetails->data();

    return( $dd->checkSnmpTable('entPhysicalDescr') or
            $dd->checkSnmpTable('entPhysicalName') );
}


sub discover
{
    my $dd = shift;
    my $devdetails = shift;

    my $data = $devdetails->data();
    my $session = $dd->session();

    $data->{'entityPhysical'} = {};

    my $chassisIndex = 0;

    my $entPhysicalDescr = $dd->walkSnmpTable('entPhysicalDescr');
    my $entPhysicalContainedIn = $dd->walkSnmpTable('entPhysicalContainedIn');
    my $entPhysicalName = $dd->walkSnmpTable('entPhysicalName');
    
    foreach my $phyIndex
        ( sort {$a <=> $b} keys %{$entPhysicalDescr} )
    {
        my $ref = {};
        $data->{'entityPhysical'}{$phyIndex} = $ref;

        # Find the chassis. It is not contained in anything.
        if( not $chassisIndex )
        {
            if( defined($entPhysicalContainedIn->{$phyIndex}) and
                $entPhysicalContainedIn->{$phyIndex} == 0 )
            {
                $chassisIndex = $phyIndex;
            }
        }

        my $descr = $entPhysicalDescr->{$phyIndex};
        if( defined($descr) and $descr ne '' )
        {
            $ref->{'descr'} = $descr;
        }

        my $name = $entPhysicalName->{$phyIndex};
        if( defined($name) and $name ne '' )
        {
            $ref->{'name'} = $name;
        }
    }
    
    if( $chassisIndex > 0 )
    {
        $data->{'entityChassisPhyIndex'} = $chassisIndex;
        my $chassisDescr = $data->{'entityPhysical'}{$chassisIndex}{'descr'};
        if( defined($chassisDescr) and $chassisDescr ne '' and
            not defined( $data->{'param'}{'comment'} ) )
        {
            Debug('ENTITY-MIB: found chassis description: ' . $chassisDescr);
            $data->{'param'}{'comment'} = $chassisDescr;
        }
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
