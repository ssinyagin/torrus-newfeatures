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

# $Id$
# Stanislav Sinyagin <ssinyagin@yahoo.com>


package Torrus::Collector;
use strict;

@Torrus::Collector::ISA = qw(Torrus::Scheduler::PeriodicTask);

use Torrus::ConfigTree;
use Torrus::Log;
use Torrus::RPN;
use Torrus::Scheduler;

our $VERSION = 1.0;

BEGIN
{
    for my $mod ( @Torrus::Collector::loadModules )
    {
        eval "require $mod";
        die( $@ ) if $@;
    }
}

# Executed once after the fork. Here modules can launch processing threads
sub initThreads
{
    for my $key ( %Torrus::Collector::initThreadsHandlers )
    {
        if( ref( $Torrus::Collector::initThreadsHandlers{$key} ) )
        {
            &{$Torrus::Collector::initThreadsHandlers{$key}}();
        }
    }
}


our %collectorTypes;

## One collector module instance holds all leaf tokens which
## must be collected at the same time.

sub new
{
    my $proto = shift;
    my %options = @_;

    if( not $options{'-Name'} )
    {
        $options{'-Name'} = "Collector";
    }

    # Repeat so many cycles immediately at start
    if( $Torrus::Collector::fastCycles > 0 )
    {
        $options{'-FastCycles'} = $Torrus::Collector::fastCycles;
    }

    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new( %options );
    bless $self, $class;

    $self->{'types_sorted'} = [];

    for my $collector_type
        ( sort {$collectorTypes{$a} <=> $collectorTypes{$b}}
          keys %collectorTypes )
    {
        $self->{'types'}{$collector_type} = {};
        $self->{'types_in_use'}{$collector_type} = 0;
        push(@{$self->{'types_sorted'}}, $collector_type);
    }

    for my $storage_type ( keys %Torrus::Collector::storageTypes )
    {
        $self->{'storage'}{$storage_type} = {};
        $self->{'storage_in_use'}{$storage_type} = 0;

        my $storage_string = $storage_type . '-storage';
        if( ref( $Torrus::Collector::initStorage{$storage_string} ) )
        {
            &{$Torrus::Collector::initStorage{$storage_string}}($self);
        }
    }

    $self->{'tree_name'} = $options{'-TreeName'};

    return $self;
}


sub addTarget
{
    my $self = shift;
    my $config_tree = shift;
    my $token = shift;

    my $ok = 1;
    $self->{'targets'}{$token}{'path'} = $config_tree->path($token);

    my $collector_type = $config_tree->getNodeParam($token, 'collector-type');
    if( not $collectorTypes{$collector_type} )
    {
        Error('Unknown collector type: ' . $collector_type);
        return;
    }

    $self->fetchParams($config_tree, $token, $collector_type);

    $self->{'targets'}{$token}{'type'} = $collector_type;
    $self->{'types_in_use'}{$collector_type} = 1;

    my $storage_types = $config_tree->getNodeParam($token, 'storage-type');
    for my $storage_type ( split( ',', $storage_types ) )
    {
        if( not $Torrus::Collector::storageTypes{$storage_type} )
        {
            Error('Unknown storage type: ' . $storage_type);
        }
        else
        {
            my $storage_string = $storage_type . '-storage';
            if( not exists( $self->{'targets'}{$token}{'storage-types'} ) )
            {
                $self->{'targets'}{$token}{'storage-types'} = [];
            }
            push( @{$self->{'targets'}{$token}{'storage-types'}},
                  $storage_type );

            $self->fetchParams($config_tree, $token, $storage_string);
            $self->{'storage_in_use'}{$storage_type} = 1;
        }
    }

    # If specified, store the value transformation code
    my $code = $config_tree->getNodeParam($token, 'transform-value');
    if( defined $code )
    {
        $self->{'targets'}{$token}{'transform'} = $code;
    }

    # If specified, store the scale RPN
    my $scalerpn = $config_tree->getNodeParam($token, 'collector-scale');
    if( defined $scalerpn )
    {
        $self->{'targets'}{$token}{'scalerpn'} = $scalerpn;
    }

    # If specified, store the value map
    my $valueMap = $config_tree->getNodeParam($token, 'value-map');
    if( defined $valueMap and length($valueMap) > 0 )
    {
        my $map = {};
        for my $item ( split( ',', $valueMap ) )
        {
            my ($key, $value) = split( ':', $item );
            $map->{$key} = $value;
        }
        $self->{'targets'}{$token}{'value-map'} = $map;
    }

    # Initialize local token, collectpor, and storage data
    if( not defined $self->{'targets'}{$token}{'local'} )
    {
        $self->{'targets'}{$token}{'local'} = {};
    }

    if( ref( $Torrus::Collector::initTarget{$collector_type} ) )
    {
        $ok = &{$Torrus::Collector::initTarget{$collector_type}}($self,
                                                                 $token);
    }

    if( $ok )
    {
        for my $storage_type
            ( @{$self->{'targets'}{$token}{'storage-types'}} )
        {
            my $storage_string = $storage_type . '-storage';
            if( ref( $Torrus::Collector::initTarget{$storage_string} ) )
            {
                &{$Torrus::Collector::initTarget{$storage_string}}($self,
                                                                   $token);
            }
        }
    }

    if( not $ok )
    {
        $self->deleteTarget( $token );
    }
}


sub fetchParams
{
    my $self = shift;
    my $config_tree = shift;
    my $token = shift;
    my $type = shift;

    if( not defined( $Torrus::Collector::params{$type} ) )
    {
        Error("\%Torrus::Collector::params does not have member $type");
        return;
    }

    my $ref = \$self->{'targets'}{$token}{'params'};

    my @maps = ( $Torrus::Collector::params{$type} );

    while( scalar( @maps ) > 0 )
    {
        &Torrus::DB::checkInterrupted();

        my @next_maps = ();
        for my $map ( @maps )
        {
            for my $param ( keys %{$map} )
            {
                my $value = $config_tree->getNodeParam( $token, $param );

                if( ref( $map->{$param} ) )
                {
                    if( defined $value )
                    {
                        if( exists $map->{$param}->{$value} )
                        {
                            if( defined $map->{$param}->{$value} )
                            {
                                push( @next_maps,
                                      $map->{$param}->{$value} );
                            }
                        }
                        else
                        {
                            Error("Parameter $param has unknown value: " .
                                  $value . " in " . $self->path($token));
                        }
                    }
                }
                else
                {
                    if( not defined $value )
                    {
                        # We know the default value
                        $value = $map->{$param};
                    }
                }
                # Finally store the value
                if( defined $value )
                {
                    $$ref->{$param} = $value;
                }
            }
        }
        @maps = @next_maps;
    }
}


sub fetchMoreParams
{
    my $self = shift;
    my $config_tree = shift;
    my $token = shift;
    my @params = @_;

    &Torrus::DB::checkInterrupted();

    my $ref = \$self->{'targets'}{$token}{'params'};

    for my $param ( @params )
    {
        my $value = $config_tree->getNodeParam( $token, $param );
        if( defined $value )
        {
            $$ref->{$param} = $value;
        }
    }
}


sub param
{
    my $self = shift;
    my $token = shift;
    my $param = shift;

    return $self->{'targets'}{$token}{'params'}{$param};
}

sub setParam
{
    my $self = shift;
    my $token = shift;
    my $param = shift;
    my $value = shift;

    $self->{'targets'}{$token}{'params'}{$param} = $value;
}


sub path
{
    my $self = shift;
    my $token = shift;

    return $self->{'targets'}{$token}{'path'};
}

sub listCollectorTargets
{
    my $self = shift;
    my $collector_type = shift;

    my @ret;
    for my $token ( keys %{$self->{'targets'}} )
    {
        if( $self->{'targets'}{$token}{'type'} eq $collector_type )
        {
            push( @ret, $token );
        }
    }
    return @ret;
}

# A callback procedure that will be executed on deleteTarget()

sub registerDeleteCallback
{
    my $self = shift;
    my $token = shift;
    my $proc = shift;

    if( not ref( $self->{'targets'}{$token}{'deleteProc'} ) )
    {
        $self->{'targets'}{$token}{'deleteProc'} = [];
    }
    push( @{$self->{'targets'}{$token}{'deleteProc'}}, $proc );
}

sub deleteTarget
{
    my $self = shift;
    my $token = shift;

    &Torrus::DB::checkInterrupted();

    Info('Deleting target: ' . $self->path($token));

    if( ref( $self->{'targets'}{$token}{'deleteProc'} ) )
    {
        for my $proc ( @{$self->{'targets'}{$token}{'deleteProc'}} )
        {
            &{$proc}( $self, $token );
        }
    }
    delete $self->{'targets'}{$token};
}

# Returns a reference to token-specific local data

sub tokenData
{
    my $self = shift;
    my $token = shift;

    return $self->{'targets'}{$token}{'local'};
}

# Returns a reference to collector type-specific local data

sub collectorData
{
    my $self = shift;
    my $type = shift;

    return $self->{'types'}{$type};
}

# Returns a reference to storage type-specific local data

sub storageData
{
    my $self = shift;
    my $type = shift;

    return $self->{'storage'}{$type};
}


# Runs each collector type, and then stores the values
sub run
{
    my $self = shift;

    undef $self->{'values'};

    for my $collector_type ( @{$self->{'types_sorted'}} )
    {
        next unless $self->{'types_in_use'}{$collector_type};

        &Torrus::DB::checkInterrupted();

        if( $Torrus::Collector::needsConfigTree
            {$collector_type}{'runCollector'} )
        {
            $self->{'config_tree'} =
                Torrus::ConfigTree->new( -TreeName => $self->{'tree_name'},
                                        -Wait => 1 );
        }

        &{$Torrus::Collector::runCollector{$collector_type}}
        ( $self, $self->collectorData($collector_type) );

        if( defined( $self->{'config_tree'} ) )
        {
            undef $self->{'config_tree'};
        }
    }

    while( my ($storage_type, $ref) = each %{$self->{'storage'}} )
    {
        next unless $self->{'storage_in_use'}{$storage_type};

        &Torrus::DB::checkInterrupted();

        if( $Torrus::Collector::needsConfigTree
            {$storage_type}{'storeData'} )
        {
            $self->{'config_tree'} =
                Torrus::ConfigTree->new( -TreeName => $self->{'tree_name'},
                                        -Wait => 1 );
        }

        &{$Torrus::Collector::storeData{$storage_type}}( $self, $ref );

        if( defined( $self->{'config_tree'} ) )
        {
            undef $self->{'config_tree'};
        }
    }

    while( my ($collector_type, $ref) = each %{$self->{'types'}} )
    {
        next unless $self->{'types_in_use'}{$collector_type};

        if( ref( $Torrus::Collector::postProcess{$collector_type} ) )
        {
            &Torrus::DB::checkInterrupted();

            if( $Torrus::Collector::needsConfigTree
                {$collector_type}{'postProcess'} )
            {
                $self->{'config_tree'} =
                    Torrus::ConfigTree->new( -TreeName => $self->{'tree_name'},
                                            -Wait => 1 );
            }

            &{$Torrus::Collector::postProcess{$collector_type}}( $self, $ref );

            if( defined( $self->{'config_tree'} ) )
            {
                undef $self->{'config_tree'};
            }
        }
    }
}


# This procedure is called by the collector type-specific functions
# every time there's a new value for a token
sub setValue
{
    my $self = shift;
    my $token = shift;
    my $value = shift;
    my $timestamp = shift;
    my $uptime = shift;

    if( $value ne 'U' )
    {
        if( defined( my $code = $self->{'targets'}{$token}{'transform'} ) )
        {
            # Screen out the percent sign and $_
            $code =~ s/DOLLAR/\$/gm;
            $code =~ s/MOD/\%/gm;
            Debug('Value before transformation: ' . $value);
            $_ = $value;
            $value = do { eval $code };
            if( $@ )
            {
                Error('Fatal error in transformation code: ' . $@ );
                $value = 'U';
            }
            elsif( $value !~ /^[0-9.+-eE]+$/o and $value ne 'U' )
            {
                Error('Non-numeric value after transformation: ' . $value);
                $value = 'U';
            }
        }
        elsif( defined( my $map = $self->{'targets'}{$token}{'value-map'} ) )
        {
            my $newValue;
            if( defined( $map->{$value} ) )
            {
                $newValue = $map->{$value};
            }
            elsif( defined( $map->{'_'} ) )
            {
                $newValue = $map->{'_'};
            }
            else
            {
                Warn('Could not find value mapping for ' . $value .
                     'in ' . $self->path($token));
            }

            if( defined( $newValue ) )
            {
                Debug('Value mapping: ' . $value . ' -> ' . $newValue);
                $value = $newValue;
            }
        }

        if( defined( $self->{'targets'}{$token}{'scalerpn'} ) )
        {
            Debug('Value before scaling: ' . $value);
            my $rpn = Torrus::RPN->new();
            $value = $rpn->run( $value . ',' .
                                $self->{'targets'}{$token}{'scalerpn'},
                                sub{} );
        }
    }

    if( isDebug() )
    {
        Debug('Value ' . $value . ' set for ' .
              $self->path($token) . ' TS=' . $timestamp);
    }

    for my $storage_type
        ( @{$self->{'targets'}{$token}{'storage-types'}} )
    {
        &{$Torrus::Collector::setValue{$storage_type}}( $self, $token,
                                                        $value, $timestamp,
                                                        $uptime );
    }
}


sub configTree
{
    my $self = shift;

    if( defined( $self->{'config_tree'} ) )
    {
        return $self->{'config_tree'};
    }
    else
    {
        Error('Cannot provide ConfigTree object');
        return
    }
}


#######  Collector scheduler  ########

package Torrus::CollectorScheduler;
@Torrus::CollectorScheduler::ISA = qw(Torrus::Scheduler);

use Torrus::ConfigTree;
use Torrus::Log;
use Torrus::Scheduler;
use Torrus::TimeStamp;


sub beforeRun
{
    my $self = shift;

    &Torrus::DB::checkInterrupted();

    my $tree = $self->treeName();
    my $config_tree = Torrus::ConfigTree->new(-TreeName => $tree, -Wait => 1);
    if( not defined( $config_tree ) )
    {
        return
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
                Torrus::DB->new( 'collector_lock', -WriteAccess => 1 );
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

        for my $period ( keys %{$targets} )
        {
            for my $offset ( keys %{$targets->{$period}} )
            {
                my $collector =
                    Torrus::Collector->new( -Period => $period,
                                           -Offset => $offset,
                                           -TreeName => $tree,
                                           -Instance => $instance );

                for my $token ( @{$targets->{$period}{$offset}} )
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

        for my $collector_type ( keys %Torrus::Collector::collectorTypes )
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
