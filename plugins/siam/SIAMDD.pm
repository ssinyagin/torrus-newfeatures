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


my $siam;

$Torrus::DevDiscover::thread_start_callbacks{'SIAMDD'} =
    sub {
        $siam = Torrus::SIAM->open();
    };


$Torrus::DevDiscover::thread_end_callbacks{'SIAMDD'} =
    sub {
        $siam->disconnect();
        undef $siam;
    };


$Torrus::DevDiscover::discovery_failed_callbacks{'SIAMDD'} =
    sub {
        my $hostParams = shift;
        if( $hostParams->{'siam-managed'} eq 'yes'
            and
            defined($hostParams->{'siam-device-inventory-id'}) )
        {
            my $devobj =
                $siam->get_device($hostParams->{'siam-device-inventory-id'});
            if( defined($devobj) )
            {
                $devobj->set_condition('torrus.imported',
                                       '0;SNMP discovery failed');
            }
        }
    };





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
       
    if( not defined($siam) )
    {
        Error('SIAM is not connected');
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
    my %ifRefDuplicates;

    foreach my $ifIndex ( keys %{$data->{'interfaces'}} )
    {
        my $interface = $data->{'interfaces'}{$ifIndex};
        next if $interface->{'excluded'};

        next unless ($interface->{'hasOctets'} or $interface->{'hasHCOctets'});
        
        $interface->{$data->{'nameref'}{'ifNodeidPrefix'}} =
            $interface->{$orig_nameref_ifNodeidPrefix};
        
        $interface->{$data->{'nameref'}{'ifNodeid'}} =
            $interface->{$orig_nameref_ifNodeid};

        # first, respect the chosen reference as discovered by other modules
        my $refkey = $interface->{$data->{'nameref'}{'ifReferenceName'}};
        $ifRef{'default'}{$refkey} = $interface;

        # then, try everything else
        foreach my $prop (@Torrus::SIAMDD::match_port_properties)
        {
            if( $prop ne $data->{'nameref'}{'ifReferenceName'}
                and
                not $ifRefDuplicates{$prop} )
            {
                my $val = $interface->{$prop};
                if( defined($val) and length($val) > 0 )
                {
                    if( defined($ifRef{$prop}{$val}) )
                    {
                        # value already seen before,
                        # this property has duplicates
                        $ifRefDuplicates{$prop} = 1;
                    }
                    else
                    {
                        $ifRef{$prop}{$val} = $interface;
                    }
                }
            }
        }                        
    }

    # Find the matches of service units against device interfaces
    my $svcunits = $devobj->get_all_service_units();
    foreach my $unit ( @{$svcunits} )
    {
        my $unit_type = $unit->attr('siam.svcunit.type');

        if( $unit_type eq 'IFMIB.Port' )
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
                    if( defined($ifRef{'default'}{$val}) )
                    {
                        $interface = $ifRef{'default'}{$val};
                    }
                    else
                    {
                        foreach my $prop
                            (@Torrus::SIAMDD::match_port_properties)
                        {
                            if( not $ifRefDuplicates{$prop} and
                                defined($ifRef{$prop}{$val}) )
                            {
                                $interface = $ifRef{$prop}{$val};
                            }
                        }
                    }
                        
                    if( defined($interface) )
                    {
                        Debug('Matched interface name: ' . $val);
                    }
                    else
                    {
                        Debug('Did not match interface name: ' . $val);
                    }
                }
            }
            
            if( defined($interface) )
            {
                my $nodeid = $unit->attr('torrus.port.nodeid');
                if( not defined($nodeid) )
                {
                    Error('SIAM::ServiceUnit, id="' . $unit->id .
                          '" does not define torrus.port.nodeid');
                    $unit->set_condition('torrus.imported',
                                         '0;Undefined torrus.port.nodeid');
                }
                else
                {
                    $interface->{$data->{'nameref'}{'ifNodeidPrefix'}} = '';
                    $interface->{$data->{'nameref'}{'ifNodeid'}} = $nodeid;

                    # Apply the service access bandwidth
                    my $bw = $unit->attr('torrus.port.bandwidth');
                    if( not defined($bw) or $bw == 0 )
                    {
                        if( defined( $interface->{'ifSpeed'} ) )
                        {
                            $bw = $interface->{'ifSpeed'};
                        }
                    }

                    if( $bw > 0 )
                    {
                        $interface->{'param'}{'bandwidth-limit-in'} =
                            $bw / 1e6;
                        $interface->{'param'}{'bandwidth-limit-out'} =
                            $bw / 1e6;
                        $interface->{'childCustomizations'}->{'InOut_bps'}->{
                            'upper-limit'} = $bw;
                        $interface->{'childCustomizations'}->{'Bytes_In'} ->{
                            'upper-limit'} = $bw / 8;
                        $interface->{'childCustomizations'}->{'Bytes_Out'} ->{
                            'upper-limit'} = $bw / 8;
                        $interface->{'param'}{'monitor-vars'} =
                            sprintf('bw=%g', $bw);
                    }        
                    
                    $unit->set_condition('torrus.imported', 1);
                }
            }
            else
            {
                $unit->set_condition('torrus.imported',
                                     '0;Could not match interface name');
            }
        }
    }
    
    $devobj->set_condition('torrus.imported', 1);
    
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
