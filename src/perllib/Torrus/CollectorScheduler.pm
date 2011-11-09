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

# Stanislav Sinyagin <ssinyagin@yahoo.com>



#######  Collector scheduler  ########

package Torrus::CollectorScheduler;
use strict;
use warnings;

use base 'Torrus::Scheduler';

use Torrus::ConfigTree;
use Torrus::Log;
use Torrus::TimeStamp;


sub beforeRun
{
    my $self = shift;

    &Torrus::DB::checkInterrupted();

    my $tree = $self->treeName();
    my $config_tree = new Torrus::ConfigTree(-TreeName => $tree, -Wait => 1);
    if( not defined( $config_tree ) )
    {
        return undef;
    }

    my $data = $self->data();

    my $instance = $self->{'options'}{'-Instance'};
        
    # Prepare the list of tokens, sorted by period and offset,
    # from config tree or from cache.

    my $need_new_tasks = 0;

    Torrus::TimeStamp::init();
    my $timestamp_key = $tree . ':' . $instance . ':collector_cache';
    my $known_ts = Torrus::TimeStamp::get( $timestamp_key );
    my $actual_ts = $config_tree->getTimestamp();
    
    if( $actual_ts >= $known_ts or not $data->{'targets_initialized'} )
    {
        my $db_lock;
        my $cursor_lock;
        if( $Torrus::Collector::exclusiveStartupLock )
        {
            Info('Acquiring an exclusive lock for configuration slurp');
            $db_lock =
                new Torrus::DB( 'collector_lock', -WriteAccess => 1 );        
            $cursor_lock = $db_lock->cursor( -Write => 1 );
        }
        
        Info('Initializing tasks for collector instance ' . $instance);
        Debug("Config TS: $actual_ts, Collector TS: $known_ts");
        my $init_start = time();

        my $targets = {};

        my $db_tokens =
            new Torrus::DB('collector_tokens' . '_' . $instance . '_' .
                           $config_tree->{'ds_config_instance'},
                           -Subdir => $tree);
        
        my $cursor = $db_tokens->cursor();
        while( my ($token, $schedule) = $db_tokens->next($cursor) )
        {
            my ($period, $offset) = split(/:/o, $schedule);
            if( not exists( $targets->{$period}{$offset} ) )
            {
                $targets->{$period}{$offset} = [];
            }
            push( @{$targets->{$period}{$offset}}, $token );

            &Torrus::DB::checkInterrupted();
        }
        $db_tokens->c_close($cursor);
        undef $cursor;
        $db_tokens->closeNow();
        undef $db_tokens;
        
        &Torrus::DB::checkInterrupted();

        # Set the timestamp
        &Torrus::TimeStamp::setNow( $timestamp_key );
        
        $self->flushTasks();

        foreach my $period ( keys %{$targets} )
        {
            foreach my $offset ( keys %{$targets->{$period}} )
            {
                my $collector =
                    new Torrus::Collector( -Period => $period,
                                           -Offset => $offset,
                                           -TreeName => $tree,
                                           -Instance => $instance );

                foreach my $token ( @{$targets->{$period}{$offset}} )
                {
                    &Torrus::DB::checkInterrupted();
                    $collector->addTarget( $config_tree, $token );
                }

                $self->addTask( $collector );
            }
        }

        if( $Torrus::Collector::exclusiveStartupLock )
        {
            $db_lock->c_close($cursor_lock);
            undef $cursor_lock;
            $db_lock->closeNow();
            undef $db_lock;
        }

        Verbose(sprintf("Tasks initialization finished in %d seconds",
                        time() - $init_start));

        $data->{'targets_initialized'} = 1;        
        Info('Tasks for collector instance ' . $instance . ' initialized');

        foreach my $collector_type ( keys %Torrus::Collector::collectorTypes )
        {
            if( ref($Torrus::Collector::initCollectorGlobals{
                $collector_type}) )
            {
                &{$Torrus::Collector::initCollectorGlobals{
                    $collector_type}}($tree, $instance);
                
                Verbose('Initialized collector globals for type: ' .
                        $collector_type);
            }
        }
    }
    
    Torrus::TimeStamp::release();
    
    return 1;
}


1;


# Local Variables:
# mode: perl
# indent-tabs-mode: nil
# perl-indent-level: 4
# End:
