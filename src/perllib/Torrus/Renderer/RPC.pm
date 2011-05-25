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
#  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 02111-1307, USA.

# Stanislav Sinyagin <ssinyagin@yahoo.com>

package Torrus::Renderer::RPC;

use strict;

use Torrus::ConfigTree;
use Torrus::Log;

use JSON ();
use IO::File;

# Set to true if you want JSON to be pretty and canonical
our $pretty_json;


# List of parameters that are always queried
our @default_leaf_params;

# never return these parameters
our %params_blacklist;

# make sure we don't pull too much data
our $result_limit = 100;

# All our methods are imported by Torrus::Renderer;

sub render_rpc
{
    my $self = shift;
    my $config_tree = shift;
    my $token = shift;
    my $view = shift;
    my $outfile = shift;
              
    my $result = {'success' => 1, 'data' => {}};

    # Prepare the list of parameters to retrieve via an RPC call
    my @params;
    push(@params, @default_leaf_params);

    my $additional_params = $self->{'options'}{'variables'}{'GET_PARAMS'};
    if( defined($additional_params) )
    {
        foreach my $p (split(/\s*,\s*/o, $additional_params))
        {
            if( $params_blacklist{$p} )
            {
                $result->{'success'} = 0;
                $result->{'error'} = 'Parameter ' . $p . ' is blacklisted';
            }
            else
            {
                push(@params, $p);
            }
        }
    }

    if( $result->{'success'} )
    {
        # process the call
        my $callproc = $self->{'options'}{'variables'}{'RPCCALL'};
        if( defined($callproc) )
        {
            if( $callproc eq 'WALK_LEAVES' )
            {
                rpc_walk_leaves($self, $config_tree,
                                $token, \@params, $result);
            }
            else
            {
                $result->{'success'} = 0;
                $result->{'error'} = 'Unsupported RPC call: ' . $callproc;
            }
        }
        else
        {
            $result->{'success'} = 0;
            $result->{'error'} = 'Missing RPC call name in RPCCALL';
        }
    }

    my $json = new JSON;

    if( $pretty_json or $self->{'options'}{'variables'}{'PRETTY'})
    {
        $json->pretty;
        $json->canonical;
    }

    my $fh = new IO::File($outfile, 'w');
    if( not $fh )
    {
        Error("Error opening $outfile for writing: $!");
        return undef;
    }

    $fh->binmode(':utf8');
    print $fh $json->encode($result);
    $fh->close;

    my $expires = $config_tree->getParam($view, 'expires');

    return ($expires+time(), 'application/json');
}



sub rpc_walk_leaves
{
    my $self = shift;
    my $config_tree = shift;
    my $token = shift;
    my $params = shift;
    my $result = shift;

    if( scalar(keys %{$result->{'data'}}) > $result_limit )
    {
        $result->{'success'} = 0;
        $result->{'error'} = 'Result is too big. Aborting the tree walk';
        return;
    }
    
    if( $config_tree->isLeaf($token) )
    {
        my $data = {'path' => $config_tree->path($token)};
        foreach my $p (@{$params})
        {
            my $val = $config_tree->getNodeParam($token, $p);
            if( defined($val) )
            {
                $data->{$p} = $val;
            }
        }

        $result->{'data'}{$token} = $data;
    }
    elsif( $config_tree->isSubtree($token) )
    {
        foreach my $ctoken ($config_tree->getChildren($token))
        {
            rpc_walk_leaves($self, $config_tree, $ctoken, $params, $result);
        }
    }
}



1;


# Local Variables:
# mode: perl
# indent-tabs-mode: nil
# perl-indent-level: 4
# End:
