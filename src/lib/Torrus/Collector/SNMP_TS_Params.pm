#  Copyright (C) 2018  Stanislav Sinyagin
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

package Torrus::Collector::SNMP_TS_Params;


use strict;

# List of needed parameters and default values

our %requiredLeafParams =
    (
     'snmp-ts-column-oid' => undef,  # the actual data column
     'snmp-ts-ref-oid' => undef,     # reference column
     '+snmp-ts-unit-scale' => undef, # how timestamp relates to 1 second
     );


my %skip_snmp_params =
    (
     'snmp-object' => 1,
     'snmp-object-type' => 1,
     );
     

sub initValidatorLeafParams
{
    my $hashref = shift;

    # Copy parameters from SNMP collector, except for 'snmp-object'
    while(my($key, $val) =
          each %{$hashref->{'ds-type'}{'collector'}{'collector-type'}{'snmp'}})
    {
        if( not $skip_snmp_params{$key} )
        {
            $requiredLeafParams{$key} = $val;
        }
    }
    
    $hashref->{'ds-type'}{'collector'}{'collector-type'}{'snmp-ts'} =
        \%requiredLeafParams;
}




1;


# Local Variables:
# mode: perl
# indent-tabs-mode: nil
# perl-indent-level: 4
# End:
