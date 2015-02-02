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
use warnings;

use Torrus::ConfigTree;
use Torrus::Log;

use RRDs;
use JSON ();
use IO::File;
use Math::BigFloat;

# Set to true if you want JSON to be pretty and canonical
our $pretty_json;


# List of parameters that are always queried
our @default_leaf_params;

# never return these parameters
our %params_blacklist;

# make sure we don't pull too much data
our $result_limit = 100;

my %rpc_methods =
    (
     'WALK_LEAVES' => {
         'call' => \&rpc_walk_leaves,
         'needs_params' => 1,
     },
     
     'AGGREGATE_DS'   => {
         'call' => \&rpc_aggregate_ds,
     },
     
     'TIMESERIES'   => {
         'call' => \&rpc_timeseries,
     },
     
     'SEARCH_NODEID' => {
         'call' => \&rpc_search_nodeid,
         'needs_params' => 1,
     },
     );

    
# All our methods are imported by Torrus::Renderer;

sub render_rpc
{
    my $self = shift;
    my $config_tree = shift;
    my $token = shift;
    my $view = shift;
    my $outfile = shift;
              
    my $result = {'success' => 1, 'data' => {}};

    my $callproc = $self->{'options'}{'variables'}{'RPCCALL'};
    if( not defined $callproc )
    {
        $result->{'success'} = 0;
        $result->{'error'} = 'Missing RPC call name in RPCCALL';
    }
    elsif( not defined($rpc_methods{$callproc}) )
    {
        $result->{'success'} = 0;
        $result->{'error'} = 'Unsupported RPC call: ' . $callproc;
    }
        
    # Prepare the list of parameters to retrieve via an RPC call
    my @params;
    if( $result->{'success'} and
        $rpc_methods{$callproc}{'needs_params'} )
    {
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
                    last;
                }
                else
                {
                    push(@params, $p);
                }
            }
        }
    }

    # Process the call
    if( $result->{'success'} )
    {
        &{$rpc_methods{$callproc}{'call'}}
        ($self, $config_tree,
         {
             'token' => $token,
             'view'  => $view,
             'params' => \@params,
             'result' => $result });
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
    my $opts = shift;

    my $token = $opts->{'token'};
    my $params = $opts->{'params'};
    my $result = $opts->{'result'};
    

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
            rpc_walk_leaves($self, $config_tree,
                            {'token' => $ctoken,
                             'params' => $params,
                             'result' => $result});
        }
    }
    return;
}



my @rpc_print_statements =
    (
     {
         'name' => 'START',
         'args' => ['CDEF:B1=Aavg,POP,TIME',
                    'VDEF:B2=B1,MINIMUM',
                    'PRINT:B2:%.0lf'],
     },
     {
         'name' => 'END',
         'args' => ['CDEF:C1=Aavg,POP,TIME',
                    'VDEF:C2=C1,MAXIMUM',
                    'PRINT:C2:%.0lf'],
     },
     {
         'name' => 'AVG',
         'args' => ['VDEF:D1=Aavg,AVERAGE',
                    'PRINT:D1:%le'],
     },
     {
         'name' => 'AVAIL',
         'args' => ['CDEF:F1=Aavg,UN,0,100,IF',
                    'VDEF:F2=F1,AVERAGE',
                    'PRINT:F2:%.2lf'],
     },
     );

my @rpc_print_max_statements =
    (
     {
         'name' => 'MAX',
         'args' => ['VDEF:E1=Amax,MAXIMUM',
                    'PRINT:E1:%le'],
     },
     );

my %rrd_print_opts =
    (
     'start'  => '--start',
     'end'    => '--end',
     );
     

sub rpc_aggregate_ds
{
    my $self = shift;
    my $config_tree = shift;
    my $opts = shift;

    my $token = $opts->{'token'};
    my $view = $opts->{'view'};
    my $params = $opts->{'params'};
    my $result = $opts->{'result'};
    
    if( not $config_tree->isLeaf($token) )
    {
        $result->{'success'} = 0;
        $result->{'error'} = 'AGGREGATE_DS method supports only leaf nodes';
        return;
    }

    if( $config_tree->getNodeParam($token, 'ds-type') eq 'rrd-multigraph' )
    {
        $result->{'success'} = 0;
        $result->{'error'} =
            'AGGREGATE_DS method does not support rrd-multigraph leaves';
        return undef;
    }

    my $leaftype = $config_tree->getNodeParam($token, 'leaf-type');
    if( $leaftype ne 'rrd-def' )
    {
        $result->{'success'} = 0;
        $result->{'error'} = 'Unsupported leaf-type: ' . $leaftype;
        return;
    }

    my $rra = $config_tree->getNodeParam($token, 'rrd-create-rra');
    my $has_max = ($rra =~ /RRA:MAX:/s);
        
    my @args;    
    
    push( @args, $self->rrd_make_opts( $config_tree, $token, $view,
                                       \%rrd_print_opts, ) );
    
    push( @args,
          $self->rrd_make_def($config_tree, $token, 'Aavg', 'AVERAGE') );
    if( $has_max )
    {
        push( @args,
              $self->rrd_make_def($config_tree, $token, 'Amax', 'MAX') );
    }

    my @prints;
    push( @prints, @rpc_print_statements );
    if( $has_max )
    {
        push( @prints, @rpc_print_max_statements );
    }
    
    foreach my $entry ( @prints )
    {
        push( @args, @{$entry->{'args'}} );
    }
    
    Debug('RRDs::graphv arguments: ' . join(' ', @args));

    my $r = RRDs::graphv('-', @args);

    my $ERR=RRDs::error;
    if( $ERR )
    {
        $result->{'success'} = 0;
        $result->{'error'} = 'RRD::graphv returned error: ' . $ERR;
        return undef;
    }

    my $data = {};
    my $i = 0;

    foreach my $entry ( @prints )
    {
        my $key = 'print[' . $i . ']';
        my $val = $r->{$key};

        if( not defined($val) )
        {
            $val = 'NaN';
        }

        $data->{$entry->{'name'}} = $val;
        $i++;
    }

    $result->{'data'}{$token} = $data;
    return;
}




sub rpc_timeseries
{
    my $self = shift;
    my $config_tree = shift;
    my $opts = shift;

    my $token = $opts->{'token'};
    my $view = $opts->{'view'};
    my $params = $opts->{'params'};
    my $result = $opts->{'result'};
    
    if( not $config_tree->isLeaf($token) )
    {
        $result->{'success'} = 0;
        $result->{'error'} = 'TIMESERIES supports only leaf nodes';
        return;
    }

    my @args;
    foreach my $opt ('step', 'maxrows')
    {
        my $value = $self->{'options'}->{'variables'}->{'G' . $opt};
        if( defined($value) )
        {
            push(@args, '--' . $opt, $value);
        }
    }

    my $dataonly =
        $self->{'options'}{'variables'}{'DATAONLY'} ? 1:0;
    
    my ($rrgraph_args, $obj) =
        $self->prepare_rrgraph_args($config_tree, $token, 'embedded',
                                    {'data_only' => $dataonly});

    Debug('rrgraph_args: ' . join(' ', @{$rrgraph_args}));

    my @xport_names;
        
    for(my $i=0; $i < scalar(@{$rrgraph_args}); $i++)
    {
        my $val = $rrgraph_args->[$i];
        if( ($val eq '--start') or ($val eq '--end') )
        {
            $i++;
            push(@args, $val, $rrgraph_args->[$i]);
        }
        elsif( $val =~ /^C?DEF/o )
        {
            push(@args, $val);
        }
        elsif( $val =~ /^LINE\d*:([a-zA-Z_][a-zA-Z0-9_]*)/o or
               $val =~ /^AREA:([a-zA-Z_][a-zA-Z0-9_]*)/o )
        {
            push(@xport_names, $1);
        }
    }

    foreach my $name ( @xport_names )
    {
        push(@args, 'XPORT:' . $name . ':' . $name);
    }
    
    Debug('RRDs::xport arguments: ' . join(' ', @args));

    my @xport_ret = RRDs::xport(@args);
    
    my $ERR=RRDs::error;
    if( $ERR )
    {
        $result->{'success'} = 0;
        $result->{'error'} = 'RRD::xport returned error: ' . $ERR;
        return undef;
    }

    my $r = $result->{'data'};

    foreach my $ret_name
        ('start', 'end', 'step', 'cols', 'names', 'data')
    {
        $r->{$ret_name} = shift @xport_ret;
    }    

    if( not $dataonly )
    {
        # remove --start and --end from rrgraph_args
        my $i = 0;
        while( $i < scalar(@{$rrgraph_args}) )
        {
            my $val = $rrgraph_args->[$i];
            if( ($val eq '--start') or ($val eq '--end') )
            {
                splice(@{$rrgraph_args}, $i, 2);
            }
            else
            {
                $i++;
            }
        }
        
        $r->{'rrgraph_args'} = $rrgraph_args;
    }

    # convert numbers to strings, undefs to NaN, andinfinities to
    # Infinity and -Infinity

    for( my $i=0; $i < scalar(@{$r->{'data'}}); $i++ )
    {
        for( my $j=0; $j < scalar(@{$r->{'data'}[$i]}); $j++ )
        {
            my $val = $r->{'data'}[$i][$j];
            if( not defined($val) )
            {
                $val = 'NaN';
            }
            else
            {
                $val = Math::BigFloat->new($val);
                if( $val->is_nan() )
                {
                    $val = 'NaN';
                }
                elsif( $val->is_inf('+') )
                {
                    $val = 'Infinity';
                }
                elsif( $val->is_inf('-') )
                {
                    $val = '-Infinity';
                }
                else
                {
                    $val = $val->bstr();
                }
            }
            
            $r->{'data'}[$i][$j] = $val;
        }
    }
    
    return;
}




sub rpc_search_nodeid
{
    my $self = shift;
    my $config_tree = shift;
    my $opts = shift;

    my $params = $opts->{'params'};
    my $result = $opts->{'result'};

    my $search_prefix = $self->{'options'}{'variables'}{'PREFIX'};
    if( not defined $search_prefix )
    {
        $result->{'success'} = 0;
        $result->{'error'} = 'Missing the search prefix in PREFIX';
        return;
    }

    my $search_results = $config_tree->searchNodeidPrefix($search_prefix);

    if( not defined($search_results) or scalar(@{$search_results}) == 0 )
    {
        $result->{'data'} = {};
        return;
    }
   
    
    if( scalar(@{$search_results}) > $result_limit )
    {
        $result->{'success'} = 0;
        $result->{'error'} = 'Result is too big. Aborting the RPC call';
        return;
    }
    
    # results are pairs [nodeid,token]
    foreach my $res ( @{$search_results} )
    {
        my $token = $res->[1];
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
    }
    return;
}




1;


# Local Variables:
# mode: perl
# indent-tabs-mode: nil
# perl-indent-level: 4
# End:
