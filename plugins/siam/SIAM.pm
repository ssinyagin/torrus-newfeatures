#  Copyright (C) 2011  Stanislav Sinyagin
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


# Stanislav Sinyagin <ssinyagin@k-open.com>

# This module is an interface to SIAM API

package Torrus::SIAM;

use strict;
use warnings;

use SIAM;
use YAML;

use Torrus::Log;
use Torrus::SIAMLogger;


# Variables should be initialised in siam-siteconfig.pl
our $siam_config;

     


# Creates a SIAM object, connects and returns it.
sub open
{
    my $class = shift;
    
    my $siamcfg = eval { YAML::LoadFile($siam_config) };
    if( $@ )
    {
        Error("Cannot load YAML data from ${siam_config}: $@");
        return undef;        
    }
    
    $siamcfg->{'Logger'} = new Torrus::SIAMLogger;

    my $siam = new SIAM($siamcfg);
    if( not defined($siam) )
    {
        Error('Failed to load SIAM');
        return undef;
    }

    if( not $siam->connect() )
    {
        Error('Failed connecting to SIAM');
        return undef;
    }

    return $siam;        
}





1;


# Local Variables:
# mode: perl
# indent-tabs-mode: nil
# perl-indent-level: 4
# End:
