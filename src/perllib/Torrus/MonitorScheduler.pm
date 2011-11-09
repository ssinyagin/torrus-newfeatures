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

# Stanislav Sinyagin <ssinyagin@yahoo.com>


#######  Monitor scheduler  ########

package Torrus::MonitorScheduler;
use strict;
use warnings;
use base 'Torrus::Scheduler';

use Torrus::ConfigTree;
use Torrus::Log;
use Torrus::TimeStamp;

sub beforeRun
{
    my $self = shift;

    my $tree = $self->treeName();
    my $config_tree = new Torrus::ConfigTree(-TreeName => $tree, -Wait => 1);
    if( not defined( $config_tree ) )
    {
        return undef;
    }

    my $data = $self->data();

    # Prepare the list of tokens, sorted by period and offset,
    # from config tree or from cache.

    my $need_new_tasks = 0;

    Torrus::TimeStamp::init();
    my $known_ts = Torrus::TimeStamp::get($tree . ':monitor_cache');
    my $actual_ts = $config_tree->getTimestamp();
    if( $actual_ts >= $known_ts )
    {
        if( defined($self->{'delay'}) and $self->{'delay'} > 0 )
        {
            Info(sprintf('Delaying for %d seconds', $self->{'delay'}));
            sleep( $self->{'delay'} );
        }

        Info("Rebuilding monitor cache");
        Debug("Config TS: $actual_ts, Monitor TS: $known_ts");

        undef $data->{'targets'};
        $need_new_tasks = 1;

        $data->{'db_tokens'} = new Torrus::DB( 'monitor_tokens',
                                               -Subdir => $tree,
                                               -WriteAccess => 1,
                                               -Truncate    => 1 );
        $self->cacheMonitors( $config_tree, $config_tree->token('/') );
        # explicitly close, since we don't need it often, and sometimes
        # open it in read-only mode
        $data->{'db_tokens'}->closeNow();
        undef $data->{'db_tokens'};

        # Set the timestamp
        &Torrus::TimeStamp::setNow($tree . ':monitor_cache');
    }
    Torrus::TimeStamp::release();

    &Torrus::DB::checkInterrupted();

    if( not $need_new_tasks and not defined $data->{'targets'} )
    {
        $need_new_tasks = 1;

        $data->{'db_tokens'} = new Torrus::DB('monitor_tokens',
                                              -Subdir => $tree);
        my $cursor = $data->{'db_tokens'}->cursor();
        while( my ($token, $schedule) = $data->{'db_tokens'}->next($cursor) )
        {
            my ($period, $offset, $mlist) = split(':', $schedule);
            if( not exists( $data->{'targets'}{$period}{$offset} ) )
            {
                $data->{'targets'}{$period}{$offset} = [];
            }
            push( @{$data->{'targets'}{$period}{$offset}}, $token );
            $data->{'mlist'}{$token} = [];
            push( @{$data->{'mlist'}{$token}}, split(',', $mlist) );
        }
        $data->{'db_tokens'}->c_close($cursor);
        undef $cursor;
        $data->{'db_tokens'}->closeNow();
        undef $data->{'db_tokens'};
    }

    &Torrus::DB::checkInterrupted();

    # Now fill in Scheduler's task list, if needed

    if( $need_new_tasks )
    {
        Verbose("Initializing tasks");
        my $init_start = time();
        $self->flushTasks();

        foreach my $period ( keys %{$data->{'targets'}} )
        {
            foreach my $offset ( keys %{$data->{'targets'}{$period}} )
            {
                my $monitor = new Torrus::Monitor( -Period => $period,
                                                   -Offset => $offset,
                                                   -TreeName => $tree,
                                                   -SchedData => $data );

                foreach my $token ( @{$data->{'targets'}{$period}{$offset}} )
                {
                    &Torrus::DB::checkInterrupted();
                    
                    $monitor->addTarget( $config_tree, $token );
                }

                $self->addTask( $monitor );
            }
        }
        Verbose(sprintf("Tasks initialization finished in %d seconds",
                        time() - $init_start));
    }

    Verbose("Monitor initialized");

    return 1;
}


sub cacheMonitors
{
    my $self = shift;
    my $config_tree = shift;
    my $ptoken = shift;

    my $data = $self->data();

    foreach my $ctoken ( $config_tree->getChildren( $ptoken ) )
    {
        &Torrus::DB::checkInterrupted();

        if( $config_tree->isSubtree( $ctoken ) )
        {
            $self->cacheMonitors( $config_tree, $ctoken );
        }
        elsif( $config_tree->isLeaf( $ctoken ) and
               ( $config_tree->getNodeParam($ctoken, 'ds-type') ne
                 'rrd-multigraph') )
        {
            my $mlist = $config_tree->getNodeParam( $ctoken, 'monitor' );
            if( defined $mlist )
            {
                my $period = sprintf('%d',
                                     $config_tree->getNodeParam
                                     ( $ctoken, 'monitor-period' ) );
                my $offset = sprintf('%d',
                                     $config_tree->getNodeParam
                                     ( $ctoken, 'monitor-timeoffset' ) );
                
                $data->{'db_tokens'}->put( $ctoken,
                                           $period.':'.$offset.':'.$mlist );
                
                push( @{$data->{'targets'}{$period}{$offset}}, $ctoken );
                $data->{'mlist'}{$ctoken} = [];
                push( @{$data->{'mlist'}{$ctoken}}, split(',', $mlist) );
            }
        }
    }
}


1;


# Local Variables:
# mode: perl
# indent-tabs-mode: nil
# perl-indent-level: 4
# End:
