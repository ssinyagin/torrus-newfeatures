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

# Stanislav Sinyagin <ssinyagin@k-open.com>



## Class for report fields table

package Torrus::SQL::ReportFields;
use strict;
use warnings;

use base 'Torrus::SQL';

use Torrus::Log;

# The name of the table and columns 
# defaults configured in torrus-config.pl
our $tableName;
our %columns;

sub add
{
    my $self = shift;
    my $reportId = shift;
    my $attrs = shift;
    
    my $id = $self->sequenceNext();
    
    $self->{'sql'}->insert({
        'table' => $tableName,
        'fields' => { $columns{'id'}         => $id,
                      $columns{'rep_id'}     => $reportId,
                      $columns{'name'}       => $attrs->{'name'},
                      $columns{'serviceid'}  => $attrs->{'serviceid'},
                      $columns{'value'}      => $attrs->{'value'},
                      $columns{'units'}      => $attrs->{'units'} } });
    return;
}


sub getAll
{
    my $self = shift;
    my $reportId = shift;
       
    $self->{'sql'}->select({
        'table' => $tableName,
        'where' => { $columns{'rep_id'} => $reportId },
        'fields' => [ $columns{'name'},
                      $columns{'serviceid'},
                      $columns{'value'},
                      $columns{'units'}] });

    return $self->fetchall([ 'name', 'serviceid', 'value', 'units' ]);
}


sub removeAll
{
    my $self = shift;
    my $reportId = shift;
       
    $self->{'sql'}->delete({
        'table' => $tableName,
        'where' => { $columns{'rep_id'} => $reportId }});
    return;
}    
    
    
    
    
1;


# Local Variables:
# mode: perl
# indent-tabs-mode: nil
# perl-indent-level: 4
# End:
