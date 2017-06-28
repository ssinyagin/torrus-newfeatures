#  Copyright (C) 2002  Stanislav Sinyagin
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

# Manage the properties assigned to Service IDs

package Torrus::ServiceID;

use strict;
use warnings;

use Torrus::Log;
use Torrus::Redis;
use JSON;


sub new
{
    my $self = {};
    my $class = shift;
    bless $self, $class;

    $self->{'json'} = JSON->new->canonical(1)->allow_nonref(1);
    
    $self->{'redis'} =
        Torrus::Redis->new(server => $Torrus::Global::redisServer);
    $self->{'params_hname'} =
        $Torrus::Global::redisPrefix . 'serviceid_params';
    $self->{'tokens_hname'} =
        $Torrus::Global::redisPrefix . 'serviceid_tokens';
    
    return $self;
}


sub idExists
{
    my $self = shift;
    my $serviceid = shift;
    return defined($self->{'redis'}->hget($self->{'params_hname'},
                                          $serviceid));
}


sub set
{
    my $self = shift;
    my $serviceid = shift;
    my $params = shift;

    my $redis = $self->{'redis'};
    my $old_params = $redis->hget($self->{'params_hname'}, $serviceid);

    if( defined($old_params) )
    {
        $old_params = $self->{'json'}->decode($old_params);
        if(defined($old_params->{'token'}) )
        {
            Error('Cannot set new parameters for ServiceID ' . $serviceid .
                  ' while it is assigned to token ' . $old_params->{'token'});
            return 0;
        }
    }

    $redis->hset($self->{'params_hname'}, $serviceid,
                 $self->{'json'}->encode($params));

    if( defined($params->{'token'}) )
    {
        $redis->hset($self->{'tokens_hname'}, $params->{'token'},
                     $serviceid);
    }
        
    return 1;
}


sub tokenDeleted
{
    my $self = shift;
    my $token = shift;

    my $redis = $self->{'redis'};
    
    my $serviceid = $redis->hget($self->{'tokens_hname'}, $token);
    if( defined($serviceid) )
    {
        my $params = $self->{'json'}->decode(
            $redis->hget($self->{'params_hname'}, $serviceid));
        delete $params->{'token'};
        
        $redis->hset($self->{'params_hname'}, $serviceid,
                     $self->{'json'}->encode($params));
        $redis->hdel($self->{'tokens_hname'}, $token);
    }
    return;
}
        

sub getAllTokens
{
    my $self = shift;
    return { $self->{'redis'}->hgetall($self->{'tokens_hname'}) };
}
             
    

sub getParams
{
    my $self = shift;
    my $serviceid = shift;

    my $params = $self->{'redis'}->hget($self->{'params_hname'}, $serviceid);

    if( defined($params) )
    {
        return $self->{'json'}->decode($params);
    }

    return {};
}


sub getAllForTree
{
    my $self = shift;
    my $tree = shift;

    my $ret = [];
    my %all = $self->{'redis'}->hgetall($self->{'params_hname'});

    foreach my $serviceid (sort keys %all)
    {
        my $params = $self->{'json'}->decode($all{$serviceid});
        if( defined($params->{'trees'}) and
            grep {$_ eq $tree} split(',', $params->{'trees'}) )
        {
            push( @{$ret}, $serviceid);
        }
    }
    return $ret;
}


            
            
            
            

1;


# Local Variables:
# mode: perl
# indent-tabs-mode: nil
# perl-indent-level: 4
# End:
