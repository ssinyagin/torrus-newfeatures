#  Copyright (C) 2016  Stanislav Sinyagin
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

package Torrus::Renderer::Health;
use strict;
use warnings;

use Torrus::ConfigTree;
use Torrus::Log;

use File::Copy;
use RRDs;

# All our methods are imported by Torrus::Renderer;

sub render_health
{
    my $self = shift;
    my $config_tree = shift;
    my $token = shift;
    my $view = shift;
    my $outfile = shift;

    my $has_health = $config_tree->getNodeParam($token, 'has-health-status', 1);
    if( not defined($has_health) or $has_health ne 'yes' )
    {
        my $path = $config_tree->path($token);
        Error($path .
              ': has-health-status is not set to yes, cannot display health');
        return undef;
    }

    my $health_nodeid =
        $config_tree->getNodeParam($token, 'health-status-nodeid');
    if( not defined($health_nodeid) )
    {
        my $path = $config_tree->path($token);
        Error($path .
              ': health-status-nodeid is not defined, cannot display health');
        return undef;
    }

    my $health_token = $config_tree->getNodeByNodeid($health_nodeid);
    if( not defined($health_token) )
    {
        my $path = $config_tree->path($token);
        Error($path .
              ': health-status-nodeid points to an undefined nodeid, ' .
              'cannot display health');
        return undef;
    }

    if( not $config_tree->isLeaf($health_token) )
    {
        my $path = $config_tree->path($health_token);
        Error($path . ' is referred for health status, but is not a leaf');
        return undef;        
    }
    
    my $leaftype = $config_tree->getNodeParam($health_token, 'leaf-type');
    if( $leaftype ne 'rrd-def' )
    {
        my $path = $config_tree->path($health_token);
        Error($path .
              ' is referred for health status, but is not of type rrd-def');
        return undef;
    }

    my $t_end = time();
    my $timespan = $config_tree->getNodeParam($token, 'health-lookup-period');
    if( not defined($timespan) )
    {
        $timespan = 900;
    }
    
    my $t_start = $t_end - $timespan;

    $self->{'options'}->{'variables'}->{'Gstart'} = $t_start;
    $self->{'options'}->{'variables'}->{'Gend'} = $t_end;
        
    my @args;        

    push( @args, $self->rrd_make_opts(
              $config_tree, $health_token, $view,
              {'start' => '--start', 'end' => '--end'} ) );

    push( @args,
          $self->rrd_make_def($config_tree, $health_token, 'Aavg', 'AVERAGE') );

    push( @args, 'VDEF:D1=Aavg,AVERAGE', 'PRINT:D1:%le' );
    
    # Info('RRDs::graphv arguments: ' . join(' ', @args));

    my $r = RRDs::graphv('-', @args);

    my $ERR=RRDs::error;
    if( $ERR )
    {
        Error('RRD::graphv returned error: ' . $ERR);
        return undef;
    }

    my $value = $r->{'print[0]'};
    
    # Info("health value: " . $value);
    
    my $status = 'good';
    if( $value < $config_tree->getNodeParam($token, 'health-level-good') )
    {
        if( $value < $config_tree->getNodeParam($token,
                                                'health-level-warning') )
        {
            $status = 'critical';
        }
        else
        {
            $status = 'warning';
        }
    }

    my $imgfile = $config_tree->getParam($view, $status . '-img');
    # if relative path, the icon is in our default dir
    if( $imgfile !~ /^\// )
    {
        $imgfile = $Torrus::Global::healthIconsDir . '/' . $imgfile;
    }

    if( not -r $imgfile )
    {
        Error("Cannot read the health icon file: " . $imgfile);
        return undef;
    }

    copy($imgfile, $outfile);
    my $expires = $config_tree->getParam($view, 'expires');
    return ($expires+$t_end, 'image/png');
    
    return;
}


1;


# Local Variables:
# mode: perl
# indent-tabs-mode: nil
# perl-indent-level: 4
# End:
