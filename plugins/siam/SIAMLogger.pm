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

# Stanislav Sinyagin <ssinyagin@yahoo.com>

# Wrapper around Torrus logger to work for SIAM notifications

package Torrus::SIAMLogger;

use strict;
use warnings;

use Torrus::Log;


sub new
{
    my $self = {};
    my $class = shift;
    bless $self, $class;

    return $self;
}


sub debug
{
    my $self = shift;
    my $msg = shift;
    Debug($msg);
}


sub info
{
    my $self = shift;
    my $msg = shift;
    Info($msg);
}
    
sub warn
{
    my $self = shift;
    my $msg = shift;
    Warn($msg);
}
    

sub error
{
    my $self = shift;
    my $msg = shift;
    Error($msg);
}
    


1;


# Local Variables:
# mode: perl
# indent-tabs-mode: nil
# perl-indent-level: 4
# End:
