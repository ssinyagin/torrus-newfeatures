#  Copyright (C) 2005  Stanislav Sinyagin
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

package Torrus::Collector::ExternalStorage;

use Torrus::ConfigTree;
use Torrus::Log;

use strict;
use Math::BigInt lib => 'GMP';
use Math::BigFloat;

# Pluggable backend module implements all storage-speific tasks
BEGIN
{
    eval( 'require ' . $Torrus::Collector::ExternalStorage::backend );
    die( $@ ) if $@;    
}

# These variables must be set by the backend module
our $backendInit;
our $backendOpenSession;
our $backendStoreData;
our $backendCloseSession;

# Register the storage type
$Torrus::Collector::storageTypes{'ext'} = 1;


# List of needed parameters and default values

$Torrus::Collector::params{'ext-storage'} = {
    'ext-dstype' => {
        'GAUGE' => undef,
        'COUNTER32' => {
            'ext-counter-max' => undef },
        'COUNTER64' => {
            'ext-counter-max' => undef }},
    'ext-service-id' => undef
    };




$Torrus::Collector::initTarget{'ext-storage'} =
    \&Torrus::Collector::ExternalStorage::initTarget;

sub initTarget
{
    my $collector = shift;
    my $token = shift;

    my $sref = $collector->storageData( 'ext' );

    $collector->registerDeleteCallback
        ( $token, \&Torrus::Collector::ExternalStorage::deleteTarget );

    my $serviceid =
        $collector->param($token, 'ext-service-id');

    if( defined( $sref->{'serviceid'}{$serviceid} ) )
    {
        Error('ext-service-id is not unique: ' . $serviceid);
        exit 1;
    }

    $sref->{'serviceid'}{$serviceid} = 1;

    my $processor;
    my $dstype = $collector->param($token, 'ext-dstype');
    if( $dstype eq 'GAUGE' )
    {
        $processor = \&Torrus::Collector::ExternalStorage::processGauge;
    }
    else
    {
        if( $dstype eq 'COUNTER32' )
        {
            $processor =
                \&Torrus::Collector::ExternalStorage::processCounter32;
        }
        else
        {
            $processor =
                \&Torrus::Collector::ExternalStorage::processCounter64;
        }
        
        my $max = $collector->param( $token, 'ext-counter-max' );
        if( defined( $max ) )
        {
            $sref->{'max'}{$token} = Math::BigFloat->new($max);
        }
    }

    $sref->{'tokens'}{$token} = $processor;

    &{$backendInit}( $collector, $token );
}



$Torrus::Collector::setValue{'ext'} =
    \&Torrus::Collector::ExternalStorage::setValue;


sub setValue
{
    my $collector = shift;
    my $token = shift;
    my $value = shift;
    my $timestamp = shift;

    my $sref = $collector->storageData( 'ext' );

    my $procvalue =
        &{$sref->{'tokens'}{$token}}( $collector, $token, $value, $timestamp );
    
    $sref->{'values'}{$token} = [$procvalue, $timestamp];
}


sub processGauge
{
    my $collector = shift;
    my $token = shift;
    my $value = shift;
    my $timestamp = shift;

    return $value;
}


sub processCounter32
{
    my $collector = shift;
    my $token = shift;
    my $value = shift;
    my $timestamp = shift;

    return processCounter( 32, $collector, $token, $value, $timestamp );
}

sub processCounter64
{
    my $collector = shift;
    my $token = shift;
    my $value = shift;
    my $timestamp = shift;

    return processCounter( 64, $collector, $token, $value, $timestamp );
}

my $base32 = Math::BigInt->new(2)->bpow(32);
my $base64 = Math::BigInt->new(2)->bpow(64);

sub processCounter
{
    my $base = shift;
    my $collector = shift;
    my $token = shift;
    my $value = shift;
    my $timestamp = shift;

    my $sref = $collector->storageData( 'ext' );
    my $ret;

    $value = Math::BigInt->new( $value );
    
    if( exists( $sref->{'counters'}{$token} ) )
    {
        my( $prevValue, $prevTimestamp ) = @{$sref->{'counters'}{$token}};
        if( $prevValue->bcmp( $value ) > 0 ) # previous is bigger
        {
            $ret = Math::BigFloat->new($base==32 ? $base32:$base64);
            $ret->bsub( $prevValue );
            $ret->badd( $value );
        }
        else
        {
            $ret = Math::BigFloat->new( $value );
            $ret->bsub( $prevValue );
        }
        $ret->bdiv( $timestamp - $prevTimestamp );
        if( defined( $sref->{'max'}{$token} ) )
        {
            if( $ret->bcmp( $sref->{'max'}{$token} ) > 0 )
            {
                $ret = undef;
            }
        }
    }

    $sref->{'counters'}{$token} = [ $value, $timestamp ];

    return $ret;
}



$Torrus::Collector::storeData{'ext'} =
    \&Torrus::Collector::ExternalStorage::storeData;

# timestamp of last unavailable storage
my $storageUnavailable = 0;

# how often we retry - configurable in torrus-config.pl
our $unavailableRetry;

# maximum age for backlog in case of unavailable storage.
# We stop recording new data when maxage is reached.

sub storeData
{
    my $collector = shift;
    my $sref = shift;
    
    &{$backendOpenSession}();

    while( my($token, $valuepair) = each( %{$sref->{'values'}{$token}} ) )
    {
        my( $value, $timestamp ) = @{$valuepair};
        my $serviceid =
            $collector->param($token, 'ext-service-id');

        my $toBacklog = 0;
        
        if( $storageUnavailable > 0 and 
            time() < $storageUnavailable + $unavailableRetry )
        {
            $toBacklog = 1;
        }
        else
        {
            if( exists( $sref->{'backlog'} ) )
            {
                # Try to flush the backlog first
                my $ok = 1;
                while( scalar(@{$sref->{'backlog'}}) > 0 and $ok )
                {
                    my $triple = shift @{$sref->{'backlog'}};
                    if( not &{$backendStoreData}( @{$triple} ) )
                    {
                        unshift( @{$sref->{'backlog'}}, $triple );
                        $ok = 0;
                        $toBacklog = 1;
                    }
                }
                if( $ok )
                {
                    delete( $sref->{'backlog'} );
                }                    
            }

            if( not $toBacklog )
            {
                if( not
                    &{$backendStoreData}( $timestamp, $serviceid, $value ) )
                {
                    $toBacklog = 1;
                }
            }
        }
        
        if( $toBacklog )
        {
            if( $storageUnavailable == 0 )
            {
                $storageUnavailable = time();
            }

            if( not exists( $sref->{'backlog'} ) )
            {
                $sref->{'backlog'} = [];
                $sref->{'backlogStart'} = time();
            }
            
            if( time() < $sref->{'backlogStart'} + backlogMaxage )
            {
                push( @{$sref->{'backlog'}},
                      [ $timestamp, $serviceid, $value ] );                
            }
        }
    }
                
    undef $sref->{'values'};
    &{$backendCloseSession}();
}





# Callback executed by Collector

sub deleteTarget
{
    my $collector = shift;
    my $token = shift;

    my $sref = $collector->storageData( 'ext' );

    my $serviceid =
        $collector->param($token, 'ext-service-id');
    delete $sref->{'serviceid'}{$serviceid};

    if( defined( $sref->{'counters'}{$token} ) )
    {
        delete $sref->{'counters'}{$token};
    }
    
    delete $sref->{'tokens'}{$token};
}


1;


# Local Variables:
# mode: perl
# indent-tabs-mode: nil
# perl-indent-level: 4
# End:
