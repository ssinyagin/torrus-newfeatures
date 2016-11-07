#  Copyright (C) 2016  Stanislav Sinyagin
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

package Torrus::ReportOutput::XLSX;

use strict;
use warnings;
use base 'Torrus::ReportOutput';

use Excel::Writer::XLSX;
use Date::Format;

use Torrus::Log;
use Torrus::ReportOutput;
use Torrus::SiteConfig;



sub init
{
    my $self = shift;

    Torrus::SiteConfig::loadStyling();
    
    my $xlsxdir = $self->{'outdir'} . '/xlsx';
    if( not -d $xlsxdir )
    {
        Verbose('Creating directory: ' . $xlsxdir);
        if( not mkdir( $xlsxdir ) )
        {
            Error('Cannot create directory ' . $xlsxdir . ': ' . $!);
            return 0;
        }
    }
    $self->{'xlsxdir'} = $xlsxdir;
    
    return 1;
}





# Print monthly report
# fields:
# month => reportname => serviceid => fieldname => {value, units}
sub genMonthlyOutput
{
    my $self = shift;
    my $year = shift;    
    my $fields = shift;

    my $filename = $self->{'xlsxdir'} . '/monthly_usage.' . $year . '.xlsx';
    
    my $workbook = Excel::Writer::XLSX->new($filename);
    
    my $c_tblheader = $workbook->set_custom_color(40, '#003366');
    
    my $f_tblheader = $workbook->add_format
        ( bold => 1,
          bottom => 1,
          align => 'center',
          bg_color => $c_tblheader,
          color => 'white' ); 

    my $f_num = $workbook->add_format(num_format => '0.00');
    
    foreach my $month (sort {$b<=>$a} keys %{$fields})
    {
        my $worksheet = $workbook->add_worksheet($year.$month);

        my $col = 0;
        my $row = 0;

        $worksheet->set_column($col, $col, 40);
        $worksheet->write($row, $col, "Service ID", $f_tblheader);
        $col++;
        
        $worksheet->set_column($col, $col, 25);
        $worksheet->write($row, $col, "Average, Mbps", $f_tblheader);
        $col++;

        $worksheet->set_column($col, $col, 25);
        $worksheet->write($row, $col, "95th Percentile, Mbps", $f_tblheader);
        $col++;

        $worksheet->set_column($col, $col, 25);
        $worksheet->write($row, $col, "Maximum, Mbps", $f_tblheader);
        $col++;

        $worksheet->set_column($col, $col, 25);
        $worksheet->write($row, $col, "Unavailable samples, %", $f_tblheader);
        $col++;

        $worksheet->set_column($col, $col, 25);
        $worksheet->write($row, $col, "Volume, GB", $f_tblheader);

        $row++;

        foreach my $reportName (keys %{$fields->{$month}})
        {
            if( $reportName eq 'MonthlyUsage' )
            {
                my $r = $fields->{$month}{$reportName};
                foreach my $serviceid (sort keys %{$r})
                {
                    $col=0;
                    $worksheet->write_string($row, $col, $serviceid);
                    $col++;
                    foreach my $varname ('AVG', '95TH_PERCENTILE', 'MAX',
                                         'UNAVAIL', 'VOLUME')
                    {
                        $worksheet->write_number
                            ($row, $col,
                             $r->{$serviceid}{$varname}{'value'},
                             $f_num);
                        $col++;
                    }
                    
                    $row++;
                }
            }
        }
    }

    $workbook->close();
    Verbose("Wrote $filename");
    
    return 1;
}
    

    

1;


# Local Variables:
# mode: perl
# indent-tabs-mode: nil
# perl-indent-level: 4
# End:
