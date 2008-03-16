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

# $Id$



package Torrus::Collector::RawExport;

use strict;
use threads;
use threads::shared;
use Thread::Queue;
use IO::File;
use Date::Format;


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
}



$Torrus::Collector::initTarget{'raw-storage'} = \&initTarget;


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
        my $filejob = &threads::shared::share({});
        
        $filejob->{'filename'} = $filename;
        $filejob->{'ts_format'} = $sref->{'timestamp_format'}{$filename};
        $filejob->{'separator'} = $sref->{'field_separator'}{$filename};
        $filejob->{'values'} = &threads::shared::share([]);
        
        while( my($token, $dummy) = each %{$tokens} )
        {
            if( exists( $sref->{'values'}{$token} ) )
            {
                my $rowentry = &threads::shared::share({});

                # Convert BigInt to string
                my $val = $sref->{'values'}{$token}[0];
                if( ref( $val ) )
                {
                    $val = $val->bstr();
                }
                
                $rowentry->{'value'} = $val;
                $rowentry->{'time'} = $sref->{'values'}{$token}[1];
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
}


sub rawUpdateThread
{
    &Torrus::Log::setTID( threads->tid() );
    
    while(1)
    {
        my $filejob = $thrUpdateQueue->dequeue();

        my $fname = time2str( $filejob->{'filename'}, time() );
        
        my $fh = new IO::File( $fname, O_WRONLY|O_CREAT|O_APPEND );

        if( not defined($fh) )
        {
            Error('Cannot open ' . $fname . ' for writing: ' . $!);
            next;
        }

        my $ts_format = $filejob->{'ts_format'};
        my $separator = $filejob->{'separator'};

        foreach my $rowentry ( @{$filejob->{'values'}} )
        {
            print $fh ( join( $separator,
                              time2str( $ts_format, $rowentry->{'time'} ),
                              $rowentry->{'rowid'},
                              $rowentry->{'value'} ),
                        "\n");
        }

        $fh->close();
        
        Debug('RawExport: wrote ' . $fname);
    }
}


1;

