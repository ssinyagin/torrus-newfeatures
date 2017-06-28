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


package Torrus::Collector;
use strict;
use warnings;

use base 'Torrus::Scheduler::PeriodicTask';

use Torrus::ConfigTree;
use Torrus::Log;
use Torrus::RPN;

BEGIN
{
    foreach my $mod ( @Torrus::Collector::loadModules )
    {
        if( not eval('require ' . $mod) or $@ )
        {
            die($@);
        }
    }
}

# Executed once after the fork. Here modules can launch processing threads
sub initThreads
{
    foreach my $key ( %Torrus::Collector::initThreadsHandlers )
    {
        if( ref( $Torrus::Collector::initThreadsHandlers{$key} ) )
        {
            &{$Torrus::Collector::initThreadsHandlers{$key}}();
        }
    }
    return;
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
    
    foreach my $collector_type
        ( sort {$collectorTypes{$a} <=> $collectorTypes{$b}}
          keys %collectorTypes )
    {
        $self->{'types'}{$collector_type} = {};
        $self->{'types_in_use'}{$collector_type} = 0;
        push(@{$self->{'types_sorted'}}, $collector_type);
    }

    foreach my $storage_type ( keys %Torrus::Collector::storageTypes )
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
    my $token = shift;
    my $params = shift;

    my $ok = 1;

    if( exists($self->{'targets'}{$token}) )
    {
        $self->deleteTarget($token);
    }
    
    $self->{'targets'}{$token}{'params'} = $params;

    my $collector_type = $self->param($token, 'collector-type');
    if( not $collectorTypes{$collector_type} )
    {
        Error('Unknown collector type: ' . $collector_type);
        return;
    }

    $self->{'targets'}{$token}{'type'} = $collector_type;
    $self->{'types_in_use'}{$collector_type} = 1;
    
    $self->{'targets'}{$token}{'storage-types'} = [];
    my $storage_types = $self->param($token, 'storage-type');
    foreach my $storage_type ( split( ',', $storage_types ) )
    {
        if( not $Torrus::Collector::storageTypes{$storage_type} )
        {
            Error('Unknown storage type: ' . $storage_type);
        }
        else
        {
            my $storage_string = $storage_type . '-storage';
            push( @{$self->{'targets'}{$token}{'storage-types'}},
                  $storage_type );
            $self->{'storage_in_use'}{$storage_type} = 1;
        }
    }

    # If specified, store the value transformation code
    my $code = $self->param($token, 'transform-value');
    if( defined $code )
    {
        $self->{'targets'}{$token}{'transform'} = $code;
    }
    
    # If specified, store the scale RPN
    my $scalerpn = $self->param($token, 'collector-scale');
    if( defined $scalerpn )
    {
        $self->{'targets'}{$token}{'scalerpn'} = $scalerpn;
    }
    
    # If specified, store the value map
    my $valueMap = $self->param($token, 'value-map');
    if( defined $valueMap and length($valueMap) > 0 )
    {
        my $map = {};
        foreach my $item ( split( ',', $valueMap ) )
        {
            my ($key, $value) = split( ':', $item );
            $map->{$key} = $value;
        }
        $self->{'targets'}{$token}{'value-map'} = $map;
    }

    # Initialize local token, collector, and storage data
    $self->{'targets'}{$token}{'local'} = {};
    
    if( ref( $Torrus::Collector::initTarget{$collector_type} ) )
    {
        $ok = &{$Torrus::Collector::initTarget{$collector_type}}(
            $self, $token);
    }

    if( $ok )
    {
        foreach my $storage_type
            ( @{$self->{'targets'}{$token}{'storage-types'}} )
        {
            my $storage_string = $storage_type . '-storage';
            if( ref( $Torrus::Collector::initTarget{$storage_string} ) )
            {
                $ok =
                    &{$Torrus::Collector::initTarget{
                        $storage_string}}($self, $token) ? $ok:0;
            }
        }
    }
    
    if( not $ok )
    {
        $self->deleteTarget( $token );
    }
    return;
}




sub param
{
    my $self = shift;
    my $token = shift;
    my $param = shift;

    return $self->{'targets'}{$token}{'params'}{$param};
}

# The following 3 methods get around undefined parameters and
# make "use warnings" happy

sub paramEnabled
{
    my $self = shift;
    my $token = shift;
    my $param = shift;
    my $val = $self->param($token, $param);
    return (defined($val) and ($val eq 'yes'));
}

sub paramDisabled
{
    my $self = shift;
    my $token = shift;
    my $param = shift;
    my $val = $self->param($token, $param);
    return (not defined($val) or ($val ne 'yes'));
}

sub paramString
{
    my $self = shift;
    my $token = shift;
    my $param = shift;
    my $val = $self->param($token, $param);
    return (defined($val) ? $val:'');    
}


sub setParam
{
    my $self = shift;
    my $token = shift;
    my $param = shift;
    my $value = shift;

    $self->{'targets'}{$token}{'params'}{$param} = $value;
    return;
}


sub path
{
    my $self = shift;
    my $token = shift;

    return $self->{'targets'}{$token}{'params'}{'path'};
}

sub listCollectorTargets
{
    my $self = shift;
    my $collector_type = shift;

    my @ret;
    foreach my $token ( keys %{$self->{'targets'}} )
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
    return;
}

sub deleteTarget
{
    my $self = shift;
    my $token = shift;

    Debug('Deleting target: ' . $self->path($token));
    
    if( ref( $self->{'targets'}{$token}{'deleteProc'} ) )
    {
        foreach my $proc ( @{$self->{'targets'}{$token}{'deleteProc'}} )
        {
            &{$proc}( $self, $token );
        }
    }
    delete $self->{'targets'}{$token};
    return;
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

    foreach my $collector_type ( @{$self->{'types_sorted'}} )
    {
        next unless $self->{'types_in_use'}{$collector_type};

        if( $Torrus::Collector::needsConfigTree
            {$collector_type}{'runCollector'} )
        {
            $self->{'config_tree'} =
                new Torrus::ConfigTree( -TreeName => $self->{'tree_name'} );
        }
        
        &{$Torrus::Collector::runCollector{$collector_type}}
        ( $self, $self->collectorData($collector_type) );
        
        if( defined( $self->{'config_tree'} ) )
        {
            delete $self->{'config_tree'};
        }
    }

    while( my ($storage_type, $ref) = each %{$self->{'storage'}} )
    {
        next unless $self->{'storage_in_use'}{$storage_type};
        
        if( $Torrus::Collector::needsConfigTree
            {$storage_type}{'storeData'} )
        {
            $self->{'config_tree'} =
                new Torrus::ConfigTree( -TreeName => $self->{'tree_name'},
                                        -Wait => 1 );
        }

        &{$Torrus::Collector::storeData{$storage_type}}( $self, $ref );

        if( defined( $self->{'config_tree'} ) )
        {
            delete $self->{'config_tree'};
        }        
    }
    
    while( my ($collector_type, $ref) = each %{$self->{'types'}} )
    {
        next unless $self->{'types_in_use'}{$collector_type};
        
        if( ref( $Torrus::Collector::postProcess{$collector_type} ) )
        {
            if( $Torrus::Collector::needsConfigTree
                {$collector_type}{'postProcess'} )
            {
                $self->{'config_tree'} =
                    new Torrus::ConfigTree( -TreeName => $self->{'tree_name'},
                                            -Wait => 1 );
            }
            
            &{$Torrus::Collector::postProcess{$collector_type}}( $self, $ref );

            if( defined( $self->{'config_tree'} ) )
            {
                delete $self->{'config_tree'};
            }
        }
    }

    $self->setStatValue('Objects', scalar(keys %{$self->{'targets'}}));
    
    return;
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
            $value = eval($code);
            if( not defined($value) or $@ )
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
            my $rpn = new Torrus::RPN;
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

    foreach my $storage_type
        ( @{$self->{'targets'}{$token}{'storage-types'}} )
    {
        &{$Torrus::Collector::setValue{$storage_type}}( $self, $token,
                                                        $value, $timestamp,
                                                        $uptime );
    }
    return;
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
        return undef;
    }
}


1;


# Local Variables:
# mode: perl
# indent-tabs-mode: nil
# perl-indent-level: 4
# End:
