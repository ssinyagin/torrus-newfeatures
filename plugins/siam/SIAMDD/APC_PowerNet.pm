#  Copyright (C) 2013  Stanislav Sinyagin
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

# SIAM integration for APC PDU power meters

package Torrus::DevDiscover::SIAMDD::APC_PowerNet;

use strict;
use warnings;

use Torrus::Log;



$Torrus::DevDiscover::SIAMDD::registry{'APC_PowerNet'} = {
    'sequence'            => 800,
    'prepare'             => \&prepare,
    'list_dev_components' => \&list_dev_components,
    'match_devc'          => \&match_devc,
    'postprocess'         => undef,
};


sub prepare
{
    my $dd = shift;
    my $devdetails = shift;

    my $data = $devdetails->data();

    if( not $devdetails->isDevType('APC_PowerNet') )
    {
        return;
    }

    $data->{'siam'}{'assets'}{'APC_PowerNet'} = 1;
    $data->{'siam'}{'skip_IFMIB'} = 1;

    return;
}


sub list_dev_components
{
    my $dd = shift;
    my $devdetails = shift;

    my $data = $devdetails->data();

    my $ret = [];

    if( $data->{'siam'}{'assets'}{'APC_PowerNet'} )
    {
        if( $devdetails->hasCap('apc_rPDU2') or
            $devdetails->hasCap('apc_rPDU') )
        {
            my $attr = {};
            $attr->{'siam.object.complete'} = 1;
            $attr->{'siam.devc.type'} = 'Power.PDU';
            $attr->{'siam.devc.name'} = 'PDU';
            
            push(@{$ret}, $attr);
        }        
    }
    
    return $ret;
}



sub match_devc
{
    my $dd = shift;
    my $devdetails = shift;
    my $devc = shift;

    my $data = $devdetails->data();

    if( not $data->{'siam'}{'assets'}{'APC_PowerNet'} or
        $devc->attr('siam.devc.type') ne 'Power.PDU' )
    {
        return 0;
    }
    
    if( $devdetails->hasCap('apc_rPDU2') or
        $devdetails->hasCap('apc_rPDU') )
    {
        $data->{'param'}{'nodeid-pdu'} = $devc->attr('torrus.nodeid');
        return 1;
    }
        
    return 0;
}





1;


# Local Variables:
# mode: perl
# indent-tabs-mode: nil
# perl-indent-level: 4
# End:
