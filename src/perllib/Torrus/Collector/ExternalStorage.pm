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
    elsif( $dstype eq 'COUNTER32' )
    {
        $processor = \&Torrus::Collector::ExternalStorage::processCounter32;
    }
    else
    {
        $processor = \&Torrus::Collector::ExternalStorage::processCounter64;
    }
    $sref->{'tokens'}{$token} = $processor;
}



$Torrus::Collector::setValue{'ext'} =
    \&Torrus::Collector::ExternalStorage::setValue;


sub setValue
{
    my $collector = shift;
    my $token = shift;
    my $value = shift;
    my $timestamp = shift;
    my $uptime = shift;

    my $sref = $collector->storageData( 'ext' );

    $sref->{'values'}{$token} = [$value, $timestamp, $uptime];
}


$Torrus::Collector::storeData{'ext'} =
    \&Torrus::Collector::ExternalStorage::storeData;

sub storeData
{
    my $collector = shift;
    my $sref = shift;


    undef $sref->{'values'};
}





# Callback executed by Collector

sub deleteTarget
{
    my $collector = shift;
    my $token = shift;

    my $sref = $collector->storageData( 'ext' );

    delete $sref->{'tokens'}{$token};
}


1;


# Local Variables:
# mode: perl
# indent-tabs-mode: nil
# perl-indent-level: 4
# End:
