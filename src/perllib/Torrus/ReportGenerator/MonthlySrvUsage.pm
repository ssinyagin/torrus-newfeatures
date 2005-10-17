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

# For all service IDs available, build monthly usage figures:
# Average, Maximum, and Percentile (default 95th percentile)
# 

package Torrus::ReportGenerator::MonthlySrvUsage;

use strict;
use POSIX qw(floor);
use Date::Parse;

use Torrus::Log;
use Torrus::ReportGenerator;

use base 'Torrus::ReportGenerator';

sub isMonthly
{
    return 1;
}

sub usesSrvExport
{
    return 1;
}


sub generate
{
    my $self = shift;

    my $percentile = $self->{'options'}->{'Percentile'};
    if( not defined( $percentile ) )
    {
        $percentile = 95;
    }

    my $step = $self->{'options'}->{'Step'};
    if( not defined( $step ) )
    {
        $step = 300;
    }
    
    my $srvIDs = $self->{'srvexport'}->getServiceIDs();

    foreach my $serviceid ( @{$srvIDs} )
    {
        Debug('MonthlySrvUsage: Generating report for ' . $serviceid);

        my $data = $self->{'srvexport'}->getIntervalData
            ( $self->{'StartDate'}, $self->{'EndDate'}, $serviceid );

        next if scalar( @{$data} ) == 0;
        
        my @aligned = ();
        $#aligned= floor( $self->{'RangeSeconds'} / $step );
        my $nDatapoints = scalar( @aligned );
            
        # Fill in the aligned array. For each interval by modulo(step),
        # we take the maximum value from the available data

        my $maxVal = 0;
        
        foreach my $row ( @{$data} )
        {
            my $rowtime = str2time( $row->{'srv_date'} . 'T' .
                                    $row->{'srv_time'} );
            my $pos = floor( ($rowtime - $self->{'StartUnixTime'}) / $step );
            my $value = $row->{'value'};
            
            if( ( not defined( $aligned[$pos] ) ) or
                $aligned[$pos] < $value )
            {
                $aligned[$pos] = $value;
                if( $value > $maxVal )
                {
                    $maxVal = $value;
                }
            }
        }

        # Set undefined values to zero and calculate the average

        my $sum = 0;
        my $unavailCount = 0;
        foreach my $pos ( 0 .. $#$aligned )
        {
            if( not defined( $aligned[$pos] ) )
            {
                $aligned[$pos] = 0;
                $unavailCount++;
            }
            else
            {
                $sum += $aligned[$pos];
            }
        }

        my $avgVal = $sum / $nDatapoints;

        # Calculate the percentile

        my @sorted = sort {$a <=> $b} @aligned;
        my $pcPos = floor( $nDatapoints * $percentile / 100 );
        my $pcVal = $sorted[$pcPos];
        
        $self->{'backend'}->addField( $self->{'reportId'}, {
            'name'      => 'MAX',
            'serviceid' => $serviceid,
            'value'     => $maxVal });
        
        $self->{'backend'}->addField( $self->{'reportId'}, {
            'name'      => 'AVG',
            'serviceid' => $serviceid,
            'value'     => $avgVal });
                                      
        $self->{'backend'}->addField( $self->{'reportId'}, {
            'name'      => sprintf('%s%s', $percentile, 'PERCENTILE'),
            'serviceid' => $serviceid,
            'value'     => $pcVal });
        
        $self->{'backend'}->addField( $self->{'reportId'}, {
            'name'      => 'UNAVAIL',
            'serviceid' => $serviceid,
            'value'     => $unavailCount });        
    }

    $self->{'backend'}->finalize();
}



1;


# Local Variables:
# mode: perl
# indent-tabs-mode: nil
# perl-indent-level: 4
# End:
