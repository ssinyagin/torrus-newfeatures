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




package Torrus::Collector::RawExport_Params;

use strict;

###  Initialize the configuration validator with module-specific parameters

my $validatorLeafParams = {
    'raw-datadir'          => undef,
    'raw-file'             => undef,
    'raw-field-separator'  => undef,
    'raw-timestamp-format' => undef,
    'raw-rowid'            => undef,
    '+raw-counter-base'     => {
        '32' => undef,
        '64' => undef,
    },
    '+raw-counter-maxrate'  => undef,
};

sub initValidatorLeafParams
{
  my $hashref = shift;

  $hashref->{'ds-type'}{'collector'}{'@storage-type'}{'raw'} =
      $validatorLeafParams;
}



1;

