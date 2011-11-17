#  Copyright (C) 2010  Stanislav Sinyagin
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

# Discovery plugin for M-Net.de
# see tp-m-net.pod or tp-m-net.txt for detailed documentation

package Torrus::DevDiscover::M_net;

use strict;
use Torrus::Log;


$Torrus::DevDiscover::registry{'M_net'} = {
    'sequence'     => 600,
    'checkdevtype' => \&checkdevtype,
    'discover'     => \&discover,
    'buildConfig'  => \&buildConfig
    };


our %oiddef =
    (
     );

my %bw_scale =
    ('T' => 1.0e12,
     'G' => 1.0e9,
     'M' => 1.0e6,
     'K' => 1.0e3);
     

sub checkdevtype
{
    my $dd = shift;
    my $devdetails = shift;

    if( $devdetails->isDevType('RFC2863_IF_MIB') and
        $devdetails->param('M_net::manage') eq 'yes' )
    {
        if( defined( $devdetails->param('M_net::nodeid-prefix-key') ) )
        {
            my $data = $devdetails->data();
            
            if( $devdetails->hasCap('nodeidReferenceManaged') )
            {
                Error('M_net conflicts with ' .
                      $data->{'nodeidManagedBy'} . ' in nodeid management. ' .
                      'Modify the discovery instructions to enable only one ' .
                      'of the modules to manage nodeid.');
                return 0;
            }
            
            $devdetails->setCap('nodeidReferenceManaged');
            $data->{'nodeidManagedBy'} = 'M_net';
        }
        
        return 1;
    }

    return 0;
}


sub discover
{
    my $dd = shift;
    my $devdetails = shift;

    my $session = $dd->session();
    my $data = $devdetails->data();

    my %skip_interfaces;
    my $str = $devdetails->param('M_net::skip-interfaces');
    if( defined( $str ) )
    {
        foreach my $name ( split( /\s*,\s*/, $str ) )
        {
            $skip_interfaces{$name} = 1;
        }
    }

    # Copy the old nodeid values into a new reference map
    my $orig_nameref_ifNodeidPrefix =
        $data->{'nameref'}{'ifNodeidPrefix'};
    my $orig_nameref_ifNodeid =
        $data->{'nameref'}{'ifNodeid'};

    $data->{'nameref'}{'ifNodeidPrefix'} = 'M_net_ifNodeidPrefix';
    $data->{'nameref'}{'ifNodeid'} = 'M_net_ifNodeid';

    foreach my $ifIndex ( keys %{$data->{'interfaces'}} )
    {
        my $interface = $data->{'interfaces'}{$ifIndex};
        next if $interface->{'excluded'};

        $interface->{$data->{'nameref'}{'ifNodeidPrefix'}} =
            $interface->{$orig_nameref_ifNodeidPrefix};
        
        $interface->{$data->{'nameref'}{'ifNodeid'}} =
            $interface->{$orig_nameref_ifNodeid};
    }

    # Process comment strings and populate nodeid when matched
    
    my $nodeid_prefix_key = $devdetails->param('M_net::nodeid-prefix-key');
    
    foreach my $ifIndex ( keys %{$data->{'interfaces'}} )
    {
        my $interface = $data->{'interfaces'}{$ifIndex};
        
        next if $interface->{'excluded'};

        my $comment;
        
        if( defined $data->{'nameref'}{'ifComment'} and
            not defined( $interface->{'param'}{'comment'} ) and
            length( $interface->{$data->{'nameref'}{'ifComment'}} ) > 0 )
        {
            $comment = $interface->{$data->{'nameref'}{'ifComment'}};
        }

        next unless defined( $comment );

        my $subtreeName = $interface->{$data->{'nameref'}{'ifSubtreeName'}};

        if( $skip_interfaces{$subtreeName} )
        {
            Debug('Skipping ' . $subtreeName . ' from M_net processing');
            next;
        }

        my $mnet_attr = {};
        foreach my $pair ( split( /\s*;\s*/, $comment ) )
        {
            my ($key, $val) = split( /\s*=\s*/, $pair );

            if( defined( $key ) and defined( $val ) )
            {
                $mnet_attr->{lc $key} = $val;
            }
        }

        my $bw = 0;
        
        if( defined( $mnet_attr->{'bw'} ) )
        {
            $bw = uc $mnet_attr->{'bw'};
            if( $bw =~ /([A-Z])$/ )
            {
                my $scale = $bw_scale{$1};
                $bw =~ s/([A-Z])$//;
                $bw *= $scale;
            }
        }
        else
        {
            if( defined( $interface->{'ifSpeed'} ) )
            {
                $bw = $interface->{'ifSpeed'};
            }
        }
        
        if( $bw > 0 )
        {
            $interface->{'param'}{'bandwidth-limit-in'} = $bw / 1e6;
            $interface->{'param'}{'bandwidth-limit-out'} = $bw / 1e6;
            $interface->{'childCustomizations'}->{'InOut_bps'}->{
                'upper-limit'} = $bw;
            $interface->{'childCustomizations'}->{'Bytes_In'} ->{
                'upper-limit'} = $bw / 8;
            $interface->{'childCustomizations'}->{'Bytes_Out'} ->{
                'upper-limit'} = $bw / 8;
            $interface->{'param'}{'mnet-bw'} = $bw;
            $interface->{'param'}{'monitor-vars'} = sprintf('bw=%g', $bw);
        }        

        $interface->{'mnet-attributes'} = $mnet_attr;

        # Populate the rest of interface attributes as parameters.
        # They can be used in monitor notifications.
        # all non-alphanumeric symbols in key names are replaced with dashes

        while( my ($key, $val) = each %{$mnet_attr} )
        {
            $key =~ s/[^a-zA-Z0-9]+/-/go;            
            $interface->{'param'}{'mnet-attr-' . $key} = $val;
        }

        # Set the nodeid prefix
        
        if( defined( $nodeid_prefix_key ) )
        {
            if( defined( $mnet_attr->{$nodeid_prefix_key} ) )
            {
                $interface->{$data->{'nameref'}{'ifNodeidPrefix'}} =
                    $nodeid_prefix_key . '//';

                $interface->{$data->{'nameref'}{'ifNodeid'}} = 
                    $mnet_attr->{$nodeid_prefix_key};
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
}


#######################################
# Selectors interface
#

$Torrus::DevDiscover::selectorsRegistry{'M_net'} = {
    'getObjects'      => \&getSelectorObjects,
    'getObjectName'   => \&getSelectorObjectName,
    'checkAttribute'  => \&checkSelectorAttribute,
    'applyAction'     => \&applySelectorAction,
};


## Objects are interface indexes

sub getSelectorObjects
{
    return &Torrus::DevDiscover::RFC2863_IF_MIB::getSelectorObjects( @_ );
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

    # Chop off trailing digits, if any
    $attr =~ s/\d+$//;
    
    my $value =  $interface->{'mnet-attributes'}{lc $attr};
    
    if( defined( $value ) )
    {
        return ( $value =~ $checkval ) ? 1:0;
    }
    else
    {
        return 0;
    }
}


sub getSelectorObjectName
{
    return &Torrus::DevDiscover::RFC2863_IF_MIB::getSelectorObjectName( @_ );
}


sub applySelectorAction
{
    return &Torrus::DevDiscover::RFC2863_IF_MIB::applySelectorAction( @_ );
}
   




1;


# Local Variables:
# mode: perl
# indent-tabs-mode: nil
# perl-indent-level: 4
# End:
