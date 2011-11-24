#  Copyright (C) 2011   Dean Hamstead
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

# Dean Hamstead <dean@fragfest.com.au>

package Torrus::DevDiscover::HPProCurve;

use strict;
use warnings;

use Torrus::Log;

our $VERSION = 1.0;

$Torrus::DevDiscover::registry{'HPProCurve'} = {
    'sequence'     => 500,
    'checkdevtype' => \&checkdevtype,
    'discover'     => \&discover,
    'buildConfig'  => \&buildConfig
    };

our %oiddef =
    (
     # this is defined in HP-ICF-OID
     'hp'                    => '1.3.6.1.4.1.11',
     'hpnm'                  => '1.3.6.1.4.1.11.2',

     # HP ProCurve Switch

     # from STATISTICS-MIB
     'hpSwitchCpuStat'      => '1.3.6.1.4.1.11.2.14.11.5.1.9.6.1',

     # from NETSWITCH-MIB
     # Technically this is a table, but i dont have an example
     # with more than one entry
     'hpLocalMemTable'      => '1.3.6.1.4.1.11.2.14.11.5.1.1.2.1.1.1',
     'hpLocalMemSlotIndex'  => '1.3.6.1.4.1.11.2.14.11.5.1.1.2.1.1.1.1',
     'hpLocalMemTotalBytes' => '1.3.6.1.4.1.11.2.14.11.5.1.1.2.1.1.1.5',
     'hpLocalMemFreeBytes'  => '1.3.6.1.4.1.11.2.14.11.5.1.1.2.1.1.1.6',
     'hpLocalMemAllocBytes' => '1.3.6.1.4.1.11.2.14.11.5.1.1.2.1.1.1.7',
     );



sub checkdevtype
{
    my $dd = shift;
    my $devdetails = shift;

    return $dd->checkSnmpTable( 'hpnm' );
}


sub discover
{
    my $dd = shift;
    my $devdetails = shift;

    my $session = $dd->session();
    my $data = $devdetails->data();

    my $hpLocalMemTable =
        $session->get_table( -baseoid => $dd->oiddef('hpLocalMemTable') );

    my $hpLocalMemTable = $dd->walkSnmpTable('hpLocalMemTable');
    if( scalar(keys %{$hpLocalMemTable}) > 0 )
    {
        $devdetails->setCap('hpLocalMemTable');
        $data->{'hpLocalMem'} = [];
        
        push( @{$data->{'hpLocalMem'}},
              sort {$a <=> $b} keys %{$hpLocalMemTable} );
    }

    return 1;
}


sub buildConfig
{
    my $devdetails = shift;
    my $cb = shift;
    my $devNode = shift;
    my $data = $devdetails->data();

    # PROG: Add static CPU information
    $cb->addSubtree( $devNode, 'HP_CPU',
                   { 'precedence' => 999 },
                   [ 'HPProCurve::hp-procurve-cpu' ] );

    if( $devdetails->hasCap('hpLocalMemTable') )
    {
        my $nodeInput =
            $cb->addSubtree( $devNode, 'HP_Memory',
                             { 'comment' => 'HP Memory Slots' },
                             [ 'HPProCurve::hp-procurve-memory-subtree' ] );
        
        for my $INDEX ( @{$data->{'hpLocalMem'}} )
        {
            $cb->addSubtree( $nodeInput, sprintf('Local_Slot_%d', $INDEX),
                             { 'memslot-index' => $INDEX },
                             [ 'HPProCurve::hp-procurve-memory-leaf' ] );
        }
    }

    return;
}


1;


# Local Variables:
# mode: perl
# indent-tabs-mode: nil
# perl-indent-level: 4
# End:
