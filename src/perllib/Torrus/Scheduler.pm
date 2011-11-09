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


# Task scheduler.
# Task object MUST implement two methods:
# run() -- the running cycle
# whenNext() -- returns the next time it must be run.
# See also: Torrus::Scheduler::PeriodicTask class definition
#
# Options:
#   -Tree        => tree name
#   -ProcessName => process name and commandline options
#   -RunOnce     => 1       -- this prevents from infinite loop.   


package Torrus::Scheduler;

use strict;
use warnings;
use Torrus::SchedulerInfo;
use Torrus::Log;

sub new
{
    my $self = {};
    my $class = shift;
    my %options = @_;
    bless $self, $class;

    %{$self->{'options'}} = %options;
    %{$self->{'data'}} = ();

    if( not defined( $options{'-Tree'} ) or
        not defined( $options{'-ProcessName'} ) )
    {
        die();
    }

    $self->{'stats'} = new Torrus::SchedulerInfo( -Tree => $options{'-Tree'},
                                                  -WriteAccess => 1 );    
    return $self;
}


sub DESTROY
{
    my $self = shift;
    delete $self->{'stats'};
}

sub treeName
{
    my $self = shift;
    return $self->{'options'}{'-Tree'};
}

sub setProcessStatus
{
    my $self = shift;
    my $text = shift;
    $0 = $self->{'options'}{'-ProcessName'} . ' [' . $text . ']';
}

sub addTask
{
    my $self = shift;
    my $task = shift;
    my $when = shift;

    if( not defined $when )
    {
        # If not specified, run immediately
        $when = time() - 1;
    }
    $self->storeTask( $task, $when );
    $self->{'stats'}->clearStats( $task->id() );
}


sub storeTask
{
    my $self = shift;
    my $task = shift;
    my $when = shift;

    if( not defined( $self->{'tasks'}{$when} ) )
    {
        $self->{'tasks'}{$when} = [];
    }
    push( @{$self->{'tasks'}{$when}}, $task );
}
    

sub flushTasks
{
    my $self = shift;

    if( defined( $self->{'tasks'} ) )
    {
        foreach my $when ( keys %{$self->{'tasks'}} )
        {
            foreach my $task ( @{$self->{'tasks'}{$when}} )
            {
                $self->{'stats'}->clearStats( $task->id() );
            }
        }
        undef $self->{'tasks'};
    }
}


sub run
{
    my $self = shift;

    my $stop = 0;

    while( not $stop )
    {
        $self->setProcessStatus('initializing scheduler');
        while( not $self->beforeRun() )
        {
            &Torrus::DB::checkInterrupted();
            
            Error('Scheduler initialization error. Sleeping ' .
                  $Torrus::Scheduler::failedInitSleep . ' seconds');

            &Torrus::DB::setUnsafeSignalHandlers();
            sleep($Torrus::Scheduler::failedInitSleep);
            &Torrus::DB::setSafeSignalHandlers();
        }
        $self->setProcessStatus('');
        my $nextRun = time() + 3600;
        foreach my $when ( keys %{$self->{'tasks'}} )
        {
            # We have 1-second rounding error
            if( $when <= time() + 1 )
            {
                foreach my $task ( @{$self->{'tasks'}{$when}} )
                {
                    &Torrus::DB::checkInterrupted();
                    
                    my $startTime = time();

                    $self->beforeTaskRun( $task, $startTime, $when );
                    $task->beforeRun( $self->{'stats'} );

                    $self->setProcessStatus('running');
                    $task->run();                    
                    $task->afterRun( $self->{'stats'}, $startTime );
                    $self->afterTaskRun( $task, $startTime );

                    my $whenNext = $task->whenNext();
                    
                    if( $whenNext > 0 )
                    {
                        if( $whenNext == $when )
                        {
                            Error("Incorrect time returned by task");
                        }
                        $self->storeTask( $task, $whenNext );
                        if( $nextRun > $whenNext )
                        {
                            $nextRun = $whenNext;
                        }
                    }
                }
                delete $self->{'tasks'}{$when};
            }
            elsif( $nextRun > $when )
            {
                $nextRun = $when;
            }
        }

        if( $self->{'options'}{'-RunOnce'} or
            ( scalar( keys %{$self->{'tasks'}} ) == 0 and
              not $self->{'options'}{'-RunAlways'} ) )
        {
            $self->setProcessStatus('');
            $stop = 1;
        }
        else
        {
            if( scalar( keys %{$self->{'tasks'}} ) == 0 )
            {
                Info('Tasks list is empty. Will sleep until ' .
                     scalar(localtime($nextRun)));
            }

            $self->setProcessStatus('sleeping');
            &Torrus::DB::setUnsafeSignalHandlers();            
            Debug('We will sleep until ' . scalar(localtime($nextRun)));
            
            if( $Torrus::Scheduler::maxSleepTime > 0 )
            {
                Debug('This is a VmWare-like clock. We devide the sleep ' .
                      'interval into small pieces');
                while( time() < $nextRun )
                {
                    my $sleep = $nextRun - time();
                    if( $sleep > $Torrus::Scheduler::maxSleepTime )
                    {
                        $sleep = $Torrus::Scheduler::maxSleepTime;
                    }
                    Debug('Sleeping ' . $sleep . ' seconds');
                    sleep( $sleep );
                }
            }
            else
            {
                my $sleep = $nextRun - time();
                if( $sleep > 0 )
                {
                    sleep( $sleep );
                }
            }

            &Torrus::DB::setSafeSignalHandlers();
        }
    }
}


# A method to override by ancestors. Executed every time before the
# running cycle. Must return true value when finishes.
sub beforeRun
{
    my $self = shift;
    Debug('Torrus::Scheduler::beforeRun() - doing nothing');
    return 1;
}


sub beforeTaskRun
{
    my $self = shift;
    my $task = shift;
    my $startTime = shift;
    my $plannedStartTime = shift;

    if( (not $task->didNotRun()) and
        $task->initialized() and
        $startTime > $plannedStartTime + 1 )
    {
        my $late = $startTime - $plannedStartTime;
        Verbose(sprintf('Task delayed %d seconds', $late));
        $self->{'stats'}->setStatsValues( $task->id(), 'LateStart', $late );
    }
}


sub afterTaskRun
{
    my $self = shift;
    my $task = shift;
    my $startTime = shift;

    my $len = time() - $startTime;
    Verbose(sprintf('%s task finished in %d seconds', $task->name(), $len));
    
    $self->{'stats'}->setStatsValues( $task->id(), 'RunningTime', $len );
}


# User data can be stored here
sub data
{
    my $self = shift;
    return $self->{'data'};
}


1;


# Local Variables:
# mode: perl
# indent-tabs-mode: nil
# perl-indent-level: 4
# End:
