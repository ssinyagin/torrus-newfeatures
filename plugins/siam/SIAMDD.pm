#  Copyright (C) 2011  Stanislav Sinyagin
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


# Stanislav Sinyagin <ssinyagin@yahoo.com>

# Discovery module for SIAM API

package Torrus::DevDiscover::SIAMDD;

use strict;
use warnings;

use Torrus::SIAM;
use Torrus::Log;

$Torrus::DevDiscover::registry{'SIAMDD'} = {
    'sequence'     => 600,
    'checkdevtype' => \&checkdevtype,
    'discover'     => \&discover,
    'buildConfig'  => \&buildConfig
    };


sub checkdevtype
{
    my $dd = shift;
    my $devdetails = shift;

    my $data = $devdetails->data();
    
    if( $devdetails->param('siam-managed') eq 'yes' )
    {
        if( $devdetails->hasCap('nodeidReferenceManaged') )
        {
            Error('SIAMDD conflicts with ' .
                  $data->{'nodeidManagedBy'} . ' in nodeid management. ' .
                  'Modify the discovery instructions to enable only one ' .
                  'of the modules to manage nodeid.');
            return 0;
        }
            
        $devdetails->setCap('nodeidReferenceManaged');
        $data->{'nodeidManagedBy'} = 'SIAMDD';
        
        return 1;
    }

    return 0;
}


sub discover
{
    my $dd = shift;
    my $devdetails = shift;

    my $data = $devdetails->data();

    my $invid = $devdetails->param('siam-device-inventory-id');
    if( not defined($invid) )
    {
        Error('Undefined parameter: siam-device-inventory-id');
        return 0;
    }

    my $siam = Torrus::SIAM->open();
    if( not defined($siam) )
    {
        Error('Cannot connect to SIAM database');
        return 0;
    }

    my $devobj = $siam->get_device($invid);
    if( not defined($devobj) )
    {
        Error('Cannot find a device with siam.device.inventory_id="' .
              $invid . '" in SIAM database');
        return 0;
    }

    # index the interfaces by ifReferenceName
    # also populate our nodeid references
    my $orig_nameref_ifNodeidPrefix =
        $data->{'nameref'}{'ifNodeidPrefix'};

    my $orig_nameref_ifNodeid =
        $data->{'nameref'}{'ifNodeid'};

    $data->{'nameref'}{'ifNodeidPrefix'} = 'SIAM_ifNodeidPrefix';
    $data->{'nameref'}{'ifNodeid'} = 'SIAM_ifNodeid';
    
    my %ifRef;
    foreach my $ifIndex ( keys %{$data->{'interfaces'}} )
    {
        my $interface = $data->{'interfaces'}{$ifIndex};
        next if $interface->{'excluded'};

        $interface->{$data->{'nameref'}{'ifNodeidPrefix'}} =
            $interface->{$orig_nameref_ifNodeidPrefix};
        
        $interface->{$data->{'nameref'}{'ifNodeid'}} =
            $interface->{$orig_nameref_ifNodeid};
        
        my $refkey = $interface->{$data->{'nameref'}{'ifReferenceName'}};
        $ifRef{$refkey} = $interface;
    }

    # Find the matches of service units against device interfaces
    my $svcunits = $devobj->get_all_service_units();
    foreach my $unit ( @{$svcunits} )
    {
        my $unit_type = $unit->attr('siam.svcunit.type');

        if( $unit_type eq 'IFMIB' )
        {
            Debug('Processing ServiceUnit: ' . $unit->id);
            my $interface;
        
            foreach my $attr (@Torrus::SIAMDD::match_port_name_attributes)
            {
                last if defined($interface);
                
                my $val = $unit->attr($attr);                
                if( defined($val) )
                {
                    Debug('Trying to match interface name: ' . $val);
                    if( defined($ifRef{$val}) )
                    {
                        $interface = $ifRef{$val};
                        Debug('Match interface name: ' . $val);
                    }
                    else
                    {
                        Debug('Did not match interface name: ' . $val);
                    }
                }
            }
            
            if( defined($interface) )
            {
                my $dataelements = $unit->get_data_elements();
                my $ok = 1;
                
                foreach my $el (@{$dataelements})
                {                    
                    if( $el->attr('siam.svcdata.driver') ne
                        'Torrus.TimeSeries' )
                    {
                        next;
                    }
                    
                    my $data_type = $el->attr('siam.svcdata.type');
                    if( $data_type ne 'PortTraffic' )
                    {
                        Error('SIAM::ServiceDataElement, id="' . $el->id .
                              '" has unsupported siam.svcdata.type: ' .
                              $data_type);
                        $el->set_condition('torrus.import_successful',
                                           '0;Unsupported siam.svcdata.type');
                        $ok = 0;
                        next;
                    }

                    my $nodeid = $el->attr('torrus.nodeid');
                    if( not defined($nodeid) )
                    {
                        Error('SIAM::ServiceDataElement, id="' . $el->id .
                              '" does not define torrus.nodeid');
                        $el->set_condition('torrus.import_successful',
                                           '0;Undefined torrus.nodeid');
                        $ok = 0;
                        next;
                    }

                    $interface->{$data->{'nameref'}{'ifNodeidPrefix'}} = '';
                    $interface->{$data->{'nameref'}{'ifNodeid'}} = $nodeid;
                    $el->set_condition('torrus.import_successful', 1);
                }

                if( $ok )
                {
                    $unit->set_condition('torrus.import_successful', 1);
                }
                else
                {
                    $unit->set_condition('torrus.import_successful',
                                         '0;Failed matching a data element');
                }
            }
            else
            {
                $unit->set_condition('torrus.import_successful',
                                     '0;Could not match interface name');
            }
        }
    }
    
    $siam->disconnect();
    return 1;
}


sub buildConfig
{
    my $devdetails = shift;
    my $cb = shift;
    my $devNode = shift;
}


1;


# Local Variables:
# mode: perl
# indent-tabs-mode: nil
# perl-indent-level: 4
# End:
