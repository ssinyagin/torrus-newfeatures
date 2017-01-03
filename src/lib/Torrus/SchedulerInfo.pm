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


# Task scheduler runtime information. Quite basic statistics access.

package Torrus::SchedulerInfo;

use strict;
use warnings;

use Redis;
use Torrus::Log;

sub new
{
    my $self = {};
    my $class = shift;
    my %options = @_;
    bless $self, $class;

    %{$self->{'options'}} = %options;

    die() if not defined( $options{'-Tree'} );

    $self->{'redis'} = Redis->new(server => $Torrus::Global::redisServer);
    $self->{'redis_hname'} =
        $Torrus::Global::redisPrefix . 'scheduler_stats:' . $options{'-Tree'};

    return $self;
}



sub readStats
{
    my $self = shift;

    my $stats = {};

    my $all = $self->{'redis'}->hgetall($self->{'redis_hname'});
    while( scalar(@{$all}) > 0 )
    {
        my $key = shift @{$all};
        my $value = shift @{$all};
        
        my( $id, $variable ) = split( '#', $key );
        if( defined( $id ) and defined( $variable ) )
        {
            $stats->{$id}{$variable} = $value;
        }
    }

    return $stats;
}


sub setValue
{
    my $self = shift;
    my $id = shift;
    my $variable = shift;
    my $value = shift;

    $self->{'redis'}->hset($self->{'redis_hname'},
                           join('#', $id, $variable), $value );
    return;
}

sub getValue
{
    my $self = shift;
    my $id = shift;
    my $variable = shift;
    
    return $self->{'redis'}->hget($self->{'redis_hname'},
                                  join('#', $id, $variable));
}


sub clearStats
{
    my $self = shift;
    my $id = shift;

    my $all = $self->{'redis'}->hgetall($self->{'redis_hname'});
    while( scalar(@{$all}) > 0 )
    {
        my $key = shift @{$all};
        my $value = shift @{$all};
        
        my( $db_id, $variable ) = split( '#', $key );
        if( defined( $db_id ) and defined( $variable ) and
            $id eq $db_id )
        {
            $self->{'redis'}->hdel($self->{'redis_hname'}, $key);
        }
    }
    return;
}


sub clearAll
{
    my $self = shift;
    $self->{'redis'}->del($self->{'redis_hname'});
    return;
}


sub setStatsValues
{
    my $self = shift;
    my $id = shift;
    my $variable = shift;
    my $value = shift;

    $self->setValue( $id, 'Last' . $variable, $value );

    my $maxName = 'Max' . $variable;
    my $maxVal = $self->getValue( $id, $maxName );
    if( not defined( $maxVal ) or $value > $maxVal )
    {
        $maxVal = $value;
    }
    $self->setValue( $id, $maxName, $maxVal );

    my $minName = 'Min' . $variable;
    my $minVal = $self->getValue( $id, $minName );
    if( not defined( $minVal ) or $value < $minVal )
    {
        $minVal = $value;
    }
    $self->setValue( $id, $minName, $minVal );

    my $timesName = 'NTimes' . $variable;
    my $nTimes = $self->getValue( $id, $timesName );

    my $avgName = 'Avg' . $variable;
    my $average = $self->getValue( $id, $avgName );

    if( not defined( $nTimes ) )
    {
        $nTimes = 1;
        $average = $value;
    }
    else
    {
        $average = ( $average * $nTimes + $value ) / ( $nTimes + 1 );
        $nTimes++;
    }
    $self->setValue( $id, $timesName, $nTimes );
    $self->setValue( $id, $avgName, $average );

    my $expAvgName = 'ExpAvg' . $variable;
    my $expAverage = $self->getValue( $id, $expAvgName );
    if( not defined( $expAverage ) )
    {
        $expAverage = $value;
    }
    else
    {
        my $alpha = $Torrus::Scheduler::statsExpDecayAlpha;
        $expAverage = $alpha * $value + ( 1 - $alpha ) * $expAverage;
    }
    $self->setValue( $id, $expAvgName, $expAverage );
    return;
}


sub incStatsCounter
{
    my $self = shift;
    my $id = shift;
    my $variable = shift;
    my $increment = shift;

    if( not defined( $increment ) )
    {
        $increment = 1;
    }

    my $name = 'Count' . $variable;
    my $previous = $self->getValue( $id, $name );

    if( not defined( $previous ) )
    {
        $previous = 0;
    }
    
    $self->setValue( $id, $name, $previous + $increment );
    return;
}



1;


# Local Variables:
# mode: perl
# indent-tabs-mode: nil
# perl-indent-level: 4
# End:
