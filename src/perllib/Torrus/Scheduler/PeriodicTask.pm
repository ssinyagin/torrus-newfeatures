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


# Periodic task base class
# Options:
#   -Period   => seconds    -- cycle period
#   -Offset   => seconds    -- time offset from even period moments
#   -Name     => "string"   -- Symbolic name for log messages
#   -Instance => N          -- instance number
#   -FastCycles => N        -- optional number of cycles to run immediately

package Torrus::Scheduler::PeriodicTask;
use strict;
use warnings;

use Torrus::Log;

sub new
{
    my $self = {};
    my $class = shift;
    my %options = @_;
    bless $self, $class;

    if( not defined( $options{'-Instance'} ) )
    {
        $options{'-Instance'} = 0;
    }

    %{$self->{'options'}} = %options;

    $self->{'options'}{'-Period'} = 0 unless
        defined( $self->{'options'}{'-Period'} );

    $self->{'options'}{'-Offset'} = 0 unless
        defined( $self->{'options'}{'-Offset'} );
        
    $self->{'options'}{'-Name'} = "PeriodicTask" unless
        defined( $self->{'options'}{'-Name'} );

    $self->{'options'}{'-FastCycles'} = 0 unless
        defined($self->{'options'}{'-FastCycles'});
    
    $self->{'missedPeriods'} = 0;

    $self->{'options'}{'-Started'} = time();

    # Array of (Name, Value) pairs for any kind of stats    
    $self->{'statValues'} = [];

    # counter of passed cycles 
    $self->{'cycles'} = 0;
    
    Debug("New Periodic Task created: period=" .
          $self->{'options'}{'-Period'} .
          " offset=" . $self->{'options'}{'-Offset'});

    return $self;
}


sub whenNext
{
    my $self = shift;

    if( $self->period() > 0 )
    {
        my $now = time();
        
        if( not $self->initialized() )
        {
            # Repeat immediately  (after a small pause)
            # as many cycles as required at start
            return $now + 2;
        }

        my $period = $self->period();
        my $offset = $self->offset();
        my $previous;

        if( defined $self->{'previousSchedule'} )
        {
            if( $now - $self->{'previousSchedule'} <= $period )
            {
                $previous = $self->{'previousSchedule'};
            }
            elsif( not $Torrus::Scheduler::ignoreClockSkew )
            {
                Error('Last run of ' . $self->{'options'}{'-Name'} .
                      ' was more than ' . $period . ' seconds ago');
                $self->{'missedPeriods'} =
                    int( ($now - $self->{'previousSchedule'}) / $period );
            }
        }
        if( not defined( $previous ) )
        {
            $previous = $now - ($now % $period) + $offset;
        }

        my $whenNext = $previous + $period;
        $self->{'previousSchedule'} = $whenNext;
        
        Debug("Task ". $self->{'options'}{'-Name'}.
              " wants to run next time at " . scalar(localtime($whenNext)));
        return $whenNext;
    }
    else
    {
        return undef;
    }
}


sub beforeRun
{
    my $self = shift;
    my $stats = shift;

    Verbose(sprintf('%s periodic task started. Period: %d:%.2d; ' .
                    'Offset: %d:%.2d',
                    $self->name(),
                    int( $self->period() / 60 ), $self->period() % 60,
                    int( $self->offset() / 60 ), $self->offset() % 60));
    return;
}


sub afterRun
{
    my $self = shift;
    my $stats = shift;
    my $startTime = shift;

    $self->{'cycles'}++;

    my $len = time() - $startTime;
    if( $len > $self->period() )
    {
        Warn(sprintf('%s task execution (%d) longer than period (%d)',
                     $self->name(), $len, $self->period()));
        
        $stats->setStatsValues( $self->id(), 'TooLong', $len );
        $stats->incStatsCounter( $self->id(), 'OverrunPeriods',
                                 int( $len > $self->period() ) );
    }

    if( $self->{'missedPeriods'} > 0 )
    {
        $stats->incStatsCounter( $self->id(), 'MissedPeriods',
                                 $self->{'missedPeriods'} );
        $self->{'missedPeriods'} = 0;
    }

    foreach my $pair( @{$self->{'statValues'}} )
    {
        $stats->setStatsValues( $self->id(), @{$pair} );
    }
    $self->{'statValues'} = [];
    return;
}


sub run
{
    my $self = shift;
    Error("Dummy class Torrus::Scheduler::PeriodicTask was run");
    return;
}


sub period
{
    my $self = shift;
    return $self->{'options'}->{'-Period'};
}


sub offset
{
    my $self = shift;
    return $self->{'options'}->{'-Offset'};
}


sub didNotRun
{
    my $self = shift;
    return( not defined( $self->{'previousSchedule'} ) );
}

sub initialized
{
    my $self = shift;
    return ($self->{'cycles'} >= $self->{'options'}{'-FastCycles'});
}

sub name
{
    my $self = shift;
    return $self->{'options'}->{'-Name'};
}

sub instance
{
    my $self = shift;
    return $self->{'options'}->{'-Instance'};
}


sub whenStarted
{
    my $self = shift;
    return $self->{'options'}->{'-Started'};
}


sub id
{
    my $self = shift;
    return join(':', 'P', $self->name(), $self->instance(),
                $self->period(), $self->offset());
}

sub setStatValue
{
    my $self = shift;
    my $name = shift;
    my $value = shift;

    push( @{$self->{'statValues'}}, [$name, $value] );
    return;
}

1;


# Local Variables:
# mode: perl
# indent-tabs-mode: nil
# perl-indent-level: 4
# End:
