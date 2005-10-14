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

# Class for Reporter data manipulation
package Torrus::SQL::ReportFields;
package Torrus::SQL::Reports;

use strict;

use Torrus::SQL;
use base 'Torrus::SQL';

use Torrus::Log;
use Torrus::SQL::ReportFields;

# The name of the table and columns 
# defaults configured in torrus-config.pl
our $tableName;
our %columns;


sub new
{
    my $class = shift;
    my $subtype = shift;

    my $self  = $class->SUPER::new( $subtype );

    $self->{'fields'} = Torrus::SQL::ReportFields->new( $subtype );
    
    bless ($self, $class);
    return $self;
}
    

# Find or create a new row in reports table
# 
sub reportId
{
    my $self = shift;
    my $repdate = shift;
    my $reptime = shift;
    my $repname = shift;

    my $result = $self->{'sql'}->select_one_to_arrayref({
        'fields' => [ $columns{'id'} ],
        'table' => $tableName,
        'where' => { $columns{'rep_date'}   => $repdate,
                     $columns{'rep_time'}   => $reptime,
                     $columns{'reportname'} => $repname } });
    
    if( defined( $result ) )
    {
        return $result->[0];
    }
    else
    {
        my $id = $self->sequenceNext();

        $self->{'sql'}->insert({
            'table' => $tableName,
            'fields' => { $columns{'id'} => $id,
                          $columns{'rep_date'}   => $repdate,
                          $columns{'rep_time'}   => $reptime,
                          $columns{'reportname'} => $repname } });
        
        return $id;
    }
}



# Add a new field to a report. The field is a hash array reference
# with keys: 'name', 'serviceid', 'value'

sub addField
{
    my $self = shift;
    my $reportId = shift;
    my $field = shift;
   
    $self->{'fields'}->add( $reportId, $field );
}


sub getFields
{
    my $self = shift;
    my $reportId = shift;

    return $self->{'fields'}->getAll( $reportId );
}
    

        
################################################
## Class for report fields table

package Torrus::SQL::ReportFields;
use strict;

use Torrus::SQL;
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
                      $columns{'value'}      => $attrs->{'value'} } });
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
                      $columns{'value'} ] });

    return $self->fetchall([ 'name', 'serviceid', 'value' ]);
}
    

    
    
    
    
1;


# Local Variables:
# mode: perl
# indent-tabs-mode: nil
# perl-indent-level: 4
# End:
