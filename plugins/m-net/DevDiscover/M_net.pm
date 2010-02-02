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

# $Id$
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

    if( $devdetails->isDevType('CiscoIOS') or
        $devdetails->isDevType('AlcatelLucent') )
    {
        if( $devdetails->param('M_net::skip-host') ne 'yes' )
        {
            return 1;
        }
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

        my %comment_param;
        foreach my $pair ( split( /\s*;\s*/, $comment ) )
        {
            my ($key, $val) = split( /\s*=\s*/, $pair );

            if( defined( $key ) and defined( $val ) )
            {
                $comment_param{$key} = $val;
            }
        }

        if( defined( $comment_param{'bw'} ) )
        {
            my $bw = uc $comment_param{'bw'};
            if( $bw =~ /([A-Z])$/ )
            {
                my $scale = $bw_scale{$1};
                $bw =~ s/([A-Z])$//;
                $bw *= $scale;
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




1;


# Local Variables:
# mode: perl
# indent-tabs-mode: nil
# perl-indent-level: 4
# End:
