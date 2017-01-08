#  Copyright (C) 2002-2017  Stanislav Sinyagin
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



#######  Collector scheduler  ########

package Torrus::CollectorScheduler;
use strict;
use warnings;

use base 'Torrus::Scheduler';

use Torrus::AgentConfig;
use Torrus::Log;

sub beforeRun
{
    my $self = shift;

    my $tree = $self->treeName();
    my $instance = $self->{'options'}{'-Instance'};
    my $data = $self->data();

    my $cb_updated = sub {
        my $token = shift;
        my $params = shift;

        my $period = $params->{'collector-period'};
        my $offset = $params->{'collector-timeoffset'};

        my $old_collector = $data->{'token_agent'}{$token};
        if( defined($old_collector) and
            ($old_collector->period() != $period or
             $old_collector->offset() != $offset) )
        {
            $old_collector->deleteTarget($token);
            delete $data->{'token_agent'}{$token};
        }
        
        my $collector = $data->{'task_agent'}{$period}{$offset};

        if( not defined($collector) )
        {
            $collector =
                new Torrus::Collector( -Period => $period,
                                       -Offset => $offset,
                                       -TreeName => $tree,
                                       -Instance => $instance );
            
            $data->{'task_agent'}{$period}{$offset} = $collector;
            $self->addTask($collector);
        }

        $collector->addTarget( $token, $params );
        $data->{'token_agent'}{$token} = $collector;
    };

    my $cb_deleted = sub {
        my $token = shift;

        my $collector = $data->{'token_agent'}{$token};
        $collector->deleteTarget($token);
        delete $data->{'token_agent'}{$token};
    };

    my $ts_before_update = time();
    my $updated = 0;
    if( not defined($data->{'agent_config'}) )
    {
        $data->{'agent_config'} =
            new Torrus::AgentConfig($tree, 'collector', $instance);
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
