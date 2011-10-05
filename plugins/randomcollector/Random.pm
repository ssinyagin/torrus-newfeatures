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
#  Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.

# $Id$
# Stanislav Sinyagin <ssinyagin@yahoo.com>


# Use a Perl plugin module as the collector source

package Torrus::Collector::Random;

use Torrus::ConfigTree;
use Torrus::Log;

use strict;
use Math::Trig;

# Register the collector type
$Torrus::Collector::collectorTypes{'random'} = 1;

###  Initialize the configuration validator with module-specific parameters

my %validatorLeafParams =
    (
     'rnd-baseline-type'     => {
         'flat' => undef,
         'sin' => {
             'rnd-baseline-period'    => undef,
             'rnd-baseline-offset'    => undef,
             'rnd-baseline-amplitude' => undef
             }
     },
     'rnd-amplitude'         => undef,
     'rnd-baseline-height'   => undef
     );

sub initValidatorLeafParams
{
    my $hashref = shift;
    $hashref->{'ds-type'}{'collector'}{'collector-type'}{'random'} =
        \%validatorLeafParams;
}


# List of needed parameters and default values

$Torrus::Collector::params{'random'} = \%validatorLeafParams;

$Torrus::Collector::initTarget{'random'} = \&Torrus::Collector::Random::initTarget;

sub initTarget
{
    my $collector = shift;
    my $token = shift;

    # Nothing to do actually...

    return 1;
}


# This is first executed per target

$Torrus::Collector::runCollector{'random'} =
    \&Torrus::Collector::Random::runCollector;

sub runCollector
{
    my $collector = shift;
    my $cref = shift;

    my $now = time();

    for my $token ( $collector->listCollectorTargets('random') )
    {
        my $value = $collector->param( $token, 'rnd-baseline-height' );
        my $ampl = $collector->param( $token, 'rnd-amplitude' );

        $value += rand( $ampl * 2 ) - $ampl;

        my $type = $collector->param( $token, 'rnd-baseline-type' );
        if( $type eq 'sin' )
        {
            my $sinampl = $collector->param($token, 'rnd-baseline-amplitude');
            my $period =  $collector->param($token, 'rnd-baseline-period');
            my $offset =  $collector->param($token, 'rnd-baseline-offset');

            $value += $sinampl * sin( 2 * pi * ($now + $offset)/$period );
        }

        $collector->setValue( $token, $value, $now );
    }
}


1;


# Local Variables:
# mode: perl
# indent-tabs-mode: nil
# perl-indent-level: 4
# End:
