#  Copyright (C) 2002-2011  Stanislav Sinyagin
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


#######  Monitor scheduler  ########

package Torrus::MonitorScheduler;
use strict;
use warnings;
use base 'Torrus::Scheduler';

use Torrus::AgentConfig;
use Torrus::Log;

sub beforeRun
{
    my $self = shift;

    my $tree = $self->treeName();
    my $instance = 0;
    my $data = $self->data();

    my $cb_updated = sub {
        my $token = shift;
        my $params = shift;

        my $period = $params->{'monitor-period'};
        my $offset = $params->{'monitor-timeoffset'};
        my $monitor = $data->{'task'}{$period}{$offset};

        if( not defined($monitor) )
        {
            $monitor =
                new Torrus::Monitor( -Period => $period,
                                     -Offset => $offset,
                                     -TreeName => $tree,
                                     -Instance => $instance );
            
            $data->{'task'}{$period}{$offset} = $monitor;
            $self->addTask($monitor);
        }

        $monitor->addTarget( $token, $params );
        $data->{'agent'}{$token} = $monitor;
    };

    my $cb_deleted = sub {
        my $token = shift;

        my $monitor = $data->{'agent'}{$token};
        $monitor->deleteTarget($token);
        delete $data->{'agent'}{$token};
    };

    my $ts_before_update = time();
    my $updated = 0;
    if( not defined($data->{'agent_config'}) )
    {
        $data->{'agent_config'} =
            new Torrus::AgentConfig($tree, 'monitor', $instance);
        
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
