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

package Torrus::TimeStamp;

use Torrus::DB;
use Torrus::Log;

use strict;

$Torrus::TimeStamp::db = undef;

END
{
    Torrus::TimeStamp::release();
}

sub init
{
    not defined( $Torrus::TimeStamp::db ) or
        die('$Torrus::TimeStamp::db is defined at init');
    $Torrus::TimeStamp::db = new Torrus::DB('timestamps', -WriteAccess => 1);
}

sub release
{
    undef $Torrus::TimeStamp::db;
}

sub setNow
{
    my $tname = shift;
    ref( $Torrus::TimeStamp::db ) or
        die('$Torrus::TimeStamp::db is not defined at setNow');
    $Torrus::TimeStamp::db->put( $tname, time() );
}

sub get
{
    my $tname = shift;
    ref( $Torrus::TimeStamp::db ) or
        die('$Torrus::TimeStamp::db is not defined at get');
    my $stamp = $Torrus::TimeStamp::db->get( $tname );
    return defined($stamp) ? $stamp : 0;
}


1;


# Local Variables:
# mode: perl
# indent-tabs-mode: nil
# perl-indent-level: 4
# End:
