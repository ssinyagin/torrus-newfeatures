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

# Stanislav Sinyagin <ssinyagin@yahoo.com>

package Torrus::Collector::Cisco_cbQoS_Params;


use strict;

# List of needed parameters and default values

our %requiredLeafParams =
    (
     'cbqos-direction'              => {
         'input'          => undef,
         'output'         => undef },
     
     'cbqos-interface-name'         => undef,
     
     'cbqos-interface-type'         =>  {
         'mainInterface'  => undef,
         'subInterface'   => undef,
         'frDLCI'         => {
             'cbqos-fr-dlci' => undef },
         'atmPVC'         => {
             'cbqos-atm-vpi' => undef,
             'cbqos-atm-vci' => undef },
         'controlPlane'   => {
             'cbqos-phy-ent-idx' => undef },
         'vlanPort'       => {
             'cbqos-vlan-idx' => undef },
         'evc'            => {
             'cbqos-evc' => undef },
     },
     
     'cbqos-object-type'            => {
         'policymap'      => undef,
         'classmap'       => {
             'cbqos-class-map-name' => undef },
         'matchStatement' => {
             'cbqos-match-statement-name' => undef },
         'queueing'       => {
             'cbqos-queueing-bandwidth' => undef },
         'randomDetect'   => undef,
         'trafficShaping' => {
             'cbqos-shaping-rate' => undef },
         'police'         => {
             'cbqos-police-rate' => undef },
         'set'            => undef },
     
     'cbqos-parent-name' => undef,
     'cbqos-full-name' => undef
     );


sub initValidatorLeafParams
{
    my $hashref = shift;
    $hashref->{'ds-type'}{'collector'}{'collector-type'}{'cisco-cbqos'} =
        \%requiredLeafParams;
}


1;


# Local Variables:
# mode: perl
# indent-tabs-mode: nil
# perl-indent-level: 4
# End:
