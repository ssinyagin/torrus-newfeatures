#  Copyright (C) 2017  Stanislav Sinyagin
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



#######  Scheduler for Collector and Monitor agents  ########

package Torrus::AgentScheduler;
use strict;
use warnings;

use base 'Torrus::Scheduler';

use Torrus::AgentConfig;
use Torrus::Log;


our %agentConfig;

$agentConfig{'collector'} = {
    'period' => 'collector-period',
    'offset' => 'collector-timeoffset',
    'class' => 'Torrus::Collector',
};

$agentConfig{'monitor'} = {
    'period' => 'monitor-period',
    'offset' => 'monitor-timeoffset',
    'class' => 'Torrus::Monitor',
};


sub new
{
    my $proto = shift;
    my %options = @_;
    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new( %options );
    bless $self, $class;

    if( not defined( $options{'-AgentName'} ) )
    {
        die('-AgentName missing');
    }

    eval 'require ' . $agentConfig{$options{'-AgentName'}}{'class'};
    die($@) if $@;
    return $self;
}
    
    
sub beforeRun
{
    my $self = shift;

    my $tree = $self->treeName();
    my $instance = $self->{'options'}{'-Instance'};

    my $agent_name = $self->{'options'}{'-AgentName'};
    my $period_param = $agentConfig{$agent_name}{'period'};
    my $offset_param = $agentConfig{$agent_name}{'offset'};
    my $agent_class = $agentConfig{$agent_name}{'class'};
    
    my $data = $self->data();

    my $cb_updated = sub {
        my $token = shift;
        my $params = shift;

        my $period = $params->{$period_param};
        die($period_param . ' is undefined for ' . $token)
            unless defined($period);
        my $offset = $params->{$offset_param};
        die($offset_param . ' is undefined for ' . $token)
            unless defined($offset);

        my $old_agent = $data->{'token_agent'}{$token};
        if( defined($old_agent) and
            ($old_agent->period() != $period or
             $old_agent->offset() != $offset) )
        {
            $old_agent->deleteTarget($token);
            delete $data->{'token_agent'}{$token};
        }
        
        my $agent = $data->{'task_agent'}{$period}{$offset};

        if( not defined($agent) )
        {
            $agent =
                $agent_class->new( -Period => $period,
                                   -Offset => $offset,
                                   -TreeName => $tree,
                                   -Instance => $instance );
            
            $data->{'task_agent'}{$period}{$offset} = $agent;
            $self->addTask($agent);
        }

        $agent->addTarget( $token, $params );
        $data->{'token_agent'}{$token} = $agent;
    };

    my $cb_deleted = sub {
        my $token = shift;

        my $agent = $data->{'token_agent'}{$token};
        $agent->deleteTarget($token);
        delete $data->{'token_agent'}{$token};
    };

    my $ts_before_update = time();
    my $updated = 0;
    if( not defined($data->{'agent_config'}) )
    {
        $data->{'agent_config'} =
            new Torrus::AgentConfig($tree, $agent_name, $instance);
    }

    if( $data->{'agent_config'}->needsFlush() )
    {
        $data->{'task_agent'} = {};
        $data->{'token_agent'} = {};
        $self->flushTasks();
        $data->{'agent_config'}->readAll($cb_updated);
        $updated = 1;
    }
    else
    {
        $updated = 
            $data->{'agent_config'}->readUpdates($cb_updated, $cb_deleted);
    }

    if( $updated )
    {
        Verbose(sprintf("Updated tasks in %d seconds",
                        time() - $ts_before_update));
    }
        
    return 1;
}


1;


# Local Variables:
# mode: perl
# indent-tabs-mode: nil
# perl-indent-level: 4
# End:
