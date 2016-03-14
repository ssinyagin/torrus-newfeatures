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


# Stanislav Sinyagin <ssinyagin@k-open.com>

# SIAM integration for IF-MIB discovery

package Torrus::DevDiscover::SIAMDD::IFMIB;

use strict;
use warnings;

use Torrus::Log;


$Torrus::DevDiscover::SIAMDD::registry{'IFMIB'} = {
    'sequence'            => 1000,
    'prepare'             => \&prepare,
    'list_dev_components' => \&list_dev_components,
    'match_devc'          => \&match_devc,
    'postprocess'         => \&postprocess,
};


sub prepare
{
    my $dd = shift;
    my $devdetails = shift;
    my $devobj = shift;
    
    my $data = $devdetails->data();

    if( not $devdetails->isDevType('RFC2863_IF_MIB') or
        $data->{'siam'}{'skip_IFMIB'} )
    {
        return;
    }

    $data->{'siam'}{'assets'}{'IFMIB'} = 1;

    
    # index the interfaces by ifReferenceName
    # also populate our nodeid references
    my $orig_nameref_ifNodeidPrefix =
        $data->{'nameref'}{'ifNodeidPrefix'};

    my $orig_nameref_ifNodeid =
        $data->{'nameref'}{'ifNodeid'};

    $data->{'nameref'}{'ifNodeidPrefix'} = 'SIAM_ifNodeidPrefix';
    $data->{'nameref'}{'ifNodeid'} = 'SIAM_ifNodeid';

    $data->{'siam'}{'ifRef'} = {};
    $data->{'siam'}{'ifRefDuplicates'} = {};

    foreach my $ifIndex ( keys %{$data->{'interfaces'}} )
    {
        my $interface = $data->{'interfaces'}{$ifIndex};
        next if $interface->{'excluded'};
        
        $interface->{$data->{'nameref'}{'ifNodeidPrefix'}} =
            $interface->{$orig_nameref_ifNodeidPrefix};
        
        $interface->{$data->{'nameref'}{'ifNodeid'}} =
            $interface->{$orig_nameref_ifNodeid};

        # first, respect the chosen reference as discovered by other modules
        my $refkey = $interface->{$data->{'nameref'}{'ifReferenceName'}};
        $data->{'siam'}{'ifRef'}{'default'}{$refkey} = $interface;

        # then, try everything else
        foreach my $prop (@Torrus::SIAMDD::match_port_properties)
        {
            if( $prop ne $data->{'nameref'}{'ifReferenceName'} )
            {
                my $val = $interface->{$prop};
                if( defined($val) and length($val) > 0 )
                {
                    if( defined($data->{'siam'}{'ifRef'}{$prop}{$val}) )
                    {
                        # value already seen before,
                        # this property has duplicates
                        $data->{'siam'}{'ifRefDuplicates'}{$prop}{$val} = 1;
                    }
                    else
                    {
                        $data->{'siam'}{'ifRef'}{$prop}{$val} = $interface;
                    }
                }
            }
        }                        
    }

    foreach my $attr ('torrus.if.adminup_only', 'torrus.if.siam_known_only')
    {
        if( $devobj->attr($attr) )
        {
            $data->{'siam'}{$attr} = 1;
        }
    }

    return;
}


sub list_dev_components
{
    my $dd = shift;
    my $devdetails = shift;

    my $data = $devdetails->data();

    my $ret = [];

    if( $data->{'siam'}{'assets'}{'IFMIB'} )
    {
        my $sort_by_ifindex =
            $devdetails->paramDisabled('RFC2863_IF_MIB::sort-by-name');
            

        foreach my $ifIndex ( keys %{$data->{'interfaces'}} )
        {
            my $interface = $data->{'interfaces'}{$ifIndex};
            next if $interface->{'excluded'};
            
            my $attr = {};
            $attr->{'siam.object.complete'} = 1;
            $attr->{'siam.devc.type'} = 'IFMIB.Port';
            $attr->{'siam.devc.name'} =
                $interface->{$data->{'nameref'}{'ifReferenceName'}};

            my $descr = '-';
            if( defined($data->{'nameref'}{'ifComment'}) and
                defined($interface->{$data->{'nameref'}{'ifComment'}}) and
                $interface->{$data->{'nameref'}{'ifComment'}} ne '' )
            {
                $descr = $interface->{$data->{'nameref'}{'ifComment'}};
            }
            $attr->{'siam.devc.description'} = $descr;

            if( $sort_by_ifindex )
            {
                $attr->{'display.sort.string'} =
                    sprintf('%s%.15d',
                            $data->{'param'}{'system-id'}, $ifIndex);
            }            

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

    if( not $data->{'siam'}{'assets'}{'IFMIB'} or
        $devc->attr('siam.devc.type') ne 'IFMIB.Port' )
    {
        return 0;
    }

    my $interface;
    my $ifRef = $data->{'siam'}{'ifRef'};
        
    foreach my $attr (@Torrus::SIAMDD::match_port_name_attributes)
    {
        last if defined($interface);
        
        my $val = $devc->attr($attr);                
        if( defined($val) )
        {
            Debug('Trying to match interface name: ' . $val);
            if( defined($ifRef->{'default'}{$val}) )
            {
                $interface = $ifRef->{'default'}{$val};
            }
            else
            {
                foreach my $prop
                    (@Torrus::SIAMDD::match_port_properties)
                {
                    if( (not $data->{'siam'}{'ifRefDuplicates'}{$prop}{$val})
                        and
                        defined($ifRef->{$prop}{$val}) )
                    {
                        $interface = $ifRef->{$prop}{$val};
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
        $interface->{'SIAM::matched'} = 1;
        $interface->{$data->{'nameref'}{'ifNodeidPrefix'}} = '';
        $interface->{$data->{'nameref'}{'ifNodeid'}} =
            $devc->attr('torrus.nodeid');
        $interface->{'param'}{'siam-devicecomponent'} = $devc->id();

        # Apply the service access bandwidth
        my $bw = $devc->attr('torrus.port.bandwidth');
        if( not defined($bw) or $bw == 0 )
        {
            if( defined( $interface->{'ifSpeed'} ) )
            {
                $bw = $interface->{'ifSpeed'};
            }
        }
        
        if( defined($bw) and $bw > 0 )
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

        my $monitor_names = $devc->attr('torrus.port.monitors');
        if( defined($monitor_names) and $monitor_names =~ /\w/ )
        {
            $interface->{'childCustomizations'}->{'Bytes_In'} ->{
                'monitor'} = $monitor_names;
            $interface->{'childCustomizations'}->{'Bytes_Out'} ->{
                'monitor'} = $monitor_names;

            my $new_vars = $devc->attr('torrus.port.monitor_vars');
            if( defined($new_vars) )
            {
                my $vars = $interface->{'param'}{'monitor-vars'};
                if( defined($vars) )
                {
                    $vars .= ';' . $new_vars;
                }
                else
                {
                    $vars = $new_vars;
                }
                $interface->{'param'}{'monitor-vars'} = $vars;
            }
        }

        foreach my $level ('warn', 'crit')
        {
            my $val = $devc->attr('torrus.port.' . $level);
            next unless ( defined($val) and $val > 0 );
            
            $interface->{'childCustomizations'}->{'InOut_bps'}->{
                $level . '-level'} = $val;
            $interface->{'childCustomizations'}->{'Bytes_In'} ->{
                $level . '-level'} = $val / 8;
            $interface->{'childCustomizations'}->{'Bytes_Out'} ->{
                $level . '-level'} = $val / 8;

            # RFC2863_IF_MIB::bandwidth-usage parameter is checked in
            # RFC2863_IF_MIB and customizations are ignored if the
            # bandwidth usage is not displayed
            if( defined($bw) and $bw > 0 )
            {
                $interface->{'childCustomizations'}->{'Bandwidth_Usage'} ->{
                    $level . '-level'} = 100.0 * $val / $bw;
            }
        }

        if( $interface->{'ifAdminStatus'} != 1 )
        {
            $devc->set_condition
                ('torrus.warning',
                 'Port is administratively down on the device');
        }

        if( $Torrus::SIAMDD::ifmib_search_svcc_in_description and
            defined($data->{'nameref'}{'ifComment'}) )
        {
            if( not defined ($Torrus::SIAMDD::ifmib_search_svcc_pattern) )
            {
                Error('$Torrus::SIAMDD::ifmib_search_svcc_in_description ' .
                      'is true, but ' .
                      '$Torrus::SIAMDD::ifmib_search_svcc_pattern ' .
                      ' is not defined');
            }
            else
            {
                my $comment =
                    $interface->{$data->{'nameref'}{'ifComment'}};
                
                if( defined($comment) and
                    $comment =~ $Torrus::SIAMDD::ifmib_search_svcc_pattern )
                {
                    my $svcc_match = $1;
                    if( defined($svcc_match) and length($svcc_match) > 0 )
                    {
                        Debug('Found SVCC identifier ' . $svcc_match .
                              ' in IFMIB port description');
                        if( defined($Torrus::SIAMDD::ifmib_search_svcc_prefix) )
                        {
                            $svcc_match =
                                $Torrus::SIAMDD::ifmib_search_svcc_prefix .
                                $svcc_match;
                        }

                        eval {
                            $devc->set_condition
                                ('siam.devc.link_svcc', $svcc_match);
                        };

                        if( $@ )
                        {
                            Error('Error setting siam.devc.link_svcc on  ' .
                                  $devc->id() . ': ' . $@);
                        }
                        else
                        {
                            my $name =
                                $interface->{$data->{'nameref'}{
                                    'ifReferenceName'}};
                            
                            Verbose('Linked SIAM::ServiceComponent with ' .
                                    'siam.svcc.inventory_id=' . $svcc_match .
                                    ' to ' . $devdetails->param('system-id') .
                                    ' port ' . $name);
                        }
                    }
                }
            }
        }
    }
    
    return( defined($interface) );
}



sub postprocess
{
    my $dd = shift;
    my $devdetails = shift;

    my $data = $devdetails->data();

    if( not $data->{'siam'}{'assets'}{'IFMIB'} )
    {
        return;
    }
        
    # Admin-down interfaces which were not matched against SIAM have no
    # further interest, and we exclude them
    
    if( $devdetails->paramEnabled
        ('SIAM::exclude-unmatched-admindown-interfaces') )
    {
        foreach my $ifIndex ( keys %{$data->{'interfaces'}} )
        {
            my $interface = $data->{'interfaces'}{$ifIndex};
            next if $interface->{'excluded'};

            if( $interface->{'ifAdminStatus'} != 1 and
                (not $interface->{'SIAM::matched'}) )
            {
                $interface->{'excluded'} = 1;
            }
        }
    }

    if( $data->{'siam'}{'torrus.if.adminup_only'} )
    {
        foreach my $ifIndex ( keys %{$data->{'interfaces'}} )
        {
            my $interface = $data->{'interfaces'}{$ifIndex};
            next if $interface->{'excluded'};

            if( $interface->{'ifAdminStatus'} != 1 )
            {
                $interface->{'excluded'} = 1;
            }
        }
    }

    if( $data->{'siam'}{'torrus.if.siam_known_only'} )
    {
        foreach my $ifIndex ( keys %{$data->{'interfaces'}} )
        {
            my $interface = $data->{'interfaces'}{$ifIndex};
            next if $interface->{'excluded'};
            
            if( not $interface->{'SIAM::matched'} )
            {
                $interface->{'excluded'} = 1;
            }
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
