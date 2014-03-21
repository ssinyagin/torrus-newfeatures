#
#  Copyright (C) 2008  Stanislav Sinyagin
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
#  Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.




package Torrus::Collector::RawExport;

use strict;
use threads;
use threads::shared;
use Thread::Queue;
use Date::Format;
use Math::BigInt;
use Math::BigFloat;
use IO::File;

use Torrus::Log;


# Register the storage type
$Torrus::Collector::storageTypes{'raw'} = 1;


# List of needed parameters and default values

$Torrus::Collector::params{'raw-storage'} = {
    'raw-datadir'          => undef,
    'raw-file'             => undef,
    'raw-field-separator'  => undef,
    'raw-timestamp-format' => undef,
    'raw-rowid'            => undef,
    'raw-counter-base'     => undef,
    'raw-counter-maxrate'  => undef,
};


our $thrQueueLimit;

our $thrUpdateQueue;
our $thrUpdateThread;


$Torrus::Collector::initThreadsHandlers{'raw-storage'} = \&initThreads;

sub initThreads
{
    Verbose('Initializing the background thread for Raw export');
    
    $thrUpdateQueue = new Thread::Queue;
    $thrUpdateThread = threads->create( \&rawUpdateThread );
    $thrUpdateThread->detach();
    return;
}



$Torrus::Collector::initTarget{'raw-storage'} = \&initTarget;


my $base32 = Math::BigInt->new(2)->bpow(32);
my $base64 = Math::BigInt->new(2)->bpow(64);

sub initTarget
{
    my $collector = shift;
    my $token = shift;

    my $sref = $collector->storageData( 'raw' );

    $collector->registerDeleteCallback( $token, \&deleteTarget );

    my $filename = $collector->param($token, 'raw-file');
    # Replace hash symbol with percent symbol for srtftime format
    $filename =~ s/\#/%/go;
    
    $filename = $collector->param($token, 'raw-datadir') . '/' . $filename;
    $sref->{'byfile'}{$filename}{$token} = 1;
    $sref->{'filename'}{$token} = $filename;

    # We assume that timestamp format is the same within one file
    
    if( not exists( $sref->{'timestamp_format'}{$filename} ) )
    {
        my $timestamp_format =
            $collector->param($token, 'raw-timestamp-format');
        $timestamp_format =~ s/\#/%/go;
        $sref->{'timestamp_format'}{$filename} = $timestamp_format;

        $sref->{'field_separator'}{$filename} =
            $collector->param($token, 'raw-field-separator');
    }

    my $base = $collector->param($token, 'raw-counter-base');
    if( defined( $base ) )
    {       
        $sref->{'base'}{$token} = ($base == 32 ? $base32:$base64);
        
        my $maxrate = $collector->param($token, 'raw-counter-maxrate');
        if( defined( $maxrate ) )
        {
            $sref->{'maxrate'}{$token} = Math::BigFloat->new($maxrate);
        }
    }

    return 1;
}



# Callback executed by Collector

sub deleteTarget
{
    my $collector = shift;
    my $token = shift;

    my $sref = $collector->storageData( 'raw' );
    my $filename = $sref->{'filename'}{$token};

    delete $sref->{'filename'}{$token};

    delete $sref->{'byfile'}{$filename}{$token};
    if( scalar( keys %{$sref->{'byfile'}{$filename}} ) == 0 )
    {
        delete $sref->{'byfile'}{$filename};
        delete $sref->{'timestamp_format'}{$filename};
        delete $sref->{'field_separator'}{$filename};
    }

    delete $sref->{'values'}{$token};
    delete $sref->{'base'}{$token};
    delete $sref->{'maxrate'}{$token};
    return;
}




$Torrus::Collector::setValue{'raw'} = \&setValue;


sub setValue
{
    my $collector = shift;
    my $token = shift;
    my $value = shift;
    my $timestamp = shift;
    my $uptime = shift;

    my $sref = $collector->storageData('raw');

    $sref->{'values'}{$token} = [$value, $timestamp];
    return;
}


$Torrus::Collector::storeData{'raw'} = \&storeData;

sub storeData
{
    my $collector = shift;
    my $sref = shift;

    my $qSize = $thrUpdateQueue->pending();
    $collector->setStatValue( 'RawQueue', $qSize );
    if( $qSize > $thrQueueLimit )
    {
        Error('Cannot enqueue Raw Export jobs: queue size is above limit');
    }
    
    while( my ($filename, $tokens) = each %{$sref->{'byfile'}} )
    {
        &Torrus::DB::checkInterrupted();

        my $filejob = &threads::shared::share({});
        
        $filejob->{'filename'} = $filename;
        $filejob->{'ts_format'} = $sref->{'timestamp_format'}{$filename};
        my $separator = $sref->{'field_separator'}{$filename};
        $filejob->{'separator'} = $separator;
        $filejob->{'values'} = &threads::shared::share([]);
        
        while( my($token, $dummy) = each %{$tokens} )
        {
            if( exists( $sref->{'values'}{$token} ) )
            {
                &Torrus::DB::checkInterrupted();
                
                my $rowentry = &threads::shared::share({});

                my ( $value, $timestamp ) = @{$sref->{'values'}{$token}};

                if( exists( $sref->{'base'}{$token} ) )
                {
                    # we're dealing with a counter. Calculate the increment

                    if( $value eq 'U' )
                    {
                        delete $sref->{'prevCounter'}{$token};
                        delete $sref->{'prevTimestamp'}{$token};
                        next;
                    }

                    # make sure we always work with BigInt objects
                    $value = Math::BigInt->new($value);
                    
                    my $increment;
                    my $prevTimestamp;
                    
                    if( exists( $sref->{'prevCounter'}{$token} ) )
                    {
                        my $prevValue = $sref->{'prevCounter'}{$token};
                        $prevTimestamp = $sref->{'prevTimestamp'}{$token};
                        
                        if( $prevValue->bcmp( $value ) > 0 ) 
                        {
                            # previous is bigger
                            $increment =
                                Math::BigInt->new($sref->{'base'}{$token});
                            $increment->bsub( $prevValue );
                            $increment->badd( $value );
                        }
                        else
                        {
                            $increment = Math::BigInt->new( $value );
                            $increment->bsub( $prevValue );
                        }
                        
                        
                        if( defined( $sref->{'maxrate'}{$token} ) )
                        {
                            my $rate = Math::BigFloat->new( $increment );
                            $rate->bdiv( $timestamp - $prevTimestamp );
                            if( $rate->bcmp($sref->{'maxrate'}{$token}) > 0 )
                            {
                                $increment = undef;
                            }
                        }
                    }
                    
                    $sref->{'prevCounter'}{$token} = $value;
                    $sref->{'prevTimestamp'}{$token} = $timestamp;

                    # Set the value to pair of text values: increment, interval
                    if( defined( $increment ) )
                    {
                        $value = join( $separator, $increment->bstr(),
                                       $timestamp - $prevTimestamp );
                    }
                    else
                    {
                        # nothing to store, proceed to the next token
                        next;
                    }
                }
                else
                {
                    if( ref( $value ) )
                    {
                        # Convert BigInt to string
                        $value = $value->bstr();
                    }
                }
                    
                $rowentry->{'value'} = $value;
                $rowentry->{'time'} = $timestamp;
                $rowentry->{'rowid'} =
                    $collector->param($token, 'raw-rowid');
                
                push( @{$filejob->{'values'}}, $rowentry );
            }
        }

        if( scalar( @{$filejob->{'values'}} ) > 0 )
        {
            $thrUpdateQueue->enqueue( $filejob );
        }
    }
    
    delete $sref->{'values'};
    return;
}


sub rawUpdateThread
{
    &Torrus::DB::setSafeSignalHandlers();
    &Torrus::Log::setTID( threads->tid() );
    
    while(1)
    {
        &Torrus::DB::checkInterrupted();

        my $filejob = $thrUpdateQueue->dequeue();

        my $fname = time2str( $filejob->{'filename'}, time() );

        while( $fname =~ /\^(\d+)\^/ )
        {
            my $stepsize = $1;
            my $curr_seconds = time() % 86400;
            my $curr_step =
                sprintf('%.5d',
                        $curr_seconds - ($curr_seconds % $stepsize));
            $fname =~ s/\^(\d+)\^/$curr_step/;
        }
        
        my $rawout = IO::File->new('>> ' . $fname);

        if( not $rawout )
        {
            Error('Cannot open ' . $fname . ' for writing: ' . $!);
            next;
        }

        my $ts_format = $filejob->{'ts_format'};
        my $separator = $filejob->{'separator'};

        foreach my $rowentry ( @{$filejob->{'values'}} )
        {
            $rawout->print( join( $separator,
                                  time2str( $ts_format, $rowentry->{'time'} ),
                                  $rowentry->{'rowid'},
                                  $rowentry->{'value'} ),
                            "\n");
            
            &Torrus::DB::checkInterrupted();
        }

        $rawout->close();
        
        Debug('RawExport: wrote ' . $fname);
    }
}


1;

