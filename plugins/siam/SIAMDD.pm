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

BEGIN
{
    foreach my $mod ( @Torrus::SIAMDD::loadModules )
    {
        if( not eval('require ' . $mod) or $@ )
        {
            die($@);
        }
    }
}


use Torrus::SIAM;
use Torrus::Log;
use JSON;

my $siam;
my $siamSemaphore;

if( not $Torrus::Global::threadsEnabled )
{
    Error('Torrus::DevDiscover::SIAMDD requires threads to be enabled');
    exit(1);
}


$Torrus::DevDiscover::threading_init_callbacks{'SIAMDD'} =
    sub {
        require Thread::Semaphore;
        $siamSemaphore = new Thread::Semaphore;
};

$Torrus::DevDiscover::thread_start_callbacks{'SIAMDD'} =
    sub {
        if( defined($Torrus::SIAM::siam_config) and
            -f $Torrus::SIAM::siam_config )
        {            
            $siamSemaphore->down();
            eval { $siam = Torrus::SIAM->open(); };
            
            if( $@ or not defined($siam) )
            {
                Error('Cannot initialize SIAM connection: ' . $@);
            }
            
            $siamSemaphore->up();
        }
        else
        {
            Error('Missing or invalid SIAM configuration file');
        }
};


$Torrus::DevDiscover::thread_end_callbacks{'SIAMDD'} =
    sub {
        if( defined($siam) )
        {
            $siamSemaphore->down();
            eval { $siam->disconnect(); };
            $siamSemaphore->up();

            undef $siam;
        }
};


$Torrus::DevDiscover::discovery_failed_callbacks{'SIAMDD'} =
    sub {
        if( defined($siam) )
        {
            my $hostParams = shift;
            if( defined($hostParams->{'SIAM::managed'})
                and
                $hostParams->{'SIAM::managed'} eq 'yes'
                and
                defined($hostParams->{'SIAM::device-inventory-id'}) )
            {
                $siamSemaphore->down();

                eval { 
                    my $devobj = $siam->get_device
                        ($hostParams->{'SIAM::device-inventory-id'});
                    if( defined($devobj) )
                    {
                        $devobj->set_condition('torrus.imported',
                                               '0;SNMP discovery failed');
                    }
                };                

                if( $@ )
                {
                    Error('Error updating SIAM: ' . $@);
                }
                
                $siamSemaphore->up();

                
            }
        }
};



our %registry;


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
    
    if( $devdetails->paramEnabled('SIAM::managed') )
    {
        if( not defined($siam) )
        {
            Error('Device has SIAM::managed enabled, ' .
                  'but SIAM is not connected');
            exit(1);
        }
        
        if( $devdetails->hasCap('nodeidReferenceManaged') )
        {
            Error('SIAMDD conflicts with ' .
                  $data->{'nodeidManagedBy'} . ' in nodeid management. ' .
                  'Modify the discovery instructions to enable only one ' .
                  'of the modules to manage nodeid.');
            exit(1);
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

    my $invid = $devdetails->param('SIAM::device-inventory-id');
    if( not defined($invid) )
    {
        Error('Undefined parameter: SIAM::device-inventory-id');
        return 0;
    }
    
    if( not defined($siam) )
    {
        Error('SIAM is not connected');
        return 0;
    }

    $siamSemaphore->down();

    my $devobj = eval { $siam->get_device($invid) };
    if( $@ )
    {
        Error('SIAM failure: ' . $@);
        exit(1);
    }
    
    if( not defined($devobj) )
    {
        Error('Cannot find a device with siam.device.inventory_id="' .
              $invid . '" in SIAM database');
        $siamSemaphore->up();
        return 0;
    }

    Debug('SIAMDD: ' . scalar(keys %registry) . ' registry entries');

    foreach my $entry
        ( sort {$registry{$a}{'sequence'} <=> $registry{$b}{'sequence'}}
          keys %registry )
    {
        if( defined($registry{$entry}{'prepare'}) )
        {
            &{$registry{$entry}{'prepare'}}($dd, $devdetails);
        }
    }

    
    if( $devobj->attr('torrus.create_device_components') )
    {
        # create SIAM::DeviceComponent objects from discovery results

        my $devc_objects = [];

        foreach my $entry
            ( sort {$registry{$a}{'sequence'} <=> $registry{$b}{'sequence'}}
              keys %registry )
        {
            if( defined($registry{$entry}{'list_dev_components'}) )
            {
                my $r =
                    &{$registry{$entry}{'list_dev_components'}}($dd,
                                                                $devdetails);
                push(@{$devc_objects}, @{$r});
            }
        }
        
        Debug('SIAMDD: Syncing ' . scalar(@{$devc_objects}) .
              ' device components');
        eval {
            $devobj->set_condition('siam.device.set_components',
                                   encode_json($devc_objects)) };
        if( $@ )
        {
            Error('SIAM failure: ' . $@);
            exit(1);
        }
    }

    # Find the matches of device components against device interfaces
    my $components = eval { $devobj->get_components() };
    if( $@ )
    {
        Error('SIAM failure: ' . $@);
        exit(1);
    }

    foreach my $devc ( @{$components} )
    {
        next unless $devc->is_complete();

        if( not defined($devc->attr('torrus.nodeid')) )
        {
            Error('SIAM::DeviceComponent, id="' . $devc->id .
                  '" does not define torrus.nodeid');
            eval { $devc->set_condition('torrus.warning',
                                        'Undefined torrus.nodeid') };
            if( $@ )
            {
                Error('SIAM failure: ' . $@);
                exit(1);
            }

            next;
        }
        
        my $matched = 0;
        
        foreach my $entry
            ( sort {$registry{$a}{'sequence'} <=> $registry{$b}{'sequence'}}
              keys %registry )
        {
            last if $matched;
            
            if( defined($registry{$entry}{'match_devc'}) )
            {
                eval {
                    $matched =
                        &{$registry{$entry}{'match_devc'}}($dd, $devdetails,
                                                           $devc)
                };

                if( $@ )
                {
                    Error('SIAM failure: ' . $@);
                    exit(1);
                }                
            }
        }

        eval {
            if( $matched )
            {
                $devc->set_condition('torrus.imported', 1);
            }
            else
            {
                $devc->set_condition('torrus.imported',
                                     '0;Could not match the component name');
            }
        };
        
        if( $@ )
        {
            Error('SIAM failure: ' . $@);
            exit(1);
        }
    }
    
    foreach my $entry
        ( sort {$registry{$a}{'sequence'} <=> $registry{$b}{'sequence'}}
          keys %registry )
    {
        if( defined($registry{$entry}{'postprocess'}) )
        {
            &{$registry{$entry}{'postprocess'}}($dd, $devdetails);
        }
    }
    
    eval { $devobj->set_condition('torrus.imported', 1) };
    if( $@ )
    {
        Error('SIAM failure: ' . $@);
        exit(1);
    }
    
    $siamSemaphore->up();
    
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
